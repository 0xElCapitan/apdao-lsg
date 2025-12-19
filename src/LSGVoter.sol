// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBribe} from "./interfaces/IBribe.sol";

/// @title LSGVoter
/// @notice Core governance contract for Liquid Signal Governance
/// @dev Manages voting, delegation, and revenue distribution based on NFT ownership
contract LSGVoter is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Duration of each voting epoch (7 days)
    uint256 public constant EPOCH_DURATION = 7 days;

    /// @notice Start timestamp for epoch calculation (Monday, Jan 1, 2024 00:00:00 UTC)
    uint256 public constant EPOCH_START = 1704067200;

    /// @notice Maximum number of strategies allowed
    uint256 public constant MAX_STRATEGIES = 20;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the seat NFT contract (voting power source)
    address public immutable seatNFT;

    /// @notice Address of the treasury (receives revenue when no votes)
    address public immutable treasury;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    // Revenue management
    /// @notice Address authorized to call notifyRevenue
    address public revenueRouter;

    /// @notice Array of all revenue tokens received
    address[] public revenueTokens;

    /// @notice Mapping to check if token is already in revenueTokens array
    mapping(address => bool) public isRevenueToken;

    // Per-token revenue tracking
    /// @notice Global revenue index per token (increases as revenue arrives)
    mapping(address => uint256) internal tokenIndex;

    /// @notice Last index synced for each strategy-token pair
    mapping(address => mapping(address => uint256)) internal strategy_TokenSupplyIndex;

    /// @notice Claimable revenue for each strategy-token pair
    mapping(address => mapping(address => uint256)) public strategy_TokenClaimable;

    // Strategy management
    /// @notice Array of all strategy addresses
    address[] public strategies;

    /// @notice Whether a strategy has been added (cannot be removed from array)
    mapping(address => bool) public strategy_IsValid;

    /// @notice Whether a strategy is still active (can be killed)
    mapping(address => bool) public strategy_IsAlive;

    /// @notice Bribe contract address for each strategy
    mapping(address => address) public strategy_Bribe;

    /// @notice Total voting power allocated to each strategy
    mapping(address => uint256) public strategy_Weight;

    /// @notice Total voting power allocated across all strategies
    uint256 public totalWeight;

    // Voting
    /// @notice Votes per account per strategy
    mapping(address => mapping(address => uint256)) public account_Strategy_Votes;

    /// @notice List of strategies voted for by each account
    mapping(address => address[]) public account_StrategyVotes;

    /// @notice Total voting power used by each account
    mapping(address => uint256) public account_UsedWeight;

    /// @notice Last epoch when account voted
    mapping(address => uint256) public account_LastVoted;

    // Delegation
    /// @notice Delegation mapping (owner => delegate)
    mapping(address => address) public delegation;

    /// @notice Total delegated power per delegate
    mapping(address => uint256) public delegatedPower;

    // Emergency
    /// @notice Address authorized to call emergency functions
    address public emergencyMultisig;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new strategy is added
    event StrategyAdded(address indexed strategy, address indexed bribe);

    /// @notice Emitted when a strategy is killed
    event StrategyKilled(address indexed strategy);

    /// @notice Emitted when an account votes
    event Voted(address indexed voter, address indexed strategy, uint256 weight);

    /// @notice Emitted when an account resets their votes
    event VoteReset(address indexed voter);

    /// @notice Emitted when revenue is notified
    event RevenueNotified(address indexed token, uint256 amount);

    /// @notice Emitted when revenue is distributed to a strategy
    event RevenueDistributed(address indexed strategy, address indexed token, uint256 amount);

    /// @notice Emitted when delegation is set
    event DelegateSet(address indexed owner, address indexed delegate);

    /// @notice Emitted when emergency pause is triggered
    event EmergencyPause(address indexed caller);

    /// @notice Emitted when revenue router is updated
    event RevenueRouterUpdated(address indexed oldRouter, address indexed newRouter);

    /// @notice Emitted when emergency multisig is updated
    event EmergencyMultisigUpdated(address indexed oldMultisig, address indexed newMultisig);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Account has already voted in current epoch
    error AlreadyVotedThisEpoch();

    /// @notice Strategy was never added to the system
    error StrategyNotValid();

    /// @notice Strategy has been killed
    error StrategyNotAlive();

    /// @notice Array lengths don't match
    error ArrayLengthMismatch();

    /// @notice Weight is zero
    error ZeroWeight();

    /// @notice Caller is not authorized
    error NotAuthorized();

    /// @notice Invalid address (zero address)
    error InvalidAddress();

    /// @notice Maximum strategies limit reached
    error MaxStrategiesReached();

    /// @notice Cannot delegate to self
    error CannotDelegateToSelf();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Requires account hasn't voted in current epoch
    modifier onlyNewEpoch(address account) {
        if (account_LastVoted[account] >= currentEpoch()) {
            revert AlreadyVotedThisEpoch();
        }
        _;
    }

    /// @notice Requires caller to be revenue router
    modifier onlyRevenueRouter() {
        if (msg.sender != revenueRouter) revert NotAuthorized();
        _;
    }

    /// @notice Requires caller to be owner or emergency multisig
    modifier onlyEmergency() {
        if (msg.sender != emergencyMultisig && msg.sender != owner()) revert NotAuthorized();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the LSGVoter contract
    /// @param _seatNFT Address of the seat NFT contract
    /// @param _treasury Address of the treasury
    /// @param _emergencyMultisig Address of the emergency multisig
    constructor(
        address _seatNFT,
        address _treasury,
        address _emergencyMultisig
    ) {
        if (_seatNFT == address(0) || _treasury == address(0)) revert InvalidAddress();
        seatNFT = _seatNFT;
        treasury = _treasury;
        emergencyMultisig = _emergencyMultisig;
    }

    /*//////////////////////////////////////////////////////////////
                            VOTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get voting power for an account (considers delegation)
    /// @param account Address to check voting power for
    /// @return Voting power (NFT balance + delegated power, or 0 if delegated away)
    function getVotingPower(address account) public view returns (uint256) {
        // If account has delegated, they have 0 voting power
        if (delegation[account] != address(0)) {
            return 0;
        }

        // Base power from NFT ownership
        uint256 basePower = IERC721(seatNFT).balanceOf(account);

        // Add delegated power
        return basePower + delegatedPower[account];
    }

    /// @notice Vote for strategies with given weights
    /// @param _strategies Array of strategy addresses to vote for
    /// @param _weights Array of weights for each strategy
    function vote(
        address[] calldata _strategies,
        uint256[] calldata _weights
    ) external nonReentrant whenNotPaused onlyNewEpoch(msg.sender) {
        if (_strategies.length != _weights.length) revert ArrayLengthMismatch();

        // Reset existing votes
        _reset(msg.sender);

        uint256 votingPower = getVotingPower(msg.sender);
        if (votingPower == 0) revert ZeroWeight();

        // Calculate total weight
        uint256 totalVoteWeight = 0;
        for (uint256 i = 0; i < _strategies.length; i++) {
            if (strategy_IsValid[_strategies[i]] && strategy_IsAlive[_strategies[i]]) {
                totalVoteWeight += _weights[i];
            }
        }

        if (totalVoteWeight == 0) revert ZeroWeight();

        // Allocate votes proportionally
        uint256 usedWeight = 0;
        for (uint256 i = 0; i < _strategies.length; i++) {
            address strategy = _strategies[i];

            if (!strategy_IsValid[strategy] || !strategy_IsAlive[strategy]) continue;

            uint256 strategyWeight = (_weights[i] * votingPower) / totalVoteWeight;
            if (strategyWeight == 0) continue;

            // Update all token indices for this strategy
            _updateStrategyIndices(strategy);

            strategy_Weight[strategy] += strategyWeight;
            account_Strategy_Votes[msg.sender][strategy] = strategyWeight;
            account_StrategyVotes[msg.sender].push(strategy);

            // Update bribe balance
            IBribe(strategy_Bribe[strategy])._deposit(strategyWeight, msg.sender);

            usedWeight += strategyWeight;
            emit Voted(msg.sender, strategy, strategyWeight);
        }

        totalWeight += usedWeight;
        account_UsedWeight[msg.sender] = usedWeight;
        account_LastVoted[msg.sender] = currentEpoch();
    }

    /// @notice Reset votes for caller
    function reset() external nonReentrant onlyNewEpoch(msg.sender) {
        _reset(msg.sender);
        account_LastVoted[msg.sender] = currentEpoch();
        emit VoteReset(msg.sender);
    }

    /// @notice Internal reset logic
    /// @param account Account to reset votes for
    function _reset(address account) internal {
        address[] storage strategyVotes = account_StrategyVotes[account];
        uint256 voteCnt = strategyVotes.length;

        for (uint256 i = 0; i < voteCnt; i++) {
            address strategy = strategyVotes[i];
            uint256 votes = account_Strategy_Votes[account][strategy];

            if (votes > 0) {
                _updateStrategyIndices(strategy);
                strategy_Weight[strategy] -= votes;
                account_Strategy_Votes[account][strategy] = 0;

                IBribe(strategy_Bribe[strategy])._withdraw(votes, account);
            }
        }

        totalWeight -= account_UsedWeight[account];
        account_UsedWeight[account] = 0;
        delete account_StrategyVotes[account];
    }

    /*//////////////////////////////////////////////////////////////
                          DELEGATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Delegate voting power to another address
    /// @param _delegate Address to delegate to (use address(0) to undelegate)
    function delegate(address _delegate) external nonReentrant {
        if (_delegate == msg.sender) revert CannotDelegateToSelf();

        address currentDelegate = delegation[msg.sender];
        uint256 power = IERC721(seatNFT).balanceOf(msg.sender);

        // Remove from current delegate
        if (currentDelegate != address(0)) {
            delegatedPower[currentDelegate] -= power;
        }

        // Add to new delegate
        if (_delegate != address(0)) {
            delegatedPower[_delegate] += power;
        }

        delegation[msg.sender] = _delegate;
        emit DelegateSet(msg.sender, _delegate);
    }

    /// @notice Remove delegation
    function undelegate() external nonReentrant {
        address currentDelegate = delegation[msg.sender];
        if (currentDelegate == address(0)) return;

        uint256 power = IERC721(seatNFT).balanceOf(msg.sender);
        delegatedPower[currentDelegate] -= power;
        delegation[msg.sender] = address(0);

        emit DelegateSet(msg.sender, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        REVENUE DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Called by RevenueRouter to notify new revenue
    /// @param _token Address of the revenue token
    /// @param _amount Amount of revenue received
    function notifyRevenue(address _token, uint256 _amount) external onlyRevenueRouter nonReentrant {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        if (!isRevenueToken[_token]) {
            revenueTokens.push(_token);
            isRevenueToken[_token] = true;
        }

        if (totalWeight == 0) {
            // No votes, send to treasury
            IERC20(_token).safeTransfer(treasury, _amount);
            return;
        }

        uint256 ratio = (_amount * 1e18) / totalWeight;
        if (ratio > 0) {
            tokenIndex[_token] += ratio;
        }

        emit RevenueNotified(_token, _amount);
    }

    /// @notice Distribute accumulated revenue to a strategy for a specific token
    /// @param _strategy Strategy address
    /// @param _token Token address
    function distribute(address _strategy, address _token) public nonReentrant {
        _updateStrategyIndex(_strategy, _token);

        uint256 claimable = strategy_TokenClaimable[_strategy][_token];
        if (claimable > 0) {
            strategy_TokenClaimable[_strategy][_token] = 0;
            IERC20(_token).safeTransfer(_strategy, claimable);
            emit RevenueDistributed(_strategy, _token, claimable);
        }
    }

    /// @notice Distribute all tokens to a strategy
    /// @param _strategy Strategy address
    function distributeAllTokens(address _strategy) external {
        for (uint256 i = 0; i < revenueTokens.length; i++) {
            distribute(_strategy, revenueTokens[i]);
        }
    }

    /// @notice Distribute a token to all strategies
    /// @param _token Token address
    function distributeToAllStrategies(address _token) external {
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategy_IsAlive[strategies[i]]) {
                distribute(strategies[i], _token);
            }
        }
    }

    /// @notice Update strategy index for a specific token
    /// @param _strategy Strategy address
    /// @param _token Token address
    function _updateStrategyIndex(address _strategy, address _token) internal {
        uint256 weight = strategy_Weight[_strategy];
        if (weight > 0) {
            uint256 supplyIndex = strategy_TokenSupplyIndex[_strategy][_token];
            uint256 index = tokenIndex[_token];
            strategy_TokenSupplyIndex[_strategy][_token] = index;

            uint256 delta = index - supplyIndex;
            if (delta > 0 && strategy_IsAlive[_strategy]) {
                uint256 share = (weight * delta) / 1e18;
                strategy_TokenClaimable[_strategy][_token] += share;
            }
        } else {
            strategy_TokenSupplyIndex[_strategy][_token] = tokenIndex[_token];
        }
    }

    /// @notice Update all token indices for a strategy
    /// @param _strategy Strategy address
    function _updateStrategyIndices(address _strategy) internal {
        for (uint256 i = 0; i < revenueTokens.length; i++) {
            _updateStrategyIndex(_strategy, revenueTokens[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the revenue router address
    /// @param _router New revenue router address
    function setRevenueRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert InvalidAddress();
        emit RevenueRouterUpdated(revenueRouter, _router);
        revenueRouter = _router;
    }

    /// @notice Add a new strategy
    /// @param _strategy Strategy contract address
    /// @param _bribe Bribe contract address for this strategy
    /// @return Strategy address
    function addStrategy(
        address _strategy,
        address _bribe
    ) external onlyOwner returns (address) {
        if (strategies.length >= MAX_STRATEGIES) revert MaxStrategiesReached();
        if (_strategy == address(0) || _bribe == address(0)) revert InvalidAddress();

        strategies.push(_strategy);
        strategy_IsValid[_strategy] = true;
        strategy_IsAlive[_strategy] = true;
        strategy_Bribe[_strategy] = _bribe;

        // Initialize indices for all tokens
        for (uint256 i = 0; i < revenueTokens.length; i++) {
            strategy_TokenSupplyIndex[_strategy][revenueTokens[i]] = tokenIndex[revenueTokens[i]];
        }

        emit StrategyAdded(_strategy, _bribe);
        return _strategy;
    }

    /// @notice Kill a strategy and send pending revenue to treasury
    /// @param _strategy Strategy address to kill
    function killStrategy(address _strategy) external onlyOwner {
        if (!strategy_IsAlive[_strategy]) revert StrategyNotAlive();

        // Update and send pending to treasury
        for (uint256 i = 0; i < revenueTokens.length; i++) {
            address token = revenueTokens[i];
            _updateStrategyIndex(_strategy, token);
            uint256 claimable = strategy_TokenClaimable[_strategy][token];
            if (claimable > 0) {
                strategy_TokenClaimable[_strategy][token] = 0;
                IERC20(token).safeTransfer(treasury, claimable);
            }
        }

        strategy_IsAlive[_strategy] = false;
        emit StrategyKilled(_strategy);
    }

    /*//////////////////////////////////////////////////////////////
                          EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emergency pause (callable by owner or emergency multisig)
    function emergencyPause() external onlyEmergency {
        _pause();
        emit EmergencyPause(msg.sender);
    }

    /// @notice Unpause (owner only)
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Set emergency multisig address
    /// @param _multisig New emergency multisig address
    function setEmergencyMultisig(address _multisig) external onlyOwner {
        if (_multisig == address(0)) revert InvalidAddress();
        emit EmergencyMultisigUpdated(emergencyMultisig, _multisig);
        emergencyMultisig = _multisig;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get current epoch number
    /// @return Current epoch
    function currentEpoch() public view returns (uint256) {
        return (block.timestamp - EPOCH_START) / EPOCH_DURATION;
    }

    /// @notice Get start timestamp for a specific epoch
    /// @param epoch Epoch number
    /// @return Start timestamp
    function epochStartTime(uint256 epoch) public pure returns (uint256) {
        return EPOCH_START + (epoch * EPOCH_DURATION);
    }

    /// @notice Get time remaining until next epoch
    /// @return Seconds until next epoch starts
    function timeUntilNextEpoch() public view returns (uint256) {
        uint256 nextEpochStart = epochStartTime(currentEpoch() + 1);
        return nextEpochStart - block.timestamp;
    }

    /// @notice Get all strategies
    /// @return Array of strategy addresses
    function getStrategies() external view returns (address[] memory) {
        return strategies;
    }

    /// @notice Get strategies an account voted for
    /// @param account Address to check
    /// @return Array of strategy addresses
    function getAccountVotes(address account) external view returns (address[] memory) {
        return account_StrategyVotes[account];
    }

    /// @notice Get all revenue tokens
    /// @return Array of revenue token addresses
    function getRevenueTokens() external view returns (address[] memory) {
        return revenueTokens;
    }

    /// @notice Get pending revenue for a strategy-token pair
    /// @param _strategy Strategy address
    /// @param _token Token address
    /// @return Pending revenue amount
    function pendingRevenue(address _strategy, address _token) external view returns (uint256) {
        uint256 weight = strategy_Weight[_strategy];
        if (weight == 0) return 0;

        uint256 delta = tokenIndex[_token] - strategy_TokenSupplyIndex[_strategy][_token];
        if (delta == 0) return 0;

        return (weight * delta) / 1e18;
    }
}
