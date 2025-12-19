// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IKodiakRouter, ILBT} from "../interfaces/IKodiakRouter.sol";

/// @title LBTBoostStrategy
/// @notice Strategy that swaps tokens via Kodiak and deposits to LBT as backing
/// @dev Used to boost LBT backing with protocol revenue
contract LBTBoostStrategy is IStrategy, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum slippage allowed (5% = 500 basis points)
    uint256 public constant MAX_SLIPPAGE_BPS = 500;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Swap deadline extension (30 minutes)
    uint256 public constant DEADLINE_EXTENSION = 30 minutes;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the LSGVoter contract
    address public immutable override voter;

    /// @notice Address of the Kodiak router
    address public immutable kodiakRouter;

    /// @notice Address of the LBT contract
    address public immutable lbt;

    /// @notice Target token for swaps (e.g., WETH)
    address public immutable targetToken;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Swap path for each source token
    /// @dev token => encoded swap path to targetToken
    mapping(address => bytes) public swapPaths;

    /// @notice Whether a token has a configured swap path
    mapping(address => bool) public hasSwapPath;

    /// @notice Slippage tolerance in basis points (default 1%)
    uint256 public slippageBps;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when strategy executes (swap + deposit)
    /// @param token Input token address
    /// @param amountIn Amount of input tokens
    /// @param amountOut Amount of target tokens received from swap
    event Executed(address indexed token, uint256 amountIn, uint256 amountOut);

    /// @notice Emitted when LBT backing is added
    /// @param token Token deposited as backing
    /// @param amount Amount deposited
    event BackingAdded(address indexed token, uint256 amount);

    /// @notice Emitted when a swap path is set
    /// @param token Source token address
    /// @param path Encoded swap path
    event SwapPathSet(address indexed token, bytes path);

    /// @notice Emitted when a swap path is removed
    /// @param token Source token address
    event SwapPathRemoved(address indexed token);

    /// @notice Emitted when slippage is updated
    /// @param oldSlippage Previous slippage in bps
    /// @param newSlippage New slippage in bps
    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);

    /// @notice Emitted when tokens are rescued from the contract
    /// @param token Address of the token rescued
    /// @param to Address tokens were sent to
    /// @param amount Amount of tokens rescued
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    /// @notice Emitted when swap fails (non-fatal, tokens remain in contract)
    /// @param token Token that failed to swap
    /// @param amount Amount that failed to swap
    /// @param reason Reason for failure
    event SwapFailed(address indexed token, uint256 amount, string reason);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Invalid address (zero address)
    error InvalidAddress();

    /// @notice Slippage too high
    error SlippageTooHigh();

    /// @notice No swap path configured for token
    error NoSwapPath();

    /// @notice Swap returned less than minimum
    error InsufficientOutput();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the LBTBoostStrategy
    /// @param _voter Address of the LSGVoter contract
    /// @param _kodiakRouter Address of the Kodiak router
    /// @param _lbt Address of the LBT contract
    /// @param _targetToken Target token for swaps (e.g., WETH)
    constructor(
        address _voter,
        address _kodiakRouter,
        address _lbt,
        address _targetToken
    ) {
        if (_voter == address(0)) revert InvalidAddress();
        if (_kodiakRouter == address(0)) revert InvalidAddress();
        if (_lbt == address(0)) revert InvalidAddress();
        if (_targetToken == address(0)) revert InvalidAddress();

        voter = _voter;
        kodiakRouter = _kodiakRouter;
        lbt = _lbt;
        targetToken = _targetToken;
        slippageBps = 100; // Default 1% slippage
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the swap path for a source token
    /// @param token Source token address
    /// @param path Encoded swap path (token -> ... -> targetToken)
    function setSwapPath(address token, bytes calldata path) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        swapPaths[token] = path;
        hasSwapPath[token] = true;
        emit SwapPathSet(token, path);
    }

    /// @notice Remove swap path for a token
    /// @param token Source token address
    function removeSwapPath(address token) external onlyOwner {
        delete swapPaths[token];
        hasSwapPath[token] = false;
        emit SwapPathRemoved(token);
    }

    /// @notice Update slippage tolerance
    /// @param _slippageBps New slippage in basis points
    function setSlippage(uint256 _slippageBps) external onlyOwner {
        if (_slippageBps > MAX_SLIPPAGE_BPS) revert SlippageTooHigh();
        uint256 oldSlippage = slippageBps;
        slippageBps = _slippageBps;
        emit SlippageUpdated(oldSlippage, _slippageBps);
    }

    /*//////////////////////////////////////////////////////////////
                          STRATEGY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute strategy: swap token to target, then deposit to LBT
    /// @param token Address of the token to swap
    /// @return amount Amount of target tokens deposited to LBT
    function execute(address token) external override nonReentrant returns (uint256 amount) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) return 0;

        // If token is already target token, skip swap
        if (token == targetToken) {
            _depositToLBT(balance);
            emit Executed(token, balance, balance);
            return balance;
        }

        // Check if swap path exists
        if (!hasSwapPath[token]) {
            emit SwapFailed(token, balance, "No swap path");
            return 0;
        }

        // Perform swap via Kodiak
        amount = _swap(token, balance);

        // Deposit swapped tokens to LBT
        if (amount > 0) {
            _depositToLBT(amount);
        }

        emit Executed(token, balance, amount);
    }

    /// @notice Execute strategy for multiple tokens
    /// @param tokens Array of token addresses to process
    /// @return amounts Array of target token amounts deposited to LBT
    function executeAll(address[] calldata tokens) external override nonReentrant returns (uint256[] memory amounts) {
        amounts = new uint256[](tokens.length);
        uint256 totalDeposit = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));

            if (balance == 0) continue;

            // If token is already target token, add to total
            if (token == targetToken) {
                amounts[i] = balance;
                totalDeposit += balance;
                emit Executed(token, balance, balance);
                continue;
            }

            // Check if swap path exists
            if (!hasSwapPath[token]) {
                emit SwapFailed(token, balance, "No swap path");
                continue;
            }

            // Perform swap via Kodiak
            uint256 amountOut = _swap(token, balance);
            amounts[i] = amountOut;
            totalDeposit += amountOut;

            emit Executed(token, balance, amountOut);
        }

        // Deposit all swapped tokens to LBT in one call
        if (totalDeposit > 0) {
            _depositToLBT(totalDeposit);
        }
    }

    /// @notice Emergency rescue function to recover stuck tokens
    /// @param token Address of the token to rescue
    /// @param to Address to send rescued tokens to
    /// @param amount Amount of tokens to rescue
    function rescueTokens(address token, address to, uint256 amount) external override onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        IERC20(token).safeTransfer(to, amount);
        emit TokensRescued(token, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Perform swap via Kodiak router
    /// @param token Source token to swap
    /// @param amountIn Amount to swap
    /// @return amountOut Amount of target tokens received
    function _swap(address token, uint256 amountIn) internal returns (uint256 amountOut) {
        bytes memory path = swapPaths[token];

        // Get expected output
        try IKodiakRouter(kodiakRouter).getAmountOut(amountIn, path) returns (uint256 expectedOut) {
            // Calculate minimum output with slippage
            uint256 minOut = (expectedOut * (BPS_DENOMINATOR - slippageBps)) / BPS_DENOMINATOR;

            // Approve router
            IERC20(token).safeApprove(kodiakRouter, 0);
            IERC20(token).safeApprove(kodiakRouter, amountIn);

            // Execute swap
            try IKodiakRouter(kodiakRouter).swapExactTokensForTokens(
                amountIn,
                minOut,
                path,
                address(this),
                block.timestamp + DEADLINE_EXTENSION
            ) returns (uint256 swapOut) {
                amountOut = swapOut;
            } catch Error(string memory reason) {
                emit SwapFailed(token, amountIn, reason);
                // Reset approval
                IERC20(token).safeApprove(kodiakRouter, 0);
            } catch {
                emit SwapFailed(token, amountIn, "Swap execution failed");
                // Reset approval
                IERC20(token).safeApprove(kodiakRouter, 0);
            }
        } catch {
            emit SwapFailed(token, amountIn, "Quote failed");
        }
    }

    /// @notice Deposit target tokens to LBT as backing
    /// @param amount Amount of target tokens to deposit
    function _depositToLBT(uint256 amount) internal {
        IERC20(targetToken).safeApprove(lbt, 0);
        IERC20(targetToken).safeApprove(lbt, amount);
        ILBT(lbt).addBacking(targetToken, amount);
        emit BackingAdded(targetToken, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the balance of a specific token in the strategy
    /// @param token Address of the token
    /// @return Balance of the token
    function tokenBalance(address token) external view override returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Check if this contract supports the IStrategy interface
    /// @return True always
    function supportsStrategy() external pure override returns (bool) {
        return true;
    }

    /// @notice Get the swap path for a token
    /// @param token Source token address
    /// @return path Encoded swap path
    function getSwapPath(address token) external view returns (bytes memory path) {
        return swapPaths[token];
    }
}
