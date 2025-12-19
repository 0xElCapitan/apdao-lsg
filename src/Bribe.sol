// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title Bribe
/// @notice Synthetix-style reward distribution for strategy voters
/// @dev Uses virtual balances (vote weights) instead of token deposits
/// @dev Supports multiple reward tokens with 7-day distribution periods
contract Bribe is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Duration of reward distribution period (7 days)
    uint256 public constant DURATION = 7 days;

    /// @notice Maximum number of reward tokens allowed
    uint256 public constant MAX_REWARD_TOKENS = 10;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the Voter contract (only caller for deposit/withdraw)
    address public immutable voter;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice List of all reward tokens
    address[] public rewardTokens;

    /// @notice Whether a token is already in rewardTokens array
    mapping(address => bool) public isRewardToken;

    /// @notice Virtual balance per account (vote weight)
    mapping(address => uint256) public balanceOf;

    /// @notice Total virtual supply (total vote weight)
    uint256 public totalSupply;

    // Per-token reward state (Synthetix pattern)
    /// @notice Timestamp when rewards finish for each token
    mapping(address => uint256) public periodFinish;

    /// @notice Reward rate per second for each token
    mapping(address => uint256) public rewardRate;

    /// @notice Last time reward was updated for each token
    mapping(address => uint256) public lastUpdateTime;

    /// @notice Stored reward per token (scaled by 1e18)
    mapping(address => uint256) public rewardPerTokenStored;

    /// @notice Reward per token paid to each account (token => account => amount)
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;

    /// @notice Unclaimed rewards for each account (token => account => amount)
    mapping(address => mapping(address => uint256)) public rewards;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when virtual balance is deposited
    event Deposited(address indexed account, uint256 amount);

    /// @notice Emitted when virtual balance is withdrawn
    event Withdrawn(address indexed account, uint256 amount);

    /// @notice Emitted when rewards are notified
    event RewardNotified(address indexed token, uint256 amount, uint256 rewardRate);

    /// @notice Emitted when rewards are claimed
    event RewardClaimed(address indexed account, address indexed token, uint256 amount);

    /// @notice Emitted when a new reward token is added
    event RewardTokenAdded(address indexed token);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Caller is not the voter contract
    error NotVoter();

    /// @notice Invalid address (zero address)
    error InvalidAddress();

    /// @notice Maximum reward tokens reached
    error MaxRewardTokensReached();

    /// @notice Reward amount is zero
    error ZeroRewardAmount();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function to voter contract only
    modifier onlyVoter() {
        if (msg.sender != voter) revert NotVoter();
        _;
    }

    /// @notice Updates reward state for all tokens before action
    modifier updateReward(address account) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            rewardPerTokenStored[token] = rewardPerToken(token);
            lastUpdateTime[token] = lastTimeRewardApplicable(token);
            if (account != address(0)) {
                rewards[token][account] = earned(account, token);
                userRewardPerTokenPaid[token][account] = rewardPerTokenStored[token];
            }
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize Bribe contract
    /// @param _voter Address of the Voter contract
    constructor(address _voter) {
        if (_voter == address(0)) revert InvalidAddress();
        voter = _voter;
    }

    /*//////////////////////////////////////////////////////////////
                          VOTER-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit virtual balance for an account (voter-only)
    /// @dev Called by Voter when user votes for this strategy
    /// @param amount Amount of voting power to deposit
    /// @param account Address of the account
    function _deposit(uint256 amount, address account) external onlyVoter nonReentrant updateReward(account) {
        if (amount == 0) return;
        balanceOf[account] += amount;
        totalSupply += amount;
        emit Deposited(account, amount);
    }

    /// @notice Withdraw virtual balance for an account (voter-only)
    /// @dev Called by Voter when user resets their votes
    /// @param amount Amount of voting power to withdraw
    /// @param account Address of the account
    function _withdraw(uint256 amount, address account) external onlyVoter nonReentrant updateReward(account) {
        if (amount == 0) return;
        balanceOf[account] -= amount;
        totalSupply -= amount;
        emit Withdrawn(account, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Notify contract of new reward amount
    /// @dev Can be called by anyone (typically the strategy contract)
    /// @param token Address of the reward token
    /// @param amount Amount of rewards to distribute over DURATION
    function notifyRewardAmount(address token, uint256 amount) external nonReentrant updateReward(address(0)) {
        if (token == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroRewardAmount();

        // Transfer tokens from caller
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Add token to list if new
        if (!isRewardToken[token]) {
            if (rewardTokens.length >= MAX_REWARD_TOKENS) revert MaxRewardTokensReached();
            rewardTokens.push(token);
            isRewardToken[token] = true;
            emit RewardTokenAdded(token);
        }

        // Calculate new reward rate
        if (block.timestamp >= periodFinish[token]) {
            // New reward period
            rewardRate[token] = amount / DURATION;
        } else {
            // Add to existing period
            uint256 remaining = periodFinish[token] - block.timestamp;
            uint256 leftover = remaining * rewardRate[token];
            rewardRate[token] = (amount + leftover) / DURATION;
        }

        lastUpdateTime[token] = block.timestamp;
        periodFinish[token] = block.timestamp + DURATION;

        emit RewardNotified(token, amount, rewardRate[token]);
    }

    /// @notice Claim all earned rewards for caller
    /// @return amounts Array of amounts claimed for each reward token
    function getReward() external nonReentrant updateReward(msg.sender) returns (uint256[] memory amounts) {
        amounts = new uint256[](rewardTokens.length);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 reward = rewards[token][msg.sender];
            if (reward > 0) {
                rewards[token][msg.sender] = 0;
                IERC20(token).safeTransfer(msg.sender, reward);
                amounts[i] = reward;
                emit RewardClaimed(msg.sender, token, reward);
            }
        }
    }

    /// @notice Claim rewards for a specific token
    /// @param token Address of the reward token to claim
    /// @return amount Amount claimed
    function getRewardForToken(address token) external nonReentrant updateReward(msg.sender) returns (uint256 amount) {
        amount = rewards[token][msg.sender];
        if (amount > 0) {
            rewards[token][msg.sender] = 0;
            IERC20(token).safeTransfer(msg.sender, amount);
            emit RewardClaimed(msg.sender, token, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get last time rewards were applicable for a token
    /// @param token Address of the reward token
    /// @return Timestamp of last applicable time
    function lastTimeRewardApplicable(address token) public view returns (uint256) {
        return block.timestamp < periodFinish[token] ? block.timestamp : periodFinish[token];
    }

    /// @notice Get accumulated reward per token (scaled by 1e18)
    /// @param token Address of the reward token
    /// @return Reward per token value
    function rewardPerToken(address token) public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored[token];
        }
        return
            rewardPerTokenStored[token] +
            (((lastTimeRewardApplicable(token) - lastUpdateTime[token]) * rewardRate[token] * 1e18) / totalSupply);
    }

    /// @notice Get earned rewards for an account
    /// @param account Address to check
    /// @param token Reward token address
    /// @return Amount of rewards earned
    function earned(address account, address token) public view returns (uint256) {
        return
            ((balanceOf[account] * (rewardPerToken(token) - userRewardPerTokenPaid[token][account])) / 1e18) +
            rewards[token][account];
    }

    /// @notice Get all reward tokens
    /// @return Array of reward token addresses
    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    /// @notice Get number of reward tokens
    /// @return Count of reward tokens
    function rewardTokensLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    /// @notice Get remaining rewards for a token in current period
    /// @param token Address of the reward token
    /// @return Remaining rewards to be distributed
    function left(address token) external view returns (uint256) {
        if (block.timestamp >= periodFinish[token]) return 0;
        uint256 remaining = periodFinish[token] - block.timestamp;
        return remaining * rewardRate[token];
    }
}
