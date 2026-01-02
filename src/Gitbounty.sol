// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

/**
 * Gitbounty (Factory-compatible)
 * - NO FunctionsClient / NO Automation interface in the child
 * - Factory is the ONLY FunctionsClient and the ONLY Automation Upkeep target
 *
 * Child responsibilities:
 *  - Hold funds + payout logic
 *  - Provide args to factory via getArgs()
 *  - Accept fulfillment from factory via onFunctionsFulfilled()
 *
 * Notes:
 *  - performUpkeep/checkUpkeep are removed (factory schedules attempts)
 *  - s_lastRequestId is still stored for sanity matching
 */
interface IGitbountyFactory {
    function closeBounty(address bounty) external;
}

contract Gitbounty is ConfirmedOwner {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error Gitbounty__SendNonZeroEth();
    error Gitbounty__NoFundToWithdraw();
    error Gitbounty__TransferFailed();
    error Gitbounty__NotOpen();
    error Gitbounty__CriteriaNotSet();
    error Gitbounty__OnlyFactory();
    error UnexpectedRequestID(bytes32 requestId);

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    enum GitbountyState {
        BASE,
        EMPTY,
        READY,
        CALCULATING,
        PAID
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/
    address public immutable factory;

    // Factory/Functions bookkeeping
    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;

    // Payment record keeping
    string public lastWinnerUser;
    string public last_repo_owner;
    string public last_repo;
    string public last_issueNumber;
    uint256 public last_BountyAmount;
    address private s_lastWinner;

    // Funding
    mapping(address => uint256) private s_contributions;
    address[] private funders;
    uint256 private s_totalFunding;
    uint256 private s_funderCount;

    // Bounty criteria
    string private repo_owner;
    string private repo;
    string private issueNumber;

    GitbountyState private s_gitbountyState;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event BountyFunded(address indexed sender, uint256 value);
    event BountyFundWithdrawn(address indexed sender, uint256 value);
    event BountyClaimed(address indexed winner, uint256 value);

    event Response(bytes32 indexed requestId, bytes response, bytes err);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _factory) ConfirmedOwner(msg.sender) {
        require(_factory != address(0), "factory required");
        factory = _factory;

        s_gitbountyState = GitbountyState.BASE;
    }

    /*//////////////////////////////////////////////////////////////
                           BOUNTY LIFECYCLE
    //////////////////////////////////////////////////////////////*/
    function isBountyReady() external view returns (bool) {
        return s_gitbountyState == GitbountyState.READY;
    }

    function setBountyCriteria(string calldata _owner, string calldata _repo, string calldata _issue) public onlyOwner {
        repo_owner = _owner;
        repo = _repo;
        issueNumber = _issue;
    }

    function createAndFundBounty(
        string calldata _owner,
        string calldata _repo,
        string calldata _issue
    ) external payable onlyOwner {
        setBountyCriteria(_owner, _repo, _issue);
        _fundBounty(msg.sender, msg.value);
        s_gitbountyState = GitbountyState.READY;
    }

    function deleteAndRefundBounty() public onlyOwner {
        _refundAllFunders();

        // Reset bounty criteria
        repo_owner = "";
        repo = "";
        issueNumber = "";

        s_gitbountyState = GitbountyState.EMPTY;
    }

    function resetContract() external onlyOwner {
        // Refund any funds
        _refundAllFunders();

        // Reset criteria
        repo_owner = "";
        repo = "";
        issueNumber = "";

        // Reset winners
        s_lastWinner = address(0);
        lastWinnerUser = "";
        last_BountyAmount = 0;

        // Reset factory/callback state
        s_lastRequestId = bytes32(0);
        s_lastResponse = "";
        s_lastError = "";

        // Reset state
        s_gitbountyState = GitbountyState.BASE;
    }

    function abandonInFlight() external onlyOwner {
        // allow the bounty to be retried from scratch
        s_lastRequestId = bytes32(0);
        if (s_gitbountyState == GitbountyState.CALCULATING) {
            s_gitbountyState = GitbountyState.READY;
        }
    }


    /*//////////////////////////////////////////////////////////////
                              FUNDING
    //////////////////////////////////////////////////////////////*/
    function _fundBounty(address sender, uint256 amount) internal {
        if (amount == 0) revert Gitbounty__SendNonZeroEth();

        if (s_contributions[sender] == 0) {
            s_funderCount++;
            funders.push(sender);
        }

        s_contributions[sender] += amount;
        s_totalFunding += amount;

        emit BountyFunded(sender, amount);
    }

    function fundBounty() public payable {
        _fundBounty(msg.sender, msg.value);
        // If someone funds an empty/base bounty, you may want to keep it EMPTY until owner sets criteria.
        // We won't auto-change state here.
    }

    function withdrawBountyFund() external {
        uint256 amount = s_contributions[msg.sender];
        if (amount == 0) revert Gitbounty__NoFundToWithdraw();

        // Effects
        s_contributions[msg.sender] = 0;
        s_totalFunding -= amount;
        s_funderCount--;

        // Interaction
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert Gitbounty__TransferFailed();

        emit BountyFundWithdrawn(msg.sender, amount);
    }

    function _refundAllFunders() internal {
        for (uint256 i = 0; i < funders.length; i++) {
            address funder = funders[i];
            uint256 amount = s_contributions[funder];
            if (amount > 0) {
                s_contributions[funder] = 0;
                (bool success, ) = funder.call{value: amount}("");
                if (!success) revert Gitbounty__TransferFailed();
                emit BountyFundWithdrawn(funder, amount);
            }
        }
        _resetContributions();
    }

    function _resetContributions() internal {
        for (uint256 i = 0; i < funders.length; i++) {
            s_contributions[funders[i]] = 0;
        }
        delete funders;
        s_totalFunding = 0;
        s_funderCount = 0;
    }

    /*//////////////////////////////////////////////////////////////
                           FACTORY INTEGRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Factory calls this before making the Functions request (or right after) to record request id and mark state.
    /// The provided factory contract already sets inFlight and schedules; we only mark local CALCULATING.
    /// @dev Not strictly required, but keeps your state machine clear.
    function markCalculating(bytes32 requestId) external {
        if (msg.sender != factory) revert Gitbounty__OnlyFactory();
        s_gitbountyState = GitbountyState.CALCULATING;
        s_lastRequestId = requestId;
    }

    /// @notice Factory reads args from this contract to build its Functions request.
    function getArgs() external view returns (string memory repoOwner, string memory _repo, string memory _issueNumber) {
        repoOwner = repo_owner;
        _repo = repo;
        _issueNumber = issueNumber;
    }

    /// @notice Factory forwards Functions fulfillment to this bounty.
    function onFunctionsFulfilled(
        bytes32 requestId,
        address winner,
        bytes calldata response,
        bytes calldata err
    ) external {
        if (msg.sender != factory) revert Gitbounty__OnlyFactory();

        // Strict request matching:
        if (s_lastRequestId != bytes32(0) && s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId);
        }

        s_lastRequestId = requestId;
        s_lastResponse = response;
        s_lastError = err;

        _handleFulfillment(requestId, winner, response, err);
    }

    function _handleFulfillment(bytes32 requestId, address winner, bytes calldata response, bytes calldata err) internal {
        // Decode response as UTF-8 string (GitHub username)
        string memory result = string(response);

        // Soft-fail if result is empty or "not_found"
        if (
            bytes(result).length == 0 ||
            keccak256(bytes(result)) == keccak256(bytes("not_found"))
        ) {
            s_gitbountyState = GitbountyState.READY;
            emit Response(requestId, response, err);
            return;
        }

        // Soft-fail if unmapped
        if (winner == address(0)) {
            s_gitbountyState = GitbountyState.READY;
            emit Response(requestId, response, err);
            return;
        }

        // ----- CEI pattern -----
        uint256 amount = s_totalFunding;

        // Effects (commit state before external call; revert rolls all back if transfer fails)
        s_lastWinner = winner;
        lastWinnerUser = result;
        last_repo_owner = repo_owner;
        last_repo = repo;
        last_issueNumber = issueNumber;
        last_BountyAmount = amount;

        // Clear criteria & contributions
        repo_owner = "";
        repo = "";
        issueNumber = "";

        _resetContributions();

        s_gitbountyState = GitbountyState.PAID;

        // Interaction
        (bool success, ) = winner.call{value: amount}("");
        if (!success) revert Gitbounty__TransferFailed();

        emit BountyClaimed(winner, amount);
        emit Response(requestId, response, err);

        // Optional: inform factory to stop scheduling this bounty.
        // If your factory's closeBounty is onlyOwner, this will revert.
        // You can either:
        //  (a) remove this call, or
        //  (b) add a "closeBountyFromChild" function in factory restricted to registered children.
        // try IGitbountyFactory(factory).closeBounty(address(this)) {} catch {}
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    function getGitbountyState() external view returns (GitbountyState) {
        return s_gitbountyState;
    }

    function getContribution() external view returns (uint256) {
        return s_contributions[msg.sender];
    }

    function getFunderCount() external view returns (uint256) {
        return s_funderCount;
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getRepoOwner() external view returns (string memory) {
        return repo_owner;
    }

    function getRepo() external view returns (string memory) {
        return repo;
    }

    function getIssueNumber() external view returns (string memory) {
        return issueNumber;
    }

    function getLastResponse() external view returns (bytes memory) {
        return s_lastResponse;
    }
}
