// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {Gitbounty} from "../src/Gitbounty.sol";

contract DeployGitbountyImpl is Script {
    function run() external returns (Gitbounty implementation) {
        vm.startBroadcast();
        // Deploy the implementation once (EIP-1167 clones will point at this)
        implementation = new Gitbounty();
        vm.stopBroadcast();

        console2.log("Gitbounty implementation:", address(implementation));
        console2.log("Set it as GITBOUNTY_IMPL in .env");
    }
}
