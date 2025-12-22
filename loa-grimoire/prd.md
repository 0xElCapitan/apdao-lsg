# Product Requirements Document

> **Source of Truth Notice**
> Generated from code analysis on 2025-12-22 via Loa v0.7.0.
> All claims cite `file:line` evidence.

## Document Metadata

| Field | Value |
|-------|-------|
| Generated | 2025-12-22T17:10:00Z |
| Source | Code reality extraction |
| Drift Score | 8% (excellent alignment) |
| Contracts Analyzed | 6 + 1 interface |
| Test Coverage | 242 tests (3,778 test LOC) |

---

## 1. Product Overview

### 1.1 Purpose

apDAO Liquid Signal Governance (LSG) is an NFT-gated governance system enabling soulbound seat holders to vote weekly on protocol revenue allocation on Berachain.

> **Evidence**: `src/LSGVoter.sol:13-14`
> ```solidity
> /// @title LSGVoter
> /// @notice Core governance contract for Liquid Signal Governance
> /// @dev Manages voting, delegation, and revenue distribution based on NFT ownership
> ```

### 1.2 Core Value Proposition

1. **NFT-Gated Governance**: Only seat NFT holders can vote
2. **Weekly Voting Epochs**: 7-day cycles with automatic reset
3. **Multi-Strategy Revenue Allocation**: Revenue distributed to strategies based on votes
4. **Synthetix-Style Rewards**: Efficient accumulator pattern for reward distribution

---

## 2. User Types

### 2.1 Seat NFT Holders

Primary users who participate in governance.

> **Evidence**: `src/LSGVoter.sol:36`
> ```solidity
> /// @notice Address of the seat NFT contract (voting power source)
> address public immutable seatNFT;
> ```

**Capabilities**:
- Vote on strategy allocation (`vote()` - L239)
- Reset votes (`reset()` - L291)
- Delegate voting power (`delegate()` - L327)
- Claim rewards from Bribe contracts

**Constraints**:
- One vote per epoch per seat
- Voting power = NFT balance + delegated power - delegated away

> **Evidence**: `src/LSGVoter.sol:223-234`
> ```solidity
> function getVotingPower(address account) public view returns (uint256) {
>     if (delegation[account] != address(0)) {
>         return 0;  // Delegated away
>     }
>     uint256 basePower = IERC721(seatNFT).balanceOf(account);
>     return basePower + delegatedPower[account];
> }
> ```

### 2.2 Protocol Owner (apDAO Governance)

Administrative entity controlling system configuration.

**Capabilities**:
- Add/kill strategies (`addStrategy()`, `killStrategy()`)
- Set revenue router (`setRevenueRouter()`)
- Emergency pause (`emergencyPause()`)
- Unpause system (`unpause()`)

> **Evidence**: All owner functions use `onlyOwner` modifier from OpenZeppelin

### 2.3 Emergency Multisig

Secondary administrative entity for emergency response.

> **Evidence**: `src/LSGVoter.sol:191-195`
> ```solidity
> modifier onlyEmergency() {
>     if (msg.sender != emergencyMultisig && msg.sender != owner())
>         revert NotAuthorized();
>     _;
> }
> ```

**Capabilities**:
- Emergency pause only

---

## 3. Features

### 3.1 Voting System

**Status**: Active in code

**Description**: Weekly epoch-based voting where seat holders allocate their voting power to strategies.

> **Evidence**: `src/LSGVoter.sol:239-288`

**Behavior**:
1. Voters call `vote()` with strategy addresses and weights
2. Previous votes automatically reset at epoch boundary
3. Weights are normalized and allocated proportionally
4. Bribe contracts updated with virtual balances

**Epoch Configuration**:
```solidity
// src/LSGVoter.sol:22-26
uint256 public constant EPOCH_DURATION = 7 days;
uint256 public constant EPOCH_START = 1704067200; // Jan 1, 2024
```

### 3.2 Delegation

**Status**: Active in code

**Description**: Seat holders can delegate their voting power to another address.

> **Evidence**: `src/LSGVoter.sol:325-357`

**Behavior**:
1. Delegator's voting power becomes 0
2. Delegate's voting power increases by delegated NFT balance
3. Can undelegate to restore voting power

### 3.3 Revenue Distribution

**Status**: Active in code

**Description**: Revenue is distributed to strategies based on vote weights using an accumulator pattern.

> **Evidence**: `src/LSGVoter.sol:363-446`

**Flow**:
1. `MultiTokenRouter.flush()` sends tokens to `LSGVoter.notifyRevenue()`
2. Token index updated: `tokenIndex[_token] += (_amount * 1e18) / totalWeight`
3. `distribute()` calculates each strategy's share and transfers tokens
4. Strategies execute their specific logic

**Edge Case**: If `totalWeight == 0`, revenue goes to treasury
> **Evidence**: `src/LSGVoter.sol:374-377`

### 3.4 Bribe Rewards (Synthetix Pattern)

**Status**: Active in code

**Description**: Voters earn rewards proportional to their vote weight using the Synthetix staking reward pattern.

> **Evidence**: `src/Bribe.sol:9-11`
> ```solidity
> /// @notice Synthetix-style reward distribution for strategy voters
> /// @dev Uses virtual balances (vote weights) instead of token deposits
> /// @dev Supports multiple reward tokens with 7-day distribution periods
> ```

