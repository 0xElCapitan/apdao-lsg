# apDAO LSG Integration Verification Checklist

## Purpose

This checklist verifies that all contracts are correctly deployed and configured for the LSG system to function properly.

---

## Pre-Verification Setup

```bash
# Export deployed contract addresses
export VOTER=0x...
export BRIBE=0x...
export ROUTER=0x...
export DIRECT_DIST=0x...
export GROWTH_TREASURY_STRATEGY=0x...
export LBT_BOOST=0x...

# Export test accounts
export TEST_NFT_ID=1  # Token ID of test NFT

# Set RPC URL
export RPC_URL=https://bartio.rpc.berachain.com
```

---

## 1. Contract Configuration Verification

### 1.1 LSGVoter Configuration
```bash
# Check router is set
cast call $VOTER "router()(address)" --rpc-url $RPC_URL
# Expected: $ROUTER address

# Check bribe is set
cast call $VOTER "bribe()(address)" --rpc-url $RPC_URL
# Expected: $BRIBE address

# Check seat NFT is set
cast call $VOTER "seatNFT()(address)" --rpc-url $RPC_URL
# Expected: SEAT_NFT address

# Check treasury is set
cast call $VOTER "treasury()(address)" --rpc-url $RPC_URL
# Expected: TREASURY address
```

**Checklist:**
- [ ] Router correctly set
- [ ] Bribe correctly set
- [ ] Seat NFT correctly set
- [ ] Treasury correctly set

### 1.2 Strategy Registration
```bash
# Check DirectDistributionStrategy is registered
cast call $VOTER "isStrategy(address)(bool)" $DIRECT_DIST --rpc-url $RPC_URL
# Expected: true

# Check GrowthTreasuryStrategy is registered
cast call $VOTER "isStrategy(address)(bool)" $GROWTH_TREASURY_STRATEGY --rpc-url $RPC_URL
# Expected: true

# Check LBTBoostStrategy is registered (if deployed)
cast call $VOTER "isStrategy(address)(bool)" $LBT_BOOST --rpc-url $RPC_URL
# Expected: true
```

**Checklist:**
- [ ] DirectDistributionStrategy registered
- [ ] GrowthTreasuryStrategy registered
- [ ] LBTBoostStrategy registered (if applicable)

### 1.3 Strategy Configuration
```bash
# Check DirectDistributionStrategy bribe reference
cast call $DIRECT_DIST "bribe()(address)" --rpc-url $RPC_URL
# Expected: $BRIBE address

# Check GrowthTreasuryStrategy treasury
cast call $GROWTH_TREASURY_STRATEGY "growthTreasury()(address)" --rpc-url $RPC_URL
# Expected: GROWTH_TREASURY address

# Check LBTBoostStrategy target token (if deployed)
cast call $LBT_BOOST "targetToken()(address)" --rpc-url $RPC_URL
# Expected: TARGET_TOKEN address
```

**Checklist:**
- [ ] DirectDistributionStrategy points to Bribe
- [ ] GrowthTreasuryStrategy points to correct treasury
- [ ] LBTBoostStrategy has correct target token

---

## 2. Voting Flow Verification

### 2.1 Vote for Strategy
```bash
# Vote for DirectDistributionStrategy
cast send $VOTER "vote(uint256,address)" $TEST_NFT_ID $DIRECT_DIST \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Check vote is recorded
cast call $VOTER "getVote(uint256)(address)" $TEST_NFT_ID --rpc-url $RPC_URL
# Expected: $DIRECT_DIST address

# Check voting power
cast call $VOTER "getVotingPower(address)(uint256)" $DIRECT_DIST --rpc-url $RPC_URL
# Expected: 1 (one NFT voting for this strategy)
```

**Checklist:**
- [ ] Vote transaction succeeds
- [ ] Vote is correctly recorded
- [ ] Voting power updated

### 2.2 Change Vote
```bash
# Change vote to GrowthTreasuryStrategy
cast send $VOTER "vote(uint256,address)" $TEST_NFT_ID $GROWTH_TREASURY_STRATEGY \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Verify old strategy lost power
cast call $VOTER "getVotingPower(address)(uint256)" $DIRECT_DIST --rpc-url $RPC_URL
# Expected: 0

# Verify new strategy gained power
cast call $VOTER "getVotingPower(address)(uint256)" $GROWTH_TREASURY_STRATEGY --rpc-url $RPC_URL
# Expected: 1
```

**Checklist:**
- [ ] Vote change succeeds
- [ ] Old strategy power decreased
- [ ] New strategy power increased

---

## 3. Revenue Distribution Flow

### 3.1 Send Revenue to Router
```bash
# Send test tokens to router (use a test ERC20)
cast send $TEST_TOKEN "transfer(address,uint256)" $ROUTER 1000000000000000000 \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Check router balance
cast call $TEST_TOKEN "balanceOf(address)(uint256)" $ROUTER --rpc-url $RPC_URL
# Expected: 1000000000000000000 (1 token with 18 decimals)
```

