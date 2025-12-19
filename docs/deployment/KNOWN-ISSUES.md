# apDAO LSG Known Issues & Design Decisions

## Overview

This document lists intentional design decisions, known limitations, and out-of-scope items for the apDAO Liquid Signal Governance (LSG) system. These items are not bugs but conscious trade-offs made during development.

---

## Intentional Design Decisions

### 1. Epoch-Based Voting

**Design:** Votes are locked per epoch (7 days). Users cannot change votes mid-epoch.

**Rationale:**
- Prevents vote manipulation around revenue distribution
- Provides predictable governance periods
- Aligns with weekly epoch pattern used in many DeFi governance systems

**Trade-off:** Less flexible voting, but more secure revenue distribution.

---

### 2. Virtual Balances in Bribe Contract

**Design:** Bribe contract uses virtual balances (vote weights) instead of actual token deposits.

**Rationale:**
- Voting power is derived from NFT ownership, not token staking
- Eliminates need for users to deposit/withdraw tokens
- Reduces gas costs and complexity

**Implications:**
- Balances only changed by trusted Voter contract
- No direct user deposits possible (by design)

---

### 3. Anyone Can Notify Rewards on Bribe

**Design:** `notifyRewardAmount()` on Bribe is callable by anyone.

**Rationale:**
- Allows strategies to forward rewards without needing special permissions
- Enables third parties to add incentives to specific strategies
- Simpler integration with external reward sources

**Implications:**
- Anyone can add rewards (not a vulnerability, just flexibility)
- Caller must approve and transfer tokens

---

### 4. Non-Fatal Swap Failures in LBTBoostStrategy

**Design:** Swap failures emit `SwapFailed` event but don't revert.

**Rationale:**
- Revenue processing should be robust to temporary DEX issues
- Tokens remain in contract for later rescue or retry
- Prevents one failing token from blocking others in `executeAll()`

**Trade-off:** Silent failures require monitoring; tokens may accumulate if not rescued.

---

### 5. Strategy Cannot Be Removed (Only Killed)

**Design:** Once added, strategies remain in the array forever. `killStrategy()` only sets `strategy_IsAlive = false`.

**Rationale:**
- Prevents array manipulation vulnerabilities
- Historical record of all strategies
- Simpler state management

**Implications:**
- Array grows over time (bounded by MAX_STRATEGIES = 20)
- Killed strategies still occupy space but cost minimal gas to skip

---

### 6. Single Revenue Router

**Design:** Only one address can call `notifyRevenue()` on LSGVoter.

**Rationale:**
- Single source of truth for revenue
- Prevents unauthorized revenue injection
- Simpler access control

**Trade-off:** Less flexible; requires router update to change revenue source.

---

### 7. No Upgradeability

**Design:** Contracts are not upgradeable.

**Rationale:**
- Simpler security model
- No proxy vulnerabilities
- Immutable guarantees for users

**Implications:**
- Bug fixes require migration
- New features require new contract deployment

---

### 8. Integer Division Precision Loss in Vote Weights

**Design:** Vote weight calculation uses integer division: `(weight * votingPower) / totalVoteWeight`

**Location:** `LSGVoter.sol:268`

**Rationale:**
- Acceptable for governance weights (not financial)
- Dust amounts (< 1 wei) are negligible
- Simplifies implementation

**Impact:** At most 1 wei per strategy per vote, not exploitable.

---

## Known Limitations

### 1. Maximum Strategies Limit

**Limit:** 20 strategies maximum (`MAX_STRATEGIES`)

**Reason:** Prevent unbounded loop gas costs during distribution

**Mitigation:** Sufficient for governance use case; can deploy new Voter if needed

---

### 2. Maximum Reward Tokens Limit

**Limit:** 10 reward tokens per Bribe (`MAX_REWARD_TOKENS`)

**Reason:** Prevent gas exhaustion during reward updates

**Mitigation:** Sufficient for typical use; new Bribe can be deployed if needed

---

### 3. No Partial Vote Reset

**Limitation:** Users must reset all votes, cannot remove single strategy vote

**Reason:** Simplifies implementation and prevents edge cases

**Mitigation:** Full reset + new vote in same epoch accomplishes same goal

---

### 4. Swap Path Configuration Required for LBTBoostStrategy

**Limitation:** Each token requires manual swap path configuration

**Reason:** Paths are token-specific and may vary

**Mitigation:** Admin configures paths; unknown tokens remain in contract for rescue

---

### 5. No Flash Loan Protection

**Consideration:** No explicit flash loan checks

**Assessment:** NFT-based voting power cannot be flash-borrowed (ERC721 doesn't support flash loans). Revenue distribution is pro-rata to vote weights set in previous epoch.

**Status:** Not a vulnerability for this design.

---

## Out of Scope for Audit

### 1. External Dependencies

The following are assumed to be secure and correctly implemented:

- **OpenZeppelin Contracts 4.x** - Standard library
- **Kodiak DEX Router** - External DEX on Berachain
- **LBT (Liquid Backing Token)** - External protocol contract
- **Seat NFT Contract** - External NFT contract (assumed ERC721-compliant)

### 2. Off-Chain Components

- Deployment scripts (Foundry)
- Configuration management
- Monitoring and alerting
- Frontend integration

### 3. Future Enhancements

The following are planned but not included in this audit:

- Timelock for admin functions
- Multi-sig integration
- Cross-chain governance
- Governance token (beyond NFT)

---

## Upgrade Path Considerations

### Upgrading Voter

If LSGVoter needs to be replaced:

1. Deploy new Voter contract
2. Update MultiTokenRouter to point to new Voter
3. Re-add strategies to new Voter (with new Bribe contracts)
4. Users re-vote on new contract
5. Old Voter can be paused

### Upgrading Strategies

Strategies can be replaced individually:

1. Kill old strategy (`killStrategy()`)
2. Deploy new strategy contract
3. Add new strategy (`addStrategy()`)
4. Users can re-vote for new strategy

### Upgrading Bribe

Each strategy has its own Bribe:

1. Deploy new Bribe with same Voter reference
2. Add new strategy pointing to new Bribe
3. Old rewards can still be claimed from old Bribe
4. New rewards flow to new Bribe

---

## Monitoring Recommendations

### Critical Alerts

| Condition | Action |
|-----------|--------|
| `SwapFailed` event | Review swap path configuration |
| Large token balance in strategy | May need manual execution or rescue |
| `EmergencyPause` event | Investigate immediately |
| Unusual `notifyRevenue` amounts | Verify revenue source |

### Health Checks

| Check | Frequency |
|-------|-----------|
| Strategy balances | Daily |
| Reward token exhaustion | Weekly |
| Swap path validity | Before new token addition |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-19 | Initial document for Pashov audit |