**Key Formulas**:
```solidity
// src/Bribe.sol:250-253
rewardPerTokenStored[token] +
    (((lastTimeRewardApplicable(token) - lastUpdateTime[token])
      * rewardRate[token] * 1e18) / totalSupply);

// src/Bribe.sol:259-262
((balanceOf[account] * (rewardPerToken(token) - userRewardPerTokenPaid[token][account])) / 1e18)
    + rewards[token][account];
```

---

## 4. Strategies (Code-Verified)

### 4.1 DirectDistributionStrategy

**Purpose**: Forward revenue directly to Bribe for voter rewards

> **Evidence**: `src/strategies/DirectDistributionStrategy.sol:12-13`
> ```solidity
> /// @title DirectDistributionStrategy
> /// @notice Strategy that forwards all received tokens to the associated Bribe contract
> ```

**Execution**:
1. Receives tokens from `LSGVoter.distribute()`
2. Approves Bribe contract
3. Calls `IBribe.notifyRewardAmount()`
4. Bribe distributes to voters over 7 days

### 4.2 GrowthTreasuryStrategy

**Purpose**: Forward revenue to Growth Treasury multisig

> **Evidence**: `src/strategies/GrowthTreasuryStrategy.sol:11-12`
> ```solidity
> /// @title GrowthTreasuryStrategy
> /// @notice Strategy that forwards all received tokens to the Growth Treasury multisig
> ```

**Execution**:
1. Receives tokens from `LSGVoter.distribute()`
2. Transfers directly to `growthTreasury` address

### 4.3 LBTBoostStrategy

**Purpose**: Swap tokens via Kodiak DEX and deposit as LBT backing

> **Evidence**: `src/strategies/LBTBoostStrategy.sol:11-13`
> ```solidity
> /// @title LBTBoostStrategy
> /// @notice Strategy that swaps tokens via Kodiak and deposits to LBT as backing
> /// @dev Used to boost LBT backing with protocol revenue
> ```

**Execution**:
1. Receives tokens from `LSGVoter.distribute()`
2. Swaps to target token via Kodiak Router
3. Deposits swapped tokens to LBT as backing

**Safety Features**:
- Max slippage: 5% (`MAX_SLIPPAGE_BPS = 500`)
- Default slippage: 1%
- Non-fatal swap failures (tokens remain for rescue)

---

## 5. System Constraints

### 5.1 Technical Constraints

| Constraint | Value | Evidence |
|------------|-------|----------|
| Max Strategies | 20 | `src/LSGVoter.sol:29` |
| Max Reward Tokens | 10 | `src/Bribe.sol:23` |
| Epoch Duration | 7 days | `src/LSGVoter.sol:23` |
| Reward Period | 7 days | `src/Bribe.sol:20` |
| Max Swap Slippage | 5% | `src/strategies/LBTBoostStrategy.sol:22` |

### 5.2 Security Constraints

- All state-changing functions protected by `ReentrancyGuard`
- Token transfers use `SafeERC20`
- Admin functions protected by `onlyOwner`
- Emergency pause available to owner + multisig

### 5.3 Immutability

- Core contracts have no upgrade mechanism
- Seat NFT address is immutable
- Treasury address is immutable
- Bribe voter address is immutable

---

## 6. Test Coverage

| Category | Test Count | Evidence |
|----------|------------|----------|
| LSGVoter | 55 | `test/LSGVoter.t.sol` |
| Bribe | 44 | `test/Bribe.t.sol` |
| MultiTokenRouter | 29 | `test/MultiTokenRouter.t.sol` |
| DirectDistribution | 23 | `test/DirectDistributionStrategy.t.sol` |
| GrowthTreasury | 26 | `test/GrowthTreasuryStrategy.t.sol` |
| LBTBoost | 45 | `test/LBTBoostStrategy.t.sol` |
| Integration | 20 | `test/VoterBribeIntegration.t.sol`, `test/StrategyIntegration.t.sol` |
| **Total** | **242** | - |

> **Source**: `docs/deployment/AUDIT-SCOPE.md:187-196`

---

## 7. External Dependencies

| Dependency | Used By | Purpose |
|------------|---------|---------|
| OpenZeppelin 4.x | All contracts | Security primitives |
| Kodiak DEX Router | LBTBoostStrategy | Token swaps |
| LBT Contract | LBTBoostStrategy | Backing deposits |
| Seat NFT | LSGVoter | Voting power source |
| Vase Finance | Revenue source | Subvalidator revenue |

---

## 8. Success Metrics

Based on code analysis, the system is designed for:

1. **Gas Efficiency**: Accumulator pattern avoids iteration over all holders
2. **Flexibility**: Multiple strategies with different revenue destinations
3. **Security**: Standard OpenZeppelin patterns, comprehensive test suite
4. **Audit Readiness**: 242 tests, documented invariants, security self-review

---

## Sources

- `src/LSGVoter.sol` - Core voting contract
- `src/Bribe.sol` - Reward distribution
- `src/MultiTokenRouter.sol` - Revenue aggregation
- `src/strategies/*.sol` - Strategy implementations
- `docs/deployment/AUDIT-SCOPE.md` - Audit documentation
- `docs/deployment/SECURITY-SELF-REVIEW.md` - Security checklist
