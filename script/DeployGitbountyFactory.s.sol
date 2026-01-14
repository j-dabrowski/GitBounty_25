// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {GitbountyFactory} from "../src/GitbountyFactory.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployGitbountyFactory is Script {
    function run() external returns (GitbountyFactory factory) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        address impl = vm.envAddress("GITBOUNTY_IMPL"); // <-- set in .env

        string memory source = vm.readFile("script.js");

        vm.startBroadcast(config.account);
        factory = new GitbountyFactory(
            impl,
            config.functionsRouter,
            config.donID,
            config.functionsSubscriptionId,
            config.callbackGasLimit,
            source,
            config.encryptedSecretsUrls
        );
        vm.stopBroadcast();

        console2.log("Factory:", address(factory));
    }
}
