// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {Gitbounty} from "../src/Gitbounty.sol";
import {HelperConfig} from "./HelperConfig.s.sol";  // Adjust path if needed
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";
import {MockFunctionsOracle} from "test/mocks/MockFunctionsOracle.sol";

contract DeployGitbounty is Script {
    function run() public {
        deployContract();
    }

    function deployContract() public returns (Gitbounty, HelperConfig) {
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

        // check request_gitbounty - secretsManager gets imported via chainlink/functions-toolkit
        // get unencrypted secrets URL from helperconfig, then encrypt it here via secretsManager
        // then pass encrypted secret to the new contract constructor

        vm.startBroadcast(config.account);
        Gitbounty gitbounty = new Gitbounty(
            config.interval,
            config.functionsOracle,
            config.donID,
            config.functionsSubscriptionId,
            script,
            config.encryptedSecretsUrls
        );
        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();
        // don't need to broadcast this here, because we broadcast inside the consumer contract 'addConsumer'
        addConsumer.addConsumer(address(gitbounty), config.vrfCoordinator, config.subscriptionId, config.account);

        return (gitbounty, helperConfig);
    }

}