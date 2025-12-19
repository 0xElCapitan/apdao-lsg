// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {GrowthTreasuryStrategy} from "../src/strategies/GrowthTreasuryStrategy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @title GrowthTreasuryStrategyTest
/// @notice Comprehensive tests for GrowthTreasuryStrategy
contract GrowthTreasuryStrategyTest is Test {
    GrowthTreasuryStrategy public strategy;
    MockERC20 public token1;
    MockERC20 public token2;

    address public owner = address(this);
    address public voter = address(0x1);
    address public treasury = address(0x2);
    address public alice = address(0x3);
    address public newTreasury = address(0x4);

    uint256 public constant INITIAL_AMOUNT = 1000 ether;

    // Events for testing
    event Forwarded(address indexed token, uint256 amount);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        // Deploy mocks
        token1 = new MockERC20("Token 1", "TKN1", 18);
        token2 = new MockERC20("Token 2", "TKN2", 18);

        // Deploy strategy
        strategy = new GrowthTreasuryStrategy(voter, treasury);

        // Mint tokens to strategy
        token1.mint(address(strategy), INITIAL_AMOUNT);
        token2.mint(address(strategy), INITIAL_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_SetsVoter() public view {
        assertEq(strategy.voter(), voter);
    }

    function test_Constructor_SetsTreasury() public view {
        assertEq(strategy.growthTreasury(), treasury);
    }

    function test_Constructor_RevertIfVoterZero() public {
        vm.expectRevert(GrowthTreasuryStrategy.InvalidAddress.selector);
        new GrowthTreasuryStrategy(address(0), treasury);
    }

    function test_Constructor_RevertIfTreasuryZero() public {
        vm.expectRevert(GrowthTreasuryStrategy.InvalidAddress.selector);
        new GrowthTreasuryStrategy(voter, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        SET TREASURY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetGrowthTreasury_UpdatesAddress() public {
        strategy.setGrowthTreasury(newTreasury);

        assertEq(strategy.growthTreasury(), newTreasury);
    }

    function test_SetGrowthTreasury_EmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit TreasuryUpdated(treasury, newTreasury);

        strategy.setGrowthTreasury(newTreasury);
    }

    function test_SetGrowthTreasury_RevertIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setGrowthTreasury(newTreasury);
    }

    function test_SetGrowthTreasury_RevertIfZeroAddress() public {
        vm.expectRevert(GrowthTreasuryStrategy.InvalidAddress.selector);
        strategy.setGrowthTreasury(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            EXECUTE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_ForwardsTokensToTreasury() public {
        uint256 treasuryBalanceBefore = token1.balanceOf(treasury);

        strategy.execute(address(token1));

        assertEq(token1.balanceOf(treasury), treasuryBalanceBefore + INITIAL_AMOUNT);
        assertEq(token1.balanceOf(address(strategy)), 0);
    }

    function test_Execute_ReturnsAmount() public {
        uint256 amount = strategy.execute(address(token1));

        assertEq(amount, INITIAL_AMOUNT);
    }

    function test_Execute_EmitsForwarded() public {
        vm.expectEmit(true, false, false, true);
        emit Forwarded(address(token1), INITIAL_AMOUNT);

        strategy.execute(address(token1));
    }

    function test_Execute_ReturnsZeroIfNoBalance() public {
        // Deploy new strategy with no tokens
        GrowthTreasuryStrategy emptyStrategy = new GrowthTreasuryStrategy(voter, treasury);

        uint256 amount = emptyStrategy.execute(address(token1));

        assertEq(amount, 0);
    }

    function test_Execute_MultipleTokens() public {
        strategy.execute(address(token1));
        strategy.execute(address(token2));

        assertEq(token1.balanceOf(treasury), INITIAL_AMOUNT);
        assertEq(token2.balanceOf(treasury), INITIAL_AMOUNT);
    }

    function test_Execute_UseUpdatedTreasury() public {
        strategy.setGrowthTreasury(newTreasury);

        strategy.execute(address(token1));

        assertEq(token1.balanceOf(newTreasury), INITIAL_AMOUNT);
        assertEq(token1.balanceOf(treasury), 0);
    }

    /*//////////////////////////////////////////////////////////////
                          EXECUTE ALL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteAll_ForwardsAllTokens() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        uint256[] memory amounts = strategy.executeAll(tokens);

        assertEq(amounts.length, 2);
        assertEq(amounts[0], INITIAL_AMOUNT);
        assertEq(amounts[1], INITIAL_AMOUNT);
        assertEq(token1.balanceOf(treasury), INITIAL_AMOUNT);
        assertEq(token2.balanceOf(treasury), INITIAL_AMOUNT);
    }

    function test_ExecuteAll_SkipsZeroBalance() public {
        MockERC20 token3 = new MockERC20("Token 3", "TKN3", 18);

        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(token3); // Zero balance
        tokens[2] = address(token2);

        uint256[] memory amounts = strategy.executeAll(tokens);

        assertEq(amounts[0], INITIAL_AMOUNT);
        assertEq(amounts[1], 0);
        assertEq(amounts[2], INITIAL_AMOUNT);
    }

    function test_ExecuteAll_EmitsForwardedForEach() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        vm.expectEmit(true, false, false, true);
        emit Forwarded(address(token1), INITIAL_AMOUNT);
        vm.expectEmit(true, false, false, true);
        emit Forwarded(address(token2), INITIAL_AMOUNT);

        strategy.executeAll(tokens);
    }

    /*//////////////////////////////////////////////////////////////
                        RESCUE TOKENS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RescueTokens_TransfersToRecipient() public {
        uint256 rescueAmount = 100 ether;

        strategy.rescueTokens(address(token1), alice, rescueAmount);

        assertEq(token1.balanceOf(alice), rescueAmount);
        assertEq(token1.balanceOf(address(strategy)), INITIAL_AMOUNT - rescueAmount);
    }

    function test_RescueTokens_EmitsEvent() public {
        uint256 rescueAmount = 100 ether;

        vm.expectEmit(true, true, false, true);
        emit TokensRescued(address(token1), alice, rescueAmount);

        strategy.rescueTokens(address(token1), alice, rescueAmount);
    }

    function test_RescueTokens_RevertIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.rescueTokens(address(token1), alice, 100 ether);
    }

    function test_RescueTokens_RevertIfToZero() public {
        vm.expectRevert(GrowthTreasuryStrategy.InvalidAddress.selector);
        strategy.rescueTokens(address(token1), address(0), 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TokenBalance_ReturnsCorrectBalance() public view {
        assertEq(strategy.tokenBalance(address(token1)), INITIAL_AMOUNT);
    }

    function test_TokenBalance_ReturnsZeroForUnknownToken() public {
        MockERC20 unknownToken = new MockERC20("Unknown", "UNK", 18);
        assertEq(strategy.tokenBalance(address(unknownToken)), 0);
    }

    function test_SupportsStrategy_ReturnsTrue() public view {
        assertTrue(strategy.supportsStrategy());
    }

    /*//////////////////////////////////////////////////////////////
                          ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_CanBeCalledByAnyone() public {
        vm.prank(alice);
        uint256 amount = strategy.execute(address(token1));

        assertEq(amount, INITIAL_AMOUNT);
    }

    function test_ExecuteAll_CanBeCalledByAnyone() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        vm.prank(alice);
        uint256[] memory amounts = strategy.executeAll(tokens);

        assertEq(amounts[0], INITIAL_AMOUNT);
    }
}
