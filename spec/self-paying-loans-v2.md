# Self-Paying Loans Specification

> **Version:** v2.0
> **Status:** ✅ IMPLEMENTED (Phase 1 MVP Complete)
> **Author:** Tide Protocol
> **Last Updated:** January 2026

## Executive Summary

Self-Paying Loans is Tide's DeFi expansion that allows SupporterPass holders to borrow against their yield-bearing NFTs. Rewards from the pass automatically repay the loan, creating a "set and forget" borrowing experience.

**Key Value Propositions:**
- **For Borrowers:** Instant liquidity without selling, loan pays itself
- **For Tide:** New revenue stream (origination fees, interest, liquidation fees)
- **For Ecosystem:** Novel DeFi primitive, attracts capital

---

## 1. Overview

### 1.1 What Is It?

A lending protocol where:
1. User deposits SupporterPass as collateral
2. User receives SUI loan (up to 50% LTV)
3. Pass rewards automatically repay the loan
4. When fully repaid, user gets pass back

### 1.2 Why It Matters

| Problem | Solution |
|---------|----------|
| Backers want liquidity but don't want to sell | Borrow against pass, keep ownership |
| Idle capital in DeFi | Put yield-bearing NFTs to work |
| Complex loan management | Self-paying, no active management |
| Lender capital efficiency | Continuous repayment from yield |

### 1.3 Core Invariants

1. **Collateral Custody:** Pass MUST remain in LoanVault until loan resolved
2. **Single Loan:** Each pass can have at most one active loan
3. **Reward Capture:** All rewards from collateralized pass go to loan repayment
4. **No Loss Guarantee:** Conservative parameters ensure Tide treasury is protected

---

## 2. Fee Structure & Revenue Model

### 2.1 Fee Types

| Fee | Rate | Paid By | Paid To | When |
|-----|------|---------|---------|------|
| **Origination Fee** | 1.0% | Borrower | Tide Treasury | On borrow |
| **Interest Rate** | 5.0% APR | Borrower | Tide Treasury | Accrues daily |
| **Liquidation Fee** | 5.0% | Borrower (from collateral) | Tide Treasury | On liquidation |
| **Keeper Tip** | 0.1% | Borrower (from rewards) | Keeper | On harvest |

### 2.2 Revenue Projection

Assuming $1M total loans outstanding:

| Revenue Source | Calculation | Annual Revenue |
|----------------|-------------|----------------|
| Origination Fees | $1M × 1% | $10,000 |
| Interest | $1M × 5% | $50,000 |
| Liquidation Fees | $100K liquidated × 5% | $5,000 |
| **Total** | | **$65,000** |

### 2.3 Insurance Fund

To protect against black swan events:
- **Allocation:** 20% of all loan revenue → Insurance Fund
- **Purpose:** Cover any residual losses from liquidations
- **Cap:** Once fund reaches 10% of total loans, excess goes to treasury

---

## 3. Risk Management

### 3.1 Risk Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| **Max LTV** | 50% | Conservative, large buffer |
| **Liquidation Threshold** | 75% | Trigger before underwater |
| **Liquidation Bonus** | 5% | Incentivize quick liquidation |
| **Min Loan** | 1 SUI | Prevent dust loans |
| **Max Loan Duration** | 365 days | Limit exposure time |

### 3.2 Safety Layers

```
Pass Value: 100 SUI
├── Max Loan (50% LTV): 50 SUI
│   └── Origination Fee (1%): 0.5 SUI → TIDE EARNS IMMEDIATELY
│       └── Net to Borrower: 49.5 SUI
│
├── Liquidation Threshold (75%): 75 SUI
│   └── Buffer: 25 SUI before any risk
│
├── Liquidation Scenario:
│   └── If pass drops to 66.67 SUI:
│       ├── Loan: 50 SUI (75% of 66.67)
│       ├── Liquidator pays: 50 SUI
│       ├── Liquidator gets: 66.67 SUI pass
│       ├── Liquidator profit: ~16.67 SUI
│       └── Tide: Got 50 SUI back ✅
│
└── Worst Case (no liquidator, pass = 0):
    ├── Tide loss: 50 SUI
    ├── Tide earned: 0.5 SUI origination
    ├── Insurance fund covers remainder
    └── Exposure limits prevent catastrophic loss
```

