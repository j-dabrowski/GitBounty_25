// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffleWithFunctions} from "script/DeployRaffleWithFunctions.s.sol";
import {RaffleWithFunctions} from "../../src/RaffleWithFunctions.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockFunctionsOracle} from "../mocks/MockFunctionsOracle.sol";
import {CodeConstants, HelperConfig} from "script/HelperConfig.s.sol";

contract RaffleWithFunctionsTest is CodeConstants, Test {
    RaffleWithFunctions public raffle;
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
        DeployRaffleWithFunctions deployer = new DeployRaffleWithFunctions();
        (raffle, helperConfig) = deployer.deployContract();
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
        assertEq(raffle.s_lastRequestId(), bytes32(0));
        assertEq(raffle.s_lastResponse().length, 0);
        assertEq(raffle.s_lastError().length, 0);
        assertEq(raffle.functionsSubId(), functionsSubscriptionId);
        string memory deployedSource = raffle.source();
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
        raffle.fundBounty{value: 0.1 ether}();
        
        vm.prank(funder2);
        raffle.fundBounty{value: 0.1 ether}();
        
        vm.prank(funder3);
        raffle.fundBounty{value: 0.1 ether}();

        _;
    }

    modifier singleFundedBounty() {
        address funder1 = address(1);
        vm.deal(funder1, 1 ether);
        vm.prank(funder1);
        raffle.fundBounty{value: 0.1 ether}();
        _;
    }

    function testFundBountyIncreasesContributionsAndFunding() public singleFundedBounty {
        address funder1 = address(1);
        vm.prank(funder1);
        uint256 amountFunded = raffle.getContribution();
        assertEq(amountFunded, 0.1 ether);
    }

    function testWithdrawFundBountyDecreasesContributionsAndFunding() public multiFundedBounty {
        // Get amount that will be withdrawn
        address funder1 = address(1);
        vm.prank(funder1);
        uint256 amountToWithdraw = raffle.getContribution();

        // Get balance of funder before withdraw
        uint256 balanceBefore = funder1.balance;

        // Withdraw
        vm.prank(funder1);
        raffle.withdrawBountyFund();

        // Get balance of funder after withdraw
        uint256 balanceAfter = funder1.balance;

        assertEq(balanceAfter, balanceBefore + amountToWithdraw);
    }

    function testMapGithubUsernameToAddress() public {
        string memory username = "contributor";
        address contributor = address(4);

        vm.prank(contributor);
        raffle.mapGithubUsernameToAddress(username);

        vm.expectRevert();
        vm.prank(contributor);
        raffle.mapGithubUsernameToAddress(username);

        vm.prank(contributor);
        address extractedAddress = raffle.getAddressFromUsername(username);

        assertEq(extractedAddress, contributor);
    }

    modifier usernameAndAddressMapped() {
        string memory username = "contributor";
        address contributor = address(4);

        vm.prank(contributor);
        raffle.mapGithubUsernameToAddress(username);
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
        raffle.createAndFundBounty{value: fundAmount}(ownerName, repoName, issueId);

        // Check funding recorded
        vm.prank(account);
        uint256 contribution = raffle.getContribution();
        assertEq(contribution, fundAmount, "Contribution not recorded correctly");

        // Check criteria (requires you to add getters)
        assertEq(raffle.getRepoOwner(), ownerName);
        assertEq(raffle.getRepo(), repoName);
        assertEq(raffle.getIssueNumber(), issueId);
    }

    modifier createAndFundBounty() {
        string memory ownerName = "j-dabrowski";
        string memory repoName = "Test_Repo_2025";
        string memory issueId = "1";

        uint256 fundAmount = 0.2 ether;
        // Assign ETH to owner and call as owner
        vm.deal(account, 1 ether);
        vm.prank(account);
        raffle.createAndFundBounty{value: fundAmount}(ownerName, repoName, issueId);
        _;
    }

    function testCheckUpkeepReturnsTrueWithConditions() public createAndFundBounty {
        // Skip time forward
        vm.warp(block.timestamp + interval + 1);

        // Map a username and address
        vm.prank(account);
        raffle.mapGithubUsernameToAddress("example_username");

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    function testPerformUpkeepRevertsIfNotNeeded() public {
        vm.expectRevert();
        raffle.performUpkeep("");
    }

    function testSendRequestStoresRequestId() public {
        string[] memory args = new string[](1);
        args[0] = "1";

        vm.prank(account);
        bytes32 requestId = raffle.sendRequest(uint64(functionsSubscriptionId), args);

        assertEq(raffle.s_lastRequestId(), requestId);
    }

    function testCanRequestAndFulfill() public skipFork {
        // === Setup Mapping ===
        string memory username = "contributor";
        address contributor = vm.addr(999999);
        vm.deal(contributor, 1 ether);
        vm.prank(contributor);
        raffle.mapGithubUsernameToAddress(username);

        // === Fund the Bounty ===
        string memory ownerName = "j-dabrowski";
        string memory repoName = "Test_Repo_2025";
        string memory issueId = "1";

        uint256 fundAmount = 0.2 ether;
        vm.deal(account, 1 ether);
        vm.prank(account);
        raffle.createAndFundBounty{value: fundAmount}(ownerName, repoName, issueId);

        // === Send Chainlink Functions Request ===
        string[] memory args = new string[](1);
        args[0] = username;

        vm.prank(account); // assuming account is onlyOwner
        bytes32 requestId = raffle.sendRequest(
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
        string memory decoded = string(raffle.getLastResponse());
        assertEq(decoded, username);
    }

    function testPerformUpkeepTriggersFunctionsRequest() public createAndFundBounty usernameAndAddressMapped {
        // Simulate time passing to make upkeep needed
        vm.warp(block.timestamp + interval + 1);

        // Pre-check
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assertTrue(upkeepNeeded);

        // Act
        vm.prank(account); // account must be onlyOwner
        raffle.performUpkeep("");

        // Assert state was updated
        assertEq(uint256(raffle.getRaffleState()), uint256(RaffleWithFunctions.RaffleState.CALCULATING));

        // Assert requestId is stored
        assertTrue(raffle.s_lastRequestId() != bytes32(0));
    }

    function testAccountIsOwner() public {
        assertEq(raffle.owner(), account); // Only works if your contract uses ConfirmedOwner
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
        raffle.fundBounty{value: contribution1}();
        vm.stopPrank();

        vm.startPrank(funder2);
        raffle.fundBounty{value: contribution2}();
        vm.stopPrank();

        // Set bounty criteria
        vm.prank(account);
        raffle.setBountyCriteria("owner", "repo", "42");

        // Snapshot balances before refund
        uint256 beforeBalance1 = funder1.balance;
        uint256 beforeBalance2 = funder2.balance;

        // Act - owner deletes bounty and refunds
        vm.prank(account);
        raffle.deleteAndRefundBounty();

        // Assert refunded
        uint256 afterBalance1 = funder1.balance;
        uint256 afterBalance2 = funder2.balance;

        assertEq(afterBalance1, beforeBalance1 + contribution1, "Funder1 not refunded correctly");
        assertEq(afterBalance2, beforeBalance2 + contribution2, "Funder2 not refunded correctly");

        // Assert reset state
        assertEq(raffle.getFunderCount(), 0);
        assertEq(raffle.getBalance(), 0);
        assertEq(raffle.getRepo(), "");
        assertEq(raffle.getRepoOwner(), "");
        assertEq(raffle.getIssueNumber(), "");
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
        raffle.createAndFundBounty{value: fundAmount}(ownerName, repoName, issueId);

        // Map username to contributor
        vm.prank(contributor);
        raffle.mapGithubUsernameToAddress(username);

        // Simulate Chainlink fulfillment
        bytes memory response = bytes(username);
        bytes memory err = bytes("fake error");

        // Send an actual request to store the ID
        string[] memory args = new string[](1);
        args[0] = username;

        vm.prank(account); // must be onlyOwner
        bytes32 requestId = raffle.sendRequest(functionsSubscriptionId, args);

        // Fulfill with actual request ID
        vm.prank(functionsOracle);
        raffle.handleOracleFulfillment(requestId, response, err);

        // Reset the contract
        vm.prank(account);
        raffle.resetContract();

        // === Assertions ===

        // State: Contributions
        assertEq(raffle.getFunderCount(), 0);
        assertEq(raffle.getContribution(), 0);
        assertEq(raffle.getBalance(), 0);

        // State: Username mapping
        assertEq(raffle.getAddressFromUsername(username), address(0));

        // State: Bounty metadata
        assertEq(raffle.getRepoOwner(), "");
        assertEq(raffle.getRepo(), "");
        assertEq(raffle.getIssueNumber(), "");

        // State: Winner/result
        assertEq(raffle.lastWinnerUser(), "");
        assertEq(raffle.getLastResponse().length, 0);
        assertEq(raffle.last_BountyAmount(), 0);

        // State: Enum
        assertEq(uint(raffle.getRaffleState()), uint(RaffleWithFunctions.RaffleState.BASE));
    }


}