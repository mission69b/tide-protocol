# Tide Core v1 — Implementation Plan

**Status:** Engineering Ready

This document maps the specification 1:1 to Move module files with a detailed task breakdown for systematic implementation.

---

## Implementation Order

Modules are ordered by dependency (foundation first):

```
1. constants.move     ─┐
2. errors.move        ├── Foundation (no deps)
3. events.move        ─┘
4. math.move          ── Utilities
5. tide.move          ── Global config
6. supporter_pass.move── Backer position (depends on math)
7. reward_vault.move  ── Reward distribution (depends on math, events)
8. capital_vault.move ── Principal custody (depends on math, events)
9. staking_adapter.move ── Staking (depends on capital_vault)
10. listing.move      ── Orchestration (depends on all vaults)
11. admin.move        ── Admin actions (depends on all)
```

---

## Phase 1: Foundation Modules

### Task 1.1: `constants.move`

**File:** `contracts/core/sources/constants.move`

**Purpose:** Shared constants and precision values.

| Item | Type | Value | Description |
|------|------|-------|-------------|
| `PRECISION` | u128 | 1_000_000_000_000 | 12 decimal fixed-point |
| `VERSION` | u64 | 1 | Protocol version |
| `MAX_BPS` | u64 | 10_000 | Basis points denominator |

**Tasks:**
- [ ] Define module with constant macros
- [ ] Export precision for share calculations
- [ ] Export version for upgrade checks

**Estimated complexity:** Low

---

### Task 1.2: `errors.move`

**File:** `contracts/core/sources/errors.move`

**Purpose:** Canonical error codes with `public(package) macro fun` pattern.

| Error | Code | Description |
|-------|------|-------------|
| `not_active` | 0 | Listing not in Active state |
| `paused` | 1 | Protocol is paused |
| `invalid_amount` | 2 | Zero or invalid deposit amount |
| `already_claimed` | 3 | No rewards to claim |
| `not_authorized` | 4 | Caller lacks capability |
| `invalid_state` | 5 | Invalid state transition |
| `tranche_not_ready` | 6 | Tranche not yet releasable |
| `already_released` | 7 | Tranche already released |
| `insufficient_balance` | 8 | Vault balance too low |
| `staking_locked` | 9 | Cannot unstake yet |
| `wrong_listing` | 10 | Pass doesn't belong to listing |

**Tasks:**
- [ ] Define error module
- [ ] Create macro for each error
- [ ] Add `#[test_only]` constants for testing

**Estimated complexity:** Low

---

### Task 1.3: `events.move`

**File:** `contracts/core/sources/events.move`

**Purpose:** Standardized event definitions.

| Event | Fields | Emitter |
|-------|--------|---------|
| `Deposited` | listing_id, backer, amount, shares, pass_id | listing |
| `Claimed` | listing_id, pass_id, amount | listing |
| `TrancheReleased` | listing_id, tranche_idx, amount, recipient | listing |
| `RouteIn` | listing_id, source, amount | reward_vault |
| `RewardIndexUpdated` | listing_id, old_index, new_index | reward_vault |
| `Staked` | listing_id, amount, validator | staking_adapter |
| `Unstaked` | listing_id, amount | staking_adapter |
| `StateChanged` | listing_id, old_state, new_state | listing |
| `Paused` | paused_by | tide |
| `Unpaused` | unpaused_by | tide |

**Tasks:**
- [ ] Define event structs (past tense naming)
- [ ] Add `copy, drop` abilities
- [ ] Document each event

**Estimated complexity:** Low

---

## Phase 2: Utilities

### Task 2.1: `math.move`

**File:** `contracts/core/sources/math.move`

**Purpose:** Fixed-point arithmetic for share calculations and reward index.

**Functions:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `mul_div` | `(a: u128, b: u128, c: u128): u128` | (a × b) / c with overflow protection |
| `mul_div_down` | `(a: u128, b: u128, c: u128): u128` | Floor division |
| `mul_div_up` | `(a: u128, b: u128, c: u128): u128` | Ceiling division |
| `to_shares` | `(amount: u64, total_supply: u64, total_shares: u128): u128` | Convert deposit to shares |
| `to_amount` | `(shares: u128, total_supply: u64, total_shares: u128): u64` | Convert shares to amount |