### 3.3 Exposure Limits

| Limit | Value | Purpose |
|-------|-------|---------|
| **Treasury Allocation** | Max 10% | Limit total exposure |
| **Per-User Limit** | 100 SUI | Prevent concentration |
| **Per-Listing Limit** | 1000 SUI | Diversify across listings |
| **Utilization Cap** | 80% | Keep liquidity for withdrawals |

### 3.4 Liquidation Mechanics

```
Health Factor = (Collateral × Liquidation Threshold) / Loan Balance

If Health Factor < 1.0 → Liquidation Eligible

Example:
- Collateral: 80 SUI
- Liquidation Threshold: 75%
- Loan Balance: 65 SUI
- Health Factor: (80 × 0.75) / 65 = 0.92 < 1.0 → LIQUIDATABLE
```

**Liquidation Process:**
1. Anyone can call `liquidate(loan_id, payment)`
2. Liquidator pays off remaining loan balance
3. Liquidator receives collateral (pass)
4. Liquidation fee (5%) paid to Tide from collateral
5. Borrower loses collateral but debt is cleared

---

## 4. Technical Architecture

### 4.1 Object Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              OBJECT MODEL                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   LoanVault (Shared)                                                        │
│   ├── id: UID                                                               │
│   ├── liquidity: Balance<SUI>          // Available for lending            │
│   ├── insurance_fund: Balance<SUI>     // For covering losses              │
│   ├── total_borrowed: u64              // Outstanding loans                 │
│   ├── total_repaid: u64                // Lifetime repayments              │
│   ├── total_revenue: u64               // Lifetime fees earned             │
│   ├── config: LoanConfig               // Parameters                        │
│   ├── stats: LoanStats                 // Analytics                         │
│   └── [Dynamic Fields]                                                      │
│       ├── Loan_{id}: Loan              // Loan records                      │
│       └── Pass_{id}: SupporterPass     // Collateral                        │
│                                                                              │
│   Loan (Stored in LoanVault)                                                │
│   ├── borrower: address                                                     │
│   ├── pass_id: ID                                                           │
│   ├── listing_id: ID                                                        │
│   ├── principal: u64                                                        │
│   ├── interest_accrued: u64                                                 │
│   ├── amount_repaid: u64                                                    │
│   ├── collateral_value: u64                                                 │
│   ├── created_at: u64                                                       │
│   ├── last_update: u64                                                      │
│   └── status: u8                       // Active/Repaid/Liquidated         │
│                                                                              │
│   LoanReceipt (Owned NFT)                                                   │
│   ├── id: UID                                                               │
│   ├── loan_id: ID                                                           │
│   ├── borrower: address                                                     │
│   ├── pass_id: ID                                                           │
│   └── principal: u64                                                        │
│                                                                              │
│   LoanConfig (Stored in LoanVault)                                          │
│   ├── max_ltv_bps: u64                 // 5000 = 50%                       │
│   ├── liquidation_threshold_bps: u64   // 7500 = 75%                       │
│   ├── interest_rate_bps: u64           // 500 = 5% APR                     │
│   ├── origination_fee_bps: u64         // 100 = 1%                         │
│   ├── liquidation_fee_bps: u64         // 500 = 5%                         │
│   ├── keeper_tip_bps: u64              // 10 = 0.1%                        │
│   ├── insurance_fund_bps: u64          // 2000 = 20%                       │
│   ├── min_loan: u64                    // 1 SUI                            │
│   ├── max_loan_duration: u64           // 365 days                         │
│   └── treasury_allocation_cap: u64     // 10% of treasury                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Module Structure

