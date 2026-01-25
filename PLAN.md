# Tide Core v1 — Implementation Plan

**Status:** Engineering Ready

This document maps the specification 1:1 to Move module files with a detailed task breakdown for systematic implementation.

---

## Architecture Overview

Tide v1 uses a **registry-first architecture** with **minimal council gating**:

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Tide (Global Config)                       │
│                   admin_wallet, global_pause, version                │
└─────────────────────────────────────────────────────────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              ▼                     ▼                     ▼
┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
│   TreasuryVault     │ │   ListingRegistry   │ │    CouncilConfig    │
│ (protocol fees)     │ │ listing_count, [IDs]│ │ threshold, members  │
└─────────────────────┘ └─────────────────────┘ └─────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              ┌─────────┐     ┌─────────┐     ┌─────────┐
              │Listing 1│     │Listing 2│     │Listing N│
              │ (FAITH) │     │ (future)│     │ (future)│
              └────┬────┘     └────┬────┘     └────┬────┘
                   │               │               │
        ┌──────────┼──────────┐    :               :
        ▼          ▼          ▼
  ┌───────────┐ ┌───────────┐ ┌───────────┐
  │CapitalVault│ │RewardVault│ │StakingAdapter│
  └───────────┘ └───────────┘ └───────────┘
```

**v1 Constraint:** Only FAITH (Listing #1) is configured and surfaced.

---

## Implementation Order

Modules are ordered by dependency (foundation first):

```
1. constants.move       ─┐
2. errors.move          ├── Foundation (no deps)
3. events.move          ─┘
4. math.move            ── Utilities
5. tide.move            ── Global config
6. treasury_vault.move  ── Protocol fee vault (NEW)
7. council.move         ── Council capability
8. registry.move        ── Listing registry
9. supporter_pass.move  ── Backer position
10. display.move        ── Display metadata
11. reward_vault.move   ── Reward distribution
12. capital_vault.move  ── Principal custody
13. staking_adapter.move── Staking
14. listing.move        ── Orchestration (depends on all vaults)
15. admin.move          ── Admin/convenience actions
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
| `RAISE_FEE_BPS` | u64 | 100 | 1% raise fee |
| `STAKING_BACKER_BPS` | u64 | 8_000 | 80% staking rewards to backers |
| `STAKING_TREASURY_BPS` | u64 | 2_000 | 20% staking rewards to treasury |

**Tasks:**
- [x] Define module with constant macros
- [x] Export precision for share calculations
- [x] Export version for upgrade checks

**Estimated complexity:** Low

---

### Task 1.2: `errors.move`

**File:** `contracts/core/sources/errors.move`

**Purpose:** Canonical error codes with `public fun` pattern.

| Error | Code | Description |
|-------|------|-------------|
| `not_active` | 0 | Listing not in Active state |
| `paused` | 1 | Protocol/listing is paused |
| `invalid_amount` | 2 | Zero or invalid deposit amount |
| `nothing_to_claim` | 3 | No rewards to claim |
| `not_authorized` | 4 | Caller lacks capability |
| `invalid_state` | 5 | Invalid state transition |
| `tranche_not_ready` | 6 | Tranche not yet releasable |
| `already_released` | 7 | Tranche already released |
| `insufficient_balance` | 8 | Vault balance too low |
| `staking_locked` | 9 | Cannot unstake yet |
| `wrong_listing` | 10 | Pass doesn't belong to listing |
| `not_draft` | 11 | Listing not in Draft state |

**Tasks:**
- [x] Define error module
- [x] Create public function for each error
- [x] Add `#[test_only]` constants for testing

**Estimated complexity:** Low

---

### Task 1.3: `events.move`

**File:** `contracts/core/sources/events.move`

**Purpose:** Standardized event definitions for off-chain indexing and dashboards.

**Normative Rule:** Any dashboard, explorer, or reporting surface that represents Tide data MUST be reproducible by an independent indexer using only on-chain events.

#### Listing Lifecycle Events

| Event | Fields | Purpose |
|-------|--------|---------|
| `ListingCreated` | listing_id, listing_number, issuer, release_recipient, config_hash, min_deposit, raise_fee_bps, staking_backer_bps | Full config at creation for audit trail |
| `ListingActivated` | listing_id, activation_time | Marks start of deposit period |
| `ListingFinalized` | listing_id, finalization_time, total_raised, total_backers, total_shares, num_tranches | Locks schedule and captures final raise metrics |
| `ListingCompleted` | listing_id, total_released, total_distributed_rewards | Terminal state with lifetime metrics |
| `StateChanged` | listing_id, old_state, new_state | Generic state transitions |

