// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FunctionsClient} from "@chainlink/v1/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/v1/libraries/FunctionsRequest.sol";


/**
 * @title RaffleWithFunctions
 * @notice Extends the Raffle contract to include Chainlink Functions for external approval before winner selection.
 */
contract RaffleWithFunctions is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

    /* Errors */
    error Raffle__SendNonZeroEth();
    error Raffle__NoFundToWithdraw();
    error Raffle__NoAddressMappedToUsername(string username);
    error UnexpectedRequestID(bytes32 requestId);
    // Raffle errors below
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 numberOfFunders, uint256 raffleState);

    /* type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    // Functions State variables
    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;
    // Payment Record Keeping
    address private s_lastWinner;
    uint256 private s_lastTimeStamp;
    /* state variables */
    // Funding
    mapping(string => address) private s_githubToAddress;
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
    RaffleState private s_raffleState; // start as open
    // Other
    address router;
    bytes32 donID;
    uint64 public functionsSubId;
    // Callback gas limit
    uint32 gasLimit = 300000;

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

    // JavaScript source code hardcoded
    // Fetch character name from the Star Wars API.
    // Documentation: https://swapi.info/people
    string source =
        "try {"
        "await Functions.makeHttpRequest({"
        "url: \"https://example.com/invalid-or-unreliable-url\""
        "});"
        "} catch (e) {"
        "// Swallow all errors"
        "}"

        "// Always return true"
        "return Functions.encodeString(true);";

    /**
     * @notice Initializes the contract with the Chainlink router address and sets the contract owner
     */
    constructor(
        uint256 _interval,
        address _functionsOracle,
        bytes32 _donID,
        uint64 _functionsSubId
    )
        FunctionsClient(_functionsOracle)
        ConfirmedOwner(msg.sender)
    {
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
        i_interval = _interval;
        router = _functionsOracle;
        donID = _donID;
        functionsSubId = _functionsSubId;
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
            revert Raffle__SendNonZeroEth();
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
            revert Raffle__NoFundToWithdraw(); // Define this error
        }

        s_contributions[msg.sender] = 0;
        s_totalFunding -= amount;
        s_funderCount--;

        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        
        emit BountyFundWithdrawn(msg.sender, amount);
    }

    function createAndFundBounty(
        string calldata _owner,
        string calldata _repo,
        string calldata _issue
    ) external payable onlyOwner {
        setBountyCriteria(_owner, _repo, _issue);
        _fundBounty(msg.sender, msg.value);
    }

    function mapGithubUsernameToAddress(string calldata username) external {
        require(bytes(username).length > 0, "Username required");
        require(s_githubToAddress[username] == address(0), "Username already mapped");

        s_githubToAddress[username] = msg.sender;

        emit GithubUserMapped(username, msg.sender);
    }


    // When should the winer be picked?
    /**
     * This is the function that the Chainlink nodes will call to see
     * if the lottery is ready to have a winner picked.
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed between raffle runs
     * 2. The lottery is open
     * 3. The contract has ETH (has players)
     * 4. Implicitly, your subscription has LINK
     * @param - ignored
     * @return upkeepNeeded - true if it's time to restart the lottery
     * @return - ignored
     */
    function checkUpkeep(bytes memory /* checkData */) public view 
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasFunders = s_funderCount > 0;
        bool hasBountyCriteria = bytes(repo_owner).length > 0 && bytes(repo).length > 0 && bytes(issueNumber).length > 0;

        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasFunders && hasBountyCriteria;
        return (upkeepNeeded, "");
    }

    // 1. Get a random number
    // 2. Use a random number to pick a player
    // 3. Be automatically called
    function performUpkeep(bytes calldata /* performData */ ) external {
        // Checks
        // check if enough time has passed
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_funderCount, uint256(s_raffleState));
        }
        s_raffleState = RaffleState.CALCULATING;
        
        // === Prepare Request Arguments ===
        string[] memory args = new string[](3);
        args[0] = repo_owner;
        args[1] = repo;
        args[2] = issueNumber;

        FunctionsRequest.Request memory req;
        req._initializeRequestForInlineJavaScript(source);
        if (args.length > 0) {
            req._setArgs(args);
        }

        s_lastRequestId = _sendRequest(
            req._encodeCBOR(),
            functionsSubId,
            gasLimit,
            donID
        );
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
    function getRaffleState() external view returns(RaffleState) {
        return s_raffleState;
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
     * @notice Sends an HTTP request for character information
     * @param subscriptionId The ID for the Chainlink subscription
     * @param args The arguments to pass to the HTTP request
     * @return requestId The ID of the request
     */
    function sendRequest(
        uint64 subscriptionId,
        string[] calldata args
    ) external onlyOwner returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req._initializeRequestForInlineJavaScript(source);
        if (args.length > 0) {
            req._setArgs(args);
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
        if (args.length > 0) {
            req._setArgs(args);
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
            emit Response(requestId, response, err); // log anyway
            return;
        }

        // Lookup the winner address
        address winner = s_githubToAddress[result];

        // Soft-fail if unmapped
        if (winner == address(0)) {
            emit Response(requestId, response, err); // log anyway
            return;
        }

        // Payout
        uint256 amount = s_totalFunding;
        _resetContributions();

        // Clear bounty criteria
        repo_owner = "";
        repo = "";
        issueNumber = "";

        // Reset state
        s_raffleState = RaffleState.OPEN;

        // Send payout
        (bool success, ) = winner.call{value: amount}("");
        if (!success) revert Raffle__TransferFailed();

        s_lastWinner = winner;

        emit BountyClaimed(winner, amount);
        emit Response(requestId, response, err);
    }
    
    function getLastResponse() external view returns(bytes memory lastResponse) {
        return s_lastResponse;
    }
}
