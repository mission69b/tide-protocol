# Tide Core v1 — Invariants

**Audit-Ready Invariant Reference**

This document lists all security invariants that MUST hold for Tide Core v1. Violation of any invariant constitutes a critical vulnerability.

---

## Capital Invariants

| ID | Invariant | Location |
|----|-----------|----------|
| C1 | Principal MUST ONLY flow from CapitalVault to Issuer address | `capital_vault.move` |
| C2 | Principal MUST NEVER enter RewardVault | `capital_vault.move`, `reward_vault.move` |
| C3 | Backers CANNOT withdraw principal | `capital_vault.move` |
| C4 | Capital release MUST follow deterministic schedule | `capital_vault.move`, `listing.move` |
| C5 | Released tranches CANNOT be re-released | `capital_vault.move` |
| C6 | Staking priority: unstake before release if staked | `staking_adapter.move` |

---

## Reward Invariants

| ID | Invariant | Location |
|----|-----------|----------|
| R1 | Reward index MUST be monotonically non-decreasing | `reward_vault.move` |
| R2 | Index updates ONLY when new rewards enter vault | `reward_vault.move` |
| R3 | Claim entitlement MUST move atomically with NFT ownership | `supporter_pass.move` |
| R4 | No double-claim: pass_index updates after each claim | `reward_vault.move`, `supporter_pass.move` |
| R5 | Late joiners CANNOT claim pre-deposit rewards | `supporter_pass.move` |

---

## Economics Invariants

| ID | Invariant | Location |
|----|-----------|----------|
| E1 | All parameters MUST be immutable after Listing activation | `listing.move` |
| E2 | Shares are fixed at deposit time and CANNOT change | `supporter_pass.move` |
| E3 | Rounding MUST be deterministic and favor the protocol | `math.move` |
| E4 | Revenue routing percentage MUST be immutable | `faith_router.move` |

---

## Access Control Invariants

| ID | Invariant | Location |
|----|-----------|----------|
| A1 | Only authorized router can deposit to RewardVault | `reward_vault.move` |
| A2 | Only Listing logic can trigger tranche release | `capital_vault.move` |
| A3 | Pause MUST NOT enable fund redirection | `tide.move`, `listing.move` |
| A4 | Tide holds no capital and CANNOT redirect funds | `tide.move` |
| A5 | ListingRegistry holds no capital and CANNOT redirect funds | `registry.move` |

---

## Council Invariants

| ID | Invariant | Location |
|----|-----------|----------|
| G1 | Council MUST NOT seize capital | `council.move`, `listing.move` |
| G2 | Council MUST NOT redirect rewards | `council.move`, `reward_vault.move` |
| G3 | Council MUST NOT change economics after activation | `listing.move` |
| G4 | Listing creation MUST go through registry | `registry.move`, `listing.move` |
| G5 | Per-listing pause MUST NOT allow fund redirection | `listing.move` |

---

## Fee Invariants

| ID | Invariant | Location |
|----|-----------|----------|
| F1 | All fee parameters are immutable per listing | `listing.move`, `capital_vault.move` |
| F2 | Fees MUST be disclosed in listing config prior to activation | `listing.move` |
| F3 | Treasury fees MUST NOT affect principal custody or release logic | `capital_vault.move` |
| F4 | Fee percentages MUST be included in config hash | `listing.move` |
| F5 | Raise fee (1%) collected exactly once before first release | `capital_vault.move` |
| F6 | Staking reward split (80/20) is deterministic | `staking_adapter.move` |
| F7 | No protocol skim on issuer revenue routing | `faith_router.move` |

---

## Lifecycle Invariants

| ID | Invariant | Location |
|----|-----------|----------|
| L1 | State transitions MUST be unidirectional: Draft → Active → Finalized → Completed | `listing.move` |
| L2 | Deposits ONLY accepted in Active state | `listing.move` |
| L3 | Config CANNOT change after leaving Draft state | `listing.move` |

---

## Staking Invariants

| ID | Invariant | Location |
|----|-----------|----------|
| S1 | Only locked capital may be staked | `staking_adapter.move` |
| S2 | Staking rewards flow to RewardVault, not CapitalVault | `staking_adapter.move` |
| S3 | No lending or rehypothecation | `staking_adapter.move` |
| S4 | Released tranches MUST NOT accrue staking rewards after release timestamp | `staking_adapter.move` |

---

## Verification Approach

For each invariant:

1. **Code review** — Verify logic enforces invariant
2. **Unit tests** — Test happy path and violation attempts
3. **Fuzz testing** — Random inputs cannot violate
4. **Formal verification** — (if applicable) Prove invariant holds

---

## Invariant Violation Response

If an invariant is violated:

1. **Immediate pause** — Admin triggers global pause
2. **Assessment** — Determine scope of violation
3. **Upgrade** — Deploy fix (if upgradeable)
4. **Disclosure** — Responsible disclosure to affected parties
