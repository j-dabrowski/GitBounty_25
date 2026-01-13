// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {GitbountyFactory} from "../src/GitbountyFactory.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract CreateBountyFromFactory is Script {
    error MissingFactoryAddress();

    function run() external returns (address bountyAddr) {
        HelperConfig helper = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helper.getConfig();

        address factoryAddr = vm.envOr("FACTORY_ADDRESS", address(0));
        if (factoryAddr == address(0)) revert MissingFactoryAddress();

        vm.startBroadcast(cfg.account);
        bountyAddr = GitbountyFactory(factoryAddr).createBounty();
        vm.stopBroadcast();

        console2.log("Factory:", factoryAddr);
        console2.log("NewBounty:", bountyAddr);
    }
}
