# apDAO LSG Audit Scope Document

## Project Overview

**Project Name:** apDAO Liquid Signal Governance (LSG)
**Version:** 1.0.0
**Audit Target:** Pashov Audit Group
**Submission Date:** 2025-12-19

### Purpose

LSG enables NFT-gated governance for apDAO's revenue distribution on Berachain. Seat NFT holders vote to allocate protocol revenue across multiple strategies:

1. **Direct Distribution** - Revenue distributed as voting rewards via Bribe
2. **Growth Treasury** - Revenue funds protocol growth initiatives
3. **LBT Boost** - Revenue swapped and deposited as LBT backing

---

## Contracts in Scope

### Core Contracts

| Contract | File | Lines | Description |
|----------|------|-------|-------------|
| LSGVoter | `src/LSGVoter.sol` | 584 | Core governance: voting, delegation, revenue distribution |
| Bribe | `src/Bribe.sol` | 285 | Synthetix-style reward distribution for voters |
| MultiTokenRouter | `src/MultiTokenRouter.sol` | 171 | Revenue aggregation and forwarding |

### Strategy Contracts

| Contract | File | Lines | Description |
|----------|------|-------|-------------|
| DirectDistributionStrategy | `src/strategies/DirectDistributionStrategy.sol` | 138 | Forwards tokens to Bribe for voter rewards |
| GrowthTreasuryStrategy | `src/strategies/GrowthTreasuryStrategy.sol` | 144 | Forwards tokens to growth treasury |
| LBTBoostStrategy | `src/strategies/LBTBoostStrategy.sol` | 336 | Swaps tokens via Kodiak, deposits to LBT |

### Interfaces

| Interface | File | Lines | Description |
|-----------|------|-------|-------------|
| IStrategy | `src/interfaces/IStrategy.sol` | 38 | Strategy interface definition |
| IBribe | `src/interfaces/IBribe.sol` | 32 | Bribe interface for reward notification |
| IKodiakRouter | `src/interfaces/IKodiakRouter.sol` | 43 | Kodiak DEX + LBT interfaces |

---

## Lines of Code Summary

| Category | Files | Lines |
|----------|-------|-------|
| Core Contracts | 3 | 1,040 |
| Strategy Contracts | 3 | 618 |
| Interfaces | 3 | 113 |
| **Total** | **9** | **1,771** |

**Estimated nSLOC** (excluding comments/whitespace): ~1,200 lines

---

## External Dependencies

### OpenZeppelin Contracts 4.x

| Contract | Usage |
|----------|-------|
| `ReentrancyGuard` | Reentrancy protection |
| `Ownable` | Access control |
| `Pausable` | Emergency pause capability |
| `IERC20` | ERC20 token interface |
| `IERC721` | ERC721 NFT interface |
| `SafeERC20` | Safe token transfers |

### External Protocol Integrations (Out of Scope)

| Dependency | Used By | Notes |
|------------|---------|-------|
| Kodiak DEX Router | LBTBoostStrategy | Token swaps |
| LBT Contract | LBTBoostStrategy | Backing deposits |
| Seat NFT | LSGVoter | Voting power source |

---

## Attack Surface Overview

### Entry Points

| Function | Contract | Caller | Risk Level |
|----------|----------|--------|------------|
| `vote()` | LSGVoter | NFT holders | Medium |
| `reset()` | LSGVoter | NFT holders | Low |
| `delegate()` | LSGVoter | NFT holders | Low |
| `notifyRevenue()` | LSGVoter | Revenue Router only | Medium |
| `distribute()` | LSGVoter | Anyone | Low |
| `notifyRewardAmount()` | Bribe | Anyone | Low |
| `getReward()` | Bribe | Anyone | Medium |
| `flush()` | MultiTokenRouter | Anyone | Low |
| `execute()` | Strategies | Anyone | Medium |
| `rescueTokens()` | Strategies | Owner only | Low |

### Admin Functions

| Function | Contract | Concern |
|----------|----------|---------|
| `setRevenueRouter()` | LSGVoter | Can redirect revenue |
| `addStrategy()` | LSGVoter | Can add malicious strategy |
| `killStrategy()` | LSGVoter | Can disable strategy |
| `emergencyPause()` | LSGVoter | Can halt all voting |
| `setWhitelistedToken()` | MultiTokenRouter | Can whitelist tokens |
| `setGrowthTreasury()` | GrowthTreasuryStrategy | Can redirect funds |
| `setSwapPath()` | LBTBoostStrategy | Can modify swap routes |

### Token Flows

