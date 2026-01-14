// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {GitbountyFactory} from "../src/GitbountyFactory.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract CreateBountyFromFactory is Script {
    error MissingFactoryAddress();
    error MissingRepoOwner();
    error MissingRepo();
    error MissingIssueNumber();
    error MissingBountyAmount();

    function run() external returns (address bountyAddr) {
        HelperConfig helper = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helper.getConfig();

        address factoryAddr = vm.envOr("FACTORY_ADDRESS", address(0));
        if (factoryAddr == address(0)) revert MissingFactoryAddress();

        // Required args
        string memory repoOwner = vm.envOr("REPO_OWNER", string(""));
        if (bytes(repoOwner).length == 0) revert MissingRepoOwner();

        string memory repo = vm.envOr("REPO", string(""));
        if (bytes(repo).length == 0) revert MissingRepo();

        string memory issueNumber = vm.envOr("ISSUE_NUMBER", string(""));
        if (bytes(issueNumber).length == 0) revert MissingIssueNumber();

        // Funding
        // Prefer an explicit env var so you don't accidentally create $0 bounties.
        // You can set it like: BOUNTY_VALUE=10000000000000000 (0.01 ether)
        uint256 amountWei = vm.envOr("BOUNTY_VALUE", uint256(0));
        if (amountWei == 0) {
            // default to 0.01 ether if not provided
            amountWei = 0.001 ether;
        }
        if (amountWei == 0) revert MissingBountyAmount();

        vm.startBroadcast(cfg.account);

        bountyAddr = GitbountyFactory(factoryAddr).createBounty{value: amountWei}(
            repoOwner,
            repo,
            issueNumber
        );

        vm.stopBroadcast();

        console2.log("Factory:", factoryAddr);
        console2.log("NewBounty:", bountyAddr);
        console2.log("RepoOwner:", repoOwner);
        console2.log("Repo:", repo);
        console2.log("Issue:", issueNumber);
        console2.log("Amount (wei):", amountWei);
    }
}
