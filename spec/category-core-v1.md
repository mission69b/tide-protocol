# Tide Core v1 — FEF Launch Specification

**Status:** Canonical — Engineering & Audit Ready

**Chain:** Sui (v1)

**Scope:** Core primitives only, deployed once and surfaced as **FEF** inside FAITH UI

**Explicitly NOT included:** registry, council, multi‑listing, marketplace, protocol fees

---

## Positioning

**Tide Core v1** is the minimal on‑chain infrastructure required to raise capital **after product–market fit**, without selling tokens, issuing equity, or introducing discretionary fund control.

For v1, Tide Core is deployed with **a single hardcoded listing**:

> Listing #1 — FAITH (surfaced as "Faith Expansion Fund / FEF")

FEF is a **product surface**, not a separate protocol.

---

## Design Principles (Normative)

All v1 implementations **MUST** satisfy:

- **Single Listing Only:** Exactly one listing (FAITH). No registry.
- **No Governance:** No council, voting, or approvals in v1.
- **Revenue‑Backed Only:** Rewards derive exclusively from real on‑chain revenue and native staking yield.
- **Deterministic Economics:** All parameters fixed at activation; no post‑launch changes.
- **Non‑Custodial:** Capital is controlled exclusively by on‑chain logic.
- **No Financial Engineering:** Native Sui staking only; no lending or rehypothecation.

---

## Actors (v1)

- **Backers:** Contribute SUI, receive a transferable economic position, claim rewards.
- **Issuer (FAITH):** Receives released capital and routes revenue on‑chain.
- **Tide Treasury:** Exists as a configured address but receives **no fees in v1**.

---

## On‑Chain Objects (v1)

### 1) `Tide` (shared)

Global protocol configuration.

- Treasury address (configured, unused in v1)
- Global pause flag
- Version marker

**Invariant:** Tide holds no capital and cannot redirect funds.

---

### 2) `Listing` (shared)

Represents the single active capital raise (FAITH).

- Immutable config hash
- Issuer address (FAITH)
- References to CapitalVault and RewardVault
- Lifecycle state:
    - `draft → active → finalized → completed`
- Deterministic release schedule parameters

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
- Implements time‑segmented staking

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
- SUI‑only
- Maintains a cumulative reward‑per‑share index

**Invariants:**

- Reward index MUST be monotonic
- Index updates ONLY when new rewards enter the vault
- Principal MUST NEVER enter RewardVault

---

### 6) `SupporterPass` (transferable NFT object)

Represents a backer's full economic position.

- Owned object (transferable NFT)
- Optional Display metadata
- Stores:
    - normalized contribution shares (immutable)
    - claim cursor

**Normative rules:**

- Ownership defines full reward entitlement
- Claim entitlement MUST move atomically with ownership
- Shares are fixed‑point units calculated at deposit time
- Rounding behavior MUST be deterministic

**Important:**

This object is **not** an account abstraction.

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
- Percentage is immutable post‑activation
- Routing MUST NOT be bypassable via upgrades or alternative fee paths

---

## Rewards Model (v1)

### Reward Accounting

- RewardVault maintains a cumulative reward‑per‑share index
- Each SupporterPass stores the last claimed index

**Claim formula:**

```
claimable = shares × (global_index − pass_index)
```

After claim, pass_index is updated.

**Properties:**

- Transfer‑safe
- No double‑claim
- Deterministic gas cost

### Language Constraint (Normative)

Rewards MUST NOT be described as:

- dividends
- guaranteed yield
- profit sharing
- ROI guarantees

Rewards are **variable, claimable, and usage‑derived**.

---

## Pause Semantics (v1)

Purpose: mitigate critical bugs without changing economics.

When paused:

- Capital releases STOP
- Contributions MAY be halted
- Staking MAY continue
- Revenue routing MAY continue
- Reward claims remain ENABLED by default

**Invariant:** Pause MUST NOT allow capital or reward redirection.

---

## Explicit Non‑Goals (v1)

- No registry or multi‑listing
- No council or governance
- No raise fees
- No treasury skimming
- No marketplace
- No early withdrawals or refunds
- No non‑SUI assets
- No lending or rehypothecation

---

## FAITH as Listing #1 (Reference Implementation)

- Protocol revenue = **10% of FAITH fees**
- Routed enforceably into RewardVault
- Capital released to FAITH on deterministic schedule

FAITH demonstrates:

- real revenue routing
- staking productivity while locked
- transfer‑safe reward claims
- non‑discretionary capital formation

---

## Upgrade Path (Post‑v1, Explicitly Out of Scope)

Only after v1 proof:

- Listing registry
- Council gating
- Multi‑issuer onboarding
- Raise fees & treasury policy
- Minimal marketplace

All v1 invariants MUST remain preserved.

---

## Canonical Summary

Tide Core v1 is a **single‑listing, deterministic, revenue‑backed capital primitive**.

FEF is simply its first product surface.

No duplication. No migration. No rewrite.
