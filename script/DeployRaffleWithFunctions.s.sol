// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {RaffleWithFunctions} from "../src/RaffleWithFunctions.sol";
import {HelperConfig} from "./HelperConfig.s.sol";  // Adjust path if needed
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";
import {MockFunctionsOracle} from "test/mocks/MockFunctionsOracle.sol";

contract DeployRaffleWithFunctions is Script {
    function run() public {
        deployContract();
    }

    function deployContract() public returns (RaffleWithFunctions, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        // local -> deploy mocks, get local config
        // sepolia -> get sepolia config
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        if (config.subscriptionId == 0) {
            // create subscription
            CreateSubscription createSubscription = new CreateSubscription();
            (config.subscriptionId, config.vrfCoordinator) = createSubscription.createSubscription(config.vrfCoordinator, config.account);

            // fund subscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);
        }

        string memory script = vm.readFile("script.js");

        vm.startBroadcast(config.account);
        RaffleWithFunctions raffle = new RaffleWithFunctions(
            config.interval,
            config.functionsOracle,
            config.donID,
            config.functionsSubscriptionId,
            script
        );
        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();
        // don't need to broadcast this here, because we broadcast inside the consumer contract 'addConsumer'
        addConsumer.addConsumer(address(raffle), config.vrfCoordinator, config.subscriptionId, config.account);

        return (raffle, helperConfig);
    }

}