```
contracts/core/sources/
├── loan_vault.move           # LoanVault, Loan structs
├── loan_borrow.move          # borrow() function
├── loan_repay.move           # repay(), harvest_and_repay()
├── loan_liquidate.move       # liquidate() function
├── loan_receipt.move         # LoanReceipt NFT
├── loan_config.move          # Configuration management
├── loan_math.move            # Interest calculations
├── loan_events.move          # Event definitions
└── loan_admin.move           # Admin functions
```

### 4.3 Key Functions

#### 4.3.1 Borrow

```move
/// Deposit SupporterPass as collateral and receive a loan.
public fun borrow(
    vault: &mut LoanVault,
    listing: &Listing,
    tide: &Tide,
    pass: SupporterPass,
    loan_amount: u64,
    ctx: &mut TxContext,
): (LoanReceipt, Coin<SUI>)

// Flow:
// 1. Validate: vault not paused, sufficient liquidity
// 2. Calculate collateral value (original deposit amount)
// 3. Validate: loan_amount <= collateral × max_ltv
// 4. Deduct origination fee (1%)
// 5. Store pass in vault (dynamic field)
// 6. Create Loan record
// 7. Mint LoanReceipt NFT
// 8. Transfer loan SUI to borrower
// 9. Emit LoanCreated event
```

#### 4.3.2 Harvest and Repay (Self-Paying Magic)

```move
/// Claim rewards from collateralized pass and apply to loan.
/// Permissionless - anyone can call (keeper model).
public fun harvest_and_repay(
    vault: &mut LoanVault,
    loan_id: ID,
    listing: &Listing,
    tide: &Tide,
    reward_vault: &mut RewardVault,
    ctx: &mut TxContext,
): Coin<SUI>  // Keeper tip

// Flow:
// 1. Accrue interest on loan
// 2. Borrow pass from vault (dynamic field)
// 3. Claim rewards from RewardVault
// 4. Calculate keeper tip (0.1%)
// 5. Apply remaining rewards to loan:
//    - If rewards >= remaining loan:
//        → Loan fully repaid
//        → Excess sent to borrower
//        → Pass stays locked (withdraw separately)
//    - If rewards < remaining loan:
//        → Reduce loan balance
//        → Pass stays locked
// 6. Return pass to vault
// 7. Emit event
// 8. Return keeper tip
```

#### 4.3.3 Manual Repay

```move
/// Borrower manually repays loan (partially or fully).
public fun repay(
    vault: &mut LoanVault,
    receipt: &LoanReceipt,
    payment: Coin<SUI>,
    ctx: &mut TxContext,
)

// Flow:
// 1. Validate receipt matches loan
// 2. Accrue interest
// 3. Apply payment to loan balance
// 4. If fully repaid, mark loan status
// 5. Refund overpayment
// 6. Emit event
```

#### 4.3.4 Withdraw Collateral

```move
/// Withdraw collateral after loan fully repaid.
/// Burns the LoanReceipt.
public fun withdraw_collateral(
    vault: &mut LoanVault,
    receipt: LoanReceipt,
    ctx: &mut TxContext,
): SupporterPass

// Flow:
// 1. Validate loan status is REPAID
// 2. Validate caller is borrower
// 3. Remove pass from vault
// 4. Burn receipt
// 5. Emit event
// 6. Return pass
```

#### 4.3.5 Liquidate

```move
/// Liquidate an unhealthy loan.
/// Anyone can call if health factor < 1.
public fun liquidate(
    vault: &mut LoanVault,
    loan_id: ID,
    listing: &Listing,
    payment: Coin<SUI>,
    ctx: &mut TxContext,
): SupporterPass

// Flow:
// 1. Accrue interest
// 2. Calculate health factor
// 3. Validate: health_factor < 1.0
// 4. Liquidator pays remaining loan
// 5. Deduct liquidation fee (5%) to Tide
// 6. Transfer pass to liquidator
// 7. Mark loan as LIQUIDATED
// 8. Emit event
```

### 4.4 Interest Calculation

