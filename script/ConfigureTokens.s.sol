// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {MultiTokenRouter} from "../src/MultiTokenRouter.sol";
import {LBTBoostStrategy} from "../src/strategies/LBTBoostStrategy.sol";

/// @title ConfigureTokens
/// @notice Post-deployment script to configure revenue tokens
/// @dev Run with: forge script script/ConfigureTokens.s.sol --rpc-url $RPC_URL --broadcast
contract ConfigureTokens is Script {
    /*//////////////////////////////////////////////////////////////
                            CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function run() external {
        // Load deployed contract addresses from environment
        address routerAddress = vm.envAddress("ROUTER");
        address lbtBoostAddress = vm.envOr("LBT_BOOST_STRATEGY", address(0));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("=== Token Configuration ===");
        console2.log("Router:", routerAddress);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        MultiTokenRouter router = MultiTokenRouter(routerAddress);

        // Add revenue tokens to router
        // These are the tokens that will be accepted as revenue
        _addRevenueTokens(router);

        // Configure swap paths for LBTBoostStrategy (if deployed)
        if (lbtBoostAddress != address(0)) {
            LBTBoostStrategy lbtBoost = LBTBoostStrategy(lbtBoostAddress);
            _configureSwapPaths(lbtBoost);
        }

        vm.stopBroadcast();

        console2.log("Configuration complete!");
    }

    function _addRevenueTokens(MultiTokenRouter router) internal {
        console2.log("Adding revenue tokens to router...");

        // Example tokens - modify for your deployment
        // address honey = 0x...; // HONEY token on Berachain
        // address weth = 0x...; // WETH on Berachain
        // address usdc = 0x...; // USDC on Berachain

        // Uncomment and modify these lines:
        // router.addToken(honey);
        // console2.log("  Added HONEY:", honey);

        // router.addToken(weth);
        // console2.log("  Added WETH:", weth);

        // router.addToken(usdc);
        // console2.log("  Added USDC:", usdc);

        console2.log("  (No tokens configured - modify script for your tokens)");
        console2.log("");
    }

    function _configureSwapPaths(LBTBoostStrategy lbtBoost) internal {
        console2.log("Configuring swap paths for LBTBoostStrategy...");

        // Example swap path configuration
        // Swap paths are encoded as per Kodiak router specification

        // address honey = 0x...; // HONEY token
        // bytes memory honeyToWethPath = abi.encodePacked(
        //     honey,
        //     uint24(3000), // 0.3% fee tier
        //     weth
        // );
        // lbtBoost.setSwapPath(honey, honeyToWethPath);
        // console2.log("  Set HONEY -> WETH path");

        console2.log("  (No swap paths configured - modify script for your paths)");
        console2.log("");
    }
}

/// @title VerifyDeployment
/// @notice Verification script to check deployment state
/// @dev Run with: forge script script/ConfigureTokens.s.sol:VerifyDeployment --rpc-url $RPC_URL
contract VerifyDeployment is Script {
    function run() external view {
        address voterAddress = vm.envAddress("VOTER");
        address routerAddress = vm.envAddress("ROUTER");
        address bribeAddress = vm.envAddress("BRIBE");

        console2.log("=== Deployment Verification ===");
        console2.log("");

        // Verify LSGVoter
        console2.log("LSGVoter:", voterAddress);
        (bool success, bytes memory data) = voterAddress.staticcall(
            abi.encodeWithSignature("router()")
        );
        if (success) {
            address router = abi.decode(data, (address));
            console2.log("  Router set:", router == routerAddress ? "YES" : "NO");
        }

        // Verify Router
        console2.log("MultiTokenRouter:", routerAddress);
        (success, data) = routerAddress.staticcall(
            abi.encodeWithSignature("voter()")
        );
        if (success) {
            address voter = abi.decode(data, (address));
            console2.log("  Voter reference:", voter == voterAddress ? "CORRECT" : "WRONG");
        }

        // Verify Bribe
        console2.log("Bribe:", bribeAddress);
        (success, data) = bribeAddress.staticcall(
            abi.encodeWithSignature("voter()")
        );
        if (success) {
            address voter = abi.decode(data, (address));
            console2.log("  Voter reference:", voter == voterAddress ? "CORRECT" : "WRONG");
        }

        console2.log("");
        console2.log("Verification complete!");
    }
}
