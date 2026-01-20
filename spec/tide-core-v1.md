# Tide Core v1 — FEF Launch Specification

**Status:** ✅ IMPLEMENTED — Ready for Testnet/Mainnet Deployment

**Chain:** Sui (v1)

**Scope:** Core primitives + Extensions (Marketplace, Loans)

**v1 Core:** Registry-first architecture with minimal council gating, transparent fees & treasury policy. Only **FAITH** is configured and surfaced as Listing #1 (FEF).

**v1+ Extensions:** Separate packages that depend on core:
- `tide_marketplace` — Native SupporterPass trading (5% seller fee)
- `tide_loans` — Self-paying loans against SupporterPass collateral

---

## Positioning

**Tide v1** is the minimal on-chain infrastructure required to raise capital **after product-market fit**, without selling tokens, issuing equity, or introducing discretionary fund control.

Tide v1 is deployed with a **registry-first architecture** and **minimal council gating**, but ships with **only one configured and surfaced listing**:

> **Listing #1 — FAITH (surfaced as "Faith Expansion Fund / FEF")**

FEF is a **product surface**, not a separate protocol.

The registry and council exist to establish the canonical pattern and avoid future refactors — **not** to expand the v1 product surface.

---

## Design Principles (Normative)

All v1 implementations **MUST** satisfy:

- **Registry-First:** Listings are created via a `ListingRegistry` shared object.
  - v1 MUST ship with **only one configured & surfaced listing**: FAITH (Listing #1 / FEF).
  - Additional listings MAY exist in the registry but MUST NOT be surfaced or enabled in UI.

- **Minimal Council Gating:** A small multisig council gates listing creation, activation, finalization, and pause.
  - Council MUST NOT seize capital, redirect rewards, or change live economics.

- **Revenue-Backed Only:** Rewards derive exclusively from real on-chain revenue and native staking yield.

- **Deterministic Economics:** All parameters fixed at activation; no post-launch changes.

- **Non-Custodial:** Capital is controlled exclusively by on-chain logic.

- **No Financial Engineering:** Native Sui staking only; no lending or rehypothecation.

---

## Actors (v1)

- **Backers:** Contribute SUI, receive a transferable economic position, claim rewards.
- **Issuer (FAITH):** Receives released capital and routes revenue on-chain.
- **Listing Council (Multisig):** Approves listing creation, activation/finalization, and pause/resume actions.
- **Tide Treasury:** Receives protocol fees (raise fee + staking reward split).

---

## On-Chain Objects (v1)

### 0) `ListingRegistry` (shared)

Registry of all listings.

- Maintains a monotonically increasing `listing_count`
- Stores references (IDs) to all Listing objects
- Gated creation via council capability

**v1 constraint:** Only **FAITH Listing #1** is configured and surfaced in the product.

**Invariant:** Registry holds no capital and cannot redirect funds.

---

### 1) `Tide` (shared)

Global protocol configuration.

- Treasury vault ID (reference to TreasuryVault)
- Admin wallet address
- Global pause flag (optional, per-listing pause is primary)
- Version marker

**Invariant:** Tide holds no capital and cannot redirect funds.

---

### 1.5) `TreasuryVault` (shared)

Protocol fee collection vault.

- Holds accumulated protocol fees (SUI)
- Receives: raise fees (1%), staking splits (20%), marketplace fees (5%)
- Admin-only withdrawals
- Tracks lifetime deposits and withdrawals

**Invariant:** Only authorized sources can deposit; only admin can withdraw.

---

### 2) `Listing` (shared)

Represents an active capital raise.

- Unique listing ID (from registry)
- Immutable config hash (set at creation, verified at activation)
- Issuer address
- References to CapitalVault and RewardVault
- Lifecycle state:
    - `draft → active → finalized → completed`
    - `draft/active → cancelled` (refund path)
- Deterministic release schedule parameters
- Pause flag (per-listing)

**Invariant:** Listing economics MUST NOT change after activation.

---

### 3) `CapitalVault` (owned by Listing logic)

Holds contributed principal (SUI).

- Accepts SUI deposits while listing is active
- Tracks total principal and tranche state
- Releases capital to issuer on a deterministic schedule

**Invariants:**

- Backers cannot withdraw principal
- Principal MUST ONLY flow to the issuer via tranche release
- Principal MUST NEVER enter RewardVault

---

### 4) Native Sui Staking Adapter (Productive Capital)

Provides limited capital productivity.

- Stakes **only locked capital**
- Implements time-segmented staking

**Priority Rule (Normative):**

If a tranche becomes releasable while capital remains staked:

1. Unstake the tranche amount
2. Release principal to issuer
3. No further rewards accrue to that tranche after its release timestamp

---

### 5) `RewardVault` (owned by Listing logic)

Holds and distributes rewards to backers.

**Reward sources (v1):**

1. Protocol revenue routed from FAITH
2. Native Sui staking rewards (from locked capital)

- SUI-only
- Maintains a cumulative reward-per-share index

**Invariants:**

- Reward index MUST be monotonic
- Index updates ONLY when new rewards enter the vault
- Principal MUST NEVER enter RewardVault

---

### 6) `SupporterPass` (transferable NFT object)

Represents a backer's full economic position.

**Core requirements (v1):**

- Owned object (transferable NFT)
- Stores **economic state**:
  - `listing_id` — reference to parent listing
  - `shares` — normalized contribution shares (immutable, non-zero)
  - `claim_index` — reward claim cursor (index snapshot)
- Stores **provenance metadata** (non-economic, immutable after mint):
  - `pass_number` — sequential backer number (e.g., "Backer #42")
  - `original_backer` — address of initial depositor (preserved on transfer)
  - `created_epoch` — Sui epoch when minted
- Stores **activity metadata** (updated on claim):
  - `total_claimed` — lifetime rewards claimed through this pass

**Normative rules:**

- Ownership defines full reward entitlement
- Claim entitlement MUST move atomically with ownership
- Shares are immutable after mint and MUST be > 0
- No principal or reward balances are stored on the pass
- Pass MUST NOT be destroyable in v1

**Display & presentation (v1):**

- Display metadata MUST be defined in `display.move` (presentation-only)
- Display SHOULD include `name`, `description`, `image_url`, and `link`
- `image_url` / `link` MAY point to an off-chain renderer using `{id}` placeholder
- Display configuration MUST remain non-economic

**Invariant:** `SupporterPass` contains no logic or data that can affect economics beyond share-based reward entitlement.

**Batch claiming (v1):**

- `claim_many()` allows claiming from multiple passes in one transaction
- Emits individual `Claimed` events + summary `BatchClaimed` event
- More gas-efficient than individual claims

**Kiosk support (v1):**

- `kiosk_ext::claim_from_kiosk()` allows claiming while pass is in a Kiosk
- `kiosk_ext::claim_many_from_kiosk()` for batch Kiosk claims
- Pass remains in Kiosk, rewards sent to caller

**Secondary market benefits:**

- `pass_number` provides collectibility ("I was an early backer!")
- `original_backer` provides provenance (preserved even after transfer)
- `total_claimed` shows earning history (dynamic, living NFT)

**Important:** This object is **not** an account abstraction and MUST remain minimal and auditable.

---

## Deterministic Capital Release (v1)

### Purpose

The Deterministic Capital Release mechanism defines how and when contributed capital is released to the issuer, in a manner that is:

- **Non-discretionary** — No human judgment affects timing
- **Time-based** — Purely a function of on-chain time
- **Fully auditable** — Schedule is immutable and public
- **Independent** — Not affected by revenue, performance, or behavior

This mechanism ensures capital formation without trust in people, only in code.

### Release Model (v1 Canonical Schedule)

Each Listing MUST define a fixed release schedule that is fully determined and immutable at the moment the listing is finalized.

**Canonical Schedule (12 months):**

| Phase | Timing | Amount |
|-------|--------|--------|
| Initial Release | At `finalize()` | 20% of total raised capital |
| Monthly Tranches | Months 1–12 | 80% released evenly (6.67% each) |

Each monthly tranche represents 1/12 of the remaining 80% and becomes releasable at fixed 30-day intervals from finalization.

**Note:** Raise fee (1%) is deducted before calculating release amounts.

### Schedule Computation (Normative)

Release schedule MUST be computed and stored at **listing finalization**:

```
finalization_time = Clock.timestamp_ms() at finalize()

tranche[0].amount = (total_raised - raise_fee) * 20%
tranche[0].release_time = finalization_time  // Immediate

for i in 1..=12:
    tranche[i].amount = (total_raised - raise_fee) * 80% / 12
    tranche[i].release_time = finalization_time + (i * 30 days)
```

**Time Definition (Normative):**

- All release timing MUST be enforced using `sui::clock::Clock`
- Release timestamps MUST be computed and stored at listing finalization
- No external oracle or off-chain signal may influence release timing

**Normative constraint:** Release eligibility MUST be a pure function of on-chain time and listing state.

### Release Semantics (Normative)

**Pull-based releases:**

- Any account MAY call `release_tranche()` once conditions are met
- Tranches MAY be released late but MUST NOT be skipped or lost
- Missed tranches MUST accumulate and remain releasable
- The issuer MUST NOT be able to accelerate, delay, or reorder releases

**Invariant:** Each unit of principal may be released once and only once, and only according to the predefined schedule.

### Capital Flow Invariants

| ID | Invariant |
|----|-----------|
| D1 | Released capital MUST transfer directly to the issuer address |
| D2 | Released capital MUST NOT pass through RewardVault or any intermediary |
| D3 | Released capital MUST NOT accrue staking rewards after its release timestamp |
| D4 | Release schedule MUST be immutable after finalization |
| D5 | Tranches MUST be releasable in any order (no forced sequence) |

### Relationship to Revenue & Performance (Critical)

Capital release is strictly time-based and MUST NOT depend on:

- Protocol revenue volume
- Revenue consistency
- Price performance
- User activity
- Issuer behavior (except safety violations)

**Normative rule:** Lack of revenue, reduced revenue, or zero revenue MUST NOT automatically halt or delay capital releases.

**Backers are guaranteed rules, not returns.**

### Pause Interaction (Safety Only)

Capital releases MAY be paused only via the Listing pause mechanism under objective safety conditions, including but not limited to:

- Critical bug in Tide Core contracts
- Violation or bypass of the revenue routing invariant
- Issuer upgrade breaking adapter guarantees
- Chain-level or validator-level emergency

When a listing is paused:

- ❌ Future capital releases STOP
- ✅ Previously released capital is unaffected
- ✅ Locked capital MAY remain staked
- ✅ Reward claims remain ENABLED by default

**Invariant:** Pause MUST NOT allow capital redirection, seizure, or schedule mutation.

---

## Cancellation & Refund Mechanism (v1)

### Purpose

Provides an emergency exit path for backers if a listing must be terminated before completion.

### Cancelled State

A listing MAY be cancelled only from `Draft` or `Active` states:

```
draft → cancelled
active → cancelled (before finalization only)
```

**Preconditions for cancellation:**

- No capital is currently staked (must unstake first)
- Called by council via `cancel_listing()`

### Refund Flow

When a listing enters `Cancelled` state:

1. **Listing frozen** — No further deposits, claims, or releases
2. **Refunds enabled** — Backers can call `claim_refund(pass)`
3. **Proportional calculation** — Refund = (pass.shares / total_shares) × vault_balance
4. **Pass burned** — SupporterPass is destroyed after refund
5. **SUI transferred** — Refund amount sent to caller

**Batch refunds:**

- `claim_refunds(passes)` allows multiple passes in one transaction

### Refund Invariants

| ID | Invariant |
|----|-----------|
| RF1 | Refunds ONLY available in Cancelled state |
| RF2 | Refund amount is proportional to shares |
| RF3 | Each pass can only claim refund once |
| RF4 | Pass is burned after successful refund |
| RF5 | Cannot cancel if capital is staked |

### Events

- `ListingCancelled` — Emitted when listing is cancelled
- `RefundClaimed` — Emitted for each refund

---

## Governance & Control (v1)

v1 includes **minimal council gating** to support a registry-first architecture without governance theater.

### Council Model (Normative)

- Council is a 3-5 key multisig (capability-based on-chain admin is recommended).
- Council capability is `CouncilCap` (transferable, can be held by multisig).

**Council MAY:**

- Create/register new listings
- Activate or finalize listings
- Pause or resume listings
- Approve immutable listing config hashes

**Council MUST NOT:**

- Seize capital
- Redirect rewards
- Change live listing economics after activation

### Config Hash Discipline (Normative)

- Each listing stores an immutable config hash computed at creation.
- Council approvals MUST reference a specific hash (no silent drift).
- Config hash includes: issuer address, tranche amounts, tranche times, revenue BPS.

---

## Revenue Router Standard (Mandatory)

FAITH MUST integrate a revenue router that is enforceable by contract design.

### Protocol Adapter Pattern (Normative)

Tide Core MAY include **protocol-specific adapters** implemented as **separate Move packages** under `contracts/adapters/`.

For v1 (FEF launch), the repository SHOULD include a **FAITH adapter package** (e.g., `contracts/adapters/faith_router/`) that provides a canonical, enforceable routing path from FAITH into **Listing #1 RewardVault**, while keeping **all FAITH gameplay logic out of Tide Core**.

**Normative rules:**

- Adapters MUST be thin glue layers (routing + event normalization only)
- Adapters MUST NOT contain or depend on FAITH gameplay/state logic
- Adapters MUST route SUI revenue only (v1)
- Adapters MUST emit standardized `RouteIn` events
- Adapters MUST NOT introduce new economics, fees, or discretionary controls

---

**Requirements:**

- Routes a fixed % of real protocol revenue (SUI)
- Routes ONLY to the Listing's RewardVault
- Emits standardized `RouteIn` events
- Percentage is immutable post-activation
- Routing MUST NOT be bypassable via upgrades or alternative fee paths

---

## Rewards Model (v1)

### Reward Accounting

- RewardVault maintains a cumulative reward-per-share index
- Each SupporterPass stores the last claimed index

**Claim formula:**

```
claimable = shares × (global_index − pass_index)
```

After claim, pass_index is updated.

**Properties:**

- Transfer-safe
- No double-claim
- Deterministic gas cost

### Language Constraint (Normative)

Rewards MUST NOT be described as:

- dividends
- guaranteed yield
- profit sharing
- ROI guarantees

Rewards are **variable, claimable, and usage-derived**.

---

## Pause Semantics (v1)

Purpose: mitigate critical bugs without changing economics.

**Per-listing pause** (primary):

When a listing is paused:

- Capital releases STOP
- Contributions MAY be halted
- Staking MAY continue
- Revenue routing MAY continue
- Reward claims remain ENABLED by default

**Global pause** (optional, for critical emergencies):

- Affects all listings simultaneously
- Same semantics as per-listing pause

**Invariant:** Pause MUST NOT allow capital or reward redirection.

---

## Tide Fees & Treasury Policy (v1)

Tide Core v1 includes minimal, fully disclosed infra fees designed to fund protocol maintenance without rent extraction.

### Fee Sources (Normative)

**Raise Fee (Capital Formation):**

- **1%** of total raised capital (SUI)
- Deducted before the first capital release tranche
- Routed directly to the Tide Treasury
- Emitted as `RaiseFeeCollected` event

**Staking Reward Split (Ongoing Maintenance):**

Native Sui staking rewards generated by locked capital are split deterministically:

- **80%** → Listing RewardVault (backers)
- **20%** → Tide Treasury

### Explicit Fee Exclusions (v1)

- **No revenue skim** — No protocol fee charged on issuer revenue routing
- **No dynamic fees** — All fee parameters are fixed at activation
- **No discretionary fees** — No council/admin ability to change fees

### Fee Invariants

| ID | Invariant |
|----|-----------|
| F1 | All fee parameters are immutable per listing |
| F2 | Fees MUST be disclosed in listing config prior to activation |
| F3 | Treasury fees MUST NOT affect principal custody or release logic |
| F4 | Fee percentages MUST be included in config hash |

---

## Explicit Non-Goals (v1 Core)

- No public/open listing creation (council-gated only)
- No issuer revenue skim
- No non-SUI assets
- No external lending pools (v3 future)

**Now Included (v1+ Extensions):**

- ✅ Marketplace (separate package: `tide_marketplace`)
- ✅ Self-paying loans (separate package: `tide_loans`)
- ✅ Refunds via Cancelled state (core)

---

## FAITH as Listing #1 (Reference Implementation)

- Protocol revenue = **10% of FAITH fees**
- Routed enforceably into RewardVault
- Capital released to FAITH on deterministic schedule

FAITH demonstrates:

- Real revenue routing
- Staking productivity while locked
- Transfer-safe reward claims
- Non-discretionary capital formation

---

## Repository Structure (Normative for v1)

```
tide-protocol/
├── CLAUDE.md
├── README.md
├── DEPLOYMENT.md                     # Deployment & operations guide
├── MARKETPLACE.md                    # Marketplace documentation
├── LOANS.md                          # Self-paying loans documentation
│
├── contracts/
│   ├── core/                         # Tide Core package (tide_core)
│   │   ├── Move.toml
│   │   ├── sources/
│   │   │   ├── tide.move             # Global config + pause
│   │   │   ├── registry.move         # ListingRegistry
│   │   │   ├── council.move          # Council capability + gating
│   │   │   ├── listing.move          # Listing lifecycle + claims + refunds
│   │   │   ├── capital_vault.move    # Principal custody + refund support
│   │   │   ├── reward_vault.move     # Reward distribution
│   │   │   ├── staking_adapter.move  # Native Sui staking
│   │   │   ├── supporter_pass.move   # Backer NFT (economics + provenance)
│   │   │   ├── treasury_vault.move   # Protocol fee vault (shared)
│   │   │   ├── kiosk_ext.move        # Kiosk claiming support
│   │   │   ├── display.move          # Display metadata
│   │   │   ├── admin.move            # Capability-gated admin
│   │   │   ├── math.move             # Fixed-point arithmetic
│   │   │   ├── constants.move        # Shared constants
│   │   │   ├── errors.move           # Error codes
│   │   │   └── events.move           # Event definitions (40+ events)
│   │   └── tests/
│   │       ├── *_tests.move          # Unit tests per module
│   │       └── e2e_tests.move        # End-to-end tests
│   │
│   ├── adapters/
│   │   └── faith_router/             # FAITH revenue adapter
│   │       ├── Move.toml
│   │       ├── sources/
│   │       │   └── faith_router.move
│   │       └── tests/
│   │
│   ├── marketplace/                  # Native SupporterPass marketplace
│   │   ├── Move.toml
│   │   ├── sources/
│   │   │   └── marketplace.move
│   │   └── tests/
│   │
│   └── loans/                        # Self-paying loans
│       ├── Move.toml
│       ├── sources/
│       │   └── loan_vault.move
│       └── tests/
│
├── spec/
│   ├── tide-core-v1.md               # This specification
│   ├── marketplace-v1.md             # Marketplace specification
│   ├── self-paying-loans-v2.md       # Loans specification
│   ├── frontend-spec.md              # Frontend/API specification
│   └── invariants.md                 # Security invariants
│
├── deployments/
│   ├── testnet/
│   │   └── tide_core.json            # Deployment artifacts
│   └── mainnet/
│
└── scripts/
```

**Normative rules:**

- Tide Core contracts MUST live in their own Move package
- FAITH MUST consume Tide Core as an external dependency
- No FAITH gameplay logic may live in this repository
- Naming inside Move code MUST use Tide / Listing / Vault terminology (never "FEF")

---

## Off-Chain Data Requirements (Normative)

All off-chain features (dashboards, explorers, APIs) MUST be derivable from on-chain events.

**Normative Rule:** Any dashboard, explorer, or reporting surface that represents Tide data MUST be reproducible by an independent indexer using only on-chain events.

This ensures:
- You don't own the truth
- Anyone can verify it
- No selective reporting or narrative manipulation

### Capital Transparency Dashboard

The following data MUST be derivable from events:

| Metric | Event Source |
|--------|--------------|
| Total Raised | Sum of `Deposited.amount` |
| Total Backers | Count of unique `Deposited.backer` |
| Total Released | Sum of `TrancheReleased.amount` |
| Total Revenue | Sum of `RouteIn.amount` |
| Total Distributed | Sum of `Claimed.amount` |
| Raise Fee Collected | `RaiseFeeCollected.fee_amount` |
| Staking Rewards (Backer) | Sum of `StakingRewardSplit.backer_amount` |
| Staking Rewards (Treasury) | Sum of `StakingRewardSplit.treasury_amount` |
| Release Progress | `TrancheReleased.remaining_tranches / total_tranches` |
| Current Staked | Latest `Staked.total_staked` or `Unstaked.total_staked` |
| Batch Claims | `BatchClaimed` events |
| Refunds Issued | Sum of `RefundClaimed.amount` |
| Cancelled Listings | `ListingCancelled` events |

### Marketplace Dashboard (v1+)

| Metric | Event Source |
|--------|--------------|
| Total Volume | Sum of `SaleCompleted.price` |
| Total Fees | Sum of `SaleCompleted.fee` |
| Active Listings | `ListingCreated` - `SaleCompleted` - `ListingCancelled` |
| Sales Count | Count of `SaleCompleted` |

### Loans Dashboard (v1+)

| Metric | Event Source |
|--------|--------------|
| Total Borrowed | Sum of `LoanCreated.principal` |
| Total Repaid | Sum of `LoanRepayment.amount` + `LoanFullyRepaid` |
| Active Loans | `LoanCreated` - `LoanFullyRepaid` - `LoanLiquidated` |
| Liquidations | Count of `LoanLiquidated` |
| Keeper Harvests | Sum of `HarvestExecuted.rewards_claimed` |

### Backer Identity & Reputation

Backer identity and reputation MUST be built from immutable on-chain actions:

| Metric | Event Source |
|--------|--------------|
| Backer Deposits | All `Deposited` events for backer address |
| Pass Ownership | Track `Deposited.pass_id` → current owner via Sui object queries |
| Claim History | All `Claimed` events for pass_id |
| First Deposit Epoch | Min `Deposited.epoch` for backer |
| Loyalty Score | Derived from deposit timing, hold duration, claim patterns |

### Timeline Reconstruction

Full listing timeline MUST be reconstructible:

**Happy path:**
```
ListingCreated → ListingActivated → [Deposited]* → ListingFinalized 
  → ScheduleFinalized → [TrancheReleased]* → ListingCompleted
```

**Cancellation path:**
```
ListingCreated → ListingActivated? → [Deposited]* → ListingCancelled
  → [RefundClaimed]*
```

All state transitions emit `StateChanged` for secondary verification.

---

## Upgrade Path (Future)

### Implemented in v1+

- ✅ SupporterPass marketplace (`tide_marketplace`)
- ✅ Self-paying loans (`tide_loans`)
- ✅ Refund mechanism (Cancelled state)
- ✅ Kiosk claiming support
- ✅ Batch claiming

### Future Considerations (v2+)

- Pool-based lending with external lenders
- Dynamic interest rates
- Multi-asset support
- Cross-listing aggregation
- Governance token integration

All v1 invariants MUST remain preserved in any upgrade.

---

## v1+ Extensions

The following are implemented as separate Move packages that depend on `tide_core`:

### Marketplace (`tide_marketplace`)

Native SupporterPass trading with protocol fees.

**Key features:**
- List pass for sale at any price
- Buy pass with single transaction
- 5% seller fee → TreasuryVault
- Yield-aware (pending rewards visible)

**Objects:**
- `MarketplaceConfig` (shared) — Global config, stats, pause
- `SaleListing` (shared) — Individual listing, holds pass in escrow

**See:** `spec/marketplace-v1.md`

---

### Self-Paying Loans (`tide_loans`)

Borrow SUI against SupporterPass collateral; rewards auto-repay.

**Key features:**
- 50% max LTV (conservative)
- 5% APR interest
- 1% origination fee
- Keeper harvest → auto-repayment
- Liquidation at 75% threshold

**Objects:**
- `LoanVault` (shared) — Treasury-funded lending pool
- `Loan` (dynamic field) — Individual loan data
- `LoanReceipt` (owned) — Proof of borrowing

**See:** `spec/self-paying-loans-v2.md`

---

## Test Coverage

| Package | Tests |
|---------|-------|
| tide_core | 99 |
| faith_router | 17 |
| tide_marketplace | 23 |
| tide_loans | 21 |
| **Total** | **160** |

---

## Canonical Summary

Tide Core v1 is a **registry-first, council-gated, revenue-backed capital primitive**.

FEF is simply its first (and only surfaced) product surface.

v1+ extensions (Marketplace, Loans) are additive and do not modify core invariants.

No duplication. No migration. No rewrite.