```move
/// Calculate accrued interest using simple interest.
/// 
/// Formula: interest = principal × rate × time
/// 
/// Where:
/// - principal: outstanding loan balance
/// - rate: annual interest rate (5% = 0.05)
/// - time: fraction of year elapsed
fun accrue_interest(
    loan: &mut Loan,
    interest_rate_bps: u64,
    ctx: &TxContext,
) {
    let elapsed_ms = ctx.epoch_timestamp_ms() - loan.last_update;
    let elapsed_years = elapsed_ms / (365 * 24 * 60 * 60 * 1000);
    
    let outstanding = loan.principal - loan.amount_repaid;
    let new_interest = (outstanding * interest_rate_bps * elapsed_ms) 
                       / (10_000 * 365 * 24 * 60 * 60 * 1000);
    
    loan.interest_accrued = loan.interest_accrued + new_interest;
    loan.last_update = ctx.epoch_timestamp_ms();
}
```

### 4.5 Collateral Valuation

For v2.0, we use a simple, conservative approach:

```move
/// Calculate collateral value.
/// v2.0: Use original deposit amount (1:1 with SUI deposited).
/// 
/// This is conservative because:
/// - Ignores accrued rewards (always undervalues)
/// - Ignores market premium (passes may trade above deposit)
/// - Simple and manipulation-resistant
fun calculate_collateral_value(
    pass: &SupporterPass,
    listing: &Listing,
): u64 {
    // For v2.0: Use shares as proxy for original deposit
    // shares = deposit × PRECISION / total_principal_at_deposit
    // So: deposit ≈ shares × total_principal / PRECISION (at time of deposit)
    
    // Simplified: We store original deposit in pass metadata
    // or calculate from shares at current total_principal
    
    // Conservative approach: use minimum of
    // 1. Original deposit value
    // 2. Current share value
    
    pass.original_deposit_value()
}
```

---

## 5. User Flows

