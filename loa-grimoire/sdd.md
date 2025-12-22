# System Design Document

> **Source of Truth Notice**
> Generated from code analysis on 2025-12-22 via Loa v0.7.0.
> All claims cite `file:line` evidence.

## Document Metadata

| Field | Value |
|-------|-------|
| Generated | 2025-12-22T17:10:00Z |
| Source | Code reality extraction |
| Solidity Version | 0.8.19 |
| Contracts | 6 implementation + 1 interface |
| Total LOC | 1,690 |

---

## 1. Architecture Overview

### 1.1 System Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                    apDAO LSG Architecture                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐                                                   │
│  │  Revenue     │  (External: Vase subvalidator)                    │
│  │  Source      │                                                   │
│  └──────┬───────┘                                                   │
│         │ ERC20 tokens                                              │
│         ▼                                                           │
│  ┌──────────────────┐                                               │
│  │ MultiTokenRouter │  Aggregates revenue, whitelists tokens        │
│  │  (171 LOC)       │                                               │
│  └──────┬───────────┘                                               │
│         │ flush()                                                   │
│         ▼                                                           │
│  ┌──────────────────┐                                               │
│  │    LSGVoter      │  Core governance: voting, delegation,         │
│  │   (584 LOC)      │  revenue distribution                         │
│  └──────┬───────────┘                                               │
│         │ distribute() - pro-rata by vote weight                    │
│         │                                                           │
│    ┌────┴────────────────────────┐                                  │
│    │            │                │                                  │
│    ▼            ▼                ▼                                  │
│ ┌────────┐  ┌────────┐     ┌────────────┐                          │
│ │Direct  │  │Growth  │     │ LBTBoost   │                          │
│ │Distrib │  │Treasury│     │ Strategy   │                          │
│ │(138 LOC)│ │(144 LOC)│    │ (336 LOC)  │                          │
│ └────┬───┘  └────┬───┘     └─────┬──────┘                          │
│      │           │               │                                  │
│      ▼           ▼               ▼                                  │
│ ┌────────┐  ┌────────┐     ┌────────────┐                          │
│ │ Bribe  │  │Treasury│     │ Kodiak DEX │                          │
│ │(285 LOC)│ │Multisig│     │    + LBT   │                          │
│ └────────┘  └────────┘     └────────────┘                          │
│      │                                                              │
│      ▼                                                              │
│  Seat NFT Holders (claim rewards)                                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 Contract Relationships

| Contract | Depends On | Called By |
|----------|------------|-----------|
| LSGVoter | Bribe, IERC721, IERC20 | MultiTokenRouter, Users |
| Bribe | IERC20, LSGVoter | LSGVoter, Strategies, Users |
| MultiTokenRouter | LSGVoter, IERC20 | Anyone (flush), Revenue sources |
| DirectDistributionStrategy | Bribe, IERC20 | LSGVoter (distribute) |
| GrowthTreasuryStrategy | IERC20 | LSGVoter (distribute) |
| LBTBoostStrategy | KodiakRouter, LBT, IERC20 | LSGVoter (distribute) |

---

## 2. Technology Stack

### 2.1 Core Technologies

| Component | Technology | Evidence |
|-----------|------------|----------|
| Language | Solidity 0.8.19 | All contracts: `pragma solidity 0.8.19;` |
| Framework | Foundry | `foundry.toml` |
| Security | OpenZeppelin 4.x | Import statements |
| Blockchain | Berachain (EVM) | Kodiak + LBT integrations |

### 2.2 OpenZeppelin Dependencies

```solidity
// src/LSGVoter.sol:4-9
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
```

### 2.3 External Integrations

| Integration | Contract | Purpose |
|-------------|----------|---------|
| Kodiak DEX | LBTBoostStrategy | Token swaps via `IKodiakRouter` |
| LBT Token | LBTBoostStrategy | Backing deposits via `ILBT.addBacking()` |
| Seat NFT | LSGVoter | Voting power via `IERC721.balanceOf()` |

---

## 3. Data Models

### 3.1 LSGVoter State

