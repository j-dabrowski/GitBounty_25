// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {GitbountyFactory} from "../../src/GitbountyFactory.sol";
import {Gitbounty} from "../../src/Gitbounty.sol";

import {MockFunctionsOracle} from "../mocks/MockFunctionsOracle.sol";
import {CodeConstants, HelperConfig} from "script/HelperConfig.s.sol";

contract GitbountyTest is CodeConstants, Test {
    GitbountyFactory public factory;
    Gitbounty public implementation;
    HelperConfig public helperConfig;

    MockFunctionsOracle public mockRouter;

    // From HelperConfig
    uint64 public functionsSubscriptionId;
    address public functionsRouter;
    bytes32 public donID;
    uint32 public callbackGasLimit;
    string public source;

    address public OWNER = makeAddr("owner");
    address public CONTRIBUTOR = makeAddr("contributor");
    uint256 public constant STARTING_BALANCE = 10 ether;

    uint256 public constant BOUNTY_VALUE = 0.2 ether;

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function setUp() public {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();

        functionsSubscriptionId = cfg.functionsSubscriptionId;
        functionsRouter = cfg.functionsRouter;
        donID = cfg.donID;
        callbackGasLimit = cfg.callbackGasLimit;

        // JS source (factory stores it)
        source = vm.readFile("script.js");

        // Local router is a mock
        mockRouter = MockFunctionsOracle(functionsRouter);

        // Deploy implementation + factory
        implementation = new Gitbounty();

        factory = new GitbountyFactory(
            address(implementation),
            functionsRouter,
            donID,
            functionsSubscriptionId,
            callbackGasLimit,
            source,
            cfg.encryptedSecretsUrls
        );

        vm.deal(OWNER, STARTING_BALANCE);
        vm.deal(CONTRIBUTOR, STARTING_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _createReadyBounty(string memory repoOwner, string memory repo, string memory issue)
        internal
        returns (Gitbounty bounty)
    {
        vm.prank(OWNER);
        address bountyAddr = factory.createBounty{value: BOUNTY_VALUE}(repoOwner, repo, issue);
        bounty = Gitbounty(payable(bountyAddr));
    }

    /*//////////////////////////////////////////////////////////////
                            TESTS
    //////////////////////////////////////////////////////////////*/

    function testFactoryStoresImplementation() public {
        assertEq(factory.implementation(), address(implementation));
    }

    function testCreateBountyClonesInitialisesFundsAndReady() public {
        Gitbounty bounty = _createReadyBounty("j-dabrowski", "TestRepo", "1");

        // Ownership + factory binding
        assertEq(bounty.owner(), OWNER);
        assertEq(bounty.factory(), address(factory));

        // Criteria
        assertEq(bounty.getRepoOwner(), "j-dabrowski");
        assertEq(bounty.getRepo(), "TestRepo");
        assertEq(bounty.getIssueNumber(), "1");

        // Funded by init value
        vm.prank(OWNER);
        assertEq(bounty.getContribution(), BOUNTY_VALUE);
        assertEq(address(bounty).balance, BOUNTY_VALUE);

        // Ready
        assertTrue(bounty.isBountyReady());
        assertEq(uint256(bounty.getGitbountyState()), uint256(Gitbounty.GitbountyState.READY));
    }

    function testCreateBountyRevertsIfZeroValue() public {
        vm.prank(OWNER);
        vm.expectRevert(); // either factory or child reverts (both are fine)
        factory.createBounty{value: 0}("a", "b", "1");
    }

    function testMapGithubUsernameToAddressOnFactory() public {
        string memory username = "contributor";

        vm.prank(CONTRIBUTOR);
        factory.mapGithubUsernameToAddress(username);

        assertEq(factory.getAddressFromUsername(username), CONTRIBUTOR);

        // duplicate mapping should revert
        vm.prank(CONTRIBUTOR);
        vm.expectRevert();
        factory.mapGithubUsernameToAddress(username);
    }

    function testPerformUpkeepSendsRequestAndMarksCalculating() public skipFork {
        // Create ready bounty
        Gitbounty bounty = _createReadyBounty("j-dabrowski", "TestRepo", "1");

        // Map username -> address on the FACTORY (important: payout uses factory mapping)
        string memory username = "contributor";
        vm.prank(CONTRIBUTOR);
        factory.mapGithubUsernameToAddress(username);

        // checkUpkeep should find it eligible
        (bool upkeepNeeded, bytes memory performData) = factory.checkUpkeep("");
        assertTrue(upkeepNeeded);

        // perform
        factory.performUpkeep(performData);

        // inFlight set on factory + requestId stored
        assertTrue(factory.inFlight(address(bounty)));

        bytes32 requestId = factory.lastRequestForBounty(address(bounty));
        assertTrue(requestId != bytes32(0));

        // bounty marked calculating
        assertEq(uint256(bounty.getGitbountyState()), uint256(Gitbounty.GitbountyState.CALCULATING));
        assertEq(bounty.s_lastRequestId(), requestId);
    }

    function testCanFulfillAndPayoutWinnerViaFactory() public skipFork {
        Gitbounty bounty = _createReadyBounty("j-dabrowski", "TestRepo", "1");

        // Map username -> CONTRIBUTOR
        string memory username = "contributor";
        vm.prank(CONTRIBUTOR);
        factory.mapGithubUsernameToAddress(username);

        // Trigger upkeep -> request
        (bool upkeepNeeded, bytes memory performData) = factory.checkUpkeep("");
        assertTrue(upkeepNeeded);
        factory.performUpkeep(performData);

        bytes32 requestId = factory.lastRequestForBounty(address(bounty));
        assertTrue(requestId != bytes32(0));

        uint256 contributorBefore = CONTRIBUTOR.balance;
        uint256 bountyBefore = address(bounty).balance;
        assertEq(bountyBefore, BOUNTY_VALUE);

        // Fulfill (mock router should call back into factory)
        bytes memory response = bytes(username);
        bytes memory err = bytes("");

        mockRouter.fulfillRequest(requestId, response, err);

        // CONTRIBUTOR paid
        assertEq(CONTRIBUTOR.balance, contributorBefore + BOUNTY_VALUE);

        // bounty drained + state paid
        assertEq(address(bounty).balance, 0);
        assertEq(uint256(bounty.getGitbountyState()), uint256(Gitbounty.GitbountyState.PAID));

        // factory unlocked
        assertFalse(factory.inFlight(address(bounty)));
        assertEq(factory.requestToBounty(requestId), address(0));
    }

    function testRefundAllFundersOnlyOwner() public {
        Gitbounty bounty = _createReadyBounty("j-dabrowski", "TestRepo", "1");

        // Non-owner should revert
        vm.prank(CONTRIBUTOR);
        vm.expectRevert(Gitbounty.Gitbounty__NotOwner.selector);
        bounty.refundAllFunders();

        // Owner can call
        vm.prank(OWNER);
        bounty.refundAllFunders();

        assertEq(address(bounty).balance, 0);
        assertEq(bounty.getFunderCount(), 0);
    }
}
