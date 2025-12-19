// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title MockBribe
/// @notice Mock Bribe contract for testing LSGVoter
/// @dev Tracks virtual balances without actual reward distribution logic
contract MockBribe {
    address public immutable voter;

    /// @notice Virtual balance per account
    mapping(address => uint256) public balanceOf;

    /// @notice Total virtual supply
    uint256 public totalSupply;

    /// @notice Track deposits for testing
    mapping(address => uint256) public depositCount;

    /// @notice Track withdrawals for testing
    mapping(address => uint256) public withdrawCount;

    /// @notice Track reward notifications for testing
    mapping(address => uint256) public notifiedRewards;

    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event RewardNotified(address indexed token, uint256 amount);

    error NotVoter();

    modifier onlyVoter() {
        if (msg.sender != voter) revert NotVoter();
        _;
    }

    constructor(address _voter) {
        voter = _voter;
    }

    /// @notice Deposit virtual balance (voter-only)
    /// @param amount Amount to deposit
    /// @param account Account to deposit for
    function _deposit(uint256 amount, address account) external onlyVoter {
        balanceOf[account] += amount;
        totalSupply += amount;
        depositCount[account]++;
        emit Deposited(account, amount);
    }

    /// @notice Withdraw virtual balance (voter-only)
    /// @param amount Amount to withdraw
    /// @param account Account to withdraw from
    function _withdraw(uint256 amount, address account) external onlyVoter {
        balanceOf[account] -= amount;
        totalSupply -= amount;
        withdrawCount[account]++;
        emit Withdrawn(account, amount);
    }

    /// @notice Mock reward notification
    /// @param token Token address
    /// @param amount Amount notified
    function notifyRewardAmount(address token, uint256 amount) external {
        notifiedRewards[token] += amount;
        emit RewardNotified(token, amount);
    }

    /// @notice Mock earned function (returns 0 for simplicity)
    function earned(address, address) external pure returns (uint256) {
        return 0;
    }

    /// @notice Mock getRewardTokens (returns empty array)
    function getRewardTokens() external pure returns (address[] memory) {
        return new address[](0);
    }
}
