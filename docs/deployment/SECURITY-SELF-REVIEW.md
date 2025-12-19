# apDAO LSG Security Self-Review

## Overview

This document presents the internal security review conducted in preparation for the Pashov Audit Group engagement.

**Review Date:** 2025-12-19
**Reviewer:** apDAO Development Team
**Scope:** All contracts in `contracts/src/`

---

## Security Checklist

### 1. Reentrancy Protection

| Contract | Status | Notes |
|----------|--------|-------|
| LSGVoter | ✅ PASS | Uses `ReentrancyGuard` on all external mutating functions |
| Bribe | ✅ PASS | Uses `ReentrancyGuard` on all external mutating functions |
| MultiTokenRouter | ✅ PASS | Uses `Pausable`; no reentrancy risk due to simple token forwarding |
| DirectDistributionStrategy | ✅ PASS | Uses `ReentrancyGuard` on `execute()` and `executeAll()` |
| GrowthTreasuryStrategy | ✅ PASS | Uses `ReentrancyGuard` on `execute()` and `executeAll()` |
| LBTBoostStrategy | ✅ PASS | Uses `ReentrancyGuard` on `execute()` and `executeAll()` |

**Pattern:** OpenZeppelin's `ReentrancyGuard` with `nonReentrant` modifier applied consistently.

---

### 2. Access Control

| Contract | Function | Access Control | Status |
|----------|----------|----------------|--------|
| **LSGVoter** | | | |
| | `setRevenueRouter()` | `onlyOwner` | ✅ |
| | `addStrategy()` | `onlyOwner` | ✅ |
| | `killStrategy()` | `onlyOwner` | ✅ |
| | `emergencyPause()` | `onlyEmergency` (owner OR multisig) | ✅ |
| | `unpause()` | `onlyOwner` | ✅ |
| | `setEmergencyMultisig()` | `onlyOwner` | ✅ |
| | `notifyRevenue()` | `onlyRevenueRouter` | ✅ |
| **Bribe** | | | |
| | `_deposit()` | `onlyVoter` | ✅ |
| | `_withdraw()` | `onlyVoter` | ✅ |
| | `notifyRewardAmount()` | Anyone (by design) | ✅ |
| **MultiTokenRouter** | | | |
| | `setWhitelistedToken()` | `onlyOwner` | ✅ |
| | `setVoter()` | `onlyOwner` | ✅ |
| | `pause()` / `unpause()` | `onlyOwner` | ✅ |
| **Strategies** | | | |
| | `rescueTokens()` | `onlyOwner` | ✅ |
| | `setGrowthTreasury()` | `onlyOwner` (GrowthTreasuryStrategy only) | ✅ |
| | `setSwapPath()` / `removeSwapPath()` | `onlyOwner` (LBTBoostStrategy only) | ✅ |
| | `setSlippage()` | `onlyOwner` (LBTBoostStrategy only) | ✅ |

---

### 3. Integer Overflow/Underflow

| Check | Status | Notes |
|-------|--------|-------|
| Solidity 0.8.19 | ✅ | Built-in overflow/underflow checks |
| Manual checks | ✅ | No unsafe math operations identified |
| Division by zero | ✅ | All divisions checked (e.g., `totalWeight > 0`, `totalSupply > 0`) |

---

### 4. Token Handling

| Pattern | Status | Implementation |
|---------|--------|----------------|
| SafeERC20 | ✅ | All contracts use `SafeERC20` for token operations |
| approve() pattern | ✅ | Uses `safeApprove(0)` before `safeApprove(amount)` to handle non-compliant tokens |
| Transfer checks | ✅ | `safeTransfer` and `safeTransferFrom` used throughout |
| Balance checks | ✅ | All transfers preceded by balance validation |

---

### 5. Event Emission

| Contract | Events | Status |
|----------|--------|--------|
| LSGVoter | 10 events | ✅ Complete |
| Bribe | 4 events | ✅ Complete |
| MultiTokenRouter | 4 events | ✅ Complete |
| DirectDistributionStrategy | 2 events | ✅ Complete |
| GrowthTreasuryStrategy | 3 events | ✅ Complete |
| LBTBoostStrategy | 7 events | ✅ Complete |

**All state-changing functions emit appropriate events.**

---

### 6. Edge Cases Documented

#### LSGVoter

| Edge Case | Handling |
|-----------|----------|
| Zero voting power | Reverts with `ZeroWeight()` |
| Already voted this epoch | Reverts with `AlreadyVotedThisEpoch()` |
| Invalid strategy | Reverts with `StrategyNotValid()` |
| Killed strategy | Reverts with `StrategyNotAlive()` |
| Max strategies reached | Reverts with `MaxStrategiesReached()` (limit: 20) |
| No votes → revenue | Revenue sent directly to treasury |
| Self-delegation | Reverts with `CannotDelegateToSelf()` |