### 5.1 Happy Path: Self-Paying Loan

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ DAY 0: Alice Takes a Loan                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│ Alice has: SupporterPass (deposited 100 SUI, earns ~10 SUI/month)          │
│                                                                              │
│ Alice calls: borrow(vault, listing, tide, pass, 50 SUI)                    │
│                                                                              │
│ Result:                                                                      │
│ ├── Pass locked in LoanVault                                                │
│ ├── Origination fee: 0.5 SUI (1%) → Tide                                   │
│ ├── Alice receives: 49.5 SUI + LoanReceipt                                 │
│ └── Loan balance: 50 SUI                                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ DAY 30: Keeper Harvests                                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│ Pass earned: 10 SUI in rewards                                              │
│ Interest accrued: 0.21 SUI (50 × 5% × 30/365)                              │
│                                                                              │
│ Keeper calls: harvest_and_repay(vault, loan_id, ...)                        │
│                                                                              │
│ Result:                                                                      │
│ ├── Rewards claimed: 10 SUI                                                 │
│ ├── Keeper tip: 0.01 SUI (0.1%)                                            │
│ ├── Applied to loan: 9.99 SUI                                              │
│ ├── New loan balance: 50 + 0.21 - 9.99 = 40.22 SUI                         │
│ └── Keeper receives: 0.01 SUI                                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ DAY 180: Loan Fully Repaid                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│ After 6 harvests (~60 SUI rewards, ~1.25 SUI interest):                    │
│                                                                              │
│ Keeper calls: harvest_and_repay(vault, loan_id, ...)                        │
│                                                                              │
│ Result:                                                                      │
│ ├── Remaining loan: 5 SUI                                                   │
│ ├── Rewards claimed: 12 SUI                                                 │
│ ├── Keeper tip: 0.012 SUI                                                  │
│ ├── Loan paid off: 5 SUI → Tide                                            │
│ ├── Excess: 6.988 SUI → Alice (automatic!)                                 │
│ └── Loan status: REPAID ✅                                                  │
│                                                                              │
│ Alice calls: withdraw_collateral(vault, receipt)                            │
│                                                                              │
│ Result:                                                                      │
│ ├── Receipt burned                                                          │
│ └── Alice receives: SupporterPass back 🎉                                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ SUMMARY                                                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│ Alice:                                                                       │
│ ├── Borrowed: 49.5 SUI (after fees)                                        │
│ ├── Repaid: 0 SUI (loan paid itself!)                                      │
│ ├── Received excess: ~10 SUI                                               │
│ └── Got pass back: ✅                                                       │
│                                                                              │
│ Tide:                                                                        │
│ ├── Origination fee: 0.5 SUI                                               │
│ ├── Interest earned: ~1.25 SUI                                             │
│ └── Total revenue: ~1.75 SUI                                               │
│                                                                              │
│ Keeper:                                                                      │
│ └── Tips earned: ~0.06 SUI                                                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Liquidation Path

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ SCENARIO: Bob's Loan Gets Liquidated                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│ DAY 0:                                                                       │
│ ├── Bob deposits pass (100 SUI collateral)                                  │
│ ├── Borrows 50 SUI                                                          │
│ └── Health: (100 × 75%) / 50 = 1.5 (healthy)                               │
│                                                                              │
│ DAY 365 (worst case: no harvests, rewards dried up):                        │
│ ├── Interest accrued: 50 × 5% = 2.5 SUI                                    │
│ ├── Total owed: 52.5 SUI                                                    │
│ ├── Collateral still 100 SUI                                               │
│ └── Health: (100 × 75%) / 52.5 = 1.43 (still healthy!)                     │
│                                                                              │
│ For liquidation to be possible:                                              │
│ ├── Need: collateral × 75% < loan                                          │
│ ├── Need: 100 × 75% < loan                                                 │
│ ├── Need: loan > 75 SUI                                                    │
│ └── At 5% APR, takes 10 years! 💪                                          │
│                                                                              │
│ ALTERNATIVE: Collateral value drops (listing underperforms)                 │
│                                                                              │
│ If collateral drops to 70 SUI:                                              │
│ ├── Health: (70 × 75%) / 52.5 = 1.0 (borderline)                           │
│                                                                              │
│ If collateral drops to 65 SUI:                                              │
│ ├── Health: (65 × 75%) / 52.5 = 0.93 (LIQUIDATABLE)                        │
│                                                                              │
│ Charlie calls: liquidate(vault, loan_id, 52.5 SUI)                          │
│                                                                              │
│ Result:                                                                      │
│ ├── Charlie pays: 52.5 SUI                                                 │
│ ├── Charlie receives: Pass (worth 65 SUI)                                  │
│ ├── Charlie profit: ~12.5 SUI                                              │
│ ├── Tide receives: 52.5 SUI (loan fully repaid)                            │
│ ├── Tide liquidation fee: from Charlie's profit                            │
│ └── Bob: Loses pass, debt cleared                                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Events

```move
// === Loan Lifecycle Events ===

public struct LoanCreated has copy, drop {
    loan_id: ID,
    borrower: address,
    pass_id: ID,
    listing_id: ID,
    principal: u64,
    collateral_value: u64,
    ltv_bps: u64,
    origination_fee: u64,
    epoch: u64,
}

public struct LoanRepayment has copy, drop {
    loan_id: ID,
    amount: u64,
    source: u8,           // 0=harvest, 1=manual
    remaining_balance: u64,
    epoch: u64,
}

public struct LoanFullyRepaid has copy, drop {
    loan_id: ID,
    borrower: address,
    total_principal: u64,
    total_interest: u64,
    excess_returned: u64,
    epoch: u64,
}

public struct LoanLiquidated has copy, drop {
    loan_id: ID,
    borrower: address,
    liquidator: address,
    amount_paid: u64,
    collateral_value: u64,
    liquidation_fee: u64,
    epoch: u64,
}

public struct CollateralWithdrawn has copy, drop {
    loan_id: ID,
    borrower: address,
    pass_id: ID,
    epoch: u64,
}

// === Keeper Events ===

public struct HarvestExecuted has copy, drop {
    loan_id: ID,
    rewards_claimed: u64,
    applied_to_loan: u64,
    keeper_tip: u64,
    keeper: address,
    epoch: u64,
}

// === Admin Events ===

public struct LoanConfigUpdated has copy, drop {
    parameter: vector<u8>,
    old_value: u64,
    new_value: u64,
    updated_by: address,
    epoch: u64,
}

public struct InsuranceFundDeposit has copy, drop {
    amount: u64,
    source: vector<u8>,
    new_balance: u64,
    epoch: u64,
}
```