### 3.2 Flush Router to Voter
```bash
# Flush tokens to voter
cast send $ROUTER "flush(address)" $TEST_TOKEN \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Check voter received tokens
cast call $TEST_TOKEN "balanceOf(address)(uint256)" $VOTER --rpc-url $RPC_URL
# Expected: tokens transferred to voter
```

**Checklist:**
- [ ] Tokens received by router
- [ ] Flush transaction succeeds
- [ ] Voter received tokens

### 3.3 Distribute to Strategies
```bash
# Distribute to all strategies
cast send $VOTER "distributeToAllStrategies(address)" $TEST_TOKEN \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Check strategy received tokens (based on vote allocation)
cast call $TEST_TOKEN "balanceOf(address)(uint256)" $DIRECT_DIST --rpc-url $RPC_URL
# Expected: proportional to voting power
```

**Checklist:**
- [ ] Distribution transaction succeeds
- [ ] Strategies received proportional tokens

### 3.4 Execute Strategy
```bash
# Execute DirectDistributionStrategy
cast send $DIRECT_DIST "execute(address)(uint256)" $TEST_TOKEN \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Check Bribe received tokens
cast call $TEST_TOKEN "balanceOf(address)(uint256)" $BRIBE --rpc-url $RPC_URL
# Expected: tokens forwarded to bribe
```

**Checklist:**
- [ ] Strategy execute succeeds
- [ ] Destination (Bribe/Treasury/LBT) received tokens

---

## 4. Reward Claiming Flow

### 4.1 Check Earned Rewards
```bash
# Check earned rewards for voter
cast call $BRIBE "earned(address,address)(uint256)" $TEST_TOKEN $USER_ADDRESS --rpc-url $RPC_URL
# Expected: > 0 if user has voting balance in bribe
```

### 4.2 Claim Rewards
```bash
# Claim rewards from bribe
cast send $BRIBE "getReward(address)" $TEST_TOKEN \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Check user received tokens
cast call $TEST_TOKEN "balanceOf(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL
# Expected: increased by claimed amount
```

**Checklist:**
- [ ] Earned rewards visible
- [ ] Claim transaction succeeds
- [ ] User received reward tokens

---

## 5. Epoch Transition Verification

### 5.1 Check Current Epoch
```bash
# Get current epoch
cast call $VOTER "currentEpoch()(uint256)" --rpc-url $RPC_URL

# Get epoch end timestamp
cast call $VOTER "epochEnd()(uint256)" --rpc-url $RPC_URL
```

### 5.2 Advance Epoch (after epoch ends)
```bash
# Advance to next epoch
cast send $VOTER "advanceEpoch()" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Verify epoch incremented
cast call $VOTER "currentEpoch()(uint256)" --rpc-url $RPC_URL
```

**Checklist:**
- [ ] Epoch number correct
- [ ] Epoch advancement works
- [ ] Votes carry over correctly

---

## 6. Emergency Controls Verification

### 6.1 Pause System (Emergency Multisig Only)
```bash
# Pause voter
cast send $VOTER "pause()" \
  --rpc-url $RPC_URL \
  --private-key $EMERGENCY_MULTISIG_KEY

# Verify paused
cast call $VOTER "paused()(bool)" --rpc-url $RPC_URL
# Expected: true

# Verify voting fails when paused
cast send $VOTER "vote(uint256,address)" $TEST_NFT_ID $DIRECT_DIST \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
# Expected: revert "Pausable: paused"
```

### 6.2 Unpause System
```bash
# Unpause voter
cast send $VOTER "unpause()" \
  --rpc-url $RPC_URL \
  --private-key $EMERGENCY_MULTISIG_KEY

# Verify unpaused
cast call $VOTER "paused()(bool)" --rpc-url $RPC_URL
# Expected: false
```

**Checklist:**
- [ ] Pause transaction succeeds (from emergency multisig)
- [ ] Operations blocked when paused
- [ ] Unpause transaction succeeds
- [ ] Operations resume after unpause

---

## 7. Token Rescue Verification

### 7.1 Rescue from Strategy
```bash
# Owner rescues stuck tokens
cast send $DIRECT_DIST "rescueTokens(address,address,uint256)" \
  $TEST_TOKEN $RECIPIENT 1000000000000000000 \
  --rpc-url $RPC_URL \
  --private-key $OWNER_KEY

# Verify recipient received tokens
cast call $TEST_TOKEN "balanceOf(address)(uint256)" $RECIPIENT --rpc-url $RPC_URL
```

**Checklist:**
- [ ] Rescue transaction succeeds (owner only)
- [ ] Recipient received tokens
- [ ] Non-owner rescue fails

---

## Verification Summary

| Category | Status |
|----------|--------|
| Contract Configuration | [ ] |
| Strategy Registration | [ ] |
| Voting Flow | [ ] |
| Revenue Distribution | [ ] |
| Strategy Execution | [ ] |
| Reward Claiming | [ ] |
| Epoch Transitions | [ ] |
| Emergency Controls | [ ] |
| Token Rescue | [ ] |

**Overall Status**: [ ] PASS / [ ] FAIL

**Date Verified**: _______________
**Verified By**: _______________
**Network**: _______________
