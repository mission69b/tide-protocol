# Tide Protocol Security Audit Report

**Auditor:** Claude (Automated Security Analysis)
**Date:** January 29, 2026
**Protocol Version:** v1
**Packages Reviewed:**
- `tide_core` (16 modules, ~5,700 LOC)
- `tide_loans` (1 module, ~1,000 LOC)
- `tide_marketplace` (1 module, ~600 LOC)
- `faith_router` (1 module, ~200 LOC)

---

## Executive Summary

Tide Protocol is a **capital raise platform** on Sui that enables creators to raise funds with deterministic release schedules while allowing backers to earn yield through staking rewards and protocol revenue sharing.

### Overall Assessment: **MEDIUM-HIGH SECURITY**

The protocol demonstrates solid architectural design with proper separation of concerns, capability-based access control, and well-defined invariants. However, several issues require attention before mainnet deployment.

| Severity | Count |
|----------|-------|
| **Critical** | 0 |
| **High** | 2 |
| **Medium** | 5 |
| **Low** | 7 |
| **Informational** | 8 |

---

## Architecture Security Analysis

### Positive Security Properties

1. **Principal Isolation** - Capital flows are strictly segregated between `CapitalVault` (principal) and `RewardVault` (rewards). No code path allows principal to enter the reward pool.

2. **Capability-Based Access Control** - Critical operations require:
   - `CouncilCap` for listing lifecycle management
   - `AdminCap` for protocol-level actions
   - `RouteCapability` for reward deposits
   - `ListingCap` for issuer operations

3. **Immutable Economics** - Listing configuration (`config_hash`) is computed at creation and cannot be modified after activation.

4. **Monotonic Reward Index** - `global_index` in `RewardVault` only increases, preventing reward manipulation.

5. **Atomic Pass Transfers** - `SupporterPass` transfers are atomic with claim cursor updates, preventing double-claiming.

6. **Pull-Based Tranche Releases** - Anyone can trigger tranche releases once the time has passed, reducing trust assumptions.

---

## Findings

### HIGH SEVERITY

#### H-01: Staking Reward Calculation Can Be Manipulated via Timing

**Location:** `listing.move:711-783` (`harvest_staking_rewards`)

**Description:** The `harvest_staking_rewards` function calculates rewards as `total_withdrawn - original_principal`. However, `original_principal` is tracked via `staking_adapter.staked_principal()` which is updated during unstaking. If multiple `unstake_at()` calls happen between harvest operations, the reward calculation may be incorrect.

**Impact:** Potential loss or miscalculation of staking rewards.

**Code:**
```move
// Line 726
let original_principal = staking_adapter.staked_principal();

// Line 729 - This modifies staked_principal during the call
let total_withdrawn = staking_adapter.unstake_all(system_state, ctx);
```

**Recommendation:**
1. Capture `original_principal` before any unstaking operations
2. Add a dedicated tracking variable for original staked amounts that doesn't change during unstaking
3. Consider using cumulative tracking instead of snapshot-based calculation

---

#### H-02: Loan Collateral Value Based on Historical Data Can Be Stale

**Location:** `loan_vault.move:932-947` (`calculate_collateral_value`)

**Description:** Collateral value is calculated using `capital_vault.total_principal()` which represents the original deposit amounts, not current market value. If a listing's perceived value changes (e.g., due to reputation damage or market conditions), the collateral valuation doesn't reflect this.

**Impact:** Loans may become under-collateralized without triggering liquidation, leading to bad debt.

**Code:**
```move
fun calculate_collateral_value(
    pass: &SupporterPass,
    capital_vault: &tide_core::capital_vault::CapitalVault,
): u64 {
    let total_shares = capital_vault.total_shares();
    let total_principal = capital_vault.total_principal(); // Uses original deposits
    // ...
}
```

**Recommendation:**
1. Consider implementing an oracle-based pricing mechanism
2. Add conservative haircut factors to collateral valuation
3. Implement time-weighted average pricing from marketplace sales

---

### MEDIUM SEVERITY

#### M-01: Missing Reentrancy Guard on Claim Operations

**Location:** `listing.move:359-401` (`claim`)

**Description:** While Sui's Move VM provides some protection against reentrancy, the claim function modifies state (`update_claim_index`, `add_claimed`) before external calls (`withdraw`). Although the current implementation appears safe, adding explicit reentrancy guards would provide defense-in-depth.

**Recommendation:** Consider using a reentrancy guard pattern or ensuring all state updates happen after external calls where possible.

---

#### M-02: Tranche Release Can Be Blocked by Insufficient Vault Balance

**Location:** `capital_vault.move:306-310` (`release_tranche_at`)

**Description:** If capital is withdrawn for staking but not returned before a tranche release, the release will send less than the scheduled amount:

```move
let release_amount = if (amount > self.balance.value()) {
    self.balance.value()  // Releases less than scheduled
} else {
    amount
};
```

