// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {GitbountyFactory} from "../src/GitbountyFactory.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployGitbountyFactory is Script {
    function run() external returns (GitbountyFactory factory, HelperConfig helperConfig) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // Your Chainlink Functions source (JS)
        string memory source = vm.readFile("script.js");

        vm.startBroadcast(config.account);

        // NOTE: HelperConfig calls this functionsOracle, but GitbountyFactory expects the Functions ROUTER address.
        // In your config, functionsOracle is currently used as the router address (MockFunctionsOracle locally, router on Sepolia).
        factory = new GitbountyFactory(
            config.functionsOracle,
            config.donID,
            config.functionsSubscriptionId,
            config.callbackGasLimit,
            source,
            config.encryptedSecretsUrls
        );

        vm.stopBroadcast();

        console2.log("GitbountyFactory deployed at:", address(factory));
        console2.log("Deployer/account:", config.account);
        console2.logBytes32(config.donID);
        console2.log("Functions subId:", uint256(config.functionsSubscriptionId));
        console2.log("Callback gas limit:", uint256(config.callbackGasLimit));
    }
}
