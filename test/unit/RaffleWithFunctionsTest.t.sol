// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffleWithFunctions} from "script/DeployRaffleWithFunctions.s.sol";
import {RaffleWithFunctions} from "../../src/RaffleWithFunctions.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockFunctionsOracle} from "../mocks/MockFunctionsOracle.sol";
import {CodeConstants, HelperConfig} from "script/HelperConfig.s.sol";

contract RaffleWithFunctionsTest is CodeConstants, Test {
    RaffleWithFunctions public raffle;
    HelperConfig public helperConfig;
    MockFunctionsOracle public mockRouter;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;
    address account;
    address functionsOracle;
    bytes32 donID;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() public {
        DeployRaffleWithFunctions deployer = new DeployRaffleWithFunctions();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;
        account = config.account;
        functionsOracle = config.functionsOracle;
        mockRouter = MockFunctionsOracle(functionsOracle);
        donID = config.donID;
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testCanRequestAndFulfill() public {
        // Arrange
        string[] memory args = new string[](1);
        args[0] = "true";

        vm.prank(account); // Optional if msg.sender must be custom
        bytes32 requestId = raffle.sendRequest(
            uint64(subscriptionId),
            args
        );

        // Simulate DON fulfillment
        bytes memory response = abi.encode("true");
        bytes memory error = "";

        mockRouter.fulfillRequest(requestId, response, error);

        // Optionally assert state change in raffle
        string memory decoded = abi.decode(raffle.getLastResponse(), (string));
        assertEq(decoded, "true");

    }

}