#### Deposit & Claim Events

| Event | Fields | Purpose |
|-------|--------|---------|
| `Deposited` | listing_id, backer, amount, shares, pass_id, total_raised, total_passes, epoch | Backer deposits with running totals for dashboard |
| `Claimed` | listing_id, pass_id, backer, amount, shares, old_claim_index, new_claim_index, epoch | Reward claims with audit math |

#### Capital Release Events

| Event | Fields | Purpose |
|-------|--------|---------|
| `TrancheReleased` | listing_id, tranche_idx, amount, recipient, total_tranches, remaining_tranches, cumulative_released, release_time | Capital release with progress tracking |
| `ScheduleFinalized` | listing_id, finalization_time, total_principal, initial_tranche_amount, monthly_tranche_amount, num_monthly_tranches, first_monthly_release_time, final_release_time | Full schedule for timeline visualization |

#### Revenue Events

| Event | Fields | Purpose |
|-------|--------|---------|
| `RouteIn` | listing_id, source, amount, cumulative_distributed, new_global_index | Revenue routing with running totals |
| `RewardIndexUpdated` | listing_id, old_index, new_index | Index changes for verification |

#### Staking Events

| Event | Fields | Purpose |
|-------|--------|---------|
| `Staked` | listing_id, amount, validator, total_staked | Staking activity with running total |
| `Unstaked` | listing_id, amount, total_staked | Unstaking activity with running total |
| `StakingRewardsHarvested` | listing_id, gross_rewards, backer_rewards, treasury_rewards, new_reward_index | Reward harvesting with split details |

#### Fee Events

| Event | Fields | Purpose |
|-------|--------|---------|
| `RaiseFeeCollected` | listing_id, fee_amount, treasury, total_raised, fee_bps | Raise fee collection |
| `StakingRewardSplit` | listing_id, total_rewards, backer_amount, treasury_amount, backer_bps | Staking reward distribution |
| `TreasuryPayment` | listing_id, payment_type, amount, treasury | Generic treasury payments |
| `TreasuryDeposit` | vault_id, amount, new_balance | Deposit to TreasuryVault |
| `TreasuryWithdrawal` | vault_id, amount, recipient, remaining_balance | Withdrawal from TreasuryVault |
| `TreasuryVaultDeposit` | listing_id, payment_type, amount, vault_id | Fee deposit with listing context |

#### Admin Events

| Event | Fields | Purpose |
|-------|--------|---------|
| `Paused` / `Unpaused` | paused_by / unpaused_by | Global pause state changes |
| `ListingPauseChanged` | listing_id, paused | Per-listing pause state |
| `TreasuryUpdated` | old_treasury, new_treasury | Treasury address changes |

#### Registry Events (in `registry.move`)

| Event | Fields | Purpose |
|-------|--------|---------|
| `ListingRegistered` | listing_id, listing_number, issuer | Listing creation in registry |

**Tasks:**
- [x] Define event structs (past tense naming)
- [x] Add `copy, drop` abilities
- [x] Document each event
- [x] Add running totals for dashboard derivation
- [x] Add epoch/timestamps for time-series analysis
- [x] Add verification fields (shares, indices) for audit

**Off-Chain Feature Support:**

| Feature | Required Events |
|---------|-----------------|
| Capital Transparency Dashboard | `Deposited`, `TrancheReleased`, `RouteIn`, `RaiseFeeCollected`, `StakingRewardSplit`, `ScheduleFinalized` |
| Backer Identity & Reputation | `Deposited` (pass_id, backer), `Claimed` (pass_id, backer, amount) |
| Listing Timeline | `ListingCreated`, `ListingActivated`, `ListingFinalized`, `ListingCompleted`, `TrancheReleased` |
| Treasury Reporting | `RaiseFeeCollected`, `StakingRewardSplit`, `TreasuryPayment`, `TreasuryUpdated` |
| Staking Dashboard | `Staked`, `Unstaked`, `StakingRewardsHarvested` |

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
| `mul_div_up` | `(a: u128, b: u128, c: u128): u128` | Ceiling division |
| `to_shares` | `(amount: u64, precision: u128): u128` | Convert deposit to shares |
| `calculate_claimable` | `(shares, global_index, pass_index, precision)` | Calculate rewards |
| `calculate_new_index` | `(amount, total_shares, precision)` | Index delta |

