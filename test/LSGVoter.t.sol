// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {LSGVoter} from "../src/LSGVoter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockBribe} from "./mocks/MockBribe.sol";

contract LSGVoterTest is Test {
    LSGVoter public voter;
    MockERC721 public seatNFT;
    MockERC20 public token1;
    MockERC20 public token2;
    MockBribe public bribe1;
    MockBribe public bribe2;

    address public owner = address(this);
    address public treasury = makeAddr("treasury");
    address public emergencyMultisig = makeAddr("emergencyMultisig");
    address public revenueRouter = makeAddr("revenueRouter");
    address public strategy1 = makeAddr("strategy1");
    address public strategy2 = makeAddr("strategy2");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    // Constants from contract
    uint256 constant EPOCH_DURATION = 7 days;
    uint256 constant EPOCH_START = 1704067200; // Monday, Jan 1, 2024 00:00:00 UTC

    function setUp() public {
        // Deploy contracts
        seatNFT = new MockERC721();
        voter = new LSGVoter(address(seatNFT), treasury, emergencyMultisig);

        token1 = new MockERC20("Token1", "TK1", 18);
        token2 = new MockERC20("Token2", "TK2", 18);

        bribe1 = new MockBribe(address(voter));
        bribe2 = new MockBribe(address(voter));

        // Configure voter
        voter.setRevenueRouter(revenueRouter);
        voter.addStrategy(strategy1, address(bribe1));
        voter.addStrategy(strategy2, address(bribe2));

        // Mint NFTs to users
        seatNFT.mintBatch(alice, 3);
        seatNFT.mintBatch(bob, 2);
        seatNFT.mintBatch(charlie, 1);

        // Set block timestamp to a valid epoch
        vm.warp(EPOCH_START + EPOCH_DURATION);
    }

    /*//////////////////////////////////////////////////////////////
                        EPOCH CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CurrentEpoch_CalculatesCorrectly() public {
        // Set to epoch 0 start
        vm.warp(EPOCH_START);
        assertEq(voter.currentEpoch(), 0, "Epoch 0 at start");

        // Set to middle of epoch 0
        vm.warp(EPOCH_START + 3 days);
        assertEq(voter.currentEpoch(), 0, "Still epoch 0");

        // Set to epoch 1 start
        vm.warp(EPOCH_START + EPOCH_DURATION);
        assertEq(voter.currentEpoch(), 1, "Epoch 1 after 7 days");

        // Set to epoch 10
        vm.warp(EPOCH_START + (EPOCH_DURATION * 10));
        assertEq(voter.currentEpoch(), 10, "Epoch 10 after 70 days");
    }

    function test_EpochStartTime_ReturnsCorrectTimestamp() public {
        assertEq(voter.epochStartTime(0), EPOCH_START, "Epoch 0 start");
        assertEq(voter.epochStartTime(1), EPOCH_START + EPOCH_DURATION, "Epoch 1 start");
        assertEq(voter.epochStartTime(10), EPOCH_START + (EPOCH_DURATION * 10), "Epoch 10 start");
    }

    function test_TimeUntilNextEpoch_CalculatesCorrectly() public {
        vm.warp(EPOCH_START + EPOCH_DURATION);
        assertEq(voter.timeUntilNextEpoch(), EPOCH_DURATION, "Full epoch remaining");

        vm.warp(EPOCH_START + EPOCH_DURATION + 3 days);
        assertEq(voter.timeUntilNextEpoch(), 4 days, "4 days remaining");

        vm.warp(EPOCH_START + EPOCH_DURATION + EPOCH_DURATION - 1);
        assertEq(voter.timeUntilNextEpoch(), 1, "1 second remaining");
    }

    /*//////////////////////////////////////////////////////////////
                        VOTING POWER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetVotingPower_ReturnsNFTBalance() public {
        assertEq(voter.getVotingPower(alice), 3, "Alice has 3 NFTs");
        assertEq(voter.getVotingPower(bob), 2, "Bob has 2 NFTs");
        assertEq(voter.getVotingPower(charlie), 1, "Charlie has 1 NFT");
    }

    function test_GetVotingPower_UpdatesWhenNFTTransferred() public {
        assertEq(voter.getVotingPower(alice), 3, "Alice starts with 3");

        // Transfer 1 NFT from alice to bob
        vm.prank(alice);
        seatNFT.transferFrom(alice, bob, 0);

        assertEq(voter.getVotingPower(alice), 2, "Alice now has 2");
        assertEq(voter.getVotingPower(bob), 3, "Bob now has 3");
    }

    function test_GetVotingPower_ZeroForAccountWithNoNFTs() public {
        address noNFTs = makeAddr("noNFTs");
        assertEq(voter.getVotingPower(noNFTs), 0, "No voting power without NFTs");
    }

    /*//////////////////////////////////////////////////////////////
                            VOTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Vote_AllocatesWeightsCorrectly() public {
        address[] memory strategies = new address[](2);
        strategies[0] = strategy1;
        strategies[1] = strategy2;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 60;
        weights[1] = 40;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Alice has 3 voting power, should split 60/40
        assertEq(voter.account_Strategy_Votes(alice, strategy1), 1, "Strategy1 gets 60% of 3 = 1.8 -> 1");
        assertEq(voter.account_Strategy_Votes(alice, strategy2), 1, "Strategy2 gets 40% of 3 = 1.2 -> 1");
        assertEq(voter.account_UsedWeight(alice), 2, "Total used weight is 2");
        assertEq(voter.totalWeight(), 2, "Total weight updated");
    }

    function test_Vote_SingleStrategy() public {
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        assertEq(voter.account_Strategy_Votes(alice, strategy1), 3, "All 3 votes to strategy1");
        assertEq(voter.strategy_Weight(strategy1), 3, "Strategy1 weight increased");
    }

    function test_Vote_UpdatesBribeBalances() public {
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        assertEq(bribe1.balanceOf(alice), 3, "Bribe balance updated");
        assertEq(bribe1.depositCount(alice), 1, "Deposit called once");
    }

    function test_Vote_RevertIfAlreadyVotedSameEpoch() public {
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Try to vote again in same epoch
        vm.prank(alice);
        vm.expectRevert(LSGVoter.AlreadyVotedThisEpoch.selector);
        voter.vote(strategies, weights);
    }

    function test_Vote_AllowsVoteInNextEpoch() public {
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Move to next epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // Should allow voting again
        vm.prank(alice);
        voter.vote(strategies, weights);
    }

    function test_Vote_RevertIfNoVotingPower() public {
        address noNFTs = makeAddr("noNFTs");

        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(noNFTs);
        vm.expectRevert(LSGVoter.ZeroWeight.selector);
        voter.vote(strategies, weights);
    }

    function test_Vote_RevertIfArrayLengthMismatch() public {
        address[] memory strategies = new address[](2);
        strategies[0] = strategy1;
        strategies[1] = strategy2;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        vm.expectRevert(LSGVoter.ArrayLengthMismatch.selector);
        voter.vote(strategies, weights);
    }

    function test_Vote_SkipsKilledStrategies() public {
        // Kill strategy2
        voter.killStrategy(strategy2);

        address[] memory strategies = new address[](2);
        strategies[0] = strategy1;
        strategies[1] = strategy2;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 50;
        weights[1] = 50;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // All votes should go to strategy1 (strategy2 is killed)
        assertEq(voter.account_Strategy_Votes(alice, strategy1), 3, "All votes to strategy1");
        assertEq(voter.account_Strategy_Votes(alice, strategy2), 0, "No votes to killed strategy");
    }

    function test_Vote_EmitsVotedEvents() public {
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.expectEmit(true, true, false, true);
        emit Voted(alice, strategy1, 3);

        vm.prank(alice);
        voter.vote(strategies, weights);
    }

    /*//////////////////////////////////////////////////////////////
                            RESET TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Reset_ClearsVotes() public {
        // Vote first
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        assertEq(voter.account_Strategy_Votes(alice, strategy1), 3, "Vote recorded");

        // Move to next epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // Reset
        vm.prank(alice);
        voter.reset();

        assertEq(voter.account_Strategy_Votes(alice, strategy1), 0, "Vote cleared");
        assertEq(voter.account_UsedWeight(alice), 0, "Used weight cleared");
        assertEq(voter.totalWeight(), 0, "Total weight decreased");
    }

    function test_Reset_UpdatesBribeBalances() public {
        // Vote first
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        assertEq(bribe1.balanceOf(alice), 3, "Bribe balance increased");

        // Move to next epoch and reset
        vm.warp(block.timestamp + EPOCH_DURATION);

        vm.prank(alice);
        voter.reset();

        assertEq(bribe1.balanceOf(alice), 0, "Bribe balance decreased");
        assertEq(bribe1.withdrawCount(alice), 1, "Withdraw called");
    }

    function test_Reset_RevertIfSameEpoch() public {
        // Vote first so that reset in same epoch should revert
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Now try to reset in the same epoch - should revert
        vm.prank(alice);
        vm.expectRevert(LSGVoter.AlreadyVotedThisEpoch.selector);
        voter.reset();
    }

    function test_Reset_EmitsVoteResetEvent() public {
        // Move to next epoch first
        vm.warp(block.timestamp + EPOCH_DURATION);

        vm.expectEmit(true, false, false, false);
        emit VoteReset(alice);

        vm.prank(alice);
        voter.reset();
    }

    /*//////////////////////////////////////////////////////////////
                        DELEGATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Delegate_TransfersPower() public {
        assertEq(voter.getVotingPower(alice), 3, "Alice has 3 power");
        assertEq(voter.getVotingPower(bob), 2, "Bob has 2 power");

        // Alice delegates to Bob
        vm.prank(alice);
        voter.delegate(bob);

        assertEq(voter.getVotingPower(alice), 0, "Alice power is 0 after delegation");
        assertEq(voter.getVotingPower(bob), 5, "Bob has 2 + 3 delegated = 5");
    }

    function test_Delegate_EmitsDelegateSetEvent() public {
        vm.expectEmit(true, true, false, false);
        emit DelegateSet(alice, bob);

        vm.prank(alice);
        voter.delegate(bob);
    }

    function test_Delegate_RevertIfDelegateToSelf() public {
        vm.prank(alice);
        vm.expectRevert(LSGVoter.CannotDelegateToSelf.selector);
        voter.delegate(alice);
    }

    function test_Undelegate_RestoresPower() public {
        // Delegate first
        vm.prank(alice);
        voter.delegate(bob);

        assertEq(voter.getVotingPower(alice), 0, "Alice power is 0");
        assertEq(voter.getVotingPower(bob), 5, "Bob has delegated power");

        // Undelegate
        vm.prank(alice);
        voter.undelegate();

        assertEq(voter.getVotingPower(alice), 3, "Alice power restored");
        assertEq(voter.getVotingPower(bob), 2, "Bob power back to base");
    }

    function test_Delegate_ChangeDelegatee() public {
        // Delegate to Bob
        vm.prank(alice);
        voter.delegate(bob);

        assertEq(voter.getVotingPower(bob), 5, "Bob has delegated power");

        // Change delegation to Charlie
        vm.prank(alice);
        voter.delegate(charlie);

        assertEq(voter.getVotingPower(bob), 2, "Bob power back to base");
        assertEq(voter.getVotingPower(charlie), 4, "Charlie has delegated power");
    }

    /*//////////////////////////////////////////////////////////////
                    REVENUE NOTIFICATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_NotifyRevenue_UpdatesTokenIndex() public {
        // Setup: Alice votes
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Mint tokens to router and approve
        token1.mint(revenueRouter, 1000 ether);
        vm.prank(revenueRouter);
        token1.approve(address(voter), 1000 ether);

        // Notify revenue
        vm.prank(revenueRouter);
        voter.notifyRevenue(address(token1), 1000 ether);

        // Check that token is registered
        address[] memory revenueTokens = voter.getRevenueTokens();
        assertEq(revenueTokens.length, 1, "Token registered");
        assertEq(revenueTokens[0], address(token1), "Correct token");
    }

    function test_NotifyRevenue_SendsToTreasuryIfNoVotes() public {
        // Mint tokens to router and approve
        token1.mint(revenueRouter, 1000 ether);
        vm.prank(revenueRouter);
        token1.approve(address(voter), 1000 ether);

        uint256 treasuryBefore = token1.balanceOf(treasury);

        // Notify revenue with no votes
        vm.prank(revenueRouter);
        voter.notifyRevenue(address(token1), 1000 ether);

        assertEq(token1.balanceOf(treasury), treasuryBefore + 1000 ether, "Treasury received tokens");
    }

    function test_NotifyRevenue_RevertIfNotRevenueRouter() public {
        token1.mint(alice, 1000 ether);
        vm.prank(alice);
        token1.approve(address(voter), 1000 ether);

        vm.prank(alice);
        vm.expectRevert(LSGVoter.NotAuthorized.selector);
        voter.notifyRevenue(address(token1), 1000 ether);
    }

    function test_NotifyRevenue_EmitsRevenueNotifiedEvent() public {
        // Setup votes
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Prepare tokens
        token1.mint(revenueRouter, 1000 ether);
        vm.prank(revenueRouter);
        token1.approve(address(voter), 1000 ether);

        vm.expectEmit(true, false, false, true);
        emit RevenueNotified(address(token1), 1000 ether);

        vm.prank(revenueRouter);
        voter.notifyRevenue(address(token1), 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    REVENUE DISTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Distribute_SendsCorrectAmount() public {
        // Alice votes for strategy1
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Notify revenue
        token1.mint(revenueRouter, 3000 ether);
        vm.prank(revenueRouter);
        token1.approve(address(voter), 3000 ether);

        vm.prank(revenueRouter);
        voter.notifyRevenue(address(token1), 3000 ether);

        uint256 strategyBefore = token1.balanceOf(strategy1);

        // Distribute
        voter.distribute(strategy1, address(token1));

        // Strategy should receive all tokens (has all votes)
        assertEq(token1.balanceOf(strategy1), strategyBefore + 3000 ether, "Strategy received revenue");
    }

    function test_Distribute_ProportionalToWeight() public {
        // Alice votes 100% for strategy1
        address[] memory aliceStrategies = new address[](1);
        aliceStrategies[0] = strategy1;
        uint256[] memory aliceWeights = new uint256[](1);
        aliceWeights[0] = 100;

        vm.prank(alice);
        voter.vote(aliceStrategies, aliceWeights);

        // Bob votes 100% for strategy2
        address[] memory bobStrategies = new address[](1);
        bobStrategies[0] = strategy2;
        uint256[] memory bobWeights = new uint256[](1);
        bobWeights[0] = 100;

        vm.prank(bob);
        voter.vote(bobStrategies, bobWeights);

        // Total weight = 3 (alice) + 2 (bob) = 5
        assertEq(voter.totalWeight(), 5, "Total weight is 5");

        // Notify revenue: 5000 tokens
        token1.mint(revenueRouter, 5000 ether);
        vm.prank(revenueRouter);
        token1.approve(address(voter), 5000 ether);

        vm.prank(revenueRouter);
        voter.notifyRevenue(address(token1), 5000 ether);

        // Distribute to both
        voter.distribute(strategy1, address(token1));
        voter.distribute(strategy2, address(token1));

        // Strategy1 should get 3/5 = 3000, Strategy2 should get 2/5 = 2000
        assertEq(token1.balanceOf(strategy1), 3000 ether, "Strategy1 gets 60%");
        assertEq(token1.balanceOf(strategy2), 2000 ether, "Strategy2 gets 40%");
    }

    function test_DistributeAllTokens_HandlesMultipleTokens() public {
        // Vote for strategy1
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Notify revenue for multiple tokens
        token1.mint(revenueRouter, 1000 ether);
        token2.mint(revenueRouter, 2000 ether);

        vm.prank(revenueRouter);
        token1.approve(address(voter), 1000 ether);
        vm.prank(revenueRouter);
        token2.approve(address(voter), 2000 ether);

        vm.prank(revenueRouter);
        voter.notifyRevenue(address(token1), 1000 ether);
        vm.prank(revenueRouter);
        voter.notifyRevenue(address(token2), 2000 ether);

        // Distribute all tokens
        voter.distributeAllTokens(strategy1);

        // Allow 1 wei tolerance for rounding
        assertApproxEqAbs(token1.balanceOf(strategy1), 1000 ether, 1, "Strategy1 received token1");
        assertApproxEqAbs(token2.balanceOf(strategy1), 2000 ether, 1, "Strategy1 received token2");
    }

    function test_DistributeToAllStrategies_HandlesMultipleStrategies() public {
        // Alice votes for strategy1, Bob votes for strategy2
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        strategies[0] = strategy2;
        vm.prank(bob);
        voter.vote(strategies, weights);

        // Notify revenue
        token1.mint(revenueRouter, 5000 ether);
        vm.prank(revenueRouter);
        token1.approve(address(voter), 5000 ether);

        vm.prank(revenueRouter);
        voter.notifyRevenue(address(token1), 5000 ether);

        // Distribute to all strategies
        voter.distributeToAllStrategies(address(token1));

        assertEq(token1.balanceOf(strategy1), 3000 ether, "Strategy1 received proportional share");
        assertEq(token1.balanceOf(strategy2), 2000 ether, "Strategy2 received proportional share");
    }

    function test_PendingRevenue_ReturnsCorrectAmount() public {
        // Alice votes
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Notify revenue
        token1.mint(revenueRouter, 3000 ether);
        vm.prank(revenueRouter);
        token1.approve(address(voter), 3000 ether);

        vm.prank(revenueRouter);
        voter.notifyRevenue(address(token1), 3000 ether);

        // Check pending
        uint256 pending = voter.pendingRevenue(strategy1, address(token1));
        assertEq(pending, 3000 ether, "Correct pending amount");

        // Distribute
        voter.distribute(strategy1, address(token1));

        // Check pending after distribute
        pending = voter.pendingRevenue(strategy1, address(token1));
        assertEq(pending, 0, "No pending after distribute");
    }

    /*//////////////////////////////////////////////////////////////
                    STRATEGY MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddStrategy_AddsToList() public {
        MockBribe newBribe = new MockBribe(address(voter));
        address newStrategy = makeAddr("newStrategy");

        voter.addStrategy(newStrategy, address(newBribe));

        address[] memory allStrategies = voter.getStrategies();
        assertEq(allStrategies.length, 3, "3 strategies total");
        assertEq(allStrategies[2], newStrategy, "New strategy added");
        assertTrue(voter.strategy_IsValid(newStrategy), "Strategy is valid");
        assertTrue(voter.strategy_IsAlive(newStrategy), "Strategy is alive");
    }

    function test_AddStrategy_RevertIfMaxReached() public {
        // Add strategies until max (20)
        for (uint256 i = 2; i < 20; i++) {
            MockBribe newBribe = new MockBribe(address(voter));
            address newStrategy = makeAddr(string(abi.encodePacked("strategy", i)));
            voter.addStrategy(newStrategy, address(newBribe));
        }

        // Try to add 21st strategy
        MockBribe newBribe = new MockBribe(address(voter));
        address newStrategy = makeAddr("strategy21");

        vm.expectRevert(LSGVoter.MaxStrategiesReached.selector);
        voter.addStrategy(newStrategy, address(newBribe));
    }

    function test_AddStrategy_RevertIfZeroAddress() public {
        vm.expectRevert(LSGVoter.InvalidAddress.selector);
        voter.addStrategy(address(0), address(bribe1));

        vm.expectRevert(LSGVoter.InvalidAddress.selector);
        voter.addStrategy(strategy1, address(0));
    }

    function test_AddStrategy_OnlyOwner() public {
        MockBribe newBribe = new MockBribe(address(voter));
        address newStrategy = makeAddr("newStrategy");

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        voter.addStrategy(newStrategy, address(newBribe));
    }

    function test_KillStrategy_SendsPendingToTreasury() public {
        // Alice votes for strategy2
        address[] memory strategies = new address[](1);
        strategies[0] = strategy2;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Notify revenue
        token1.mint(revenueRouter, 3000 ether);
        vm.prank(revenueRouter);
        token1.approve(address(voter), 3000 ether);

        vm.prank(revenueRouter);
        voter.notifyRevenue(address(token1), 3000 ether);

        uint256 treasuryBefore = token1.balanceOf(treasury);

        // Kill strategy
        voter.killStrategy(strategy2);

        // Pending should go to treasury
        assertEq(token1.balanceOf(treasury), treasuryBefore + 3000 ether, "Treasury received pending");
        assertFalse(voter.strategy_IsAlive(strategy2), "Strategy is not alive");
    }

    function test_KillStrategy_RevertIfAlreadyKilled() public {
        voter.killStrategy(strategy2);

        vm.expectRevert(LSGVoter.StrategyNotAlive.selector);
        voter.killStrategy(strategy2);
    }

    function test_KillStrategy_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        voter.killStrategy(strategy2);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetRevenueRouter_UpdatesRouter() public {
        address newRouter = makeAddr("newRouter");
        voter.setRevenueRouter(newRouter);

        assertEq(voter.revenueRouter(), newRouter, "Router updated");
    }

    function test_SetRevenueRouter_RevertIfZeroAddress() public {
        vm.expectRevert(LSGVoter.InvalidAddress.selector);
        voter.setRevenueRouter(address(0));
    }

    function test_SetRevenueRouter_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        voter.setRevenueRouter(makeAddr("newRouter"));
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EmergencyPause_ByOwner() public {
        voter.emergencyPause();
        assertTrue(voter.paused(), "Contract paused");
    }

    function test_EmergencyPause_ByMultisig() public {
        vm.prank(emergencyMultisig);
        voter.emergencyPause();
        assertTrue(voter.paused(), "Contract paused by multisig");
    }

    function test_EmergencyPause_BlocksVoting() public {
        voter.emergencyPause();

        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        voter.vote(strategies, weights);
    }

    function test_Unpause_ResumesOperations() public {
        voter.emergencyPause();
        voter.unpause();

        assertFalse(voter.paused(), "Contract unpaused");

        // Should be able to vote
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);
    }

    function test_Unpause_OnlyOwner() public {
        voter.emergencyPause();

        vm.prank(emergencyMultisig);
        vm.expectRevert("Ownable: caller is not the owner");
        voter.unpause();
    }

    function test_SetEmergencyMultisig_UpdatesAddress() public {
        address newMultisig = makeAddr("newMultisig");
        voter.setEmergencyMultisig(newMultisig);

        assertEq(voter.emergencyMultisig(), newMultisig, "Multisig updated");
    }

    function test_SetEmergencyMultisig_RevertIfZeroAddress() public {
        vm.expectRevert(LSGVoter.InvalidAddress.selector);
        voter.setEmergencyMultisig(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetStrategies_ReturnsAllStrategies() public {
        address[] memory allStrategies = voter.getStrategies();
        assertEq(allStrategies.length, 2, "2 strategies");
        assertEq(allStrategies[0], strategy1, "Strategy1");
        assertEq(allStrategies[1], strategy2, "Strategy2");
    }

    function test_GetAccountVotes_ReturnsVotedStrategies() public {
        address[] memory strategies = new address[](2);
        strategies[0] = strategy1;
        strategies[1] = strategy2;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 60;
        weights[1] = 40;

        vm.prank(alice);
        voter.vote(strategies, weights);

        address[] memory voted = voter.getAccountVotes(alice);
        assertEq(voted.length, 2, "Voted for 2 strategies");
    }

    function test_GetRevenueTokens_ReturnsAllTokens() public {
        // Notify revenue for tokens
        token1.mint(revenueRouter, 1000 ether);
        token2.mint(revenueRouter, 1000 ether);

        vm.startPrank(revenueRouter);
        token1.approve(address(voter), 1000 ether);
        token2.approve(address(voter), 1000 ether);

        voter.notifyRevenue(address(token1), 1000 ether);
        voter.notifyRevenue(address(token2), 1000 ether);
        vm.stopPrank();

        address[] memory tokens = voter.getRevenueTokens();
        assertEq(tokens.length, 2, "2 revenue tokens");
        assertEq(tokens[0], address(token1), "Token1");
        assertEq(tokens[1], address(token2), "Token2");
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_FullVotingCycle() public {
        // Multiple users vote
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        strategies[0] = strategy1;
        vm.prank(alice);
        voter.vote(strategies, weights);

        strategies[0] = strategy2;
        vm.prank(bob);
        voter.vote(strategies, weights);

        // Revenue arrives
        token1.mint(revenueRouter, 5000 ether);
        vm.prank(revenueRouter);
        token1.approve(address(voter), 5000 ether);

        vm.prank(revenueRouter);
        voter.notifyRevenue(address(token1), 5000 ether);

        // Distribute
        voter.distributeAllTokens(strategy1);
        voter.distributeAllTokens(strategy2);

        // Verify distribution
        assertEq(token1.balanceOf(strategy1), 3000 ether, "Strategy1 gets 3/5");
        assertEq(token1.balanceOf(strategy2), 2000 ether, "Strategy2 gets 2/5");

        // Move to next epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // Users can vote again
        strategies[0] = strategy1;
        vm.prank(alice);
        voter.vote(strategies, weights);
    }

    function test_Integration_DelegationAndVoting() public {
        // Alice delegates to Bob
        vm.prank(alice);
        voter.delegate(bob);

        // Bob votes with delegated power (2 + 3 = 5)
        address[] memory strategies = new address[](1);
        strategies[0] = strategy1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(bob);
        voter.vote(strategies, weights);

        assertEq(voter.strategy_Weight(strategy1), 5, "Bob votes with 5 power");
        assertEq(bribe1.balanceOf(bob), 5, "Bob's bribe balance is 5");
    }

    // Events for testing
    event Voted(address indexed voter, address indexed strategy, uint256 weight);
    event VoteReset(address indexed voter);
    event DelegateSet(address indexed owner, address indexed delegate);
    event RevenueNotified(address indexed token, uint256 amount);
}
