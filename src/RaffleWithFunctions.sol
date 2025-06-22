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

import {Raffle} from "./Raffle.sol";
import {FunctionsClient} from "@chainlink/v1/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/v1/../../../shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/v1/libraries/FunctionsRequest.sol";


/**
 * @title RaffleWithFunctions
 * @notice Extends the Raffle contract to include Chainlink Functions for external approval before winner selection.
 */
contract RaffleWithFunctions is FunctionsClient, Raffle {
    using FunctionsRequest for FunctionsRequest.Request;

    // State variables to store the last request ID, response, and error
    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;

    // Custom error type
    error UnexpectedRequestID(bytes32 requestId);

    // Event to log responses
    event Response(
        bytes32 indexed requestId,
        string character,
        bytes response,
        bytes err
    );

    address router;
    bytes32 donID;

    // JavaScript source code hardcoded
    // Fetch character name from the Star Wars API.
    // Documentation: https://swapi.info/people
    string source =
        "const characterId = args[0];"
        "const apiResponse = await Functions.makeHttpRequest({"
        "url: `https://swapi.info/api/people/${characterId}/`"
        "});"
        "if (apiResponse.error) {"
        "throw Error('Request failed');"
        "}"
        "const { data } = apiResponse;"
        "return Functions.encodeString(data.name);";

    //Callback gas limit
    uint32 gasLimit = 300000;
    // State variable to store the returned character information
    string public character;

    /**
     * @notice Initializes the contract with the Chainlink router address and sets the contract owner
     */
    constructor(
        uint256 _entranceFee,
        uint256 _interval,
        address _vrfCoordinator,
        bytes32 _gasLane,
        uint256 _subscriptionId,
        uint32 _callbackGasLimit,
        address _functionsOracle,
        bytes32 _donID
    )
        Raffle(_entranceFee, _interval, _vrfCoordinator, _gasLane, _subscriptionId, _callbackGasLimit)
        FunctionsClient(_functionsOracle)
    {
        router = _functionsOracle;
        donID = _donID;
    }

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
        // Update the contract's state variables with the response and any errors
        s_lastResponse = response;
        character = string(response);
        s_lastError = err;

        // Emit an event to log the response
        emit Response(requestId, character, s_lastResponse, s_lastError);
    }
    
    function getLastResponse() external view returns(bytes memory lastResponse) {
        return s_lastResponse;
    }

    /*function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        super.fulfillRandomWords(requestId, randomWords);
    }*/

}