```
                           ┌─────────────────┐
                           │ Revenue Source  │
                           │  (Vase etc)     │
                           └────────┬────────┘
                                    │ ERC20 tokens
                                    ▼
                           ┌─────────────────┐
                           │ MultiTokenRouter│
                           └────────┬────────┘
                                    │ flush()
                                    ▼
                           ┌─────────────────┐
                           │    LSGVoter     │
                           │  (notifyRevenue)│
                           └────────┬────────┘
                                    │ distribute()
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
            ┌───────────┐   ┌───────────┐   ┌───────────┐
            │ DirectDist│   │GrowthTreas│   │ LBTBoost  │
            │ Strategy  │   │  Strategy │   │ Strategy  │
            └─────┬─────┘   └─────┬─────┘   └─────┬─────┘
                  │               │               │
                  ▼               ▼               ▼
            ┌───────────┐   ┌───────────┐   ┌───────────┐
            │   Bribe   │   │  Treasury │   │    LBT    │
            └───────────┘   │  Multisig │   │ (backing) │
                            └───────────┘   └───────────┘
```

---

## Key Invariants

### LSGVoter Invariants

1. **Vote Weight Conservation:** `totalWeight == sum(strategy_Weight[s] for all s)`
2. **Account Weight Conservation:** `account_UsedWeight[a] == sum(account_Strategy_Votes[a][s] for all s)`
3. **Voting Power Limit:** `account_UsedWeight[a] <= getVotingPower(a)` at vote time
4. **Epoch Restriction:** `account_LastVoted[a] < currentEpoch()` for new votes
5. **Strategy Validity:** Only valid and alive strategies receive votes

### Bribe Invariants

1. **Balance Conservation:** `totalSupply == sum(balanceOf[a] for all a)`
2. **Reward Accounting:** `sum(earned(a, t)) + sum(claimed) <= totalRewardsNotified(t)`
3. **Virtual Balance:** Only Voter can modify balances

### Strategy Invariants

1. **Non-Revering Execute:** `execute()` should not revert on zero balance
2. **Token Conservation:** All tokens received are either forwarded or rescuable

---

## Previous Audits

### Heesho's LSG (Reference Implementation)

The apDAO LSG system is inspired by Heesho's Liquid Signal Governance pattern. While the core concepts are similar, this is a new implementation with:

- Different token handling (multi-token vs single token)
- Different strategy architecture
- Berachain-specific integrations (Kodiak, LBT)

**Note:** No direct code was copied; this is a clean-room implementation.

---

## Testing Coverage

| Category | Test Count | Coverage |
|----------|------------|----------|
| LSGVoter | 55 | High |
| Bribe | 44 | High |
| MultiTokenRouter | 29 | High |
| DirectDistributionStrategy | 23 | High |
| GrowthTreasuryStrategy | 26 | High |
| LBTBoostStrategy | 45 | High |
| Integration Tests | 20 | Medium |
| **Total** | **242** | - |

### Running Tests

```bash
cd contracts
forge test -vvv
```

---

## Build & Verification

### Compiler Configuration

```toml
# foundry.toml
[profile.default]
solc_version = "0.8.19"
optimizer = true
optimizer_runs = 200
```

### Build Commands

```bash
cd contracts
forge build
forge test
```

---

## Contact Information

| Role | Contact |
|------|---------|
| Project Lead | El Capitan (apDAO) |
| Technical Contact | [Discord: apDAO Server] |
| Repository | github.com/0xElCapitan/agentic-base |

---

## Audit Focus Areas (Recommended)

### High Priority

1. **Revenue Distribution Math** (`LSGVoter.sol:380-398`)
   - Index calculation and distribution logic
   - Potential precision loss or dust accumulation

2. **Reward Calculation** (`Bribe.sol:246-263`)
   - Synthetix reward pattern implementation
   - Edge cases with zero supply

3. **Swap Execution** (`LBTBoostStrategy.sol:269-302`)
   - Try-catch failure handling
   - Slippage protection effectiveness

### Medium Priority

4. **Vote Weight Updates**
   - Weight tracking across vote/reset cycles
   - Delegation power calculations

5. **Access Control**
   - Admin function restrictions
   - Emergency pause scope

### Lower Priority

6. **Gas Optimization**
   - Loop bounds in distribution
   - Storage vs memory usage

---

## Appendix: File Structure

```
contracts/
├── src/
│   ├── LSGVoter.sol           # Core voting and distribution
│   ├── Bribe.sol              # Reward distribution
│   ├── MultiTokenRouter.sol   # Revenue aggregation
│   ├── interfaces/
│   │   ├── IStrategy.sol
│   │   ├── IBribe.sol
│   │   └── IKodiakRouter.sol
│   └── strategies/
│       ├── DirectDistributionStrategy.sol
│       ├── GrowthTreasuryStrategy.sol
│       └── LBTBoostStrategy.sol
├── test/
│   ├── LSGVoter.t.sol
│   ├── Bribe.t.sol
│   ├── MultiTokenRouter.t.sol
│   ├── DirectDistributionStrategy.t.sol
│   ├── GrowthTreasuryStrategy.t.sol
│   ├── LBTBoostStrategy.t.sol
│   └── StrategyIntegration.t.sol
├── script/
│   ├── Deploy.s.sol
│   └── ConfigureTokens.s.sol
└── foundry.toml
```