**Invariants:**
- Rounding MUST be deterministic
- Overflow MUST abort, not wrap
- Division by zero MUST abort

**Tasks:**
- [x] Implement `mul_div` variants
- [x] Implement share conversion functions
- [x] Add overflow checks
- [x] Write unit tests for edge cases

**Estimated complexity:** Medium

---

## Phase 3: Global Config & Governance

### Task 3.1: `tide.move`

**File:** `contracts/core/sources/tide.move`

**Purpose:** Global protocol configuration (shared singleton).

**Structs:**

```move
public struct Tide has key {
    id: UID,
    admin_wallet: address,  // For treasury withdrawals
    paused: bool,
    version: u64,
}

public struct AdminCap has key, store {
    id: UID,
}
```

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `init` | internal | Create Tide + AdminCap + TreasuryVault |
| `pause` | public | Set paused = true (requires AdminCap) |
| `unpause` | public | Set paused = false (requires AdminCap) |
| `is_paused` | public | View paused state |
| `assert_not_paused` | public | Abort if paused |
| `set_admin_wallet` | public | Update admin wallet (requires AdminCap) |
| `withdraw_from_treasury` | public | Withdraw from TreasuryVault to admin (requires AdminCap) |
| `withdraw_all_from_treasury` | public | Withdraw all from TreasuryVault (requires AdminCap) |
| `withdraw_treasury_to` | public | Withdraw to custom recipient (requires AdminCap) |

**Invariants:**
- Tide holds no capital directly
- Fees flow to TreasuryVault
- Single instance (created in init)

**Tasks:**
- [x] Define structs
- [x] Implement init with OTW
- [x] Implement pause/unpause with AdminCap
- [x] Implement treasury withdrawal functions
- [x] Add getters
- [x] Write tests (5 tests)

**Estimated complexity:** Low

---

### Task 3.1a: `treasury_vault.move` (NEW)

**File:** `contracts/core/sources/treasury_vault.move`

**Purpose:** Protocol fee collection vault.

**Structs:**

```move
public struct TreasuryVault has key {
    id: UID,
    balance: Balance<SUI>,
    total_deposited: u64,
    total_withdrawn: u64,
}
```

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `new` | package | Create vault (called from tide init) |
| `deposit` | public | Deposit SUI to vault |
| `deposit_with_type` | public | Deposit with listing context and payment type |
| `withdraw` | package | Withdraw to recipient (called from tide) |
| `withdraw_all` | package | Withdraw all (called from tide) |
| `balance` | public | Get current balance |
| `total_deposited` | public | Get cumulative deposits |
| `total_withdrawn` | public | Get cumulative withdrawals |

**Fee Sources:**
- Raise fee (1%) deposited via `collect_raise_fee()`
- Staking split (20%) deposited via `harvest_staking_rewards()`

**Invariants:**
- Only AdminCap holders can withdraw (via tide.move)
- All deposits are logged with events

**Tasks:**
- [x] Define structs
- [x] Implement deposit functions
- [x] Implement withdraw functions (package-private)
- [x] Add view functions
- [x] Write tests (2 tests)

**Estimated complexity:** Low

---

### Task 3.2: `council.move` (NEW)

**File:** `contracts/core/sources/council.move`

**Purpose:** Council capability for registry-first architecture.

**Structs:**

```move
public struct CouncilCap has key, store {
    id: UID,
}

public struct CouncilConfig has key {
    id: UID,
    threshold: u64,  // Documentation only (multisig enforces)
    members: u64,
    version: u64,
}
```

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `init` | internal | Create CouncilCap + CouncilConfig |
| `transfer_cap` | public | Transfer cap to multisig |
| `threshold` | public | Get threshold |
| `members` | public | Get member count |

**Council MAY:**
- Create/register new listings
- Activate or finalize listings
- Pause or resume listings

**Council MUST NOT:**
- Seize capital
- Redirect rewards
- Change live economics after activation

**Tasks:**
- [x] Define structs
- [x] Implement init
- [x] Implement transfer
- [x] Write tests (2 tests)

