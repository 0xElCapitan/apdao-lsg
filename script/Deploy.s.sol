// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {LSGVoter} from "../src/LSGVoter.sol";
import {Bribe} from "../src/Bribe.sol";
import {MultiTokenRouter} from "../src/MultiTokenRouter.sol";
import {DirectDistributionStrategy} from "../src/strategies/DirectDistributionStrategy.sol";
import {GrowthTreasuryStrategy} from "../src/strategies/GrowthTreasuryStrategy.sol";
import {LBTBoostStrategy} from "../src/strategies/LBTBoostStrategy.sol";

/// @title Deploy
/// @notice Deployment script for apDAO LSG (Liquid Signal Governance) system
/// @dev Run with: forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
contract Deploy is Script {
    /*//////////////////////////////////////////////////////////////
                            CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    // External addresses (set via environment or config)
    address public seatNFT;
    address public treasury;
    address public emergencyMultisig;
    address public growthTreasury;
    address public kodiakRouter;
    address public lbt;
    address public targetToken; // e.g., WETH

    // Deployed contracts
    LSGVoter public voter;
    Bribe public bribe;
    MultiTokenRouter public router;
    DirectDistributionStrategy public directDistribution;
    GrowthTreasuryStrategy public growthTreasuryStrategy;
    LBTBoostStrategy public lbtBoost;

    /*//////////////////////////////////////////////////////////////
                              MAIN DEPLOY
    //////////////////////////////////////////////////////////////*/

    function run() external {
        // Load configuration from environment
        _loadConfig();

        // Validate configuration
        _validateConfig();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== apDAO LSG Deployment ===");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Phase 1: Core Contracts
        _deployCore();

        // Phase 2: Strategy Contracts
        _deployStrategies();

        // Phase 3: Configuration
        _configure();

        vm.stopBroadcast();

        // Output deployment summary
        _printSummary();
    }

    /*//////////////////////////////////////////////////////////////
                          CONFIGURATION LOADING
    //////////////////////////////////////////////////////////////*/

    function _loadConfig() internal {
        // Required addresses
        seatNFT = vm.envAddress("SEAT_NFT");
        treasury = vm.envAddress("TREASURY");
        emergencyMultisig = vm.envAddress("EMERGENCY_MULTISIG");
        growthTreasury = vm.envAddress("GROWTH_TREASURY");

        // LBTBoostStrategy dependencies (optional - can be zero for testnet)
        kodiakRouter = vm.envOr("KODIAK_ROUTER", address(0));
        lbt = vm.envOr("LBT", address(0));
        targetToken = vm.envOr("TARGET_TOKEN", address(0));
    }

    function _validateConfig() internal view {
        require(seatNFT != address(0), "SEAT_NFT not set");
        require(treasury != address(0), "TREASURY not set");
        require(emergencyMultisig != address(0), "EMERGENCY_MULTISIG not set");
        require(growthTreasury != address(0), "GROWTH_TREASURY not set");

        console2.log("Configuration validated:");
        console2.log("  SEAT_NFT:", seatNFT);
        console2.log("  TREASURY:", treasury);
        console2.log("  EMERGENCY_MULTISIG:", emergencyMultisig);
        console2.log("  GROWTH_TREASURY:", growthTreasury);
        console2.log("  KODIAK_ROUTER:", kodiakRouter);
        console2.log("  LBT:", lbt);
        console2.log("  TARGET_TOKEN:", targetToken);
        console2.log("");
    }

    /*//////////////////////////////////////////////////////////////
                          DEPLOYMENT PHASES
    //////////////////////////////////////////////////////////////*/

    function _deployCore() internal {
        console2.log("Phase 1: Deploying Core Contracts...");

        // 1. Deploy LSGVoter
        voter = new LSGVoter(seatNFT, treasury, emergencyMultisig);
        console2.log("  LSGVoter deployed at:", address(voter));

        // 2. Deploy Bribe (needs voter)
        bribe = new Bribe(address(voter));
        console2.log("  Bribe deployed at:", address(bribe));

        // 3. Deploy MultiTokenRouter (needs voter)
        router = new MultiTokenRouter(address(voter));
        console2.log("  MultiTokenRouter deployed at:", address(router));

        console2.log("");
    }

    function _deployStrategies() internal {
        console2.log("Phase 2: Deploying Strategy Contracts...");

        // 1. DirectDistributionStrategy (forwards to Bribe)
        directDistribution = new DirectDistributionStrategy(address(voter), address(bribe));
        console2.log("  DirectDistributionStrategy deployed at:", address(directDistribution));

        // 2. GrowthTreasuryStrategy (forwards to growth treasury)
        growthTreasuryStrategy = new GrowthTreasuryStrategy(address(voter), growthTreasury);
        console2.log("  GrowthTreasuryStrategy deployed at:", address(growthTreasuryStrategy));

        // 3. LBTBoostStrategy (only if Kodiak integration is configured)
        if (kodiakRouter != address(0) && lbt != address(0) && targetToken != address(0)) {
            lbtBoost = new LBTBoostStrategy(address(voter), kodiakRouter, lbt, targetToken);
            console2.log("  LBTBoostStrategy deployed at:", address(lbtBoost));
        } else {
            console2.log("  LBTBoostStrategy SKIPPED (Kodiak not configured)");
        }

        console2.log("");
    }

    function _configure() internal {
        console2.log("Phase 3: Configuring Contracts...");

        // 1. Set router on voter
        voter.setRouter(address(router));
        console2.log("  Voter router set to:", address(router));

        // 2. Set bribe on voter
        voter.setBribe(address(bribe));
        console2.log("  Voter bribe set to:", address(bribe));

        // 3. Add strategies to voter
        voter.addStrategy(address(directDistribution));
        console2.log("  DirectDistributionStrategy added to voter");

        voter.addStrategy(address(growthTreasuryStrategy));
        console2.log("  GrowthTreasuryStrategy added to voter");

        if (address(lbtBoost) != address(0)) {
            voter.addStrategy(address(lbtBoost));
            console2.log("  LBTBoostStrategy added to voter");
        }

        console2.log("");
    }

    /*//////////////////////////////////////////////////////////////
                              OUTPUT
    //////////////////////////////////////////////////////////////*/

    function _printSummary() internal view {
        console2.log("=== Deployment Summary ===");
        console2.log("");
        console2.log("Core Contracts:");
        console2.log("  LSGVoter:", address(voter));
        console2.log("  Bribe:", address(bribe));
        console2.log("  MultiTokenRouter:", address(router));
        console2.log("");
        console2.log("Strategy Contracts:");
        console2.log("  DirectDistributionStrategy:", address(directDistribution));
        console2.log("  GrowthTreasuryStrategy:", address(growthTreasuryStrategy));
        if (address(lbtBoost) != address(0)) {
            console2.log("  LBTBoostStrategy:", address(lbtBoost));
        }
        console2.log("");
        console2.log("Next Steps:");
        console2.log("  1. Verify contracts on block explorer");
        console2.log("  2. Add revenue tokens to router: router.addToken(tokenAddress)");
        console2.log("  3. Configure swap paths on LBTBoostStrategy (if deployed)");
        console2.log("  4. Test voting flow with a test NFT");
        console2.log("");
    }
}