---

## 7. Admin Functions

### 7.1 Configuration Management

```move
/// Update loan parameters (AdminCap required).
public fun update_max_ltv(vault: &mut LoanVault, admin_cap: &AdminCap, new_ltv_bps: u64)
public fun update_interest_rate(vault: &mut LoanVault, admin_cap: &AdminCap, new_rate_bps: u64)
public fun update_liquidation_threshold(vault: &mut LoanVault, admin_cap: &AdminCap, new_threshold_bps: u64)
public fun update_origination_fee(vault: &mut LoanVault, admin_cap: &AdminCap, new_fee_bps: u64)

/// Pause/unpause lending.
public fun pause_lending(vault: &mut LoanVault, admin_cap: &AdminCap)
public fun unpause_lending(vault: &mut LoanVault, admin_cap: &AdminCap)
```

### 7.2 Liquidity Management

```move
/// Deposit liquidity from treasury.
public fun deposit_liquidity(
    vault: &mut LoanVault,
    admin_cap: &AdminCap,
    liquidity: Coin<SUI>,
)

/// Withdraw liquidity to treasury.
public fun withdraw_liquidity(
    vault: &mut LoanVault,
    admin_cap: &AdminCap,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI>

/// Withdraw from insurance fund (emergency only).
public fun withdraw_insurance(
    vault: &mut LoanVault,
    admin_cap: &AdminCap,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI>
```

---

## 8. Security Considerations

### 8.1 Threat Model

| Threat | Mitigation |
|--------|------------|
| **Flash loan attack** | Loan creation requires pass ownership proven in same tx |
| **Oracle manipulation** | No oracle in v2.0 (use original deposit value) |
| **Reentrancy** | No external calls during state mutations |
| **Interest rate manipulation** | Rates set by admin, changes require timelock |
| **Collateral theft** | Pass locked in vault, only LoanReceipt holder can withdraw |
| **Keeper MEV** | Permissionless harvesting, small tips, no ordering dependency |

### 8.2 Invariants to Audit

1. `pass.owner == LoanVault` while loan is active
2. `loan.amount_repaid <= loan.principal + loan.interest_accrued`
3. `vault.total_borrowed == sum(active_loans.principal)`
4. `insurance_fund >= 0` always
5. Loan status transitions are unidirectional: Active → Repaid or Active → Liquidated

### 8.3 Access Control

| Function | Access | Rationale |
|----------|--------|-----------|
| `borrow()` | Anyone with pass | Permissionless |
| `repay()` | Anyone (receipt holder benefits) | Allow third-party repayment |
| `harvest_and_repay()` | Anyone | Keeper model |
| `withdraw_collateral()` | Receipt holder only | Proves ownership |
| `liquidate()` | Anyone (if unhealthy) | Open liquidation |
| `update_*()` | AdminCap only | Parameter changes |
| `pause/unpause()` | AdminCap only | Emergency control |

---

## 9. Implementation Phases

### Phase 1: MVP (v2.0) ✅ COMPLETE

**Scope:**
- [x] LoanVault with treasury liquidity
- [x] Basic borrow/repay/liquidate
- [x] Manual harvest_and_repay (keeper calls)
- [x] Simple collateral valuation (original deposit)
- [x] Conservative parameters (50% LTV, 5% interest)
- [x] Versioning (VERSION constant)
- [x] Admin functions (pause, config updates, liquidity management)
- [x] Unit tests (14 tests)
- [x] E2E tests (7 tests)

**Timeline:** ✅ Completed

### Phase 2: Enhanced (v2.1)

**Scope:**
- [ ] Auto-harvest integration with existing adapters
- [ ] Multiple listing support
- [ ] Improved liquidation UX
- [ ] Analytics dashboard