**Estimated complexity:** Low

---

### Task 3.3: `registry.move` (NEW)

**File:** `contracts/core/sources/registry.move`

**Purpose:** Registry of all listings with council gating.

**Struct:**

```move
public struct ListingRegistry has key {
    id: UID,
    listing_count: u64,
    listings: vector<ID>,
    version: u64,
}
```

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `init` | internal | Create registry |
| `register_listing` | public | Register listing (requires CouncilCap) |
| `listing_count` | public | Get count |
| `listing_at` | public | Get listing by index |
| `is_registered` | public | Check if registered |

**Invariant:** Registry holds no capital and cannot redirect funds.

**Tasks:**
- [x] Define structs
- [x] Implement init
- [x] Implement council-gated registration
- [x] Write tests (2 tests)

**Estimated complexity:** Low

---

## Phase 4: Backer Position

### Task 4.1: `supporter_pass.move`

**File:** `contracts/core/sources/supporter_pass.move`

**Purpose:** Transferable NFT representing backer's economic position (economics only).

**Struct:**

```move
public struct SupporterPass has key, store {
    id: UID,
    listing_id: ID,
    shares: u128,        // Fixed at deposit, immutable
    claim_index: u128,   // Last claimed reward index
    created_epoch: u64,  // When minted (non-economic)
}
```

**Normative Rules:**
- Shares are immutable after mint and MUST be > 0
- Claim index only increases
- Ownership = full entitlement
- MUST NOT store balances or custody funds
- MUST NOT call sui::display

**Tasks:**
- [x] Define struct with correct abilities
- [x] Implement package-visibility mint
- [x] Implement getters
- [x] Implement claim index update
- [x] Write transfer safety tests (6 tests)

**Estimated complexity:** Low

---

### Task 4.2: `display.move`

**File:** `contracts/core/sources/display.move`

**Purpose:** Display configuration for SupporterPass using `sui::display`.

**Display Fields:**
- `name`: "Tide Supporter Pass #{id}"
- `description`: Economic position description
- `image_url`: Off-chain renderer URL with `{id}` placeholder
- `link`: Detail page URL

**Normative Rules:**
- Display MUST NOT affect reward calculations
- Display can point to off-chain renderers

**Tasks:**
- [x] Define display setup function
- [x] Configure default display fields
- [x] Add update functions
- [ ] Document off-chain renderer API

**Estimated complexity:** Low

---

## Phase 5: Vaults

### Task 5.1: `reward_vault.move`

**File:** `contracts/core/sources/reward_vault.move`

**Purpose:** Hold rewards and maintain cumulative distribution index.

**Structs:**

```move
public struct RewardVault has key {
    id: UID,
    listing_id: ID,
    balance: Balance<SUI>,
    global_index: u128,
    total_shares: u128,
    total_distributed: u64,
}

public struct RouteCapability has key, store {
    id: UID,
    listing_id: ID,
}
```

**Invariants:**
- Index is monotonically non-decreasing
- Index updates only on deposit
- Principal never enters

**Tasks:**
- [x] Define structs
- [x] Implement deposit with index update
- [x] Implement withdraw
- [x] Implement claimable calculation
- [x] Add RouteCapability pattern
- [x] Write index monotonicity tests (5 tests)

**Estimated complexity:** Medium

---

### Task 5.2: `capital_vault.move`

**File:** `contracts/core/sources/capital_vault.move`

**Purpose:** Hold contributed principal, manage tranche releases.

**Structs:**

```move
public struct CapitalVault has key {
    id: UID,
    listing_id: ID,
    release_recipient: address,  // Artist/creator who receives released capital
    balance: Balance<SUI>,
    total_principal: u64,
    total_shares: u128,
    tranches: vector<Tranche>,
    next_tranche_idx: u64,
}

public struct Tranche has store, copy, drop {
    amount: u64,
    release_time: u64,
    released: bool,
}
```

**Invariants:**
- Principal only flows to release_recipient
- No backer withdrawals
- Released tranches cannot re-release

**Tasks:**
- [x] Define structs
- [x] Implement deposit flow
- [x] Implement share calculation
- [x] Implement tranche release
- [x] Write principal isolation tests (9 tests)

**Estimated complexity:** High

---

## Phase 6: Staking

### Task 6.1: `staking_adapter.move`