#### Bribe

| Edge Case | Handling |
|-----------|----------|
| Zero total supply | `rewardPerToken` returns stored value |
| Zero reward amount | Reverts with `ZeroRewardAmount()` |
| Max reward tokens | Reverts with `MaxRewardTokensReached()` (limit: 10) |
| Period expired | New period starts, old leftover included |

#### Strategies

| Edge Case | Handling |
|-----------|----------|
| Zero token balance | Returns 0, no revert |
| No swap path (LBT) | Emits `SwapFailed`, returns 0 |
| Swap fails (LBT) | Emits `SwapFailed`, tokens remain in contract |
| Slippage exceeded | Transaction reverts via router |

---

### 7. External Call Safety

| Contract | External Calls | Safety Measures |
|----------|----------------|-----------------|
| LSGVoter | IERC721.balanceOf | View function, read-only |
| LSGVoter | IBribe._deposit/_withdraw | Trusted contract, set by owner |
| Bribe | IERC20.transfer | SafeERC20, nonReentrant |
| Router | ILSGVoter.notifyRevenue | Trusted contract, set by owner |
| Strategies | Kodiak router swap | Try-catch wrapped, nonReentrant |
| Strategies | LBT.addBacking | Try-catch would improve safety |

---

### 8. Front-Running Considerations

| Scenario | Risk | Mitigation |
|----------|------|------------|
| Vote timing | Low | Votes are per-epoch, no immediate value extraction |
| Reward claiming | Low | Rewards are per-account, no sandwich opportunity |
| Swap execution (LBT) | Medium | Slippage protection (max 5%), deadline extension |
| Revenue distribution | Low | Pro-rata distribution, no ordering advantage |

---

### 9. Denial of Service Vectors

| Vector | Assessment |
|--------|------------|
| Unbounded loops | ✅ Limited by MAX_STRATEGIES (20) and MAX_REWARD_TOKENS (10) |
| Array pushing | ✅ Limited by max constants |
| Gas griefing | ✅ No user-controlled loop lengths in critical paths |

---

### 10. Centralization Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Owner can add/kill strategies | Medium | Timelock recommended for mainnet |
| Owner can update router | Medium | Validation ensures non-zero address |
| Owner can rescue tokens | Low | Emergency function, standard pattern |
| Emergency multisig can pause | Low | By design for emergency response |

**Recommendation:** Consider adding a timelock contract before mainnet deployment.

---

## Contract-Specific Findings

### LSGVoter

1. **Vote Weight Calculation (L268)**
   - Uses integer division which can lose precision
   - Acceptable for governance weights, not financial calculations

2. **Revenue Distribution Index (L380-383)**
   - Uses 1e18 scaling for precision
   - Matches Synthetix staking reward pattern

### Bribe

1. **Synthetix Reward Pattern**
   - Well-tested pattern from Synthetix staking contracts
   - No modifications that could introduce bugs

2. **Virtual Balances**
   - Balances only modified by trusted Voter contract
   - No direct user deposits (mitigates common staking bugs)

### LBTBoostStrategy

1. **Swap Failure Handling**
   - Non-fatal: tokens remain in contract for later rescue or retry
   - Appropriate for revenue processing

2. **Slippage Bounds**
   - MAX_SLIPPAGE_BPS = 500 (5%) prevents excessive slippage configuration
   - Default 1% is conservative

---

## Summary

| Category | Status |
|----------|--------|
| Reentrancy | ✅ All protected |
| Access Control | ✅ Appropriate restrictions |
| Integer Safety | ✅ Solidity 0.8.x, no unsafe math |
| Token Handling | ✅ SafeERC20 throughout |
| Event Emission | ✅ Complete coverage |
| Edge Cases | ✅ Documented and handled |
| External Calls | ✅ Safe patterns used |
| DoS Vectors | ✅ Bounded loops |
| Centralization | ⚠️ Timelock recommended for mainnet |

**Overall Assessment:** Codebase is production-ready with standard security patterns. Recommend adding timelock for admin functions before mainnet deployment.

---

## Recommendations for Auditors

1. **Focus Areas:**
   - Revenue distribution math (LSGVoter L380-398)
   - Reward calculation math (Bribe L250-253, L259-262)
   - Swap execution flow (LBTBoostStrategy L269-302)

2. **Known Acceptable Behaviors:**
   - Precision loss in vote weight division (governance, not financial)
   - Non-fatal swap failures (tokens remain for rescue)
   - Anyone can call `notifyRewardAmount` on Bribe (by design)

3. **External Dependencies:**
   - OpenZeppelin Contracts 4.x
   - Kodiak DEX Router (external, assumed correct)
   - LBT Contract (external, assumed correct)