**Timeline:** 2 weeks

### Phase 3: Pool-Based Lending (v3.0)

**Scope:**
- [ ] External lender deposits
- [ ] LenderPosition NFT
- [ ] Dynamic interest rates (utilization-based)
- [ ] Lender yield distribution

**Timeline:** 4-6 weeks

---

## 10. Testing Requirements

### 10.1 Unit Tests

- [ ] `test_borrow_success`
- [ ] `test_borrow_exceeds_ltv_fails`
- [ ] `test_borrow_insufficient_liquidity_fails`
- [ ] `test_repay_partial`
- [ ] `test_repay_full`
- [ ] `test_repay_overpayment_refund`
- [ ] `test_harvest_and_repay`
- [ ] `test_harvest_pays_off_loan`
- [ ] `test_harvest_excess_to_borrower`
- [ ] `test_withdraw_collateral`
- [ ] `test_withdraw_before_repaid_fails`
- [ ] `test_liquidate_unhealthy`
- [ ] `test_liquidate_healthy_fails`
- [ ] `test_interest_accrual`
- [ ] `test_origination_fee`
- [ ] `test_keeper_tip`
- [ ] `test_insurance_fund_allocation`

### 10.2 E2E Tests

- [ ] Full self-paying loan lifecycle
- [ ] Multi-harvest loan payoff
- [ ] Liquidation scenario
- [ ] Manual repayment mid-loan
- [ ] Multiple concurrent loans

### 10.3 Invariant Tests

- [ ] Total borrowed matches sum of active loans
- [ ] Collateral always in vault while loan active
- [ ] No double-spend of collateral

---

## 11. Appendix

### A. Constants

```move
// === Loan Status ===
const LOAN_ACTIVE: u8 = 0;
const LOAN_REPAID: u8 = 1;
const LOAN_LIQUIDATED: u8 = 2;

// === Default Parameters ===
const DEFAULT_MAX_LTV_BPS: u64 = 5000;           // 50%
const DEFAULT_LIQUIDATION_THRESHOLD_BPS: u64 = 7500;  // 75%
const DEFAULT_INTEREST_RATE_BPS: u64 = 500;      // 5% APR
const DEFAULT_ORIGINATION_FEE_BPS: u64 = 100;    // 1%
const DEFAULT_LIQUIDATION_FEE_BPS: u64 = 500;    // 5%
const DEFAULT_KEEPER_TIP_BPS: u64 = 10;          // 0.1%
const DEFAULT_INSURANCE_FUND_BPS: u64 = 2000;    // 20%
const DEFAULT_MIN_LOAN: u64 = 1_000_000_000;     // 1 SUI
const DEFAULT_MAX_LOAN_DURATION: u64 = 365 * 24 * 60 * 60 * 1000; // 1 year
```

### B. Error Codes

```move
const ELoanVaultPaused: u64 = 1;
const EExceedsMaxLTV: u64 = 2;
const EInsufficientLiquidity: u64 = 3;
const ELoanNotActive: u64 = 4;
const ELoanNotRepaid: u64 = 5;
const ENotBorrower: u64 = 6;
const ELoanHealthy: u64 = 7;
const EInsufficientPayment: u64 = 8;
const EExceedsExposureLimit: u64 = 9;
const EInvalidParameter: u64 = 10;
```

### C. Glossary

| Term | Definition |
|------|------------|
| **LTV** | Loan-to-Value ratio (loan / collateral) |
| **Health Factor** | (collateral × liquidation_threshold) / loan |
| **Liquidation** | Forced sale of collateral to repay loan |
| **Keeper** | Bot/user that calls harvest_and_repay for tips |
| **Origination Fee** | One-time fee on loan creation |
| **Principal** | Original loan amount |
| **Collateral** | Asset pledged to secure loan |

---

## 12. References

- [Aave V3 Documentation](https://docs.aave.com/)
- [Compound Finance](https://compound.finance/docs)
- [NFTfi](https://nftfi.com/)
- [Sui Move Documentation](https://docs.sui.io/build/move)