**Invariants:**
- Rounding MUST be deterministic
- Overflow MUST abort, not wrap
- Division by zero MUST abort

**Tasks:**
- [ ] Implement `mul_div` variants
- [ ] Implement share conversion functions
- [ ] Add overflow checks
- [ ] Write unit tests for edge cases (0, max, overflow)

**Estimated complexity:** Medium

---

## Phase 3: Global Config

### Task 3.1: `tide.move`

**File:** `contracts/core/sources/tide.move`

**Purpose:** Global protocol configuration (shared singleton).

**Struct: `Tide`**

```move
public struct Tide has key {
    id: UID,
    treasury: address,
    paused: bool,
    version: u64,
}
```

**Struct: `AdminCap`**

```move
public struct AdminCap has key, store {
    id: UID,
}
```

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `init` | internal | Create Tide + AdminCap |
| `pause` | public | Set paused = true (requires AdminCap) |
| `unpause` | public | Set paused = false (requires AdminCap) |
| `is_paused` | public | View paused state |
| `treasury` | public | View treasury address |
| `version` | public | View version |

**Invariants:**
- Tide holds no capital
- Tide cannot redirect funds
- Single instance (created in init)

**Tasks:**
- [ ] Define structs
- [ ] Implement init with OTW
- [ ] Implement pause/unpause with AdminCap
- [ ] Add getters
- [ ] Write tests

**Estimated complexity:** Low

---

## Phase 4: Backer Position

### Task 4.1: `supporter_pass.move`

**File:** `contracts/core/sources/supporter_pass.move`

**Purpose:** Transferable NFT representing backer's economic position.

**Struct: `SupporterPass`**

```move
public struct SupporterPass has key, store {
    id: UID,
    listing_id: ID,
    shares: u128,          // Fixed at deposit, immutable
    claim_index: u128,     // Last claimed reward index
    deposited_amount: u64, // Original deposit (for display)
    deposited_at: u64,     // Timestamp (for display)
}
```

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `mint` | package | Create new pass with shares |
| `shares` | public | Get share amount |
| `claim_index` | public | Get current claim index |
| `listing_id` | public | Get associated listing |
| `update_claim_index` | package | Set new claim index after claim |
| `deposited_amount` | public | Get original deposit |

**Invariants:**
- Shares are immutable after mint
- Claim index only increases
- Ownership = full entitlement

**Tasks:**
- [ ] Define struct with correct abilities
- [ ] Implement package-visibility mint
- [ ] Implement getters
- [ ] Implement claim index update
- [ ] Add Display support (optional)
- [ ] Write transfer safety tests

**Estimated complexity:** Low-Medium

---

## Phase 5: Vaults

### Task 5.1: `reward_vault.move`

**File:** `contracts/core/sources/reward_vault.move`

**Purpose:** Hold rewards and maintain cumulative distribution index.

**Struct: `RewardVault`**

```move
public struct RewardVault has key {
    id: UID,
    listing_id: ID,
    balance: Balance<SUI>,
    global_index: u128,    // Cumulative reward-per-share
    total_distributed: u64, // Lifetime distributed
}
```

**Struct: `RouteCapability`**

```move
public struct RouteCapability has key, store {
    id: UID,
    listing_id: ID,
}
```

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `new` | package | Create vault for listing |
| `deposit_rewards` | public | Add rewards, update index (requires RouteCapability) |
| `withdraw` | package | Withdraw for claim |
| `global_index` | public | Get current index |
| `balance` | public | Get current balance |
| `calculate_claimable` | public | Compute claimable for shares + index |

**Invariants:**
- Index is monotonically non-decreasing
- Index updates only on deposit
- Principal never enters

**Tasks:**
- [ ] Define structs
- [ ] Implement deposit with index update
- [ ] Implement withdraw
- [ ] Implement claimable calculation
- [ ] Add RouteCapability pattern
- [ ] Write index monotonicity tests
- [ ] Write no-principal-entry tests

**Estimated complexity:** Medium

---

### Task 5.2: `capital_vault.move`

**File:** `contracts/core/sources/capital_vault.move`

**Purpose:** Hold contributed principal, manage tranche releases.

**Struct: `CapitalVault`**

```move
public struct CapitalVault has key {
    id: UID,
    listing_id: ID,
    balance: Balance<SUI>,
    total_principal: u64,
    total_shares: u128,
    tranches: vector<Tranche>,
    next_tranche_idx: u64,
}
```

