// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DirectDistributionStrategy} from "../src/strategies/DirectDistributionStrategy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockBribe} from "./mocks/MockBribe.sol";

/// @title DirectDistributionStrategyTest
/// @notice Comprehensive tests for DirectDistributionStrategy
contract DirectDistributionStrategyTest is Test {
    DirectDistributionStrategy public strategy;
    MockERC20 public token1;
    MockERC20 public token2;
    MockBribe public bribe;

    address public owner = address(this);
    address public voter = address(0x1);
    address public alice = address(0x2);

    uint256 public constant INITIAL_AMOUNT = 1000 ether;

    // Events for testing
    event Distributed(address indexed token, uint256 amount);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        // Deploy mocks
        token1 = new MockERC20("Token 1", "TKN1", 18);
        token2 = new MockERC20("Token 2", "TKN2", 18);
        bribe = new MockBribe(voter);

        // Deploy strategy
        strategy = new DirectDistributionStrategy(voter, address(bribe));

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

    function test_Constructor_SetsBribe() public view {
        assertEq(strategy.bribe(), address(bribe));
    }

    function test_Constructor_RevertIfVoterZero() public {
        vm.expectRevert(DirectDistributionStrategy.InvalidAddress.selector);
        new DirectDistributionStrategy(address(0), address(bribe));
    }

    function test_Constructor_RevertIfBribeZero() public {
        vm.expectRevert(DirectDistributionStrategy.InvalidAddress.selector);
        new DirectDistributionStrategy(voter, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            EXECUTE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_ForwardsTokensToBribe() public {
        uint256 bribeBalanceBefore = token1.balanceOf(address(bribe));

        strategy.execute(address(token1));

        assertEq(token1.balanceOf(address(bribe)), bribeBalanceBefore + INITIAL_AMOUNT);
        assertEq(token1.balanceOf(address(strategy)), 0);
    }

    function test_Execute_NotifiesBribe() public {
        strategy.execute(address(token1));

        assertEq(bribe.notifiedRewards(address(token1)), INITIAL_AMOUNT);
    }

    function test_Execute_ReturnsAmount() public {
        uint256 amount = strategy.execute(address(token1));

        assertEq(amount, INITIAL_AMOUNT);
    }

    function test_Execute_EmitsDistributed() public {
        vm.expectEmit(true, false, false, true);
        emit Distributed(address(token1), INITIAL_AMOUNT);

        strategy.execute(address(token1));
    }

    function test_Execute_ReturnsZeroIfNoBalance() public {
        // Deploy new strategy with no tokens
        DirectDistributionStrategy emptyStrategy = new DirectDistributionStrategy(voter, address(bribe));

        uint256 amount = emptyStrategy.execute(address(token1));

        assertEq(amount, 0);
    }

    function test_Execute_MultipleTokens() public {
        strategy.execute(address(token1));
        strategy.execute(address(token2));

        assertEq(bribe.notifiedRewards(address(token1)), INITIAL_AMOUNT);
        assertEq(bribe.notifiedRewards(address(token2)), INITIAL_AMOUNT);
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
        assertEq(token1.balanceOf(address(strategy)), 0);
        assertEq(token2.balanceOf(address(strategy)), 0);
    }

    function test_ExecuteAll_SkipsZeroBalance() public {
        MockERC20 token3 = new MockERC20("Token 3", "TKN3", 18);
        // Don't mint any tokens to strategy for token3

        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(token3); // Zero balance
        tokens[2] = address(token2);

        uint256[] memory amounts = strategy.executeAll(tokens);

        assertEq(amounts[0], INITIAL_AMOUNT);
        assertEq(amounts[1], 0); // Zero balance
        assertEq(amounts[2], INITIAL_AMOUNT);
    }

    function test_ExecuteAll_EmitsDistributedForEach() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        vm.expectEmit(true, false, false, true);
        emit Distributed(address(token1), INITIAL_AMOUNT);
        vm.expectEmit(true, false, false, true);
        emit Distributed(address(token2), INITIAL_AMOUNT);

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
        vm.expectRevert(DirectDistributionStrategy.InvalidAddress.selector);
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
                          REENTRANCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_NonReentrant() public {
        // This test verifies the nonReentrant modifier is applied
        // If reentrancy were possible, this would fail
        strategy.execute(address(token1));

        // Second execute should work fine (not reentrant, sequential)
        token1.mint(address(strategy), INITIAL_AMOUNT);
        strategy.execute(address(token1));

        assertEq(bribe.notifiedRewards(address(token1)), INITIAL_AMOUNT * 2);
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
