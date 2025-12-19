// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {Bribe} from "../src/Bribe.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract BribeTest is Test {
    Bribe public bribe;
    MockERC20 public rewardToken1;
    MockERC20 public rewardToken2;

    address public voter = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public rewarder = address(0x4);

    uint256 public constant DURATION = 7 days;
    uint256 public constant INITIAL_REWARD = 7000 ether; // 1000 per day

    // Tolerance for Synthetix-style reward precision (0.001% of reward amount)
    // The rewardRate = amount / DURATION causes precision loss from integer division
    uint256 public constant PRECISION_TOLERANCE = 1e15; // 0.001 ether

    // Events for testing
    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event RewardNotified(address indexed token, uint256 amount, uint256 rewardRate);
    event RewardClaimed(address indexed account, address indexed token, uint256 amount);
    event RewardTokenAdded(address indexed token);

    function setUp() public {
        // Deploy bribe with voter as the authorized caller
        vm.prank(voter);
        bribe = new Bribe(voter);

        // Deploy reward tokens
        rewardToken1 = new MockERC20("Reward Token 1", "RWD1", 18);
        rewardToken2 = new MockERC20("Reward Token 2", "RWD2", 18);

        // Mint tokens to rewarder
        rewardToken1.mint(rewarder, 1_000_000 ether);
        rewardToken2.mint(rewarder, 1_000_000 ether);

        // Approve bribe contract
        vm.startPrank(rewarder);
        rewardToken1.approve(address(bribe), type(uint256).max);
        rewardToken2.approve(address(bribe), type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_SetsVoter() public view {
        assertEq(bribe.voter(), voter);
    }

    function test_Constructor_RevertIfZeroAddress() public {
        vm.expectRevert(Bribe.InvalidAddress.selector);
        new Bribe(address(0));
    }

    function test_Constants() public view {
        assertEq(bribe.DURATION(), 7 days);
        assertEq(bribe.MAX_REWARD_TOKENS(), 10);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_UpdatesBalance() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        assertEq(bribe.balanceOf(alice), 100 ether);
        assertEq(bribe.totalSupply(), 100 ether);
    }

    function test_Deposit_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Deposited(alice, 100 ether);

        vm.prank(voter);
        bribe._deposit(100 ether, alice);
    }

    function test_Deposit_MultipleAccounts() public {
        vm.startPrank(voter);
        bribe._deposit(100 ether, alice);
        bribe._deposit(200 ether, bob);
        vm.stopPrank();

        assertEq(bribe.balanceOf(alice), 100 ether);
        assertEq(bribe.balanceOf(bob), 200 ether);
        assertEq(bribe.totalSupply(), 300 ether);
    }

    function test_Deposit_ZeroAmountNoOp() public {
        vm.prank(voter);
        bribe._deposit(0, alice);

        assertEq(bribe.balanceOf(alice), 0);
        assertEq(bribe.totalSupply(), 0);
    }

    function test_Deposit_RevertIfNotVoter() public {
        vm.prank(alice);
        vm.expectRevert(Bribe.NotVoter.selector);
        bribe._deposit(100 ether, alice);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Withdraw_UpdatesBalance() public {
        vm.startPrank(voter);
        bribe._deposit(100 ether, alice);
        bribe._withdraw(40 ether, alice);
        vm.stopPrank();

        assertEq(bribe.balanceOf(alice), 60 ether);
        assertEq(bribe.totalSupply(), 60 ether);
    }

    function test_Withdraw_EmitsEvent() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(alice, 40 ether);

        vm.prank(voter);
        bribe._withdraw(40 ether, alice);
    }

    function test_Withdraw_ZeroAmountNoOp() public {
        vm.startPrank(voter);
        bribe._deposit(100 ether, alice);
        bribe._withdraw(0, alice);
        vm.stopPrank();

        assertEq(bribe.balanceOf(alice), 100 ether);
    }

    function test_Withdraw_RevertIfNotVoter() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        vm.prank(alice);
        vm.expectRevert(Bribe.NotVoter.selector);
        bribe._withdraw(40 ether, alice);
    }

    /*//////////////////////////////////////////////////////////////
                        NOTIFY REWARD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_NotifyRewardAmount_AddsToken() public {
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        assertEq(bribe.isRewardToken(address(rewardToken1)), true);
        assertEq(bribe.rewardTokensLength(), 1);
        assertEq(bribe.rewardTokens(0), address(rewardToken1));
    }

    function test_NotifyRewardAmount_SetsRewardRate() public {
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        // rewardRate = 7000 ether / 7 days = ~1000 ether per day
        uint256 expectedRate = INITIAL_REWARD / DURATION;
        assertEq(bribe.rewardRate(address(rewardToken1)), expectedRate);
    }

    function test_NotifyRewardAmount_SetsPeriodFinish() public {
        uint256 startTime = block.timestamp;
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        assertEq(bribe.periodFinish(address(rewardToken1)), startTime + DURATION);
    }

    function test_NotifyRewardAmount_EmitsEvent() public {
        uint256 expectedRate = INITIAL_REWARD / DURATION;

        vm.expectEmit(true, false, false, true);
        emit RewardNotified(address(rewardToken1), INITIAL_REWARD, expectedRate);

        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);
    }

    function test_NotifyRewardAmount_TransfersTokens() public {
        uint256 balanceBefore = rewardToken1.balanceOf(address(bribe));

        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        assertEq(rewardToken1.balanceOf(address(bribe)), balanceBefore + INITIAL_REWARD);
    }

    function test_NotifyRewardAmount_AddsToExistingPeriod() public {
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        // Move forward 3 days
        vm.warp(block.timestamp + 3 days);

        uint256 remaining = 4 days; // 7 - 3 = 4 days left
        uint256 leftover = remaining * (INITIAL_REWARD / DURATION);

        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        // New rate = (newAmount + leftover) / DURATION
        uint256 expectedRate = (INITIAL_REWARD + leftover) / DURATION;
        assertEq(bribe.rewardRate(address(rewardToken1)), expectedRate);
    }

    function test_NotifyRewardAmount_MultipleTokens() public {
        vm.startPrank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);
        bribe.notifyRewardAmount(address(rewardToken2), INITIAL_REWARD / 2);
        vm.stopPrank();

        assertEq(bribe.rewardTokensLength(), 2);
        assertEq(bribe.isRewardToken(address(rewardToken1)), true);
        assertEq(bribe.isRewardToken(address(rewardToken2)), true);
    }

    function test_NotifyRewardAmount_RevertIfZeroAddress() public {
        vm.prank(rewarder);
        vm.expectRevert(Bribe.InvalidAddress.selector);
        bribe.notifyRewardAmount(address(0), INITIAL_REWARD);
    }

    function test_NotifyRewardAmount_RevertIfZeroAmount() public {
        vm.prank(rewarder);
        vm.expectRevert(Bribe.ZeroRewardAmount.selector);
        bribe.notifyRewardAmount(address(rewardToken1), 0);
    }

    function test_NotifyRewardAmount_RevertIfMaxTokensReached() public {
        // Add MAX_REWARD_TOKENS (10) different tokens
        for (uint256 i = 0; i < 10; i++) {
            MockERC20 token = new MockERC20("Token", "TKN", 18);
            token.mint(rewarder, 1000 ether);
            vm.prank(rewarder);
            token.approve(address(bribe), type(uint256).max);
            vm.prank(rewarder);
            bribe.notifyRewardAmount(address(token), 1000 ether);
        }

        // 11th token should revert
        MockERC20 extraToken = new MockERC20("Extra", "EXT", 18);
        extraToken.mint(rewarder, 1000 ether);
        vm.prank(rewarder);
        extraToken.approve(address(bribe), type(uint256).max);

        vm.prank(rewarder);
        vm.expectRevert(Bribe.MaxRewardTokensReached.selector);
        bribe.notifyRewardAmount(address(extraToken), 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            EARNED TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Earned_ZeroIfNoDeposit() public {
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        vm.warp(block.timestamp + 1 days);

        assertEq(bribe.earned(alice, address(rewardToken1)), 0);
    }

    function test_Earned_ZeroIfNoRewards() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        vm.warp(block.timestamp + 1 days);

        assertEq(bribe.earned(alice, address(rewardToken1)), 0);
    }

    function test_Earned_ProportionalToBalance() public {
        // Alice deposits 100, Bob deposits 200 (1/3 and 2/3)
        vm.startPrank(voter);
        bribe._deposit(100 ether, alice);
        bribe._deposit(200 ether, bob);
        vm.stopPrank();

        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        // Wait full period
        vm.warp(block.timestamp + DURATION);

        uint256 aliceEarned = bribe.earned(alice, address(rewardToken1));
        uint256 bobEarned = bribe.earned(bob, address(rewardToken1));

        // Alice should earn ~1/3, Bob ~2/3 (within precision tolerance)
        assertApproxEqAbs(aliceEarned, INITIAL_REWARD / 3, PRECISION_TOLERANCE);
        assertApproxEqAbs(bobEarned, (INITIAL_REWARD * 2) / 3, PRECISION_TOLERANCE);
    }

    function test_Earned_AccumulatesOverTime() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        // After 1 day
        vm.warp(block.timestamp + 1 days);
        uint256 earnedAfter1Day = bribe.earned(alice, address(rewardToken1));
        assertApproxEqAbs(earnedAfter1Day, INITIAL_REWARD / 7, PRECISION_TOLERANCE);

        // After 3.5 days
        vm.warp(block.timestamp + 2.5 days);
        uint256 earnedAfter3_5Days = bribe.earned(alice, address(rewardToken1));
        assertApproxEqAbs(earnedAfter3_5Days, INITIAL_REWARD / 2, PRECISION_TOLERANCE);

        // After 7 days (full period)
        vm.warp(block.timestamp + 3.5 days);
        uint256 earnedAfter7Days = bribe.earned(alice, address(rewardToken1));
        assertApproxEqAbs(earnedAfter7Days, INITIAL_REWARD, PRECISION_TOLERANCE);
    }

    function test_Earned_StopsAfterPeriodFinish() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        // After full period
        vm.warp(block.timestamp + DURATION);
        uint256 earnedAtEnd = bribe.earned(alice, address(rewardToken1));

        // After double the period
        vm.warp(block.timestamp + DURATION);
        uint256 earnedLater = bribe.earned(alice, address(rewardToken1));

        assertEq(earnedAtEnd, earnedLater, "Should not earn more after period ends");
    }

    function test_Earned_MultipleTokens() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        vm.startPrank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);
        bribe.notifyRewardAmount(address(rewardToken2), INITIAL_REWARD / 2);
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION);

        uint256 earned1 = bribe.earned(alice, address(rewardToken1));
        uint256 earned2 = bribe.earned(alice, address(rewardToken2));

        assertApproxEqAbs(earned1, INITIAL_REWARD, PRECISION_TOLERANCE);
        assertApproxEqAbs(earned2, INITIAL_REWARD / 2, PRECISION_TOLERANCE);
    }

    /*//////////////////////////////////////////////////////////////
                          GET REWARD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetReward_TransfersEarned() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        vm.warp(block.timestamp + DURATION);

        uint256 balanceBefore = rewardToken1.balanceOf(alice);

        vm.prank(alice);
        bribe.getReward();

        uint256 balanceAfter = rewardToken1.balanceOf(alice);
        assertApproxEqAbs(balanceAfter - balanceBefore, INITIAL_REWARD, PRECISION_TOLERANCE);
    }

    function test_GetReward_ClearsRewards() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        vm.warp(block.timestamp + DURATION);

        vm.prank(alice);
        bribe.getReward();

        assertEq(bribe.earned(alice, address(rewardToken1)), 0);
    }

    function test_GetReward_EmitsEvent() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        vm.warp(block.timestamp + DURATION);

        uint256 expectedReward = bribe.earned(alice, address(rewardToken1));

        vm.expectEmit(true, true, false, true);
        emit RewardClaimed(alice, address(rewardToken1), expectedReward);

        vm.prank(alice);
        bribe.getReward();
    }

    function test_GetReward_AllTokens() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        vm.startPrank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);
        bribe.notifyRewardAmount(address(rewardToken2), INITIAL_REWARD / 2);
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION);

        vm.prank(alice);
        uint256[] memory amounts = bribe.getReward();

        assertEq(amounts.length, 2);
        assertApproxEqAbs(amounts[0], INITIAL_REWARD, PRECISION_TOLERANCE);
        assertApproxEqAbs(amounts[1], INITIAL_REWARD / 2, PRECISION_TOLERANCE);
    }

    function test_GetRewardForToken_SingleToken() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        vm.startPrank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);
        bribe.notifyRewardAmount(address(rewardToken2), INITIAL_REWARD / 2);
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION);

        uint256 balance1Before = rewardToken1.balanceOf(alice);
        uint256 balance2Before = rewardToken2.balanceOf(alice);

        vm.prank(alice);
        bribe.getRewardForToken(address(rewardToken1));

        assertApproxEqAbs(rewardToken1.balanceOf(alice) - balance1Before, INITIAL_REWARD, PRECISION_TOLERANCE);
        assertEq(rewardToken2.balanceOf(alice), balance2Before, "Token2 should not change");
    }

    function test_GetReward_ZeroIfNothingEarned() public {
        vm.prank(alice);
        uint256[] memory amounts = bribe.getReward();
        assertEq(amounts.length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LastTimeRewardApplicable_ReturnsCurrentTime() public {
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        vm.warp(block.timestamp + 1 days);

        assertEq(bribe.lastTimeRewardApplicable(address(rewardToken1)), block.timestamp);
    }

    function test_LastTimeRewardApplicable_ReturnsPeriodFinish() public {
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        uint256 finish = bribe.periodFinish(address(rewardToken1));
        vm.warp(finish + 1 days);

        assertEq(bribe.lastTimeRewardApplicable(address(rewardToken1)), finish);
    }

    function test_RewardPerToken_ZeroIfNoSupply() public {
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        vm.warp(block.timestamp + 1 days);

        assertEq(bribe.rewardPerToken(address(rewardToken1)), 0);
    }

    function test_RewardPerToken_IncreasesOverTime() public {
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        uint256 rptBefore = bribe.rewardPerToken(address(rewardToken1));

        vm.warp(block.timestamp + 1 days);

        uint256 rptAfter = bribe.rewardPerToken(address(rewardToken1));

        assertGt(rptAfter, rptBefore);
    }

    function test_GetRewardTokens_ReturnsArray() public {
        vm.startPrank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);
        bribe.notifyRewardAmount(address(rewardToken2), INITIAL_REWARD / 2);
        vm.stopPrank();

        address[] memory tokens = bribe.getRewardTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(rewardToken1));
        assertEq(tokens[1], address(rewardToken2));
    }

    function test_Left_ReturnsRemainingRewards() public {
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        uint256 leftAtStart = bribe.left(address(rewardToken1));
        assertApproxEqAbs(leftAtStart, INITIAL_REWARD, INITIAL_REWARD / DURATION); // Within 1 second of rewards

        vm.warp(block.timestamp + 3.5 days);
        uint256 leftHalfway = bribe.left(address(rewardToken1));
        assertApproxEqAbs(leftHalfway, INITIAL_REWARD / 2, INITIAL_REWARD / DURATION);

        vm.warp(block.timestamp + 3.5 days);
        uint256 leftAtEnd = bribe.left(address(rewardToken1));
        assertEq(leftAtEnd, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CompleteFlow_DepositRewardClaim() public {
        // 1. Alice deposits
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        // 2. Rewards are notified
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        // 3. Time passes
        vm.warp(block.timestamp + 3.5 days);

        // 4. Check earned (should be ~half)
        uint256 earnedMid = bribe.earned(alice, address(rewardToken1));
        assertApproxEqAbs(earnedMid, INITIAL_REWARD / 2, PRECISION_TOLERANCE);

        // 5. Claim
        vm.prank(alice);
        bribe.getReward();
        assertApproxEqAbs(rewardToken1.balanceOf(alice), INITIAL_REWARD / 2, PRECISION_TOLERANCE);

        // 6. More time passes
        vm.warp(block.timestamp + 3.5 days);

        // 7. Claim rest
        vm.prank(alice);
        bribe.getReward();
        assertApproxEqAbs(rewardToken1.balanceOf(alice), INITIAL_REWARD, PRECISION_TOLERANCE);
    }

    function test_CompleteFlow_MultipleVoters() public {
        // Alice and Bob deposit (1:2 ratio)
        vm.startPrank(voter);
        bribe._deposit(100 ether, alice);
        bribe._deposit(200 ether, bob);
        vm.stopPrank();

        // Notify rewards
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        // Full period passes
        vm.warp(block.timestamp + DURATION);

        // Both claim
        vm.prank(alice);
        bribe.getReward();

        vm.prank(bob);
        bribe.getReward();

        // Check balances (should be 1:2 ratio)
        uint256 aliceBalance = rewardToken1.balanceOf(alice);
        uint256 bobBalance = rewardToken1.balanceOf(bob);

        assertApproxEqAbs(aliceBalance * 2, bobBalance, PRECISION_TOLERANCE);
        assertApproxEqAbs(aliceBalance + bobBalance, INITIAL_REWARD, PRECISION_TOLERANCE);
    }

    function test_CompleteFlow_WithdrawBeforeClaim() public {
        // Alice deposits
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        // Rewards notified
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        // Half period passes
        vm.warp(block.timestamp + 3.5 days);

        // Alice withdraws (triggers updateReward, locks in earned amount)
        vm.prank(voter);
        bribe._withdraw(100 ether, alice);

        // More time passes (but no more earning since balance is 0)
        vm.warp(block.timestamp + 3.5 days);

        // Alice can still claim what she earned before withdrawal
        vm.prank(alice);
        bribe.getReward();

        assertApproxEqAbs(rewardToken1.balanceOf(alice), INITIAL_REWARD / 2, PRECISION_TOLERANCE);
    }

    function test_CompleteFlow_LateDeposit() public {
        // Rewards notified first
        vm.prank(rewarder);
        bribe.notifyRewardAmount(address(rewardToken1), INITIAL_REWARD);

        // Half period passes with no deposits
        vm.warp(block.timestamp + 3.5 days);

        // Alice deposits (misses first half of rewards)
        vm.prank(voter);
        bribe._deposit(100 ether, alice);

        // Rest of period passes
        vm.warp(block.timestamp + 3.5 days);

        // Alice claims (should only get half)
        vm.prank(alice);
        bribe.getReward();

        assertApproxEqAbs(rewardToken1.balanceOf(alice), INITIAL_REWARD / 2, PRECISION_TOLERANCE);
    }
}