```solidity
// Core voting state (src/LSGVoter.sol:44-106)

// Revenue tracking
address public revenueRouter;                                    // L47
address[] public revenueTokens;                                  // L50
mapping(address => bool) public isRevenueToken;                  // L53
mapping(address => uint256) internal tokenIndex;                 // L57

// Strategy management
address[] public strategies;                                     // L67
mapping(address => bool) public strategy_IsValid;                // L70
mapping(address => bool) public strategy_IsAlive;                // L73
mapping(address => address) public strategy_Bribe;               // L76
mapping(address => uint256) public strategy_Weight;              // L79
uint256 public totalWeight;                                      // L82

// Per-account voting
mapping(address => mapping(address => uint256)) public account_Strategy_Votes;  // L86
mapping(address => address[]) public account_StrategyVotes;                      // L89
mapping(address => uint256) public account_UsedWeight;                           // L92
mapping(address => uint256) public account_LastVoted;                            // L95

// Delegation
mapping(address => address) public delegation;                   // L99
mapping(address => uint256) public delegatedPower;               // L102
```

### 3.2 Bribe State (Synthetix Pattern)

```solidity
// Reward distribution state (src/Bribe.sol:36-65)

address[] public rewardTokens;                                   // L37
mapping(address => bool) public isRewardToken;                   // L40

// Virtual balances (vote weights, not actual tokens)
mapping(address => uint256) public balanceOf;                    // L43
uint256 public totalSupply;                                      // L46

// Synthetix reward accounting
mapping(address => uint256) public periodFinish;                 // L50
mapping(address => uint256) public rewardRate;                   // L53
mapping(address => uint256) public lastUpdateTime;               // L56
mapping(address => uint256) public rewardPerTokenStored;         // L59
mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;  // L62
mapping(address => mapping(address => uint256)) public rewards;                  // L65
```

### 3.3 Strategy State

| Strategy | State Variables | Evidence |
|----------|-----------------|----------|
| DirectDistribution | `voter`, `bribe` (immutable) | L22-25 |
| GrowthTreasury | `voter` (immutable), `growthTreasury` | L21, L28 |
| LBTBoost | `voter`, `kodiakRouter`, `lbt`, `targetToken` (immutable), `swapPaths`, `slippageBps` | L35-58 |

---

## 4. Key Algorithms

### 4.1 Epoch Calculation

```solidity
// src/LSGVoter.sol:534-536
function currentEpoch() public view returns (uint256) {
    return (block.timestamp - EPOCH_START) / EPOCH_DURATION;
}
```

| Constant | Value | Meaning |
|----------|-------|---------|
| `EPOCH_START` | 1704067200 | Jan 1, 2024 00:00:00 UTC |
| `EPOCH_DURATION` | 604800 | 7 days in seconds |

### 4.2 Revenue Distribution (Accumulator Pattern)

**Step 1: Update global index on revenue notification**
```solidity
// src/LSGVoter.sol:380-383
uint256 ratio = (_amount * 1e18) / totalWeight;
if (ratio > 0) {
    tokenIndex[_token] += ratio;
}
```

**Step 2: Calculate strategy share on distribution**
```solidity
// src/LSGVoter.sol:423-437
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
    }
}
```

### 4.3 Bribe Reward Calculation (Synthetix Pattern)

**Reward per token**
```solidity
// src/Bribe.sol:246-253
function rewardPerToken(address token) public view returns (uint256) {
    if (totalSupply == 0) {
        return rewardPerTokenStored[token];
    }
    return rewardPerTokenStored[token] +
        (((lastTimeRewardApplicable(token) - lastUpdateTime[token])
          * rewardRate[token] * 1e18) / totalSupply);
}
```

**Earned calculation**
```solidity
// src/Bribe.sol:259-262
function earned(address account, address token) public view returns (uint256) {
    return ((balanceOf[account] *
            (rewardPerToken(token) - userRewardPerTokenPaid[token][account])) / 1e18)
        + rewards[token][account];
}
```

### 4.4 Voting Power Calculation