**Impact:** Issuers may receive less than expected if staking operations aren't properly coordinated.

**Recommendation:**
1. Add assertion that balance >= tranche amount before release
2. Or require explicit return of staked capital before tranche release
3. Document this requirement clearly for operators

---

#### M-03: Loan Interest Calculation Uses Simple Interest

**Location:** `loan_vault.move:950-984` (`accrue_interest`)

**Description:** The loan system uses simple interest calculated on the outstanding balance. This is intentional but may lead to interest calculation discrepancies if borrowers game the timing of repayments.

**Code:**
```move
let new_interest = (
    (outstanding as u128) *
    (interest_rate_bps as u128) *
    (elapsed_ms as u128)
) / ((BPS_DENOMINATOR as u128) * (MS_PER_YEAR as u128));
```

**Recommendation:** Consider compound interest for fairer interest distribution, or document the simple interest model clearly.

---

#### M-04: Marketplace Delisting Allowed While Paused

**Location:** `marketplace.move:251-289` (`delist`)

**Description:** The `delist` function doesn't check `config.paused`, allowing sellers to delist even when the marketplace is paused. While this could be intentional (allowing users to recover their NFTs during emergency), it's inconsistent with the pause behavior of other functions.

**Recommendation:** Explicitly document this behavior or add pause check for consistency.

---

#### M-05: Council Single Point of Failure

**Location:** `council.move`

**Description:** The `CouncilCap` is a single capability that controls all council-gated operations. If this capability is lost or compromised, there's no recovery mechanism.

**Recommendation:**
1. Implement time-locked operations for critical council actions
2. Consider implementing a multi-cap system with threshold requirements
3. Add emergency recovery mechanisms with timelock

---

### LOW SEVERITY

#### L-01: Missing Event for Staking Configuration Changes

**Location:** `staking_adapter.move:102-119`

**Description:** While `set_enabled` and `set_validator` emit events, there's no comprehensive audit trail for all configuration changes.

**Recommendation:** Ensure all state-changing operations emit events for off-chain monitoring.

---

#### L-02: Potential Integer Overflow in Share Calculation

**Location:** `math.move:41-48` (`to_shares`)

**Description:** Although `mul_div` uses u256 intermediate values, the final cast to u128 could theoretically overflow in extreme scenarios.

```move
let result = ((a as u256) * (b as u256)) / (c as u256);
assert!(result <= 340282366920938463463374607431768211455u256, 1);
```

**Recommendation:** Add explicit overflow checks with clear error messages.

---

#### L-03: Loan Receipt Can Be Transferred, Breaking Collateral Withdrawal

**Location:** `loan_vault.move:145-155`

**Description:** `LoanReceipt` has `store` ability, making it transferable. If transferred, the original borrower address stored in the loan record won't match the new holder, potentially causing confusion (though `withdraw_collateral` correctly checks `receipt.borrower`).

**Recommendation:** Either:
1. Remove `store` ability to prevent transfers
2. Or allow receipt holder to withdraw collateral (update the check)

---

#### L-04: Missing Minimum Loan Validation in liquidate()

**Location:** `loan_vault.move:613-698`

**Description:** The `liquidate` function doesn't validate that the payment amount is reasonable. A malicious liquidator could theoretically pass edge cases.

**Recommendation:** Add sanity checks on payment amounts.

---

#### L-05: Tranche Times Can Be Set in the Past

**Location:** `listing.move:104-182` (`new`)

**Description:** The constructor accepts arbitrary `tranche_times` without validating they are in the future. While the schedule is recomputed at finalization, the initial values could cause confusion.

**Recommendation:** Add validation that tranche times are in the future at creation time.

---

#### L-06: No Upper Bound on Revenue BPS

**Location:** `listing.move:59`

**Description:** `revenue_bps` in `ListingConfig` has no upper bound validation. A value > 10000 would cause unexpected behavior.

**Recommendation:** Add `assert!(revenue_bps <= 10000)` validation.

---

#### L-07: Marketplace Fee Rounding Favors Protocol

**Location:** `marketplace.move:581-583`

**Description:** Fee calculation uses floor division, which slightly favors the protocol:
```move
fun calculate_fee_internal(price: u64): u64 {
    (price * FEE_BPS) / BPS_DENOMINATOR
}
```

**Recommendation:** Document this behavior or implement rounding that favors sellers for small amounts.

---

### INFORMATIONAL

#### I-01: Consider Adding Emergency Withdrawal Mechanism

For extreme scenarios (bugs, exploits), consider implementing a time-locked emergency withdrawal mechanism that can be triggered by the council.

---

#### I-02: Missing NatSpec-style Documentation

While code comments exist, standardized documentation would improve auditability and developer experience.

---

#### I-03: Test Coverage Gaps

