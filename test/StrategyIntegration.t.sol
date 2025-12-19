// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {LSGVoter} from "../src/LSGVoter.sol";
import {MultiTokenRouter} from "../src/MultiTokenRouter.sol";
import {Bribe} from "../src/Bribe.sol";
import {DirectDistributionStrategy} from "../src/strategies/DirectDistributionStrategy.sol";
import {GrowthTreasuryStrategy} from "../src/strategies/GrowthTreasuryStrategy.sol";
import {LBTBoostStrategy} from "../src/strategies/LBTBoostStrategy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockKodiakRouter} from "./mocks/MockKodiakRouter.sol";
import {MockLBT} from "./mocks/MockLBT.sol";

/// @title StrategyIntegrationTest
/// @notice End-to-end integration tests: Router → Voter → Strategy → Destination
contract StrategyIntegrationTest is Test {
    // Core contracts
    LSGVoter public voter;
    MultiTokenRouter public router;
    Bribe public bribe;

    // Strategy contracts
    DirectDistributionStrategy public directStrategy;
    GrowthTreasuryStrategy public treasuryStrategy;
    LBTBoostStrategy public lbtStrategy;

    // Mocks
    MockERC20 public revenueToken;
    MockERC20 public targetToken;
    MockERC721 public seatNFT;
    MockKodiakRouter public kodiakRouter;
    MockLBT public lbt;

    // Addresses
    address public owner = address(this);
    address public treasury = address(0x1);
    address public growthTreasury = address(0x2);
    address public emergencyMultisig = address(0x3);
    address public alice = address(0x4);
    address public bob = address(0x5);

    // Constants
    uint256 public constant EPOCH_DURATION = 7 days;
    uint256 public constant EPOCH_START = 1704067200;
    uint256 public constant REVENUE_AMOUNT = 10_000 ether;
    uint256 public constant PRECISION_TOLERANCE = 1e15;
    bytes public constant MOCK_PATH = hex"0123456789";

    function setUp() public {
        // Warp to a known epoch
        vm.warp(EPOCH_START + (10 * EPOCH_DURATION));

        // Deploy tokens
        revenueToken = new MockERC20("Revenue Token", "REV", 18);
        targetToken = new MockERC20("Target Token", "TGT", 18);
        seatNFT = new MockERC721();

        // Deploy core voter
        voter = new LSGVoter(address(seatNFT), treasury, emergencyMultisig);

        // Deploy router
        router = new MultiTokenRouter(address(voter));
        router.setWhitelistedToken(address(revenueToken), true);
        voter.setRevenueRouter(address(router));

        // Deploy Kodiak and LBT mocks
        kodiakRouter = new MockKodiakRouter(address(targetToken));
        lbt = new MockLBT();

        // Deploy bribe (for DirectDistributionStrategy)
        bribe = new Bribe(address(voter));

        // Deploy strategies
        directStrategy = new DirectDistributionStrategy(address(voter), address(bribe));
        treasuryStrategy = new GrowthTreasuryStrategy(address(voter), growthTreasury);
        lbtStrategy = new LBTBoostStrategy(
            address(voter),
            address(kodiakRouter),
            address(lbt),
            address(targetToken)
        );

        // Set up LBT strategy swap path
        lbtStrategy.setSwapPath(address(revenueToken), MOCK_PATH);

        // Add strategies to voter (using strategy addresses as the "strategy" destination)
        voter.addStrategy(address(directStrategy), address(bribe));
        voter.addStrategy(address(treasuryStrategy), address(0)); // No bribe for treasury strategy
        voter.addStrategy(address(lbtStrategy), address(0)); // No bribe for LBT strategy

        // Mint NFTs to voters
        seatNFT.mint(alice); // tokenId 0
        seatNFT.mint(alice); // tokenId 1
        seatNFT.mint(bob);   // tokenId 2

        // Fund router with revenue
        revenueToken.mint(address(router), REVENUE_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                    DIRECT DISTRIBUTION FLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Flow_DirectDistribution_RouterToVoterToStrategyToBribe() public {
        // 1. Alice votes for DirectDistributionStrategy
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = address(directStrategy);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // 2. Flush revenue from router to voter
        router.flush(address(revenueToken));

        // 3. Distribute to strategies
        voter.distributeToAllStrategies(address(revenueToken));

        // 4. Check revenue arrived at strategy
        uint256 strategyBalance = revenueToken.balanceOf(address(directStrategy));
        assertEq(strategyBalance, REVENUE_AMOUNT, "Revenue should be at strategy");

        // 5. Execute strategy to forward to bribe
        directStrategy.execute(address(revenueToken));

        // 6. Verify bribe received tokens
        assertEq(revenueToken.balanceOf(address(bribe)), REVENUE_AMOUNT, "Bribe should receive all revenue");
        assertEq(revenueToken.balanceOf(address(directStrategy)), 0, "Strategy should be empty");

        // 7. Wait for rewards to accrue
        vm.warp(block.timestamp + EPOCH_DURATION);

        // 8. Alice claims rewards from bribe
        vm.prank(alice);
        bribe.getReward();

        // 9. Verify Alice received rewards
        assertApproxEqAbs(revenueToken.balanceOf(alice), REVENUE_AMOUNT, PRECISION_TOLERANCE);
    }

    /*//////////////////////////////////////////////////////////////
                    GROWTH TREASURY FLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Flow_GrowthTreasury_RouterToVoterToStrategyToTreasury() public {
        // 1. Bob votes for GrowthTreasuryStrategy
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = address(treasuryStrategy);
        weights[0] = 100;

        vm.prank(bob);
        voter.vote(strategies, weights);

        // 2. Flush and distribute
        router.flush(address(revenueToken));
        voter.distributeToAllStrategies(address(revenueToken));

        // 3. Execute strategy
        treasuryStrategy.execute(address(revenueToken));

        // 4. Verify growth treasury received tokens
        assertEq(revenueToken.balanceOf(growthTreasury), REVENUE_AMOUNT);
        assertEq(revenueToken.balanceOf(address(treasuryStrategy)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        LBT BOOST FLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Flow_LBTBoost_RouterToVoterToStrategyToLBT() public {
        // 1. Alice votes for LBTBoostStrategy
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = address(lbtStrategy);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // 2. Flush and distribute
        router.flush(address(revenueToken));
        voter.distributeToAllStrategies(address(revenueToken));

        // 3. Execute strategy (swap via Kodiak + deposit to LBT)
        lbtStrategy.execute(address(revenueToken));

        // 4. Verify LBT received backing
        assertEq(lbt.backingOf(address(targetToken)), REVENUE_AMOUNT);
        assertEq(lbt.addBackingCount(), 1);
        assertEq(revenueToken.balanceOf(address(lbtStrategy)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    MULTI-STRATEGY FLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Flow_MultiStrategy_SplitRevenue() public {
        // Alice votes 50% for direct, 50% for treasury
        address[] memory strategies = new address[](2);
        uint256[] memory weights = new uint256[](2);
        strategies[0] = address(directStrategy);
        strategies[1] = address(treasuryStrategy);
        weights[0] = 50;
        weights[1] = 50;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Bob votes 100% for LBT
        strategies = new address[](1);
        weights = new uint256[](1);
        strategies[0] = address(lbtStrategy);
        weights[0] = 100;

        vm.prank(bob);
        voter.vote(strategies, weights);

        // Total weight: Alice 2 NFTs = 2 power, Bob 1 NFT = 1 power
        // Direct: 1 (half of Alice's 2)
        // Treasury: 1 (half of Alice's 2)
        // LBT: 1 (all of Bob's 1)
        // Total: 3

        // Flush and distribute
        router.flush(address(revenueToken));
        voter.distributeToAllStrategies(address(revenueToken));

        // Check distribution (1:1:1 ratio)
        uint256 third = REVENUE_AMOUNT / 3;
        assertApproxEqAbs(revenueToken.balanceOf(address(directStrategy)), third, PRECISION_TOLERANCE);
        assertApproxEqAbs(revenueToken.balanceOf(address(treasuryStrategy)), third, PRECISION_TOLERANCE);
        assertApproxEqAbs(revenueToken.balanceOf(address(lbtStrategy)), third, PRECISION_TOLERANCE);

        // Execute all strategies
        directStrategy.execute(address(revenueToken));
        treasuryStrategy.execute(address(revenueToken));
        lbtStrategy.execute(address(revenueToken));

        // Verify destinations received correct amounts
        assertApproxEqAbs(revenueToken.balanceOf(address(bribe)), third, PRECISION_TOLERANCE);
        assertApproxEqAbs(revenueToken.balanceOf(growthTreasury), third, PRECISION_TOLERANCE);
        assertApproxEqAbs(lbt.backingOf(address(targetToken)), third, PRECISION_TOLERANCE);
    }

    /*//////////////////////////////////////////////////////////////
                    EPOCH TRANSITION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Flow_MultipleEpochs_AccumulateRevenue() public {
        // Alice votes for direct strategy
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = address(directStrategy);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Epoch 1: First revenue
        router.flush(address(revenueToken));
        voter.distributeToAllStrategies(address(revenueToken));
        directStrategy.execute(address(revenueToken));

        // Epoch 2: More revenue
        vm.warp(block.timestamp + EPOCH_DURATION);
        revenueToken.mint(address(router), REVENUE_AMOUNT);
        router.flush(address(revenueToken));
        voter.distributeToAllStrategies(address(revenueToken));
        directStrategy.execute(address(revenueToken));

        // Bribe should have 2x revenue
        assertApproxEqAbs(revenueToken.balanceOf(address(bribe)), REVENUE_AMOUNT * 2, PRECISION_TOLERANCE);

        // Wait and claim
        vm.warp(block.timestamp + EPOCH_DURATION);
        vm.prank(alice);
        bribe.getReward();

        // Alice should receive 2x revenue
        assertApproxEqAbs(revenueToken.balanceOf(alice), REVENUE_AMOUNT * 2, PRECISION_TOLERANCE);
    }

    /*//////////////////////////////////////////////////////////////
                    EXECUTE ALL TOKENS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Flow_ExecuteAll_MultipleTokens() public {
        // Add second revenue token
        MockERC20 revenueToken2 = new MockERC20("Revenue 2", "REV2", 18);
        router.setWhitelistedToken(address(revenueToken2), true);
        revenueToken2.mint(address(router), REVENUE_AMOUNT);

        // Set up swap path for second token
        lbtStrategy.setSwapPath(address(revenueToken2), MOCK_PATH);

        // Alice votes for LBT strategy
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = address(lbtStrategy);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Flush both tokens
        router.flush(address(revenueToken));
        router.flush(address(revenueToken2));

        // Distribute both
        voter.distributeToAllStrategies(address(revenueToken));
        voter.distributeToAllStrategies(address(revenueToken2));

        // Execute all at once
        address[] memory tokens = new address[](2);
        tokens[0] = address(revenueToken);
        tokens[1] = address(revenueToken2);

        uint256[] memory amounts = lbtStrategy.executeAll(tokens);

        // Should have processed both
        assertEq(amounts[0], REVENUE_AMOUNT);
        assertEq(amounts[1], REVENUE_AMOUNT);

        // LBT should have 2x backing
        assertEq(lbt.backingOf(address(targetToken)), REVENUE_AMOUNT * 2);
    }

    /*//////////////////////////////////////////////////////////////
                    RESCUE TOKENS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Flow_RescueTokens_EmergencyRecovery() public {
        // Alice votes
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = address(directStrategy);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Distribute revenue to strategy
        router.flush(address(revenueToken));
        voter.distributeToAllStrategies(address(revenueToken));

        // Suppose there's an issue - owner rescues tokens
        address rescueTo = address(0x999);
        directStrategy.rescueTokens(address(revenueToken), rescueTo, REVENUE_AMOUNT);

        // Tokens should be rescued
        assertEq(revenueToken.balanceOf(rescueTo), REVENUE_AMOUNT);
        assertEq(revenueToken.balanceOf(address(directStrategy)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    NO VOTES FALLBACK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Flow_NoVotes_RevenueGoesToTreasury() public {
        // No one votes - flush should go to main treasury
        router.flush(address(revenueToken));

        // Revenue should be at treasury (via voter's fallback)
        assertEq(revenueToken.balanceOf(treasury), REVENUE_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                    VOTE CHANGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Flow_VoteChange_SwitchStrategy() public {
        // Alice initially votes for direct
        address[] memory strategies = new address[](1);
        uint256[] memory weights = new uint256[](1);
        strategies[0] = address(directStrategy);
        weights[0] = 100;

        vm.prank(alice);
        voter.vote(strategies, weights);

        // Distribute first revenue
        router.flush(address(revenueToken));
        voter.distributeToAllStrategies(address(revenueToken));
        directStrategy.execute(address(revenueToken));

        // Next epoch - Alice switches to treasury
        vm.warp(block.timestamp + EPOCH_DURATION);
        revenueToken.mint(address(router), REVENUE_AMOUNT);

        strategies[0] = address(treasuryStrategy);
        vm.prank(alice);
        voter.vote(strategies, weights);

        // Distribute second revenue
        router.flush(address(revenueToken));
        voter.distributeToAllStrategies(address(revenueToken));
        treasuryStrategy.execute(address(revenueToken));

        // First revenue went to bribe, second to growth treasury
        assertEq(revenueToken.balanceOf(address(bribe)), REVENUE_AMOUNT);
        assertEq(revenueToken.balanceOf(growthTreasury), REVENUE_AMOUNT);
    }
}
