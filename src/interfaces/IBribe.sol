// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title IBribe
/// @notice Interface for Bribe reward distribution contracts
/// @dev Used by LSGVoter to manage virtual balances for reward distribution
interface IBribe {
    /// @notice Deposit virtual balance for an account (voter-only)
    /// @param amount Amount of voting power to deposit
    /// @param account Address of the account
    function _deposit(uint256 amount, address account) external;

    /// @notice Withdraw virtual balance for an account (voter-only)
    /// @param amount Amount of voting power to withdraw
    /// @param account Address of the account
    function _withdraw(uint256 amount, address account) external;

    /// @notice Notify bribe contract of new reward amount
    /// @param token Address of the reward token
    /// @param amount Amount of rewards
    function notifyRewardAmount(address token, uint256 amount) external;

    /// @notice Get earned rewards for an account
    /// @param account Address to check
    /// @param token Reward token address
    /// @return Amount of rewards earned
    function earned(address account, address token) external view returns (uint256);

    /// @notice Get reward tokens list
    /// @return Array of reward token addresses
    function getRewardTokens() external view returns (address[] memory);
}
