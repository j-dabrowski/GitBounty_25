// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FunctionsClient} from "@chainlink/v1/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/v1/libraries/FunctionsRequest.sol";


/**
 * @title Gitbounty
 * @notice Extends the Raffle contract to include Chainlink Functions for external approval before winner selection.
 */
contract Gitbounty is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

    /* Errors */
    error Gitbounty__SendNonZeroEth();
    error Gitbounty__NoFundToWithdraw();
    error Gitbounty__NoAddressMappedToUsername(string username);
    error UnexpectedRequestID(bytes32 requestId);
    // Gitbounty errors below
    error Gitbounty__TransferFailed();
    error Gitbounty__NotOpen();
    error Gitbounty__UpkeepNotNeeded(uint256 balance, uint256 numberOfFunders, uint256 gitbountyState);

    /* type declarations */
    enum GitbountyState {
        BASE,
        EMPTY,
        READY,
        CALCULATING,
        PAID
    }

    // Functions State variables
    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;
    // Payment Record Keeping
    string public lastWinnerUser;
    string public last_repo_owner;
    string public last_repo;
    string public last_issueNumber;
    uint256 public last_BountyAmount;
    address private s_lastWinner;
    uint256 private s_lastTimeStamp;

    /* state variables */
    // Funding
    mapping(string => address) private s_githubToAddress;
    string[] private usernames;
    mapping(address => uint256) private s_contributions;
    address[] private funders;
    uint256 private s_totalFunding;
    uint256 private s_funderCount;
    // Bounty Criteria
    string private repo_owner;
    string private repo;
    string private issueNumber;
    // @dev duration of the interval in seconds
    uint256 private immutable i_interval;
    GitbountyState private s_gitbountyState; // start as open
    // Other
    address router;
    bytes32 donID;
    uint64 public functionsSubId;
    string public source;
    // Callback gas limit
    uint32 gasLimit = 300000;
    bytes public encryptedSecretsUrls;

    /** Events */
    event GithubUserMapped(string indexed username, address indexed userAddress);
    event BountyFunded(address indexed sender, uint256 value);
    event BountyFundWithdrawn(address indexed sender, uint256 value);
    event BountyClaimed(address indexed winner, uint256 value);

    // Event to log responses
    event Response(
        bytes32 indexed requestId,
        bytes response,
        bytes err
    );

    /**
     * @notice Initializes the contract with the Chainlink router address and sets the contract owner
     */
    constructor(
        uint256 _interval,
        address _functionsOracle,
        bytes32 _donID,
        uint64 _functionsSubId,
        string memory _sourceCode,
        bytes memory _encryptedSecretsUrls
    )
        FunctionsClient(_functionsOracle)
        ConfirmedOwner(msg.sender)
    {
        s_lastTimeStamp = block.timestamp;
        s_gitbountyState = GitbountyState.BASE;
        i_interval = _interval;
        router = _functionsOracle;
        donID = _donID;
        functionsSubId = _functionsSubId;
        source = _sourceCode;
        encryptedSecretsUrls = _encryptedSecretsUrls;
    }

    function setBountyCriteria(
        string calldata _owner,
        string calldata _repo,
        string calldata _issue
    ) public onlyOwner {
        repo_owner = _owner;
        repo = _repo;
        issueNumber = _issue;
    }

    function _fundBounty(address sender, uint256 amount) internal {
        if (amount == 0) {
            revert Gitbounty__SendNonZeroEth();
        }

        if (s_contributions[sender] == 0) {
            s_funderCount++;
            funders.push(sender); // track new funder
        }

        s_contributions[sender] += amount;
        s_totalFunding += amount;

        emit BountyFunded(sender, amount);
    }

    function fundBounty() public payable {
        _fundBounty(msg.sender, msg.value);
    }

    function withdrawBountyFund() external {
        uint256 amount = s_contributions[msg.sender];
        if (amount == 0) {
            revert Gitbounty__NoFundToWithdraw(); // Define this error
        }

        s_contributions[msg.sender] = 0;
        s_totalFunding -= amount;
        s_funderCount--;

        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) {
            revert Gitbounty__TransferFailed();
        }
        
        emit BountyFundWithdrawn(msg.sender, amount);
    }

    function deleteAndRefundBounty() public onlyOwner {
        // Refund all contributors
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
        // Reset funding state
        _resetContributions();
        // Reset bounty criteria
        repo_owner = "";
        repo = "";
        issueNumber = "";
        // Set gitbounty state to OPEN (or CALCULATING if appropriate)
        s_gitbountyState = GitbountyState.EMPTY;
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

    function mapGithubUsernameToAddress(string calldata username) external {
        require(bytes(username).length > 0, "Username required");
        require(s_githubToAddress[username] == address(0), "Username already mapped");

        s_githubToAddress[username] = msg.sender;
        usernames.push(username);

        emit GithubUserMapped(username, msg.sender);
    }

    function resetContract() external onlyOwner {
        deleteAndRefundBounty();
        
        // Reset contributions
        _resetContributions();

        // Clear GitHub username mappings
        for (uint i = 0; i < usernames.length; i++) {
            string memory user = usernames[i];
            delete s_githubToAddress[user];
        }
        delete usernames;

        // Reset bounty criteria
        repo_owner = "";
        repo = "";
        issueNumber = "";

        // Reset winners
        s_lastWinner = address(0);
        lastWinnerUser = "";
        last_BountyAmount = 0;

        // Reset Chainlink Functions-related state
        s_lastRequestId = bytes32(0);
        s_lastResponse = "";
        s_lastError = "";

        // Reset timestamp
        s_lastTimeStamp = block.timestamp;

        // Reset state
        s_gitbountyState = GitbountyState.BASE;
    }


    /**
     * @param - ignored
     * @return upkeepNeeded - true if it's time to submit a functions call
     * @return - ignored
     */
    function checkUpkeep(bytes memory /* checkData */) public view 
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isReady = s_gitbountyState == GitbountyState.READY;
        bool hasBalance = address(this).balance > 0;
        bool hasFunders = s_funderCount > 0;
        bool hasBountyCriteria = bytes(repo_owner).length > 0 && bytes(repo).length > 0 && bytes(issueNumber).length > 0;

        upkeepNeeded = timeHasPassed && isReady && hasBalance && hasFunders && hasBountyCriteria;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        // Checks
        // check if enough time has passed
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Gitbounty__UpkeepNotNeeded(address(this).balance, s_funderCount, uint256(s_gitbountyState));
        }
        s_gitbountyState = GitbountyState.CALCULATING;
        s_lastTimeStamp = block.timestamp;
        
        // === Prepare Request Arguments ===
        string[] memory args = new string[](3);
        args[0] = repo_owner;
        args[1] = repo;
        args[2] = issueNumber;

        try this.sendRequest(functionsSubId, args) returns (bytes32 requestId) {
            s_lastRequestId = requestId;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Functions request error: ", reason)));
        } catch {
            revert("Functions request failed: unknown reason");
        }
    }

    function _resetContributions() internal {
        for (uint256 i = 0; i < funders.length; i++) {
            address funder = funders[i];
            s_contributions[funder] = 0;
        }
        delete funders;
        s_totalFunding = 0;
        s_funderCount = 0;
    }

    /** Getter Functions */
    function getGitbountyState() external view returns(GitbountyState) {
        return s_gitbountyState;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getContribution() external view returns (uint256) {
        return s_contributions[msg.sender];
    }

    function getFunderCount() public view returns (uint256) {
        return s_funderCount;
    }

    function getBalance() external view returns (uint256) {
    return address(this).balance;
}

    function getAddressFromUsername(string calldata username) external view returns (address) {
        return s_githubToAddress[username];
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

    // CHAINLINK FUNCTIONS
    /**
     * @notice Checks Github for the user who created PR that was merged for the issue
     * @param subscriptionId The ID for the Chainlink subscription
     * @param args The arguments to pass to the HTTP request
     * @return requestId The ID of the request
     */
    function sendRequest(
        uint64 subscriptionId,
        string[] calldata args
    ) external returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req._initializeRequestForInlineJavaScript(source);
        // Add args if they exist
        if (args.length > 0) {
            req._setArgs(args);
        }
        // Add encrypted secrets URLs if they exist
        if (encryptedSecretsUrls.length > 0) {
            req._addSecretsReference(encryptedSecretsUrls);
        }

        s_lastRequestId = _sendRequest(
            req._encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );

        return s_lastRequestId;
    }

    function sendRequestWithSource(
        uint64 subscriptionId,
        string calldata sentSource,
        string[] calldata args
    ) external onlyOwner returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req._initializeRequestForInlineJavaScript(sentSource);
        // Add args if they exist
        if (args.length > 0) {
            req._setArgs(args);
        }
        // Add encrypted secrets URLs if they exist
        if (encryptedSecretsUrls.length > 0) {
            req._addSecretsReference(encryptedSecretsUrls);
        }

        s_lastRequestId = _sendRequest(
            req._encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );

        return s_lastRequestId;
    }

    function _fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        fulfillRequest(requestId, response, err);
    }

    /**
     * @notice Callback function for fulfilling a request
     * @param requestId The ID of the request to fulfill
     * @param response The HTTP response data
     * @param err Any errors from the Functions request
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal {
        if (s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId); // Check if request IDs match
        }
        s_lastResponse = response;
        s_lastError = err;

        // Decode the response as a UTF-8 string
        string memory result = string(response);

        // Soft-fail if result is "not_found" or empty or error signal
        if (
            bytes(result).length == 0 ||
            keccak256(bytes(result)) == keccak256("not_found")
        ) {
            // No state changes — soft fail
            s_gitbountyState = GitbountyState.READY;
            emit Response(requestId, response, err); // log anyway
            return;
        }

        // Lookup the winner address
        address winner = s_githubToAddress[result];

        // Soft-fail if unmapped
        if (winner == address(0)) {
            s_gitbountyState = GitbountyState.READY;
            emit Response(requestId, response, err); // log anyway
            return;
        }

        // Payout
        uint256 amount = s_totalFunding;

        // Send payout
        (bool success, ) = winner.call{value: amount}("");
        if (!success) revert Gitbounty__TransferFailed();

        s_lastWinner = winner;
        lastWinnerUser = result;
        last_repo_owner = repo_owner;
        last_repo = repo;
        last_issueNumber = issueNumber;
        last_BountyAmount = amount;

        // Clear bounty criteria
        repo_owner = "";
        repo = "";
        issueNumber = "";

        _resetContributions();

        // Update state
        s_gitbountyState = GitbountyState.PAID;

        emit BountyClaimed(winner, amount);
        emit Response(requestId, response, err);
    }
    
    function getLastResponse() external view returns(bytes memory lastResponse) {
        return s_lastResponse;
    }
}
