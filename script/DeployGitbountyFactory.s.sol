// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {GitbountyFactory} from "../src/GitbountyFactory.sol";
import {Gitbounty} from "../src/Gitbounty.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployGitbountyFactory is Script {
    function run() external returns (GitbountyFactory factory, HelperConfig helperConfig) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // Your Chainlink Functions source (JS)
        string memory source = vm.readFile("script.js");

        vm.startBroadcast(config.account);

        // 1) Deploy the implementation once (EIP-1167 clones will point at this)
        Gitbounty implementation = new Gitbounty();

        // 2) Deploy the factory with implementation + Functions router (your config.functionsOracle is acting as router)
        factory = new GitbountyFactory(
            address(implementation),
            config.functionsRouter, // Functions ROUTER
            config.donID,
            config.functionsSubscriptionId, // uint64
            config.callbackGasLimit, // uint32
            source,
            config.encryptedSecretsUrls
        );

        vm.stopBroadcast();

        console2.log("Gitbounty implementation deployed at:", address(implementation));
        console2.log("GitbountyFactory deployed at:", address(factory));
        console2.log("Deployer/account:", config.account);
        console2.logBytes32(config.donID);
        console2.log("Functions subId:", uint256(config.functionsSubscriptionId));
        console2.log("Callback gas limit:", uint256(config.callbackGasLimit));
    }
}
