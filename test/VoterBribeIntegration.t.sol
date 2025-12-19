// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {LSGVoter} from "../src/LSGVoter.sol";
import {Bribe} from "../src/Bribe.sol";
import {MultiTokenRouter} from "../src/MultiTokenRouter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";

/// @title VoterBribeIntegration
/// @notice Integration tests for the complete voting → bribe → claim flow
contract VoterBribeIntegrationTest is Test {
    LSGVoter public voter;
    MultiTokenRouter public router;
    Bribe public bribe1;
    Bribe public bribe2;
    MockERC20 public revenueToken;
    MockERC20 public bribeToken;
    MockERC721 public seatNFT;

    address public owner = address(this);
    address public treasury = address(0x1);
    address public emergencyMultisig = address(0x2);
    address public strategy1 = address(0x3);
    address public strategy2 = address(0x4);
    address public alice = address(0x5);
    address public bob = address(0x6);
    address public briber = address(0x7);

    uint256 public constant EPOCH_DURATION = 7 days;
    uint256 public constant EPOCH_START = 1704067200;
    uint256 public constant REVENUE_AMOUNT = 10_000 ether;
    uint256 public constant BRIBE_AMOUNT = 7000 ether;

    // Tolerance for Synthetix-style reward precision (0.001% of reward amount)
    uint256 public constant PRECISION_TOLERANCE = 1e15; // 0.001 ether

    event Voted(address indexed voter, address indexed strategy, uint256 weight);
    event RevenueNotified(address indexed token, uint256 amount);
    event RevenueDistributed(address indexed strategy, address indexed token, uint256 amount);

    function setUp() public {
        // Warp to a known epoch start for predictable testing
        vm.warp(EPOCH_START + (10 * EPOCH_DURATION)); // Epoch 10

        // Deploy tokens
        revenueToken = new MockERC20("Revenue Token", "REV", 18);
        bribeToken = new MockERC20("Bribe Token", "BRIBE", 18);
        seatNFT = new MockERC721();

        // Deploy voter
        voter = new LSGVoter(address(seatNFT), treasury, emergencyMultisig);

        // Deploy router and configure
        router = new MultiTokenRouter(address(voter));
        router.setWhitelistedToken(address(revenueToken), true);
        voter.setRevenueRouter(address(router));

        // Deploy bribes (with voter as authorized caller)
        // Note: Bribes are deployed by owner but need voter address
        bribe1 = new Bribe(address(voter));
        bribe2 = new Bribe(address(voter));

        // Add strategies with bribes
        voter.addStrategy(strategy1, address(bribe1));
        voter.addStrategy(strategy2, address(bribe2));

        // Mint NFTs to voters (Alice gets 2, Bob gets 1)
        seatNFT.mint(alice); // tokenId 0
        seatNFT.mint(alice); // tokenId 1
        seatNFT.mint(bob);   // tokenId 2

        // Fund router with revenue
        revenueToken.mint(address(router), REVENUE_AMOUNT);

        // Fund briber with bribe tokens
        bribeToken.mint(briber, BRIBE_AMOUNT * 10);
        vm.prank(briber);
        bribeToken.approve(address(bribe1), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLETE FLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_VoteFlushDistributeClaim() public {
        // 1. Alice and Bob vote for different strategies
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);

        // Alice votes for strategy1 (2 NFTs = 2 voting power)
        strategies[0] = strategy1;
        weights[0] = 100;
        vm.prank(alice);
        voter.vote(strategies, weights);

        // Bob votes for strategy2 (1 NFT = 1 voting power)
        strategies[0] = strategy2;
        vm.prank(bob);
        voter.vote(strategies, weights);

        // Check weights
        assertEq(voter.strategy_Weight(strategy1), 2);
        assertEq(voter.strategy_Weight(strategy2), 1);
        assertEq(voter.totalWeight(), 3);

        // 2. Briber adds bribe rewards to strategy1
        vm.prank(briber);
        bribe1.notifyRewardAmount(address(bribeToken), BRIBE_AMOUNT);

        // 3. Flush revenue from router
        router.flush(address(revenueToken));

        // 4. Distribute to strategies
        voter.distributeToAllStrategies(address(revenueToken));

        // Check distribution (2:1 ratio based on weights)
        // Strategy1 should get 2/3, Strategy2 should get 1/3
        uint256 strategy1Balance = revenueToken.balanceOf(strategy1);
        uint256 strategy2Balance = revenueToken.balanceOf(strategy2);

        assertApproxEqAbs(strategy1Balance, (REVENUE_AMOUNT * 2) / 3, PRECISION_TOLERANCE);
        assertApproxEqAbs(strategy2Balance, REVENUE_AMOUNT / 3, PRECISION_TOLERANCE);

        // 5. Time passes for bribe rewards to accrue
        vm.warp(block.timestamp + EPOCH_DURATION);

        // 6. Alice claims bribe rewards
        vm.prank(alice);
        bribe1.getReward();

        // Alice should receive full bribe (she's the only voter for strategy1)
        assertApproxEqAbs(bribeToken.balanceOf(alice), BRIBE_AMOUNT, PRECISION_TOLERANCE);
    }

    function test_Integration_MultipleVotersSameStrategy() public {
        // Alice (2 NFTs) and Bob (1 NFT) both vote for strategy1
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = strategy1;
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        vm.prank(bob);
        voter.vote(strategies, weights);

        // Check weights (total 3 voting power on strategy1)
        assertEq(voter.strategy_Weight(strategy1), 3);
        assertEq(voter.totalWeight(), 3);

        // Add bribe
        vm.prank(briber);
        bribe1.notifyRewardAmount(address(bribeToken), BRIBE_AMOUNT);

        // Wait for rewards
        vm.warp(block.timestamp + EPOCH_DURATION);

        // Both claim
        vm.prank(alice);
        bribe1.getReward();

        vm.prank(bob);
        bribe1.getReward();

        // Alice should get 2/3, Bob 1/3
        assertApproxEqAbs(bribeToken.balanceOf(alice), (BRIBE_AMOUNT * 2) / 3, PRECISION_TOLERANCE);
        assertApproxEqAbs(bribeToken.balanceOf(bob), BRIBE_AMOUNT / 3, PRECISION_TOLERANCE);
    }

    function test_Integration_ResetAndRevote() public {
        // Alice votes for strategy1
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = strategy1;
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        assertEq(voter.strategy_Weight(strategy1), 2);
        assertEq(bribe1.balanceOf(alice), 2);

        // Move to next epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // Alice changes vote to strategy2
        strategies[0] = strategy2;
        vm.prank(alice);
        voter.vote(strategies, weights);

        // Check weights updated
        assertEq(voter.strategy_Weight(strategy1), 0);
        assertEq(voter.strategy_Weight(strategy2), 2);

        // Check bribe balances updated
        assertEq(bribe1.balanceOf(alice), 0);
        assertEq(bribe2.balanceOf(alice), 2);
    }

    function test_Integration_BribeBeforeVote() public {
        // Bribe added before anyone votes
        vm.prank(briber);
        bribe1.notifyRewardAmount(address(bribeToken), BRIBE_AMOUNT);

        // Wait half period
        vm.warp(block.timestamp + 3.5 days);

        // Alice votes (joins mid-period)
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = strategy1;
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Wait for rest of period
        vm.warp(block.timestamp + 3.5 days);

        // Alice claims (should only get rewards from when she joined)
        vm.prank(alice);
        bribe1.getReward();

        // Should get approximately half (within tolerance due to timing)
        assertApproxEqAbs(bribeToken.balanceOf(alice), BRIBE_AMOUNT / 2, BRIBE_AMOUNT / 100);
    }

    function test_Integration_MultipleEpochsWithVoteChanges() public {
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);

        // Epoch 10: Alice votes strategy1
        strategies[0] = strategy1;
        weights[0] = 100;
        vm.prank(alice);
        voter.vote(strategies, weights);

        // Add bribe
        vm.prank(briber);
        bribe1.notifyRewardAmount(address(bribeToken), BRIBE_AMOUNT);

        // Epoch 11: Add more revenue and Bob joins
        vm.warp(block.timestamp + EPOCH_DURATION);
        revenueToken.mint(address(router), REVENUE_AMOUNT);

        vm.prank(bob);
        voter.vote(strategies, weights);

        // Epoch 12: Flush and distribute accumulated revenue
        vm.warp(block.timestamp + EPOCH_DURATION);
        router.flush(address(revenueToken));
        voter.distributeToAllStrategies(address(revenueToken));

        // Both claim bribes
        vm.prank(alice);
        bribe1.getReward();

        vm.prank(bob);
        bribe1.getReward();

        // Alice was there full period, Bob joined halfway through the bribe
        // Alice should have more than Bob
        assertGt(bribeToken.balanceOf(alice), bribeToken.balanceOf(bob));
    }

    function test_Integration_EmergencyPausePreventsVoting() public {
        // Emergency pause
        voter.emergencyPause();

        // Try to vote - should revert
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = strategy1;
        weights[0] = 100;

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        voter.vote(strategies, weights);

        // Unpause
        voter.unpause();

        // Now vote should work
        vm.prank(alice);
        voter.vote(strategies, weights);

        assertEq(voter.strategy_Weight(strategy1), 2);
    }

    function test_Integration_KilledStrategyDoesNotReceive() public {
        // Alice votes for strategy1
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = strategy1;
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Flush revenue
        router.flush(address(revenueToken));

        // Kill strategy1 before distribution
        voter.killStrategy(strategy1);

        // Try to distribute - killed strategy should not receive
        voter.distributeToAllStrategies(address(revenueToken));

        // Strategy1 should not have received (killed before distribution)
        // The pending revenue was sent to treasury when killed
        assertEq(revenueToken.balanceOf(strategy1), 0);
    }

    function test_Integration_NoVotesRevenueGoesToTreasury() public {
        // Flush revenue with no votes
        router.flush(address(revenueToken));

        // Revenue should go to treasury
        assertEq(revenueToken.balanceOf(treasury), REVENUE_AMOUNT);
    }

    function test_Integration_DelegationAffectsVotingPower() public {
        // Alice delegates to Bob
        vm.prank(alice);
        voter.delegate(bob);

        // Check voting power
        assertEq(voter.getVotingPower(alice), 0); // Delegated away
        assertEq(voter.getVotingPower(bob), 3); // 1 own + 2 from Alice

        // Bob votes with combined power
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = strategy1;
        weights[0] = 100;

        vm.prank(bob);
        voter.vote(strategies, weights);

        assertEq(voter.strategy_Weight(strategy1), 3);

        // Add bribe
        vm.prank(briber);
        bribe1.notifyRewardAmount(address(bribeToken), BRIBE_AMOUNT);

        // Wait and claim
        vm.warp(block.timestamp + EPOCH_DURATION);

        vm.prank(bob);
        bribe1.getReward();

        // Bob gets all rewards (Alice delegated but Bob voted with combined power)
        assertApproxEqAbs(bribeToken.balanceOf(bob), BRIBE_AMOUNT, PRECISION_TOLERANCE);
    }

    function test_Integration_SplitVotesAcrossStrategies() public {
        // Alice splits votes 50/50 between strategy1 and strategy2
        address[] memory strategies = new address[](2);
        uint256[] memory weights = new uint256[](2);
        strategies[0] = strategy1;
        strategies[1] = strategy2;
        weights[0] = 50;
        weights[1] = 50;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Each strategy should get 1 vote (Alice has 2 NFTs, split evenly)
        assertEq(voter.strategy_Weight(strategy1), 1);
        assertEq(voter.strategy_Weight(strategy2), 1);

        // Alice's bribe balances
        assertEq(bribe1.balanceOf(alice), 1);
        assertEq(bribe2.balanceOf(alice), 1);
    }

    function test_Integration_RevenueDistributionProportional() public {
        // Alice (2 NFTs) votes strategy1, Bob (1 NFT) votes strategy2
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);

        strategies[0] = strategy1;
        weights[0] = 100;
        vm.prank(alice);
        voter.vote(strategies, weights);

        strategies[0] = strategy2;
        vm.prank(bob);
        voter.vote(strategies, weights);

        // Flush and distribute
        router.flush(address(revenueToken));
        voter.distributeToAllStrategies(address(revenueToken));

        // 2:1 ratio based on voting power
        uint256 strategy1Balance = revenueToken.balanceOf(strategy1);
        uint256 strategy2Balance = revenueToken.balanceOf(strategy2);

        assertApproxEqAbs(strategy1Balance, (REVENUE_AMOUNT * 2) / 3, PRECISION_TOLERANCE);
        assertApproxEqAbs(strategy2Balance, REVENUE_AMOUNT / 3, PRECISION_TOLERANCE);
        assertApproxEqAbs(strategy1Balance + strategy2Balance, REVENUE_AMOUNT, PRECISION_TOLERANCE);
    }
}
