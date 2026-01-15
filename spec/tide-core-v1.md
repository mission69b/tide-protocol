# Tide Core v1 — FEF Launch Specification (LOCKED)

**Status:** Canonical — Engineering & Audit Ready

**Chain:** Sui (v1)

**Scope:** Core primitives only, deployed once and surfaced as **FEF** inside FAITH UI

**Explicitly NOT included:** marketplace

**Included in v1:** Registry-first architecture with minimal council gating, transparent fees & treasury policy. Only **FAITH** is configured and surfaced as Listing #1 (FEF).

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

- Treasury address (configured, unused in v1)
- Global pause flag (optional, per-listing pause is primary)
- Version marker

**Invariant:** Tide holds no capital and cannot redirect funds.

---

### 2) `Listing` (shared)

Represents an active capital raise.

- Unique listing ID (from registry)
- Immutable config hash (set at creation, verified at activation)
- Issuer address
- References to CapitalVault and RewardVault
- Lifecycle state:
  - `draft → active → finalized → completed`
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

### 4) Native Sui Staking Adapter

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
- Stores **economic state only**:
  - `listing_id` — reference to parent listing
  - `shares` — normalized contribution shares (immutable, non-zero)
  - `claim_index` — reward claim cursor (index snapshot)
  - Optional non-economic metadata (e.g., `created_epoch`)

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

## Explicit Non-Goals (v1)

- No public/open listing creation (council-gated only)
- No marketplace
- No issuer revenue skim
- No early withdrawals or refunds
- No non-SUI assets
- No lending or rehypothecation

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
│
├── contracts/
│   ├── core/                         # Tide Core package
│   │   ├── Move.toml
│   │   ├── sources/
│   │   │   ├── tide.move             # Global config + pause
│   │   │   ├── registry.move         # ListingRegistry
│   │   │   ├── council.move          # Council capability + gating
│   │   │   ├── listing.move          # Listing lifecycle
│   │   │   ├── capital_vault.move    # Principal custody
│   │   │   ├── reward_vault.move     # Reward distribution
│   │   │   ├── staking_adapter.move  # Native Sui staking
│   │   │   ├── supporter_pass.move   # Backer NFT (economics)
│   │   │   ├── display.move          # Display metadata
│   │   │   ├── math.move             # Fixed-point arithmetic
│   │   │   ├── constants.move        # Shared constants
│   │   │   ├── errors.move           # Error codes
│   │   │   └── events.move           # Event definitions
│   │   └── tests/
│   │
│   └── adapters/
│       └── faith_router/             # FAITH revenue adapter
│
├── spec/
│   ├── tide-core-v1.md               # This specification
│   └── invariants.md
│
└── scripts/
```

**Normative rules:**

- Tide Core contracts MUST live in their own Move package
- FAITH MUST consume Tide Core as an external dependency
- No FAITH gameplay logic may live in this repository
- Naming inside Move code MUST use Tide / Listing / Vault terminology (never "FEF")

---

## Upgrade Path (Post-v1, Explicitly Out of Scope)

Only after v1 proof:

- Surfacing additional listings in UI
- Expanded council policies
- Raise fees & treasury policy
- Minimal marketplace

All v1 invariants MUST remain preserved.

---

## Canonical Summary

Tide Core v1 is a **registry-first, council-gated, revenue-backed capital primitive**.

FEF is simply its first (and only surfaced) product surface.

No duplication. No migration. No rewrite.
