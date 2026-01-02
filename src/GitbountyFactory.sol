// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * GitbountyFactory
 * - ONE Chainlink Automation upkeep (checkUpkeep/performUpkeep) for ALL bounties
 * - ONE Chainlink Functions client (factory) for ALL Functions requests
 * - Bounties "phone home" by being registered; factory schedules retries (e.g., daily)
 * - Request routing: requestId => bounty
 *
 * Assumptions / expectations for child bounties:
 *  - They expose getArgs() returning (owner, repo, issueNumber)
 *  - They accept onFunctionsFulfilled(requestId, response, err) ONLY from this factory
 *  - They will soft-fail / keep open when response is "not_found" or unmapped
 */

import {FunctionsClient} from "@chainlink/v1/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/v1/libraries/FunctionsRequest.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

// Chainlink Automation interface (a.k.a. Keepers)
import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

interface IGitbountyChild {
    /// @notice Return repo args needed by Functions source
    function getArgs() external view returns (string memory repoOwner, string memory repo, string memory issueNumber);

    // @notice Called by the factory on the child bounty to mark it as calculating (functions request in progress)
    function markCalculating(bytes32 requestId) external;

    /// @notice Called by factory when Functions fulfills.
    function onFunctionsFulfilled(bytes32 requestId, address winner, bytes calldata response, bytes calldata err) external;

    /// @notice Check if the bounty is ready
    function isBountyReady() external view returns (bool);
}

/**
 * Minimal LINK interface for optional funding helpers (if you want on-chain top-ups).
 * Not required for core scheduling/request routing.
 */
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferAndCall(address to, uint256 amount, bytes calldata data) external returns (bool);
}