**Struct: `Tranche`**

```move
public struct Tranche has store, copy, drop {
    amount: u64,
    release_time: u64,
    released: bool,
}
```

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `new` | package | Create vault with release schedule |
| `accept_deposit` | package | Accept SUI, calculate shares |
| `release_tranche` | package | Release next tranche to issuer |
| `total_principal` | public | Get total deposited |
| `total_shares` | public | Get total shares minted |
| `is_tranche_ready` | public | Check if tranche is releasable |
| `next_tranche` | public | Get next unreleased tranche |

**Invariants:**
- Principal only flows to issuer
- No backer withdrawals
- Released tranches cannot re-release

**Tasks:**
- [ ] Define structs
- [ ] Implement deposit flow
- [ ] Implement share calculation
- [ ] Implement tranche release
- [ ] Add release schedule validation
- [ ] Write principal isolation tests
- [ ] Write tranche release tests

**Estimated complexity:** High

---

## Phase 6: Staking

### Task 6.1: `staking_adapter.move`

**File:** `contracts/core/sources/staking_adapter.move`

**Purpose:** Native Sui staking for locked capital.

**Struct: `StakingAdapter`**

```move
public struct StakingAdapter has key {
    id: UID,
    listing_id: ID,
    staked_sui: Option<StakedSui>,
    pending_unstake: u64,
    validator: address,
}
```

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `new` | package | Create adapter with validator |
| `stake` | package | Stake available capital |
| `request_unstake` | package | Request withdrawal |
| `withdraw_staked` | package | Withdraw after epoch |
| `collect_rewards` | package | Harvest staking rewards to RewardVault |
| `staked_amount` | public | Get currently staked |

**Invariants:**
- Only locked capital staked
- Rewards flow to RewardVault
- Priority: unstake before release

**Sui System Integration:**
- Uses `sui_system::request_add_stake`
- Uses `sui_system::request_withdraw_stake`
- Epoch-aware timing

**Tasks:**
- [ ] Define structs
- [ ] Implement stake flow
- [ ] Implement unstake request
- [ ] Implement epoch-aware withdrawal
- [ ] Implement reward collection
- [ ] Handle priority rule (unstake before release)
- [ ] Write staking integration tests

**Estimated complexity:** High

---

## Phase 7: Orchestration

### Task 7.1: `listing.move`

**File:** `contracts/core/sources/listing.move`

**Purpose:** Listing lifecycle and orchestration of all vaults.

**Struct: `Listing`**

```move
public struct Listing has key {
    id: UID,
    issuer: address,
    capital_vault_id: ID,
    reward_vault_id: ID,
    staking_adapter_id: ID,
    state: u8,  // 0=Draft, 1=Active, 2=Finalized, 3=Completed
    config_hash: vector<u8>,
    activation_time: u64,
    // Release schedule params
    num_tranches: u64,
    tranche_interval: u64,
    // Stats
    total_backers: u64,
}
```

**Struct: `ListingCap`**

```move
public struct ListingCap has key, store {
    id: UID,
    listing_id: ID,
}
```

**State Machine:**

| State | Value | Allowed Actions |
|-------|-------|-----------------|
| Draft | 0 | Configure, activate |
| Active | 1 | Deposit, stake, route revenue |
| Finalized | 2 | Release, claim, route revenue |
| Completed | 3 | Claim only |

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `new` | public | Create draft listing |
| `activate` | public | Transition to Active (requires ListingCap) |
| `finalize` | public | Transition to Finalized |
| `complete` | public | Transition to Completed |
| `deposit` | public | Accept backer deposit |
| `claim` | public | Claim rewards for pass |
| `release_tranche` | public | Release capital to issuer |
| `state` | public | Get current state |
| `issuer` | public | Get issuer address |

**Invariants:**
- State transitions are unidirectional
- Config immutable after activation
- Deposits only in Active state

**Tasks:**
- [ ] Define structs and state constants
- [ ] Implement lifecycle transitions
- [ ] Implement deposit orchestration
- [ ] Implement claim orchestration
- [ ] Implement release orchestration
- [ ] Emit all events
- [ ] Write state machine tests
- [ ] Write full deposit→claim flow tests

**Estimated complexity:** High

