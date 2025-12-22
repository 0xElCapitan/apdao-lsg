# Access Control Analysis

> Generated: 2025-12-22T17:10:00Z
> Source: Code extraction from src/*.sol

## Summary

| Contract | Owner Functions | Restricted Functions | Permissionless Functions |
|----------|-----------------|---------------------|-------------------------|
| LSGVoter | 6 | 2 | 10 |
| Bribe | 0 | 2 | 6 |
| MultiTokenRouter | 4 | 0 | 4 |
| LBTBoostStrategy | 4 | 0 | 5 |
| DirectDistributionStrategy | 1 | 0 | 4 |
| GrowthTreasuryStrategy | 2 | 0 | 4 |

---

## LSGVoter Access Control

### Owner-Only Functions
| Function | Evidence | Risk |
|----------|----------|------|
| `setRevenueRouter()` | `onlyOwner` modifier (L454) | Can redirect all protocol revenue |
| `addStrategy()` | `onlyOwner` modifier (L464) | Can add malicious strategy |
| `killStrategy()` | `onlyOwner` modifier (L487) | Can disable strategy, pending revenue to treasury |
| `unpause()` | `onlyOwner` modifier (L516) | Controls pause state |
| `setEmergencyMultisig()` | `onlyOwner` modifier (L522) | Controls emergency access |

### Emergency Functions
| Function | Evidence | Access |
|----------|----------|--------|
| `emergencyPause()` | `onlyEmergency` modifier (L510) | Owner OR emergencyMultisig |

### Restricted Functions
| Function | Access | Evidence |
|----------|--------|----------|
| `notifyRevenue()` | Revenue Router only | `onlyRevenueRouter` modifier (L366) |
| `vote()`, `reset()` | NFT holders with voting power | `onlyNewEpoch` + `getVotingPower > 0` check |

### Permissionless Functions
| Function | Risk Assessment |
|----------|-----------------|
| `distribute()` | Low - Pro-rata distribution, no advantage to caller |
| `distributeAllTokens()` | Low - Convenience wrapper |
| `distributeToAllStrategies()` | Low - Convenience wrapper |
| View functions | None - Read-only |

---

## Bribe Access Control

### Voter-Only Functions
| Function | Evidence | Purpose |
|----------|----------|---------|
| `_deposit()` | `onlyVoter` modifier (L145) | Virtual balance management |
| `_withdraw()` | `onlyVoter` modifier (L156) | Virtual balance management |

### Permissionless Functions
| Function | Risk Assessment |
|----------|-----------------|
| `notifyRewardAmount()` | **By design** - Anyone can add rewards |
| `getReward()` | Low - Only claims caller's rewards |
| `getRewardForToken()` | Low - Only claims caller's rewards |
| View functions | None - Read-only |

---

## MultiTokenRouter Access Control

### Owner-Only Functions
| Function | Evidence | Risk |
|----------|----------|------|
| `setWhitelistedToken()` | `onlyOwner` modifier (L83) | Controls which tokens can be routed |
| `setVoter()` | `onlyOwner` modifier (L97) | Can redirect revenue destination |
| `pause()` | `onlyOwner` modifier (L104) | Can halt revenue flow |
| `unpause()` | `onlyOwner` modifier (L109) | Controls pause state |

### Permissionless Functions
| Function | Risk Assessment |
|----------|-----------------|
| `flush()` | Low - Only forwards whitelisted tokens to Voter |
| `flushAll()` | Low - Convenience wrapper for flush |
| View functions | None - Read-only |

---

## Strategy Contracts Access Control

### LBTBoostStrategy

| Function | Access | Evidence |
|----------|--------|----------|
| `setSwapPath()` | Owner | `onlyOwner` (L151) |
| `removeSwapPath()` | Owner | `onlyOwner` (L160) |
| `setSlippage()` | Owner | `onlyOwner` (L168) |
| `rescueTokens()` | Owner | `onlyOwner` (L255) |
| `execute()` | Anyone | Permissionless - processes tokens in contract |
| `executeAll()` | Anyone | Permissionless - batch execute |

### DirectDistributionStrategy

| Function | Access | Evidence |
|----------|--------|----------|
| `rescueTokens()` | Owner | `onlyOwner` (L116) |
| `execute()` | Anyone | Permissionless - forwards to Bribe |
| `executeAll()` | Anyone | Permissionless - batch execute |

### GrowthTreasuryStrategy

| Function | Access | Evidence |
|----------|--------|----------|
| `setGrowthTreasury()` | Owner | `onlyOwner` (L80) |
| `rescueTokens()` | Owner | `onlyOwner` (L122) |
| `execute()` | Anyone | Permissionless - forwards to treasury |
| `executeAll()` | Anyone | Permissionless - batch execute |

---

## Security Patterns Detected

### 1. OpenZeppelin Access Control
- All contracts use `Ownable` for admin functions
- `Pausable` used for emergency stops
- `ReentrancyGuard` on all state-changing functions

### 2. Modifier Stacking
```solidity
// Example from LSGVoter.vote() (L239-242)
function vote(...)
    external
    nonReentrant      // Reentrancy protection
    whenNotPaused     // Emergency pause check
    onlyNewEpoch(msg.sender)  // Epoch restriction
```

### 3. Two-Tier Emergency Access
```solidity
// LSGVoter.sol:L191-194
modifier onlyEmergency() {
    if (msg.sender != emergencyMultisig && msg.sender != owner())
        revert NotAuthorized();
    _;
}
```

---

## Centralization Risks

| Risk | Severity | Mitigation Recommendation |
|------|----------|--------------------------|
| Owner can add malicious strategy | Medium | Add timelock to `addStrategy()` |
| Owner can redirect revenue router | Medium | Add timelock to `setRevenueRouter()` |
| Owner can rescue any tokens from strategies | Low | Standard emergency pattern |
| Emergency multisig can pause indefinitely | Low | By design for emergency response |

**Recommendation:** Add timelock contract for admin functions before mainnet deployment.