contract GitbountyFactory is FunctionsClient, AutomationCompatibleInterface, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error NotRegisteredBounty(address bounty);
    error UnknownRequest(bytes32 requestId);
    error InvalidBounty(address bounty);
    error NoBounties();
    error InsufficientCredits(address bounty, uint256 needed, uint256 have);
    error GitbountyFactory__UsernameAlreadyMapped();
    error OnlySelf();

    /*//////////////////////////////////////////////////////////////
                             FUNCTIONS CONFIG
    //////////////////////////////////////////////////////////////*/
    bytes32 public donID;
    uint64 public functionsSubId;
    uint32 public callbackGasLimit;
    string public source;                 // inline JS source
    bytes public encryptedSecretsUrls;    // optional secrets reference

    /*//////////////////////////////////////////////////////////////
                              AUTOMATION CONFIG
    //////////////////////////////////////////////////////////////*/
    uint256 public retryInterval = 1 days;

    // Bound scan work so upkeep doesn't run out of gas.
    uint256 public maxScan = 50;
    uint256 public maxPerform = 1;

    // Round-robin scanning cursor
    uint256 public scanIndex;

    /*//////////////////////////////////////////////////////////////
                          USERNAME - ADDRESS REGISTRY
    //////////////////////////////////////////////////////////////*/
    mapping(string => address) private s_githubToAddress;
    string[] private usernames;

    /*//////////////////////////////////////////////////////////////
                           BOUNTY REGISTRY / STATE
    //////////////////////////////////////////////////////////////*/
    address[] public bounties;
    mapping(address => bool) public isRegistered;

    // Scheduling
    mapping(address => bool) public isOpen;          // factory's view of open/closed
    mapping(address => uint256) public nextAttemptAt;
    mapping(address => bool) public inFlight;

    // Per-bounty credits (you can denominate in ETH/wei, or treat as "internal credits")
    mapping(address => uint256) public creditsWei;
    uint256 public attemptFeeWei = 0; // set to nonzero if you want users to prepay "retry budget"

    /*//////////////////////////////////////////////////////////////
                               REQUEST ROUTING
    //////////////////////////////////////////////////////////////*/
    mapping(bytes32 => address) public requestToBounty;
    mapping(address => bytes32) public lastRequestForBounty;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event BountyRegistered(address indexed bounty);
    event BountyClosed(address indexed bounty);
    event BountyOpened(address indexed bounty);

    event GithubUserMapped(string indexed username, address indexed userAddress);

    event CreditsDeposited(address indexed bounty, address indexed payer, uint256 amountWei);
    event AttemptFeeUpdated(uint256 newAttemptFeeWei);

    event FactoryConfigUpdated(bytes32 donID, uint64 subId, uint32 callbackGasLimit);
    event SourceUpdated();
    event SecretsUpdated();

    event RequestSent(bytes32 indexed requestId, address indexed bounty);
    event RequestForwarded(bytes32 indexed requestId, address indexed bounty);

    event UpkeepSelected(uint256 indexed at, address[] selected);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address functionsRouter,
        bytes32 _donID,
        uint64 _subId,
        uint32 _callbackGasLimit,
        string memory _source,
        bytes memory _encryptedSecretsUrls
    ) FunctionsClient(functionsRouter) ConfirmedOwner(msg.sender) {
        donID = _donID;
        functionsSubId = _subId;
        callbackGasLimit = _callbackGasLimit;
        source = _source;
        encryptedSecretsUrls = _encryptedSecretsUrls;

        emit FactoryConfigUpdated(donID, functionsSubId, callbackGasLimit);
        emit SourceUpdated();
        emit SecretsUpdated();
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN: REGISTER / OPEN / CLOSE
    //////////////////////////////////////////////////////////////*/
    function registerBounty(address bounty) external onlyOwner {
        if (bounty == address(0)) revert InvalidBounty(bounty);
        if (isRegistered[bounty]) return;

        // optional sanity check: does it look like a child?
        // will revert if functions not present
        IGitbountyChild(bounty).getArgs();

        isRegistered[bounty] = true;
        bounties.push(bounty);

        // start open by default
        isOpen[bounty] = true;
        nextAttemptAt[bounty] = block.timestamp; // eligible immediately (but you can set +retryInterval)
        inFlight[bounty] = false;

        emit BountyRegistered(bounty);
        emit BountyOpened(bounty);
    }

    /// @notice Owner can mark a bounty closed to stop retries (child can also call this if you want).
    function closeBounty(address bounty) external onlyOwner {
        if (!isRegistered[bounty]) revert NotRegisteredBounty(bounty);
        isOpen[bounty] = false;
        emit BountyClosed(bounty);
    }

    function openBounty(address bounty) external onlyOwner {
        if (!isRegistered[bounty]) revert NotRegisteredBounty(bounty);
        isOpen[bounty] = true;
        if (nextAttemptAt[bounty] < block.timestamp) nextAttemptAt[bounty] = block.timestamp;
        emit BountyOpened(bounty);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN: GITHUB USERNAME - ADDRESS REGISTRY
    //////////////////////////////////////////////////////////////*/
    function mapGithubUsernameToAddress(string calldata username) external {
        require(bytes(username).length > 0, "Username required");
        if (s_githubToAddress[username] != address(0)) revert GitbountyFactory__UsernameAlreadyMapped();

        s_githubToAddress[username] = msg.sender;
        usernames.push(username);

        emit GithubUserMapped(username, msg.sender);
    }
    
    function resetGithubUserMapping() external onlyOwner {
        // Clear GitHub username mappings
        for (uint256 i = 0; i < usernames.length; i++) {
            delete s_githubToAddress[usernames[i]];
        }
        delete usernames;
    }

    function getAddressFromUsername(string calldata username) external view returns (address) {
        return s_githubToAddress[username];
    }

    /*//////////////////////////////////////////////////////////////
                          USER FUNDING (CREDITS)
    //////////////////////////////////////////////////////////////*/
    /// @notice Anyone can deposit ETH credits for a specific bounty's future attempts.
    function depositCredits(address bounty) external payable {
        if (!isRegistered[bounty]) revert NotRegisteredBounty(bounty);
        creditsWei[bounty] += msg.value;
        emit CreditsDeposited(bounty, msg.sender, msg.value);
    }

    /// @notice Optional: set attempt fee; if >0, each scheduled attempt debits creditsWei[bounty].
    function setAttemptFeeWei(uint256 newFeeWei) external onlyOwner {
        attemptFeeWei = newFeeWei;
        emit AttemptFeeUpdated(newFeeWei);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN: CONFIG SETTERS
    //////////////////////////////////////////////////////////////*/
    function setFunctionsConfig(bytes32 _donID, uint64 _subId, uint32 _callbackGasLimit) external onlyOwner {
        donID = _donID;
        functionsSubId = _subId;
        callbackGasLimit = _callbackGasLimit;
        emit FactoryConfigUpdated(donID, functionsSubId, callbackGasLimit);
    }

    function setSource(string calldata newSource) external onlyOwner {
        source = newSource;
        emit SourceUpdated();
    }

    function setSecrets(bytes calldata newEncryptedSecretsUrls) external onlyOwner {
        encryptedSecretsUrls = newEncryptedSecretsUrls;
        emit SecretsUpdated();
    }

    function setAutomationParams(uint256 _retryInterval, uint256 _maxScan, uint256 _maxPerform) external onlyOwner {
        retryInterval = _retryInterval;
        maxScan = _maxScan;
        maxPerform = _maxPerform;
    }

    /*//////////////////////////////////////////////////////////////
                        ELIGIBILITY (INTERNAL VIEW)
    //////////////////////////////////////////////////////////////*/
    function _eligible(address bounty) internal view returns (bool) {
        if (!isOpen[bounty]) return false;
        if (inFlight[bounty]) return false;
        if (block.timestamp < nextAttemptAt[bounty]) return false;

        // if you want the factory to also consult the child cheaply:
        // (optional) ensures the child also thinks it's open
        if (!IGitbountyChild(bounty).isBountyReady()) return false;

        if (attemptFeeWei > 0 && creditsWei[bounty] < attemptFeeWei) return false;

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                          CHAINLINK AUTOMATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Finds up to maxPerform eligible bounties by scanning up to maxScan entries.
    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 n = bounties.length;
        if (n == 0) return (false, "");

        address[] memory selected = new address[](maxPerform);
        uint256 found = 0;

        uint256 start = scanIndex;
        uint256 scans = maxScan;
        if (scans > n) scans = n;

        for (uint256 i = 0; i < scans; i++) {
            address bounty = bounties[(start + i) % n];
            if (_eligible(bounty)) {
                selected[found] = bounty;
                found++;
                if (found == maxPerform) break;
            }
        }

        if (found == 0) return (false, "");

        // shrink array to found length
        address[] memory trimmed = new address[](found);
        for (uint256 j = 0; j < found; j++) trimmed[j] = selected[j];

        upkeepNeeded = true;
        performData = abi.encode(trimmed);
    }

    /// @notice Executes scheduled attempts and sends Functions requests via this factory.
    function performUpkeep(bytes calldata performData) external override {
        address[] memory selected = abi.decode(performData, (address[]));
        uint256 n = bounties.length;
        if (n == 0) revert NoBounties();

        // advance scanIndex roughly (so we round-robin even if performData is replayed)
        scanIndex = (scanIndex + selected.length) % n;

        emit UpkeepSelected(block.timestamp, selected);

        for (uint256 i = 0; i < selected.length; i++) {
            address bounty = selected[i];

            // Re-check eligibility (always do this; performData can be stale)
            if (!isRegistered[bounty]) continue;
            if (!_eligible(bounty)) continue;

            // ---- build args first (no state changes yet) ----
            (string memory repoOwner, string memory repo, string memory issueNumber) =
                IGitbountyChild(bounty).getArgs();

            if (bytes(repoOwner).length == 0 || bytes(repo).length == 0 || bytes(issueNumber).length == 0) {
                continue;
            }

            string[] memory args = new string[](3);
            args[0] = repoOwner;
            args[1] = repo;
            args[2] = issueNumber;

            // ---- attempt fee: ONLY commit if we successfully send+mark ----
            uint256 fee = attemptFeeWei;
            if (fee > 0 && creditsWei[bounty] < fee) {
                continue; // don't revert the entire upkeep; just skip
            }

            // ---- try/catch SEND (self-call wrapper) ----
            bytes32 requestId;
            try this._sendFunctionsRequestExternal(args) returns (bytes32 rid) {
                requestId = rid;
            } catch {
                // nothing committed yet, so just skip
                continue;
            }

            // ---- NOW commit scheduling state (only after we have requestId) ----
            nextAttemptAt[bounty] = block.timestamp + retryInterval;
            inFlight[bounty] = true;

            // ---- commit routing BEFORE external child call ----
            requestToBounty[requestId] = bounty;

            // ---- debit fee AFTER we know the request exists + routing set ----
            if (fee > 0) {
                creditsWei[bounty] -= fee;
            }

            // ---- try/catch child markCalculating ----
            try IGitbountyChild(bounty).markCalculating(requestId) {
                // ---- Save last request ID ----
                lastRequestForBounty[bounty] = requestId;
            } catch {
                // UNDO everything we just committed
                if (fee > 0) creditsWei[bounty] += fee;
                delete requestToBounty[requestId];
                inFlight[bounty] = false;
                nextAttemptAt[bounty] = block.timestamp;
                continue;
            }

            emit RequestSent(requestId, bounty);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          CHAINLINK FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _sendFunctionsRequest(string[] memory args) internal returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req._initializeRequestForInlineJavaScript(source);

        if (args.length > 0) req._setArgs(args);
        if (encryptedSecretsUrls.length > 0) req._addSecretsReference(encryptedSecretsUrls);

        requestId = _sendRequest(req._encodeCBOR(), functionsSubId, callbackGasLimit, donID);
    }

    /// @notice Functions callback lands here (factory is the only FunctionsClient).
    function _fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        address bounty = requestToBounty[requestId];
        if (bounty == address(0)) revert UnknownRequest(requestId);

        // Decode the response as a UTF-8 string
        string memory result = string(response);
        // Lookup the winner address
        address winner = s_githubToAddress[result];

        // Forward to child FIRST. If the child reverts, we revert the whole callback so the request isn't lost.
        // After a successful forward, clear routing + unlock inFlight.
        IGitbountyChild(bounty).onFunctionsFulfilled(requestId, winner, response, err);

        // ONLY AFTER successful forward: clear routing + inFlight
        delete requestToBounty[requestId];
        inFlight[bounty] = false;
        if (lastRequestForBounty[bounty] == requestId) lastRequestForBounty[bounty] = bytes32(0);

        emit RequestForwarded(requestId, bounty);
    }

    function _sendFunctionsRequestExternal(string[] calldata args) external returns (bytes32) {
        if (msg.sender != address(this)) revert OnlySelf();
        return _sendFunctionsRequest(args);
    }

    /*//////////////////////////////////////////////////////////////
                              OPTIONAL HELPERS
    //////////////////////////////////////////////////////////////*/
    function bountyCount() external view returns (uint256) {
        return bounties.length;
    }

    function dropRequest(bytes32 requestId) public onlyOwner {
        address bounty = requestToBounty[requestId];
        delete requestToBounty[requestId];

        if (bounty != address(0)) {
            if (lastRequestForBounty[bounty] == requestId) {
                lastRequestForBounty[bounty] = bytes32(0);
            }
            inFlight[bounty] = false;
            nextAttemptAt[bounty] = block.timestamp; // retry ASAP
        }
    }

    function dropLastRequestForBounty(address bounty) external onlyOwner {
        bytes32 rid = lastRequestForBounty[bounty];
        if (rid != bytes32(0)) dropRequest(rid);
        else {
            inFlight[bounty] = false;
            nextAttemptAt[bounty] = block.timestamp;
        }
    }

    /*//////////////////////////////////////////////////////////////
                      OPTIONAL: FUNDING GLOBAL UPKEEP/SUB
    //////////////////////////////////////////////////////////////*/
    // These are OPTIONAL convenience functions. Whether they work depends on the exact network + registry/subscription manager.
    // You can remove them if you want to keep this contract minimal.

    IERC20 public linkToken;
    address public automationRegistry;
    uint256 public automationUpkeepId;

    function setLinkAndAutomation(address _link, address _registry, uint256 _upkeepId) external onlyOwner {
        linkToken = IERC20(_link);
        automationRegistry = _registry;
        automationUpkeepId = _upkeepId;
    }

    /// @notice Fund the single Automation upkeep (requires LINK token + registry supporting transferAndCall funding).
    function fundAutomationUpkeep(uint256 linkAmount) external onlyOwner {
        // data format is registry-specific; many registries accept abi.encode(upkeepId)
        bytes memory data = abi.encode(automationUpkeepId);
        linkToken.transferAndCall(automationRegistry, linkAmount, data);
    }
}