The following scenarios appear under-tested:
- Multiple concurrent staking/unstaking operations
- Edge cases in reward distribution with very small amounts
- Loan liquidation with partial payments
- Marketplace sales during listing state changes

---

#### I-04: Consider Implementing Slippage Protection

For marketplace operations, consider implementing slippage protection to prevent front-running.

---

#### I-05: Version Upgrade Path Not Defined

While the code includes version fields, there's no defined upgrade path or migration strategy.

---

#### I-06: Consider Rate Limiting for Anti-Spam

The minimum deposit of 1 SUI helps, but consider additional rate limiting mechanisms for deposit/claim operations.

---

#### I-07: Loan Vault Uses Separate Admin

The `LoanVault` has its own `admin` address separate from `AdminCap`, which could lead to confusion or inconsistent access control.

**Recommendation:** Use `AdminCap` consistently across all packages.

---

#### I-08: Consider Adding Grace Period for Liquidations

Implement a warning period before liquidation to give borrowers time to repay.

---

## Invariant Verification

| Invariant | Status | Notes |
|-----------|--------|-------|
| Principal never enters RewardVault | ✅ VERIFIED | No code path allows this |
| global_index only increases | ✅ VERIFIED | Only `deposit_rewards` modifies it (additive) |
| Claim cursor atomic with withdrawal | ✅ VERIFIED | `update_claim_index` called before `withdraw` |
| Raise fee collected exactly once | ✅ VERIFIED | `raise_fee_collected` flag prevents double-collection |
| State transitions unidirectional | ✅ VERIFIED | Draft→Active→Finalized→Completed, or →Cancelled |
| Config immutable after activation | ✅ VERIFIED | `config_hash` computed at creation |
| Pass ownership = reward entitlement | ✅ VERIFIED | Claim uses pass holder's cursor |
| Tranches released only after time | ✅ VERIFIED | `clock.timestamp_ms() >= tranche.release_time` |

---

## Privileged Roles Analysis

### AdminCap Holder

**Can:**
- Pause/unpause protocol
- Change admin wallet address
- Withdraw from treasury vault

**Cannot:**
- Seize user capital
- Redirect rewards
- Modify listing economics

**Risk:** Medium - Treasury funds at risk if compromised

---

### CouncilCap Holder

**Can:**
- Create/register listings
- Activate/finalize listings
- Pause/resume individual listings
- Cancel listings
- Manage staking operations

**Cannot:**
- Seize capital directly
- Modify economics after activation
- Redirect reward flows

**Risk:** High - Central point of control for listing lifecycle

---

### RouteCapability Holder

**Can:**
- Deposit rewards to specific RewardVault

**Cannot:**
- Withdraw rewards
- Modify vault parameters

**Risk:** Low - Can only add value

---

### ListingCap Holder (Issuer)

**Can:**
- Manage listing-specific infrastructure

**Cannot:**
- Seize backer capital
- Skip release schedule

**Risk:** Low - Limited to issuer operations

---

## Gas Optimization Notes

1. **Batch Operations:** `claim_many` efficiently batches claims but creates individual events. Consider summary-only events for gas savings.

2. **Storage Patterns:** StakedSui objects in dynamic fields create gas overhead. Consider batching stake operations.

3. **Loop Iterations:** `release_all_ready_tranches` iterates all tranches. Consider tracking first unreleased index.

---

## Recommendations Summary

### Before Mainnet (Required)

1. **Fix H-01:** Correct staking reward calculation to prevent manipulation
2. **Address H-02:** Implement more robust collateral valuation or conservative parameters
3. **Review M-02:** Ensure tranche release coordination with staking
4. **Add comprehensive integration tests** for staking + release flows

### Recommended Improvements

1. Implement time-locked operations for council actions
2. Add emergency withdrawal mechanism with timelock
3. Standardize admin patterns across all packages
4. Add slippage protection for marketplace
5. Implement compound interest for loans
6. Add oracle-based pricing for loan collateral

### Documentation Required

1. Operator runbook for staking coordination
2. Emergency response procedures
3. Upgrade migration strategy
4. Economic parameter sensitivity analysis

---

## Conclusion

Tide Protocol demonstrates thoughtful security design with proper separation of concerns, capability-based access control, and well-defined invariants. The core capital raise mechanics are sound, with principal isolation being a key strength.

The main areas of concern are:
1. **Staking reward calculation edge cases** - requires fix before mainnet
2. **Loan collateral valuation** - needs more conservative parameters or oracle integration
3. **Council centralization** - consider implementing timelocks and recovery mechanisms

With the recommended fixes implemented, the protocol should be ready for mainnet deployment. A follow-up audit is recommended after addressing the high-severity findings.

---

**Disclaimer:** This security audit was performed by an automated analysis system. While comprehensive, it may not catch all potential vulnerabilities. A professional manual audit by a reputable security firm is recommended before mainnet deployment.
