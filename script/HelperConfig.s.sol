// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {MockFunctionsOracle} from "test/mocks/MockFunctionsOracle.sol";

abstract contract CodeConstants {
    // VRF Mock Values
    uint96 public MOCK_BASE_FEE = 0.25 ether;
    uint96 public MOCK_GAS_PRICE_LINK = 1e9;
    // LINK / ETH price
    int256 public MOCK_WEI_PER_UINT_LINK = 4e15;

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();
    error HelperConfig__MissingEncryptedSecretsUrlsArtifact();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint32 callbackGasLimit;
        uint256 subscriptionId;
        uint64 functionsSubscriptionId;
        address link;
        address account;
        address functionsOracle;
        bytes32 donID;

        // S3/URL-hosted secrets model
        // This is the encrypted URL blob produced by SecretsManager.encryptSecretsUrls([url]).
        bytes encryptedSecretsUrls;
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    // Cache parsed sepolia encryptedSecretsUrls
    bytes private s_sepoliaEncryptedSecretsUrls;

    constructor() {
    // Only load encrypted secrets when deploying to Sepolia
        if (block.chainid == ETH_SEPOLIA_CHAIN_ID) {
            string memory artifactPath = vm.envOr(
                "ENCRYPTED_SECRETS_URLS_PATH",
                string("offchain/encrypted-secrets-urls.sepolia.json")
            );

            string memory json = vm.readFile(artifactPath);

            bytes memory enc = vm.parseJsonBytes(json, ".encryptedSecretsUrls");
            if (enc.length == 0) revert HelperConfig__MissingEncryptedSecretsUrlsArtifact();

            s_sepoliaEncryptedSecretsUrls = enc;
        }
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].vrfCoordinator != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entranceFee: 0.01 ether, // 1e16
            interval: 30, // 30 seconds
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            callbackGasLimit: 500000,
            subscriptionId: 5678636918962447571903646274118619275519362353888589824932531789175201713390,
            functionsSubscriptionId: 5133,
            link: 0x6641415a61bCe80D97a715054d1334360Ab833Eb,
            account: 0x030C29e1B5D2A2Faf23A4ec51D0351B4e7431293, // burner account address on eth-sepolia (with testnet funds)
            functionsOracle: 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0,
            donID: 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000,
            encryptedSecretsUrls: s_sepoliaEncryptedSecretsUrls
        });
    }

    function getOrCreateAnvilEthConfig() public returns(NetworkConfig memory) {
        // check if we set an active network config
        if (localNetworkConfig.vrfCoordinator != address(0)){
            return localNetworkConfig;
        }

        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorMock = new VRFCoordinatorV2_5Mock(
            MOCK_BASE_FEE,
            MOCK_GAS_PRICE_LINK,
            MOCK_WEI_PER_UINT_LINK
        );
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();

        MockFunctionsOracle mockOracle = new MockFunctionsOracle();

        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether, // 1e16
            interval: 30, // 30 seconds
            vrfCoordinator: address(vrfCoordinatorMock),
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            callbackGasLimit: 500000,
            subscriptionId: 0,
            functionsSubscriptionId: 0,
            link: address(linkToken),
            account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38, // Foundry default address for tx.origin and msg.sender
            functionsOracle: address(mockOracle), // address of deployed mock Functions Oracle
            donID: bytes32("mock-don-id"), // placeholder
            encryptedSecretsUrls: bytes("")
        });

        return localNetworkConfig;
    }
}