---

## Phase 8: Admin

### Task 8.1: `admin.move`

**File:** `contracts/core/sources/admin.move`

**Purpose:** Capability-gated admin actions.

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `create_listing` | public | Create new listing (requires AdminCap) |
| `issue_route_capability` | public | Issue RouteCapability to adapter |
| `emergency_pause` | public | Pause protocol |
| `resume` | public | Resume protocol |

**Tasks:**
- [ ] Implement listing creation
- [ ] Implement capability issuance
- [ ] Implement pause/resume wrappers
- [ ] Write access control tests

**Estimated complexity:** Medium

---

## Phase 9: Adapter

### Task 9.1: `faith_router.move`

**File:** `contracts/adapters/faith_router/sources/faith_router.move`

**Purpose:** FAITH-specific revenue routing adapter.

**Struct: `FaithRouter`**

```move
public struct FaithRouter has key {
    id: UID,
    listing_id: ID,
    revenue_bps: u64,      // e.g., 1000 = 10%
    total_routed: u64,
    route_cap: RouteCapability,
}
```

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `new` | public | Create router with RouteCapability |
| `route` | public | Route SUI to RewardVault |
| `revenue_bps` | public | Get routing percentage |
| `total_routed` | public | Get lifetime routed |

**Invariants:**
- Revenue percentage immutable
- Routes only to RewardVault
- Emits RouteIn events

**Tasks:**
- [ ] Define structs
- [ ] Implement route function
- [ ] Emit standardized events
- [ ] Write routing tests

**Estimated complexity:** Medium

---

## Phase 10: Integration Testing

### Task 10.1: End-to-End Tests

**File:** `contracts/core/tests/e2e_tests.move`

**Test Scenarios:**

| Scenario | Description |
|----------|-------------|
| Full lifecycle | Draft → Active → deposit → route → claim → release → complete |
| Multi-backer | Multiple backers, fair reward distribution |
| Transfer claim | Transfer pass, new owner claims |
| Late joiner | Deposit after rewards, no pre-deposit claim |
| Tranche release | All tranches release correctly |
| Pause/resume | System pauses and resumes correctly |

**Tasks:**
- [ ] Implement lifecycle test
- [ ] Implement multi-backer test
- [ ] Implement transfer test
- [ ] Implement late joiner test
- [ ] Implement release test
- [ ] Implement pause test

**Estimated complexity:** High

---

## Implementation Checklist

### Foundation (Week 1)
- [ ] 1.1 constants.move
- [ ] 1.2 errors.move
- [ ] 1.3 events.move
- [ ] 2.1 math.move
- [ ] 3.1 tide.move

### Core (Week 2)
- [ ] 4.1 supporter_pass.move
- [ ] 5.1 reward_vault.move
- [ ] 5.2 capital_vault.move

### Integration (Week 3)
- [ ] 6.1 staking_adapter.move
- [ ] 7.1 listing.move
- [ ] 8.1 admin.move

### Adapter + Testing (Week 4)
- [ ] 9.1 faith_router.move
- [ ] 10.1 e2e_tests.move
- [ ] Security review
- [ ] Documentation review

---

## Risk Areas

| Risk | Mitigation |
|------|------------|
| Fixed-point overflow | Use u128, add overflow checks in math.move |
| Staking epoch timing | Document epoch delays, add pending state |
| Reward index precision | 12 decimal precision (1e12) |
| Reentrancy | No callbacks, linear execution |
| Upgrade safety | Version checks, immutable economics |

---

## Dependencies

### Sui Framework Modules Used

| Module | Usage |
|--------|-------|
| `sui::object` | Object creation |
| `sui::transfer` | Object transfers |
| `sui::balance` | Balance handling |
| `sui::coin` | Coin operations |
| `sui::event` | Event emission |
| `sui::tx_context` | Transaction context |
| `sui::clock` | Timestamp access |
| `sui_system::sui_system` | Native staking |
| `sui_system::staking_pool` | Staked SUI handling |

---

## Notes

1. **Package visibility**: Core modules use `public(package)` for internal functions
2. **Friend pattern**: Listing is friend of vaults for orchestration
3. **Capability pattern**: Admin actions require capabilities
4. **Display support**: SupporterPass should have Display for wallet UX
5. **Naming**: Use Tide terminology throughout (not Category)
