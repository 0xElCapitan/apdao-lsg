// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../src/MultiTokenRouter.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockVoter.sol";

/// @title MultiTokenRouterTest
/// @notice Comprehensive unit tests for MultiTokenRouter contract
contract MultiTokenRouterTest is Test {
    MultiTokenRouter public router;
    MockVoter public voter;
    MockERC20 public token1;
    MockERC20 public token2;
    MockERC20 public token3;

    address public owner;
    address public user1;
    address public user2;

    event TokenWhitelisted(address indexed token, bool status);
    event RevenueFlushed(address indexed token, uint256 amount);
    event VoterUpdated(address indexed oldVoter, address indexed newVoter);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy contracts
        voter = new MockVoter();
        router = new MultiTokenRouter(address(voter));

        // Deploy mock tokens
        token1 = new MockERC20("Token1", "TK1", 18);
        token2 = new MockERC20("Token2", "TK2", 6);
        token3 = new MockERC20("Token3", "TK3", 18);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_Success() public {
        assertEq(router.voter(), address(voter));
        assertEq(router.owner(), owner);
    }

    function test_Constructor_RevertIfZeroAddress() public {
        vm.expectRevert(MultiTokenRouter.InvalidAddress.selector);
        new MultiTokenRouter(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        WHITELIST TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetWhitelistedToken_Success() public {
        vm.expectEmit(true, false, false, true);
        emit TokenWhitelisted(address(token1), true);

        router.setWhitelistedToken(address(token1), true);

        assertTrue(router.whitelistedTokens(address(token1)));
        assertEq(router.tokenList(0), address(token1));
    }

    function test_SetWhitelistedToken_MultipleTokens() public {
        router.setWhitelistedToken(address(token1), true);
        router.setWhitelistedToken(address(token2), true);
        router.setWhitelistedToken(address(token3), true);

        assertTrue(router.whitelistedTokens(address(token1)));
        assertTrue(router.whitelistedTokens(address(token2)));
        assertTrue(router.whitelistedTokens(address(token3)));

        address[] memory tokens = router.getWhitelistedTokens();
        assertEq(tokens.length, 3);
        assertEq(tokens[0], address(token1));
        assertEq(tokens[1], address(token2));
        assertEq(tokens[2], address(token3));
    }

    function test_SetWhitelistedToken_RemoveToken() public {
        router.setWhitelistedToken(address(token1), true);
        assertTrue(router.whitelistedTokens(address(token1)));

        vm.expectEmit(true, false, false, true);
        emit TokenWhitelisted(address(token1), false);

        router.setWhitelistedToken(address(token1), false);
        assertFalse(router.whitelistedTokens(address(token1)));
    }

    function test_SetWhitelistedToken_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        router.setWhitelistedToken(address(token1), true);
    }

    function test_SetWhitelistedToken_RevertIfZeroAddress() public {
        vm.expectRevert(MultiTokenRouter.InvalidAddress.selector);
        router.setWhitelistedToken(address(0), true);
    }

    /*//////////////////////////////////////////////////////////////
                        FLUSH SINGLE TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Flush_SingleToken_Success() public {
        // Whitelist token
        router.setWhitelistedToken(address(token1), true);

        // Send tokens to router
        uint256 amount = 1000 ether;
        token1.mint(address(router), amount);

        assertEq(token1.balanceOf(address(router)), amount);

        // Flush tokens
        vm.expectEmit(true, false, false, true);
        emit RevenueFlushed(address(token1), amount);

        uint256 flushedAmount = router.flush(address(token1));

        assertEq(flushedAmount, amount);
        assertEq(token1.balanceOf(address(router)), 0);
        assertEq(token1.balanceOf(address(voter)), amount);
        assertEq(voter.revenueReceived(address(token1)), amount);
    }

    function test_Flush_RevertIfNotWhitelisted() public {
        token1.mint(address(router), 1000 ether);

        vm.expectRevert(abi.encodeWithSelector(MultiTokenRouter.TokenNotWhitelisted.selector, address(token1)));
        router.flush(address(token1));
    }

    function test_Flush_RevertIfNoRevenue() public {
        router.setWhitelistedToken(address(token1), true);

        vm.expectRevert(MultiTokenRouter.NoRevenueToFlush.selector);
        router.flush(address(token1));
    }

    function test_Flush_AnyoneCanCall() public {
        router.setWhitelistedToken(address(token1), true);
        token1.mint(address(router), 1000 ether);

        vm.prank(user1);
        uint256 amount = router.flush(address(token1));
        assertEq(amount, 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        FLUSH ALL TOKENS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FlushAll_MultipleTokens() public {
        // Whitelist tokens
        router.setWhitelistedToken(address(token1), true);
        router.setWhitelistedToken(address(token2), true);
        router.setWhitelistedToken(address(token3), true);

        // Send tokens to router
        uint256 amount1 = 1000 ether;
        uint256 amount2 = 500e6; // 6 decimals
        uint256 amount3 = 750 ether;

        token1.mint(address(router), amount1);
        token2.mint(address(router), amount2);
        token3.mint(address(router), amount3);

        // Flush all
        router.flushAll();

        // Verify all tokens flushed
        assertEq(token1.balanceOf(address(router)), 0);
        assertEq(token2.balanceOf(address(router)), 0);
        assertEq(token3.balanceOf(address(router)), 0);

        assertEq(token1.balanceOf(address(voter)), amount1);
        assertEq(token2.balanceOf(address(voter)), amount2);
        assertEq(token3.balanceOf(address(voter)), amount3);

        assertEq(voter.revenueReceived(address(token1)), amount1);
        assertEq(voter.revenueReceived(address(token2)), amount2);
        assertEq(voter.revenueReceived(address(token3)), amount3);
    }

    function test_FlushAll_SkipsNonWhitelisted() public {
        // Whitelist only token1 and token2
        router.setWhitelistedToken(address(token1), true);
        router.setWhitelistedToken(address(token2), true);

        // Send all three tokens
        token1.mint(address(router), 1000 ether);
        token2.mint(address(router), 500 ether);
        token3.mint(address(router), 750 ether);

        // Flush all
        router.flushAll();

        // Only whitelisted tokens should be flushed
        assertEq(token1.balanceOf(address(router)), 0);
        assertEq(token2.balanceOf(address(router)), 0);
        assertEq(token3.balanceOf(address(router)), 750 ether); // Not flushed

        assertEq(voter.notificationCount(), 2); // Only 2 tokens notified
    }

    function test_FlushAll_SkipsZeroBalance() public {
        router.setWhitelistedToken(address(token1), true);
        router.setWhitelistedToken(address(token2), true);

        // Only send token1
        token1.mint(address(router), 1000 ether);

        router.flushAll();

        assertEq(token1.balanceOf(address(voter)), 1000 ether);
        assertEq(voter.notificationCount(), 1); // Only 1 notification
    }

    function test_FlushAll_SkipsRemovedTokens() public {
        router.setWhitelistedToken(address(token1), true);
        router.setWhitelistedToken(address(token2), true);

        // Remove token2 from whitelist
        router.setWhitelistedToken(address(token2), false);

        token1.mint(address(router), 1000 ether);
        token2.mint(address(router), 500 ether);

        router.flushAll();

        // token1 flushed, token2 not flushed
        assertEq(token1.balanceOf(address(router)), 0);
        assertEq(token2.balanceOf(address(router)), 500 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Pause_BlocksFlush() public {
        router.setWhitelistedToken(address(token1), true);
        token1.mint(address(router), 1000 ether);

        router.pause();

        vm.expectRevert("Pausable: paused");
        router.flush(address(token1));
    }

    function test_Pause_BlocksFlushAll() public {
        router.setWhitelistedToken(address(token1), true);
        token1.mint(address(router), 1000 ether);

        router.pause();

        vm.expectRevert("Pausable: paused");
        router.flushAll();
    }

    function test_Unpause_RestoresFlush() public {
        router.setWhitelistedToken(address(token1), true);
        token1.mint(address(router), 1000 ether);

        router.pause();
        router.unpause();

        // Should work after unpause
        uint256 amount = router.flush(address(token1));
        assertEq(amount, 1000 ether);
    }

    function test_Pause_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        router.pause();
    }

    function test_Unpause_OnlyOwner() public {
        router.pause();

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        router.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        VOTER UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetVoter_Success() public {
        MockVoter newVoter = new MockVoter();

        vm.expectEmit(true, true, false, true);
        emit VoterUpdated(address(voter), address(newVoter));

        router.setVoter(address(newVoter));

        assertEq(router.voter(), address(newVoter));
    }

    function test_SetVoter_OnlyOwner() public {
        MockVoter newVoter = new MockVoter();

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        router.setVoter(address(newVoter));
    }

    function test_SetVoter_RevertIfZeroAddress() public {
        vm.expectRevert(MultiTokenRouter.InvalidAddress.selector);
        router.setVoter(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PendingRevenue_ReturnsBalance() public {
        uint256 amount = 1234 ether;
        token1.mint(address(router), amount);

        assertEq(router.pendingRevenue(address(token1)), amount);
    }

    function test_PendingRevenue_ZeroBalance() public {
        assertEq(router.pendingRevenue(address(token1)), 0);
    }

    function test_GetWhitelistedTokens_EmptyInitially() public {
        address[] memory tokens = router.getWhitelistedTokens();
        assertEq(tokens.length, 0);
    }

    function test_GetWhitelistedTokens_ReturnsAll() public {
        router.setWhitelistedToken(address(token1), true);
        router.setWhitelistedToken(address(token2), true);

        address[] memory tokens = router.getWhitelistedTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(token1));
        assertEq(tokens[1], address(token2));
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_MultipleFlushes() public {
        router.setWhitelistedToken(address(token1), true);

        // First flush
        token1.mint(address(router), 1000 ether);
        router.flush(address(token1));
        assertEq(voter.revenueReceived(address(token1)), 1000 ether);

        // Second flush
        token1.mint(address(router), 500 ether);
        router.flush(address(token1));
        assertEq(voter.revenueReceived(address(token1)), 1500 ether);

        // Third flush
        token1.mint(address(router), 250 ether);
        router.flush(address(token1));
        assertEq(voter.revenueReceived(address(token1)), 1750 ether);
    }

    function test_Integration_MixedFlushes() public {
        router.setWhitelistedToken(address(token1), true);
        router.setWhitelistedToken(address(token2), true);

        // Flush individual tokens
        token1.mint(address(router), 1000 ether);
        router.flush(address(token1));

        token2.mint(address(router), 500 ether);
        router.flush(address(token2));

        // Flush all with new revenue
        token1.mint(address(router), 200 ether);
        token2.mint(address(router), 100 ether);
        router.flushAll();

        assertEq(voter.revenueReceived(address(token1)), 1200 ether);
        assertEq(voter.revenueReceived(address(token2)), 600 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Flush_Amount(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);

        router.setWhitelistedToken(address(token1), true);
        token1.mint(address(router), amount);

        uint256 flushedAmount = router.flush(address(token1));

        assertEq(flushedAmount, amount);
        assertEq(token1.balanceOf(address(voter)), amount);
    }

    function testFuzz_FlushAll_MultipleAmounts(
        uint256 amount1,
        uint256 amount2,
        uint256 amount3
    ) public {
        vm.assume(amount1 > 0 && amount1 < type(uint64).max);
        vm.assume(amount2 > 0 && amount2 < type(uint64).max);
        vm.assume(amount3 > 0 && amount3 < type(uint64).max);

        router.setWhitelistedToken(address(token1), true);
        router.setWhitelistedToken(address(token2), true);
        router.setWhitelistedToken(address(token3), true);

        token1.mint(address(router), amount1);
        token2.mint(address(router), amount2);
        token3.mint(address(router), amount3);

        router.flushAll();

        assertEq(voter.revenueReceived(address(token1)), amount1);
        assertEq(voter.revenueReceived(address(token2)), amount2);
        assertEq(voter.revenueReceived(address(token3)), amount3);
    }
}
