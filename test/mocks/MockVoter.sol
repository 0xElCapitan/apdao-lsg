// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MockVoter
/// @notice Mock LSGVoter contract for testing MultiTokenRouter
contract MockVoter {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Tracks revenue received per token
    mapping(address => uint256) public revenueReceived;

    /// @notice Array of tokens that have been notified
    address[] public revenueTokens;

    /// @notice Tracks if a token has been added to revenueTokens
    mapping(address => bool) public isRevenueToken;

    /// @notice Counter for total notifications
    uint256 public notificationCount;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RevenueNotified(address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mock implementation of notifyRevenue
    /// @param token Address of the revenue token
    /// @param amount Amount of revenue
    function notifyRevenue(address token, uint256 amount) external {
        // Transfer tokens from caller
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Track revenue
        revenueReceived[token] += amount;
        notificationCount++;

        // Add to revenue tokens list if new
        if (!isRevenueToken[token]) {
            revenueTokens.push(token);
            isRevenueToken[token] = true;
        }

        emit RevenueNotified(token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get total revenue received for a token
    /// @param token Address of the token
    /// @return Total revenue received
    function getTotalRevenue(address token) external view returns (uint256) {
        return revenueReceived[token];
    }

    /// @notice Get list of all revenue tokens
    /// @return Array of revenue token addresses
    function getRevenueTokens() external view returns (address[] memory) {
        return revenueTokens;
    }

    /// @notice Get balance of a specific token held by this contract
    /// @param token Address of the token
    /// @return Token balance
    function getBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
