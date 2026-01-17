// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {GitbountyFactory} from "../src/GitbountyFactory.sol";

contract DeployGitbountyFactory is Script {
    /*//////////////////////////////////////////////////////////////
                        ERRORS
    //////////////////////////////////////////////////////////////*/
    error DeployGitbountyFactory__MissingConfig();
    error DeployGitbountyFactory__EmptyConfigFile(string path);
    error DeployGitbountyFactory__EmptyEncryptedSecretsUrls();
    error DeployGitbountyFactory__ZeroImplementationAddress();
    error DeployGitbountyFactory__EmptyFunctionsSource();

    function run() external returns (GitbountyFactory factory) {

        /*//////////////////////////////////////////////////////////////
                        GET CONFIG VALUES
        //////////////////////////////////////////////////////////////*/

        // Chain-specific config values (ETH-SEPOLIA hardcoded)
        string memory config = vm.readFile("config/eth-sepolia.json"); // local: "config/anvil.json"
        if (bytes(config).length == 0) revert DeployGitbountyFactory__MissingConfig();

        address functionsRouter = vm.parseJsonAddress(config, ".functionsRouter");
        bytes32 donID = vm.parseJsonBytes32(config, ".donID");
        uint64 functionsSubscriptionId = uint64(vm.parseJsonUint(config, ".functionsSubscriptionId"));
        uint32 callbackGasLimit = uint32(vm.parseJsonUint(config, ".callbackGasLimit"));

        // Encrypted Secrets Url (URL-hosted secrets model)
        string memory encSecretsUrlsJson = vm.readFile("offchain/encrypted-secrets-urls.sepolia.json");
        bytes memory encryptedSecretsUrls = vm.parseJsonBytes(encSecretsUrlsJson, ".encryptedSecretsUrls");
        if (encryptedSecretsUrls.length == 0) revert DeployGitbountyFactory__EmptyEncryptedSecretsUrls();
        
        // Javascript source script for CL Functions
        string memory source = vm.readFile("script.js");
        if (bytes(source).length == 0) revert DeployGitbountyFactory__EmptyFunctionsSource();

        // Gitbounty Implementation address
        address impl = vm.envAddress("GITBOUNTY_IMPL");
        if (impl == address(0)) revert DeployGitbountyFactory__ZeroImplementationAddress();

        /*//////////////////////////////////////////////////////////////
                        BROADCAST CONTRACT DEPLOYMENT
        //////////////////////////////////////////////////////////////*/

        vm.startBroadcast();
        factory = new GitbountyFactory(
            impl,
            functionsRouter,
            donID,
            functionsSubscriptionId,
            callbackGasLimit,
            source,
            encryptedSecretsUrls
        );
        vm.stopBroadcast();

        console2.log("Factory:", address(factory));
    }
}
