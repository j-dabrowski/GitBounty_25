// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FunctionsResponse} from "@chainlink/v1/libraries/FunctionsResponse.sol";

contract MockFunctionsOracle {
    bytes32 public lastRequestId;
    address public lastRequester;
    mapping(bytes32 => address) public requestToClient;

    event RequestSent(bytes32 indexed requestId, address indexed requester);
    event RequestFulfilled(bytes32 indexed requestId, bytes response, bytes error);

    /// @notice Mocks sending a request via Chainlink Functions
    function sendRequest(
        uint64,            // subscriptionId
        bytes calldata,    // data
        uint16,            // dataVersion
        uint32,            // callbackGasLimit
        bytes32            // donId
    ) external returns (bytes32 requestId) {
        requestId = keccak256(abi.encodePacked(block.timestamp, msg.sender));
        lastRequestId = requestId;
        lastRequester = msg.sender;
        requestToClient[requestId] = msg.sender;

        emit RequestSent(requestId, msg.sender);
    }

    /// @notice Simulate DON fulfilling a request
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory error
    ) public {
        address client = requestToClient[requestId];
        require(client != address(0), "Unknown request ID");

        (bool success, ) = client.call(
            abi.encodeWithSignature(
                "handleOracleFulfillment(bytes32,bytes,bytes)",
                requestId,
                response,
                error
            )
        );

        require(success, "Fulfillment failed");

        emit RequestFulfilled(requestId, response, error);
    }
}