**File:** `contracts/core/sources/staking_adapter.move`

**Purpose:** Native Sui staking for locked capital.

**Invariants:**
- Only locked capital staked
- Rewards flow to RewardVault
- Priority: unstake before release

**Tasks:**
- [x] Define structs
- [x] Implement stake flow (sui_system::request_add_stake_non_entry)
- [x] Implement unstake (unstake_at, unstake_all, unstake_for_amount)
- [x] Implement reward split (80% backers / 20% treasury)
- [x] Handle priority rule (unstake_for_amount for tranche releases)
- [x] Store StakedSui in dynamic fields
- [ ] Add unit tests (requires test_scenario with SuiSystemState)

**Estimated complexity:** High

---

## Phase 7: Orchestration

### Task 7.1: `listing.move`

**File:** `contracts/core/sources/listing.move`

**Purpose:** Listing lifecycle and orchestration of all vaults.

**Struct:**

```move
public struct Listing has key {
    id: UID,
    listing_number: u64,
    issuer: address,
    state: u8,
    config_hash: vector<u8>,
    config: ListingConfig,
    activation_time: u64,
    total_backers: u64,
    paused: bool,
}

public struct ListingConfig has copy, drop, store {
    issuer: address,               // Protocol operator (manages listing)
    release_recipient: address,    // Artist/creator (receives capital releases)
    validator: address,
    tranche_amounts: vector<u64>,
    tranche_times: vector<u64>,
    revenue_bps: u64,
}
```

**State Machine:**

| State | Value | Allowed Actions |
|-------|-------|-----------------|
| Draft | 0 | Configure, activate (council) |
| Active | 1 | Deposit, stake, route revenue |
| Finalized | 2 | Release, claim, route revenue |
| Completed | 3 | Claim only |

**Council-Gated Operations:**
- `new` (create listing via registry)
- `activate` (enable deposits)
- `finalize` (stop deposits)
- `complete` (after all tranches)
- `pause` / `resume`

**Tasks:**
- [x] Define structs and state constants
- [x] Implement council-gated creation
- [x] Implement lifecycle transitions
- [x] Implement per-listing pause
- [x] Implement config hash
- [x] Implement deposit/claim/release
- [x] Write state machine tests (via E2E tests)

**Estimated complexity:** High

---

## Phase 8: Admin

### Task 8.1: `admin.move`

**File:** `contracts/core/sources/admin.move`

**Purpose:** Convenience wrappers for admin actions.

**Functions:**

| Function | Visibility | Description |
|----------|------------|-------------|
| `pause_protocol` | public | Global pause (AdminCap) |
| `unpause_protocol` | public | Global unpause (AdminCap) |
| `create_listing` | public | Create listing (CouncilCap) |
| `pause_listing` | public | Pause listing (CouncilCap) |
| `resume_listing` | public | Resume listing (CouncilCap) |

**Tasks:**
- [x] Implement global pause wrappers
- [x] Implement council wrappers
- [x] Write access control tests (via E2E tests)

**Estimated complexity:** Low

---

## Phase 9: Adapter

### Task 9.1: `faith_router.move`

**File:** `contracts/adapters/faith_router/sources/faith_router.move`

**Purpose:** FAITH-specific revenue routing adapter.

**Documentation:** See [ADAPTERS.md](./ADAPTERS.md) for the complete adapter pattern and integration guide.

**Invariants:**
- Revenue percentage immutable
- Routes only to RewardVault
- Emits RouteIn events
- Handles both protocol revenue AND staking reward harvesting

**Tasks:**
- [x] Define structs
- [x] Implement route function
- [x] Implement share/transfer_cap functions
- [x] Implement harvest_and_route function (staking integration)
- [x] Write routing tests (via E2E tests using RouteCapability)

**Estimated complexity:** Medium

---

## Phase 10: Integration Testing

### Task 10.1: End-to-End Tests

**File:** `contracts/core/tests/e2e_tests.move`

**Test Scenarios:**

| Scenario | Description |
|----------|-------------|
| Full lifecycle | Draft → Active → deposit → route → claim → release → complete |
| Council gating | Verify only council can create/activate/pause |
| Multi-backer | Multiple backers, fair reward distribution |
| Transfer claim | Transfer pass, new owner claims |
| Late joiner | Deposit after rewards, no pre-deposit claim |
| Per-listing pause | Pause one listing, others unaffected |

