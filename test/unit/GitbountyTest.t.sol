// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployGitbounty} from "script/DeployGitbounty.s.sol";
import {Gitbounty} from "../../src/Gitbounty.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockFunctionsOracle} from "../mocks/MockFunctionsOracle.sol";
import {CodeConstants, HelperConfig} from "script/HelperConfig.s.sol";
import "forge-std/console.sol";

import {FunctionsRequest} from "@chainlink/v1/libraries/FunctionsRequest.sol";

using FunctionsRequest for FunctionsRequest.Request;

contract GitbountyTest is CodeConstants, Test {
    Gitbounty public gitbounty;
    HelperConfig public helperConfig;
    MockFunctionsOracle public mockRouter;

    uint256 interval;
    uint64 functionsSubscriptionId;
    address account;
    address functionsOracle;
    bytes32 donID;
    string source;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    event BountyFunded(address indexed sender, uint256 value);

    function setUp() public {
        DeployGitbounty deployer = new DeployGitbounty();
        (gitbounty, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        interval = config.interval;
        functionsSubscriptionId = config.functionsSubscriptionId;
        account = config.account;
        functionsOracle = config.functionsOracle;
        mockRouter = MockFunctionsOracle(functionsOracle);
        donID = config.donID;
        source = vm.readFile("script.js");
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    modifier skipFork() {
        if(block.chainid != LOCAL_CHAIN_ID){
            return;
        }
        _;
    }

    function testConstructorInitializesCorrectly() public {
        assertEq(gitbounty.s_lastRequestId(), bytes32(0));
        assertEq(gitbounty.s_lastResponse().length, 0);
        assertEq(gitbounty.s_lastError().length, 0);
        assertEq(gitbounty.functionsSubId(), functionsSubscriptionId);
        string memory deployedSource = gitbounty.source();
        assertEq(deployedSource, source, "Constructor did not set source correctly");
    }

    modifier multiFundedBounty() {
        address funder1 = address(1);
        address funder2 = address(2);
        address funder3 = address(3);

        vm.deal(funder1, 1 ether);
        vm.deal(funder2, 1 ether);
        vm.deal(funder3, 1 ether);
        
        vm.prank(funder1);
        gitbounty.fundBounty{value: 0.1 ether}();
        
        vm.prank(funder2);
        gitbounty.fundBounty{value: 0.1 ether}();
        
        vm.prank(funder3);
        gitbounty.fundBounty{value: 0.1 ether}();

        _;
    }

    modifier singleFundedBounty() {
        address funder1 = address(1);
        vm.deal(funder1, 1 ether);
        vm.prank(funder1);
        gitbounty.fundBounty{value: 0.1 ether}();
        _;
    }

    function testFundBountyIncreasesContributionsAndFunding() public singleFundedBounty {
        address funder1 = address(1);
        vm.prank(funder1);
        uint256 amountFunded = gitbounty.getContribution();
        assertEq(amountFunded, 0.1 ether);
    }

    function testWithdrawFundBountyDecreasesContributionsAndFunding() public multiFundedBounty {
        // Get amount that will be withdrawn
        address funder1 = address(1);
        vm.prank(funder1);
        uint256 amountToWithdraw = gitbounty.getContribution();

        // Get balance of funder before withdraw
        uint256 balanceBefore = funder1.balance;

        // Withdraw
        vm.prank(funder1);
        gitbounty.withdrawBountyFund();

        // Get balance of funder after withdraw
        uint256 balanceAfter = funder1.balance;

        assertEq(balanceAfter, balanceBefore + amountToWithdraw);
    }

    function testMapGithubUsernameToAddress() public {
        string memory username = "contributor";
        address contributor = address(4);

        vm.prank(contributor);
        gitbounty.mapGithubUsernameToAddress(username);

        vm.expectRevert();
        vm.prank(contributor);
        gitbounty.mapGithubUsernameToAddress(username);

        vm.prank(contributor);
        address extractedAddress = gitbounty.getAddressFromUsername(username);

        assertEq(extractedAddress, contributor);
    }

    modifier usernameAndAddressMapped() {
        string memory username = "contributor";
        address contributor = address(4);

        vm.prank(contributor);
        gitbounty.mapGithubUsernameToAddress(username);
        _;
    }

    function testCreateAndFundBountySetsCriteriaAndRecordsContribution() public {
        string memory ownerName = "j-dabrowski";
        string memory repoName = "Test_Repo_2025";
        string memory issueId = "1";

        uint256 fundAmount = 0.2 ether;

        // Expect event BEFORE the function that emits it
        vm.expectEmit(true, true, false, false);
        emit BountyFunded(account, fundAmount);

        // Assign ETH to owner and call as owner
        vm.deal(account, 1 ether);
        vm.prank(account);
        gitbounty.createAndFundBounty{value: fundAmount}(ownerName, repoName, issueId);

        // Check funding recorded
        vm.prank(account);
        uint256 contribution = gitbounty.getContribution();
        assertEq(contribution, fundAmount, "Contribution not recorded correctly");

        // Check criteria (requires you to add getters)
        assertEq(gitbounty.getRepoOwner(), ownerName);
        assertEq(gitbounty.getRepo(), repoName);
        assertEq(gitbounty.getIssueNumber(), issueId);
    }

    modifier createAndFundBounty() {
        string memory ownerName = "j-dabrowski";
        string memory repoName = "Test_Repo_2025";
        string memory issueId = "1";

        uint256 fundAmount = 0.2 ether;
        // Assign ETH to owner and call as owner
        vm.deal(account, 1 ether);
        vm.prank(account);
        gitbounty.createAndFundBounty{value: fundAmount}(ownerName, repoName, issueId);
        _;
    }

    function testCheckUpkeepReturnsTrueWithConditions() public createAndFundBounty {
        // Skip time forward
        vm.warp(block.timestamp + interval + 1);

        // Map a username and address
        vm.prank(account);
        gitbounty.mapGithubUsernameToAddress("example_username");

        (bool upkeepNeeded, ) = gitbounty.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    function testPerformUpkeepRevertsIfNotNeeded() public {
        vm.expectRevert();
        gitbounty.performUpkeep("");
    }

    function testSendRequestStoresRequestId() public {
        string[] memory args = new string[](1);
        args[0] = "1";

        vm.prank(account);
        bytes32 requestId = gitbounty.sendRequest(uint64(functionsSubscriptionId), args);

        assertEq(gitbounty.s_lastRequestId(), requestId);
    }

    function testCanRequestAndFulfill() public skipFork {
        // === Setup Mapping ===
        string memory username = "contributor";
        address contributor = vm.addr(999999);
        vm.deal(contributor, 1 ether);
        vm.prank(contributor);
        gitbounty.mapGithubUsernameToAddress(username);

        // === Fund the Bounty ===
        string memory ownerName = "j-dabrowski";
        string memory repoName = "Test_Repo_2025";
        string memory issueId = "1";

        uint256 fundAmount = 0.2 ether;
        vm.deal(account, 1 ether);
        vm.prank(account);
        gitbounty.createAndFundBounty{value: fundAmount}(ownerName, repoName, issueId);

        // === Send Chainlink Functions Request ===
        string[] memory args = new string[](1);
        args[0] = username;

        vm.prank(account); // assuming account is onlyOwner
        bytes32 requestId = gitbounty.sendRequest(
            uint64(functionsSubscriptionId),
            args
        );

        uint256 balanceBefore = contributor.balance;

        // === Simulate Fulfillment ===
        bytes memory response = bytes(username); // raw string
        bytes memory error = "";

        mockRouter.fulfillRequest(requestId, response, error);

        uint256 balanceAfter = contributor.balance;
        assertEq(balanceAfter, balanceBefore + fundAmount);

        // === Assertions ===
        string memory decoded = string(gitbounty.getLastResponse());
        assertEq(decoded, username);
    }

    function testPerformUpkeepTriggersFunctionsRequest() public createAndFundBounty usernameAndAddressMapped {
        // Simulate time passing to make upkeep needed
        vm.warp(block.timestamp + interval + 1);

        // Pre-check
        (bool upkeepNeeded, ) = gitbounty.checkUpkeep("");
        assertTrue(upkeepNeeded);

        // Act
        vm.prank(account); // account must be onlyOwner
        gitbounty.performUpkeep("");

        // Assert state was updated
        assertEq(uint256(gitbounty.getGitbountyState()), uint256(Gitbounty.GitbountyState.CALCULATING));

        // Assert requestId is stored
        assertTrue(gitbounty.s_lastRequestId() != bytes32(0));
    }

    function testAccountIsOwner() public {
        assertEq(gitbounty.owner(), account); // Only works if your contract uses ConfirmedOwner
    }

    function testDeleteAndRefundBounty() public {
        // Arrange
        address funder1 = address(0x111);
        address funder2 = address(0x222);
        uint256 contribution1 = 1 ether;
        uint256 contribution2 = 2 ether;

        vm.deal(funder1, contribution1);
        vm.deal(funder2, contribution2);

        vm.startPrank(funder1);
        gitbounty.fundBounty{value: contribution1}();
        vm.stopPrank();

        vm.startPrank(funder2);
        gitbounty.fundBounty{value: contribution2}();
        vm.stopPrank();

        // Set bounty criteria
        vm.prank(account);
        gitbounty.setBountyCriteria("owner", "repo", "42");

        // Snapshot balances before refund
        uint256 beforeBalance1 = funder1.balance;
        uint256 beforeBalance2 = funder2.balance;

        // Act - owner deletes bounty and refunds
        vm.prank(account);
        gitbounty.deleteAndRefundBounty();

        // Assert refunded
        uint256 afterBalance1 = funder1.balance;
        uint256 afterBalance2 = funder2.balance;

        assertEq(afterBalance1, beforeBalance1 + contribution1, "Funder1 not refunded correctly");
        assertEq(afterBalance2, beforeBalance2 + contribution2, "Funder2 not refunded correctly");

        // Assert reset state
        assertEq(gitbounty.getFunderCount(), 0);
        assertEq(gitbounty.getBalance(), 0);
        assertEq(gitbounty.getRepo(), "");
        assertEq(gitbounty.getRepoOwner(), "");
        assertEq(gitbounty.getIssueNumber(), "");
    }

    function testResetContractClearsAllState() public skipFork {
        // Setup modifiable state
        string memory ownerName = "j-dabrowski";
        string memory repoName = "Test_Repo_2025";
        string memory issueId = "1";
        string memory username = "contributor";
        address contributor = address(4);
        uint256 fundAmount = 0.2 ether;

        // Fund the bounty
        vm.deal(account, 1 ether);
        vm.prank(account);
        gitbounty.createAndFundBounty{value: fundAmount}(ownerName, repoName, issueId);

        // Map username to contributor
        vm.prank(contributor);
        gitbounty.mapGithubUsernameToAddress(username);

        // Simulate Chainlink fulfillment
        bytes memory response = bytes(username);
        bytes memory err = bytes("fake error");

        // Send an actual request to store the ID
        string[] memory args = new string[](1);
        args[0] = username;

        vm.prank(account); // must be onlyOwner
        bytes32 requestId = gitbounty.sendRequest(functionsSubscriptionId, args);

        // Fulfill with actual request ID
        vm.prank(functionsOracle);
        gitbounty.handleOracleFulfillment(requestId, response, err);

        // Reset the contract
        vm.prank(account);
        gitbounty.resetContract();

        // === Assertions ===

        // State: Contributions
        assertEq(gitbounty.getFunderCount(), 0);
        assertEq(gitbounty.getContribution(), 0);
        assertEq(gitbounty.getBalance(), 0);

        // State: Username mapping
        assertEq(gitbounty.getAddressFromUsername(username), address(0));

        // State: Bounty metadata
        assertEq(gitbounty.getRepoOwner(), "");
        assertEq(gitbounty.getRepo(), "");
        assertEq(gitbounty.getIssueNumber(), "");

        // State: Winner/result
        assertEq(gitbounty.lastWinnerUser(), "");
        assertEq(gitbounty.getLastResponse().length, 0);
        assertEq(gitbounty.last_BountyAmount(), 0);

        // State: Enum
        assertEq(uint(gitbounty.getGitbountyState()), uint(Gitbounty.GitbountyState.BASE));
    }


function testPrintEncodedCBOR() public {
    string memory source = "return Functions.encodeString(\"j-dabrowski\");";

    FunctionsRequest.Request memory req;

    req._initializeRequestForInlineJavaScript(source);


    bytes memory cborPayload = req._encodeCBOR();

    console.logBytes(cborPayload); // 🔍 Print the CBOR
}


}