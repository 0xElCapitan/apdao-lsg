// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {LBTBoostStrategy} from "../src/strategies/LBTBoostStrategy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockKodiakRouter} from "./mocks/MockKodiakRouter.sol";
import {MockLBT} from "./mocks/MockLBT.sol";

/// @title LBTBoostStrategyTest
/// @notice Comprehensive tests for LBTBoostStrategy
contract LBTBoostStrategyTest is Test {
    LBTBoostStrategy public strategy;
    MockERC20 public inputToken;
    MockERC20 public targetToken;
    MockKodiakRouter public router;
    MockLBT public lbt;

    address public owner = address(this);
    address public voter = address(0x1);
    address public alice = address(0x2);

    uint256 public constant INITIAL_AMOUNT = 1000 ether;
    bytes public constant MOCK_PATH = hex"0123456789";

    // Events for testing
    event Executed(address indexed token, uint256 amountIn, uint256 amountOut);
    event BackingAdded(address indexed token, uint256 amount);
    event SwapPathSet(address indexed token, bytes path);
    event SwapPathRemoved(address indexed token);
    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event SwapFailed(address indexed token, uint256 amount, string reason);

    function setUp() public {
        // Deploy mocks
        inputToken = new MockERC20("Input Token", "IN", 18);
        targetToken = new MockERC20("Target Token", "OUT", 18);
        router = new MockKodiakRouter(address(targetToken));
        lbt = new MockLBT();

        // Deploy strategy
        strategy = new LBTBoostStrategy(
            voter,
            address(router),
            address(lbt),
            address(targetToken)
        );

        // Set up swap path
        strategy.setSwapPath(address(inputToken), MOCK_PATH);

        // Mint tokens to strategy
        inputToken.mint(address(strategy), INITIAL_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_SetsVoter() public view {
        assertEq(strategy.voter(), voter);
    }

    function test_Constructor_SetsRouter() public view {
        assertEq(strategy.kodiakRouter(), address(router));
    }

    function test_Constructor_SetsLBT() public view {
        assertEq(strategy.lbt(), address(lbt));
    }

    function test_Constructor_SetsTargetToken() public view {
        assertEq(strategy.targetToken(), address(targetToken));
    }

    function test_Constructor_SetsDefaultSlippage() public view {
        assertEq(strategy.slippageBps(), 100); // 1%
    }

    function test_Constructor_RevertIfVoterZero() public {
        vm.expectRevert(LBTBoostStrategy.InvalidAddress.selector);
        new LBTBoostStrategy(address(0), address(router), address(lbt), address(targetToken));
    }

    function test_Constructor_RevertIfRouterZero() public {
        vm.expectRevert(LBTBoostStrategy.InvalidAddress.selector);
        new LBTBoostStrategy(voter, address(0), address(lbt), address(targetToken));
    }

    function test_Constructor_RevertIfLBTZero() public {
        vm.expectRevert(LBTBoostStrategy.InvalidAddress.selector);
        new LBTBoostStrategy(voter, address(router), address(0), address(targetToken));
    }

    function test_Constructor_RevertIfTargetTokenZero() public {
        vm.expectRevert(LBTBoostStrategy.InvalidAddress.selector);
        new LBTBoostStrategy(voter, address(router), address(lbt), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        SET SWAP PATH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetSwapPath_StoresPath() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 18);
        bytes memory newPath = hex"aabbccdd";

        strategy.setSwapPath(address(newToken), newPath);

        assertEq(strategy.getSwapPath(address(newToken)), newPath);
        assertTrue(strategy.hasSwapPath(address(newToken)));
    }

    function test_SetSwapPath_EmitsEvent() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 18);
        bytes memory newPath = hex"aabbccdd";

        vm.expectEmit(true, false, false, true);
        emit SwapPathSet(address(newToken), newPath);

        strategy.setSwapPath(address(newToken), newPath);
    }

    function test_SetSwapPath_RevertIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setSwapPath(address(inputToken), MOCK_PATH);
    }

    function test_SetSwapPath_RevertIfZeroAddress() public {
        vm.expectRevert(LBTBoostStrategy.InvalidAddress.selector);
        strategy.setSwapPath(address(0), MOCK_PATH);
    }

    function test_RemoveSwapPath_ClearsPath() public {
        strategy.removeSwapPath(address(inputToken));

        assertFalse(strategy.hasSwapPath(address(inputToken)));
    }

    function test_RemoveSwapPath_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit SwapPathRemoved(address(inputToken));

        strategy.removeSwapPath(address(inputToken));
    }

    /*//////////////////////////////////////////////////////////////
                        SET SLIPPAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetSlippage_UpdatesValue() public {
        strategy.setSlippage(200); // 2%

        assertEq(strategy.slippageBps(), 200);
    }

    function test_SetSlippage_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit SlippageUpdated(100, 200);

        strategy.setSlippage(200);
    }

    function test_SetSlippage_RevertIfTooHigh() public {
        vm.expectRevert(LBTBoostStrategy.SlippageTooHigh.selector);
        strategy.setSlippage(501); // > 5%
    }

    function test_SetSlippage_RevertIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setSlippage(200);
    }

    /*//////////////////////////////////////////////////////////////
                            EXECUTE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_SwapsAndDepositsToLBT() public {
        strategy.execute(address(inputToken));

        // Router should have been called
        assertEq(router.swapCount(), 1);

        // LBT should have received tokens
        assertEq(lbt.backingOf(address(targetToken)), INITIAL_AMOUNT);
        assertEq(lbt.addBackingCount(), 1);
    }

    function test_Execute_ReturnsSwappedAmount() public {
        uint256 amount = strategy.execute(address(inputToken));

        assertEq(amount, INITIAL_AMOUNT); // 1:1 exchange rate by default
    }

    function test_Execute_EmitsExecuted() public {
        vm.expectEmit(true, false, false, true);
        emit Executed(address(inputToken), INITIAL_AMOUNT, INITIAL_AMOUNT);

        strategy.execute(address(inputToken));
    }

    function test_Execute_SkipsSwapIfTargetToken() public {
        // Mint target tokens directly to strategy
        targetToken.mint(address(strategy), INITIAL_AMOUNT);

        uint256 amount = strategy.execute(address(targetToken));

        // Should not call router
        assertEq(router.swapCount(), 0);

        // But should deposit to LBT
        assertEq(lbt.backingOf(address(targetToken)), INITIAL_AMOUNT);
        assertEq(amount, INITIAL_AMOUNT);
    }

    function test_Execute_ReturnsZeroIfNoBalance() public {
        LBTBoostStrategy emptyStrategy = new LBTBoostStrategy(
            voter,
            address(router),
            address(lbt),
            address(targetToken)
        );

        uint256 amount = emptyStrategy.execute(address(inputToken));

        assertEq(amount, 0);
    }

    function test_Execute_ReturnsZeroIfNoSwapPath() public {
        MockERC20 unknownToken = new MockERC20("Unknown", "UNK", 18);
        unknownToken.mint(address(strategy), INITIAL_AMOUNT);

        vm.expectEmit(true, false, false, true);
        emit SwapFailed(address(unknownToken), INITIAL_AMOUNT, "No swap path");

        uint256 amount = strategy.execute(address(unknownToken));

        assertEq(amount, 0);
    }

    function test_Execute_HandlesSwapFailure() public {
        router.setShouldFail(true);

        vm.expectEmit(true, false, false, false);
        emit SwapFailed(address(inputToken), INITIAL_AMOUNT, "Swap failed");

        uint256 amount = strategy.execute(address(inputToken));

        assertEq(amount, 0);
        // Tokens should still be in strategy
        assertEq(inputToken.balanceOf(address(strategy)), INITIAL_AMOUNT);
    }

    function test_Execute_HandlesQuoteFailure() public {
        router.setShouldFailQuote(true);

        vm.expectEmit(true, false, false, false);
        emit SwapFailed(address(inputToken), INITIAL_AMOUNT, "Quote failed");

        uint256 amount = strategy.execute(address(inputToken));

        assertEq(amount, 0);
    }

    function test_Execute_AppliesSlippage() public {
        // Set 2x exchange rate
        router.setExchangeRate(2e18);

        strategy.execute(address(inputToken));

        // Should receive 2x tokens
        assertEq(lbt.backingOf(address(targetToken)), INITIAL_AMOUNT * 2);
    }

    /*//////////////////////////////////////////////////////////////
                          EXECUTE ALL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteAll_ProcessesMultipleTokens() public {
        MockERC20 inputToken2 = new MockERC20("Input 2", "IN2", 18);
        inputToken2.mint(address(strategy), INITIAL_AMOUNT);
        strategy.setSwapPath(address(inputToken2), MOCK_PATH);

        address[] memory tokens = new address[](2);
        tokens[0] = address(inputToken);
        tokens[1] = address(inputToken2);

        uint256[] memory amounts = strategy.executeAll(tokens);

        assertEq(amounts.length, 2);
        assertEq(amounts[0], INITIAL_AMOUNT);
        assertEq(amounts[1], INITIAL_AMOUNT);

        // LBT should have received all tokens (combined in one deposit)
        assertEq(lbt.backingOf(address(targetToken)), INITIAL_AMOUNT * 2);
    }

    function test_ExecuteAll_SkipsZeroBalance() public {
        MockERC20 emptyToken = new MockERC20("Empty", "EMP", 18);
        strategy.setSwapPath(address(emptyToken), MOCK_PATH);

        address[] memory tokens = new address[](2);
        tokens[0] = address(inputToken);
        tokens[1] = address(emptyToken);

        uint256[] memory amounts = strategy.executeAll(tokens);

        assertEq(amounts[0], INITIAL_AMOUNT);
        assertEq(amounts[1], 0);
    }

    function test_ExecuteAll_SkipsNoSwapPath() public {
        MockERC20 unknownToken = new MockERC20("Unknown", "UNK", 18);
        unknownToken.mint(address(strategy), INITIAL_AMOUNT);

        address[] memory tokens = new address[](2);
        tokens[0] = address(inputToken);
        tokens[1] = address(unknownToken);

        uint256[] memory amounts = strategy.executeAll(tokens);

        assertEq(amounts[0], INITIAL_AMOUNT);
        assertEq(amounts[1], 0);
    }

    function test_ExecuteAll_IncludesTargetTokenDirectly() public {
        targetToken.mint(address(strategy), INITIAL_AMOUNT);

        address[] memory tokens = new address[](2);
        tokens[0] = address(inputToken);
        tokens[1] = address(targetToken);

        uint256[] memory amounts = strategy.executeAll(tokens);

        assertEq(amounts[0], INITIAL_AMOUNT);
        assertEq(amounts[1], INITIAL_AMOUNT);

        // Total LBT backing
        assertEq(lbt.backingOf(address(targetToken)), INITIAL_AMOUNT * 2);
    }

    /*//////////////////////////////////////////////////////////////
                        RESCUE TOKENS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RescueTokens_TransfersToRecipient() public {
        uint256 rescueAmount = 100 ether;

        strategy.rescueTokens(address(inputToken), alice, rescueAmount);

        assertEq(inputToken.balanceOf(alice), rescueAmount);
        assertEq(inputToken.balanceOf(address(strategy)), INITIAL_AMOUNT - rescueAmount);
    }

    function test_RescueTokens_EmitsEvent() public {
        uint256 rescueAmount = 100 ether;

        vm.expectEmit(true, true, false, true);
        emit TokensRescued(address(inputToken), alice, rescueAmount);

        strategy.rescueTokens(address(inputToken), alice, rescueAmount);
    }

    function test_RescueTokens_RevertIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.rescueTokens(address(inputToken), alice, 100 ether);
    }

    function test_RescueTokens_RevertIfToZero() public {
        vm.expectRevert(LBTBoostStrategy.InvalidAddress.selector);
        strategy.rescueTokens(address(inputToken), address(0), 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TokenBalance_ReturnsCorrectBalance() public view {
        assertEq(strategy.tokenBalance(address(inputToken)), INITIAL_AMOUNT);
    }

    function test_TokenBalance_ReturnsZeroForUnknownToken() public {
        MockERC20 unknownToken = new MockERC20("Unknown", "UNK", 18);
        assertEq(strategy.tokenBalance(address(unknownToken)), 0);
    }

    function test_SupportsStrategy_ReturnsTrue() public view {
        assertTrue(strategy.supportsStrategy());
    }

    function test_GetSwapPath_ReturnsStoredPath() public view {
        assertEq(strategy.getSwapPath(address(inputToken)), MOCK_PATH);
    }

    /*//////////////////////////////////////////////////////////////
                          ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_CanBeCalledByAnyone() public {
        vm.prank(alice);
        uint256 amount = strategy.execute(address(inputToken));

        assertEq(amount, INITIAL_AMOUNT);
    }

    function test_ExecuteAll_CanBeCalledByAnyone() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(inputToken);

        vm.prank(alice);
        uint256[] memory amounts = strategy.executeAll(tokens);

        assertEq(amounts[0], INITIAL_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constants_MaxSlippage() public view {
        assertEq(strategy.MAX_SLIPPAGE_BPS(), 500);
    }

    function test_Constants_BpsDenominator() public view {
        assertEq(strategy.BPS_DENOMINATOR(), 10000);
    }

    function test_Constants_DeadlineExtension() public view {
        assertEq(strategy.DEADLINE_EXTENSION(), 30 minutes);
    }
}
