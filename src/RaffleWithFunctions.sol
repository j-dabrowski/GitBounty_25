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

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Raffle} from "./Raffle.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_X/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_X/libraries/FunctionsRequest.sol";

/**
 * @title RaffleWithFunctions
 * @notice Extends the Raffle contract to include Chainlink Functions for external approval before winner selection.
 */
contract RaffleWithFunctions is Raffle, FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    // --- State ---
    string public s_latestResult;
    bytes public s_latestResponse;
    bytes public s_latestError;
    bool public s_externalApproval;
    address private immutable i_functionsOracle;
    bytes32 private immutable i_donID;

    // --- Events ---
    event ChainlinkFunctionsRequestSent(bytes32 indexed requestId);
    event ChainlinkFunctionsResponse(bytes result, bytes err);

    constructor(
        address functionsOracle,
        bytes32 donID,
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    )
        Raffle(entranceFee, interval, vrfCoordinator, gasLane, subscriptionId, callbackGasLimit)
        FunctionsClient(functionsOracle)
    {
        i_functionsOracle = functionsOracle;
        i_donID = donID;
    }

    // --- Chainlink Functions Request Trigger ---
    function requestExternalApproval(string calldata source, string[] calldata args) external {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        if (args.length > 0) {
            req.setArgs(args);
        }
        bytes32 assignedReqID = _sendRequest(
            req.encodeCBOR(),
            i_donID,
            200_000, // gas limit for fulfillment
            0         // no upfront payment
        );
        emit ChainlinkFunctionsRequestSent(assignedReqID);
    }

    // --- Chainlink Functions Fulfillment ---
    function fulfillRequest(
        bytes32, /* requestId */
        bytes memory response,
        bytes memory err
    ) internal override {
        s_latestResponse = response;
        s_latestError = err;
        s_latestResult = string(response);
        s_externalApproval = keccak256(response) == keccak256(abi.encodePacked("true"));
        emit ChainlinkFunctionsResponse(response, err);
    }

    // --- Override winner logic to depend on approval ---
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override(Raffle) {
        require(s_externalApproval, "External approval required");
        super.fulfillRandomWords(requestId, randomWords);
    }
}