**Tasks:**
- [x] Implement lifecycle test
- [x] Implement council gating tests (via create_listing helper)
- [x] Implement multi-backer test
- [x] Implement transfer test
- [x] Implement late joiner test
- [x] Implement pause test (global pause + claims allowed when paused)

**All 6 E2E tests passing** using `sui::test_scenario`.

**Estimated complexity:** High

---

## Implementation Checklist

### Foundation (Week 1)
- [x] 1.1 constants.move
- [x] 1.2 errors.move
- [x] 1.3 events.move
- [x] 2.1 math.move
- [x] 3.1 tide.move
- [x] 3.2 council.move (NEW)
- [x] 3.3 registry.move (NEW)

### Core (Week 2)
- [x] 4.1 supporter_pass.move
- [x] 4.2 display.move
- [x] 5.1 reward_vault.move
- [x] 5.2 capital_vault.move

### Integration (Week 3)
- [x] 6.1 staking_adapter.move
- [x] 7.1 listing.move (updated for registry)
- [x] 8.1 admin.move (updated for council)

### Adapter + Testing (Week 4)
- [x] 9.1 faith_router.move
- [x] 10.1 e2e_tests.move (6 tests → now 99 tests in core)
- [x] Security review (access control verified)
- [x] Documentation review (README, MARKETPLACE.md, LOANS.md updated)

### Test Summary
- **Total Tests:** 97 (85 core + 12 adapter)
- **Core Unit Tests:** 59
- **Core E2E Tests:** 26
- **Adapter Tests:** 12
- **All Passing:** ✅

---

## Risk Areas

| Risk | Mitigation |
|------|------------|
| Fixed-point overflow | Use u128/u256, add overflow checks in math.move |
| Staking epoch timing | Document epoch delays, add pending state |
| Reward index precision | 12 decimal precision (1e12) |
| Council key compromise | 3-5 multisig, hardware wallets |
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
| `sui::display` | NFT display metadata |
| `sui::package` | Publisher for display |
| `sui_system::sui_system` | Native staking |

---

## v1+ Additions (Beyond Original Spec)

The following features have been added to expand the v1 foundation:

### Marketplace Package (`contracts/marketplace/`) ✅
- Native SupporterPass trading
- 5% seller fee → TreasuryVault
- 23 tests (20 unit + 3 E2E)
- See: `spec/marketplace-v1.md`

### Self-Paying Loans Package (`contracts/loans/`) ✅
- Borrow against SupporterPass collateral
- Auto-repay from rewards via keeper harvest
- Conservative 50% LTV, 5% interest
- 21 tests (14 unit + 7 E2E)
- See: `spec/self-paying-loans-v2.md`

### Future: DeepBook Integration (Simplified - 4-6 weeks)
- **Phase 1:** DeepBook Integration (liquidity + market rates)
- **Phase 2:** Flash Liquidations (keep only)
- **Phase 3:** DEEP Token Rewards (epoch-based)

**Removed/Deferred:**
- Custom rate curves → Use DeepBook's `borrow_rate()` directly
- Flash + Sell → Requires bid system (deferred)
- Margin trading → Removed (too complex)
- See: `spec/deepbook-integration-v1.md`

### Future: Marketplace Bid System (Planned)
- Buy orders with escrowed funds
- Instant sell to best bid
- Capital-free flash liquidations
- See: `spec/marketplace-v2.md`

### Core Enhancements ✅
- SupporterPass provenance fields (`pass_number`, `original_backer`, `total_claimed`)
- `claim_many` batch claiming
- Kiosk claiming support (`kiosk_ext.move`)
- Refund mechanism (Cancelled state)
- TreasuryVault for protocol fees

---

## Notes

1. **Registry-first:** All listings go through ListingRegistry
2. **Council gating:** CouncilCap required for listing lifecycle
3. **Per-listing pause:** Each listing has its own pause flag
4. **Config hash:** Immutable config verified via hash
5. **v1 Constraint:** Only FAITH (Listing #1) surfaced in product
6. **Naming:** Use Tide terminology throughout (never "Category" or "FEF")

---

## Total Test Coverage

| Package | Tests |
|---------|-------|
| Core | 99 |
| Faith Router | 17 |
| Marketplace | 23 |
| Loans | 21 |
| **Total** | **160** |