```solidity
// src/LSGVoter.sol:223-234
function getVotingPower(address account) public view returns (uint256) {
    // If delegated away, power = 0
    if (delegation[account] != address(0)) {
        return 0;
    }
    // Base power from NFT ownership + received delegations
    uint256 basePower = IERC721(seatNFT).balanceOf(account);
    return basePower + delegatedPower[account];
}
```

---

## 5. Security Architecture

### 5.1 Access Control Matrix

| Function | Contract | Access | Modifier |
|----------|----------|--------|----------|
| `vote()` | LSGVoter | NFT holders | `onlyNewEpoch` |
| `notifyRevenue()` | LSGVoter | Revenue Router | `onlyRevenueRouter` |
| `addStrategy()` | LSGVoter | Owner | `onlyOwner` |
| `emergencyPause()` | LSGVoter | Owner OR Multisig | `onlyEmergency` |
| `_deposit()/_withdraw()` | Bribe | Voter only | `onlyVoter` |
| `notifyRewardAmount()` | Bribe | Anyone | None (by design) |
| `execute()` | All Strategies | Anyone | None |
| `rescueTokens()` | All Strategies | Owner | `onlyOwner` |

### 5.2 Security Patterns

| Pattern | Implementation | Evidence |
|---------|----------------|----------|
| Reentrancy Guard | OpenZeppelin `nonReentrant` | All contracts |
| Safe Token Transfer | OpenZeppelin `SafeERC20` | All token operations |
| Checks-Effects-Interactions | State updated before external calls | Throughout |
| Access Control | OpenZeppelin `Ownable` | Admin functions |
| Emergency Pause | OpenZeppelin `Pausable` | LSGVoter, Router |

### 5.3 Invariants

**LSGVoter Invariants**:
1. `totalWeight == sum(strategy_Weight[s])` for all strategies
2. `account_UsedWeight[a] == sum(account_Strategy_Votes[a][s])` for all strategies
3. Only one vote per account per epoch

**Bribe Invariants**:
1. `totalSupply == sum(balanceOf[a])` for all accounts
2. Virtual balances only modified by Voter contract
3. Rewards never exceed notified amounts

---

## 6. Token Flow Diagrams

### 6.1 Revenue Flow

```
Revenue Source (Vase)
        │
        │ ERC20 transfer
        ▼
MultiTokenRouter.receive()
        │
        │ flush() or flushAll()
        ▼
LSGVoter.notifyRevenue()
        │
        ├── if totalWeight == 0 ──► Treasury
        │
        ▼
tokenIndex[token] += (amount * 1e18) / totalWeight
        │
        │ distribute() called by anyone
        ▼
Strategy receives proportional share
        │
        ├── DirectDistribution ──► Bribe.notifyRewardAmount()
        ├── GrowthTreasury ──────► Treasury Multisig
        └── LBTBoost ────────────► Kodiak Swap ──► LBT.addBacking()
```

### 6.2 Voting Flow

```
NFT Holder
    │
    │ vote([strategies], [weights])
    ▼
Check: !alreadyVotedThisEpoch (L178-182)
    │
    │ _reset() - clear previous votes
    ▼
getVotingPower() - NFT balance + delegated
    │
    │ for each strategy:
    ▼
Update strategy_Weight (L274)
Update account_Strategy_Votes (L275)
    │
    │ IBribe._deposit() for each strategy
    ▼
Bribe.balanceOf[account] += weight
Bribe.totalSupply += weight
    │
    │ account_LastVoted = currentEpoch()
    ▼
Vote Complete
```

### 6.3 Reward Claim Flow

```
NFT Holder
    │
    │ Bribe.getReward()
    ▼
updateReward(account) modifier
    │
    │ for each rewardToken:
    ▼
rewardPerTokenStored = rewardPerToken()
rewards[token][account] = earned(account, token)
    │
    │ Transfer rewards to account
    ▼
Claim Complete
```

---

## 7. Error Handling

### 7.1 Custom Errors

| Contract | Error | Trigger |
|----------|-------|---------|
| LSGVoter | `AlreadyVotedThisEpoch()` | Vote in same epoch |
| LSGVoter | `StrategyNotValid()` | Unknown strategy |
| LSGVoter | `StrategyNotAlive()` | Killed strategy |
| LSGVoter | `ZeroWeight()` | No voting power or zero weight |
| LSGVoter | `MaxStrategiesReached()` | > 20 strategies |
| Bribe | `NotVoter()` | Non-voter calling _deposit/_withdraw |
| Bribe | `MaxRewardTokensReached()` | > 10 reward tokens |
| Router | `TokenNotWhitelisted()` | Non-whitelisted token |
| LBTBoost | `SlippageTooHigh()` | Slippage > 5% |

### 7.2 Failure Modes

| Scenario | Handling | Evidence |
|----------|----------|----------|
| Swap fails (LBT) | Non-fatal, emits `SwapFailed`, tokens remain | L290-301 |
| Zero balance execute | Returns 0, no revert | All strategies |
| No votes for epoch | Revenue to treasury | L374-377 |

---

## 8. Gas Considerations

### 8.1 Bounded Loops

| Loop | Bound | Evidence |
|------|-------|----------|
| Strategy iteration | MAX_STRATEGIES = 20 | L29 |
| Reward token iteration | MAX_REWARD_TOKENS = 10 | Bribe.sol:23 |
| Revenue token iteration | Unbounded (admin-controlled) | L50 |

### 8.2 Optimization Patterns

- Accumulator pattern avoids iterating over all accounts
- Virtual balances (no actual token transfers for voting)
- Index-based distribution (O(1) per strategy)

---

## 9. Deployment Architecture

### 9.1 Deployment Order

1. Deploy Seat NFT (external)
2. Deploy Treasury address (external multisig)
3. Deploy LSGVoter(seatNFT, treasury, emergencyMultisig)
4. Deploy Bribe(voterAddress) for each strategy
5. Deploy Strategies with (voter, bribe/treasury addresses)
6. Deploy MultiTokenRouter(voterAddress)
7. Call LSGVoter.setRevenueRouter(routerAddress)
8. Call LSGVoter.addStrategy() for each strategy

### 9.2 Configuration Points

| Parameter | Contract | Admin Function |
|-----------|----------|----------------|
| Revenue Router | LSGVoter | `setRevenueRouter()` |
| Strategies | LSGVoter | `addStrategy()` |
| Emergency Multisig | LSGVoter | `setEmergencyMultisig()` |
| Whitelisted Tokens | Router | `setWhitelistedToken()` |
| Swap Paths | LBTBoost | `setSwapPath()` |
| Slippage | LBTBoost | `setSlippage()` |
| Growth Treasury | GrowthStrategy | `setGrowthTreasury()` |

---

## 10. Testing Architecture

| Test File | Coverage Target | Test Count |
|-----------|-----------------|------------|
| LSGVoter.t.sol | Core voting, delegation, distribution | 55 |
| Bribe.t.sol | Reward math, edge cases | 44 |
| MultiTokenRouter.t.sol | Flushing, whitelisting | 29 |
| DirectDistributionStrategy.t.sol | Forwarding logic | 23 |
| GrowthTreasuryStrategy.t.sol | Treasury forwarding | 26 |
| LBTBoostStrategy.t.sol | Swap + deposit | 45 |
| VoterBribeIntegration.t.sol | End-to-end flow | ~10 |
| StrategyIntegration.t.sol | Multi-strategy flow | ~10 |

---

## Sources

- `src/LSGVoter.sol:1-584`
- `src/Bribe.sol:1-285`
- `src/MultiTokenRouter.sol:1-171`
- `src/strategies/DirectDistributionStrategy.sol:1-138`
- `src/strategies/GrowthTreasuryStrategy.sol:1-144`
- `src/strategies/LBTBoostStrategy.sol:1-336`
- `src/interfaces/IBribe.sol:1-32`
- `docs/deployment/AUDIT-SCOPE.md`
- `docs/deployment/SECURITY-SELF-REVIEW.md`
