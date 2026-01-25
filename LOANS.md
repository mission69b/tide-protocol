# Self-Paying Loans

Self-Paying Loans is Tide Protocol's DeFi expansion that allows SupporterPass holders to borrow against their yield-bearing NFTs. Rewards from the pass automatically repay the loan, creating a "set and forget" borrowing experience.

## Overview

### What Is It?

A lending protocol where:
1. User deposits SupporterPass as collateral
2. User receives SUI loan (up to 50% LTV)
3. Pass rewards automatically repay the loan
4. When fully repaid, user gets pass back

### Key Value Propositions

| For | Benefit |
|-----|---------|
| **Borrowers** | Instant liquidity without selling, loan pays itself |
| **Tide** | New revenue stream (origination fees, interest) |
| **Ecosystem** | Novel DeFi primitive, attracts capital |

## Quick Start

### Borrow Against Your Pass

```bash
# 1. Borrow 50 SUI against your SupporterPass
sui client call \
  --package $LOANS_PKG \
  --module loan_vault \
  --function borrow \
  --args $LOAN_VAULT $LISTING $TIDE $CAPITAL_VAULT $PASS_ID "50000000000" \
  --gas-budget 100000000

# Returns: LoanReceipt + 49.5 SUI (after 1% origination fee)
```

### Repay Manually (Optional)

```bash
# Repay loan early (or let rewards pay it)
sui client call \
  --package $LOANS_PKG \
  --module loan_vault \
  --function repay \
  --args $LOAN_VAULT $RECEIPT_ID $PAYMENT_COIN \
  --gas-budget 100000000
```

### Harvest Rewards (Keeper)

```bash
# Anyone can trigger reward harvesting for any loan
sui client call \
  --package $LOANS_PKG \
  --module loan_vault \
  --function harvest_and_repay \
  --args $LOAN_VAULT $LOAN_ID $LISTING $TIDE $REWARD_VAULT \
  --gas-budget 100000000

# Keeper receives 0.1% tip from harvested rewards
```

### Withdraw Collateral

```bash
# After loan is fully repaid, get your pass back
sui client call \
  --package $LOANS_PKG \
  --module loan_vault \
  --function withdraw_collateral \
  --args $LOAN_VAULT $RECEIPT_ID \
  --gas-budget 100000000
```

## Fee Structure

| Fee | Rate | When Paid | To |
|-----|------|-----------|-----|
| **Origination Fee** | 1% | On borrow | Tide Treasury |
| **Interest Rate** | 5% APR | Accrues daily | Tide Treasury |
| **Liquidation Fee** | 5% | On liquidation | Tide Treasury |
| **Keeper Tip** | 0.1% | On harvest | Keeper |

## Risk Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Max LTV** | 50% | Maximum loan-to-value ratio |
| **Liquidation Threshold** | 75% | Trigger point for liquidation |
| **Min Loan** | 1 SUI | Minimum loan amount |
| **Insurance Fund** | 20% | Portion of fees allocated to insurance |

## Architecture

### Object Model

```
LoanVault (Shared)
├── liquidity: Balance<SUI>        # Available for lending
├── insurance_fund: Balance<SUI>   # For covering losses
├── config: LoanConfig             # Parameters
├── [Dynamic Fields]
│   ├── Loan_{id}: Loan            # Loan records
│   └── Pass_{id}: SupporterPass   # Collateral
│
Loan (Stored in LoanVault)
├── borrower: address
├── pass_id: ID
├── principal: u64
├── interest_accrued: u64
├── amount_repaid: u64
├── status: u8                     # Active/Repaid/Liquidated
│
LoanReceipt (Owned NFT)
├── loan_id: ID
├── borrower: address
├── principal: u64
```

### Module Structure

```
contracts/loans/
├── Move.toml                # Package config
├── sources/
│   └── loan_vault.move      # Core loan logic
└── tests/
    └── loan_vault_tests.move
```

## User Flows

### Happy Path: Self-Paying Loan

```
DAY 0: Alice borrows
├── Deposits SupporterPass (100 SUI collateral)
├── Borrows 50 SUI
├── Pays 0.5 SUI origination fee
└── Receives 49.5 SUI + LoanReceipt

DAY 30: Keeper harvests
├── Pass earned 10 SUI in rewards
├── Interest accrued: 0.21 SUI
├── Keeper tip: 0.01 SUI
├── Applied to loan: 9.99 SUI
└── New balance: 40.22 SUI

DAY 180: Loan fully repaid
├── Final harvest covers remaining balance
├── Excess sent to Alice automatically
├── Loan status: REPAID
└── Alice withdraws her pass 🎉
```

### Liquidation Path

```
If health factor drops below 1.0:
├── Anyone can call liquidate()
├── Liquidator pays remaining loan
├── Liquidator receives collateral
├── 5% liquidation fee to Tide
└── Borrower loses collateral, debt cleared
```

## Health Factor

```
Health Factor = (Collateral × Liquidation Threshold) / Outstanding Balance

If Health Factor < 1.0 → Loan is liquidatable

Example:
- Collateral: 80 SUI
- Liquidation Threshold: 75%
- Outstanding: 65 SUI
- Health Factor: (80 × 0.75) / 65 = 0.92 < 1.0 → LIQUIDATABLE
```

## Admin Functions

| Function | Access | Description |
|----------|--------|-------------|
| `deposit_liquidity` | AdminCap | Add lending capital |
| `withdraw_liquidity` | AdminCap | Remove lending capital |
| `withdraw_insurance` | AdminCap | Emergency insurance withdrawal |
| `pause` | AdminCap | Pause new borrowing |
| `unpause` | AdminCap | Resume borrowing |
| `update_max_ltv` | AdminCap | Change LTV limit |
| `update_interest_rate` | AdminCap | Change interest rate |
| `update_liquidation_threshold` | AdminCap | Change threshold |

## Events

| Event | When Emitted |
|-------|--------------|
| `LoanCreated` | New loan created |
| `LoanRepayment` | Payment applied to loan |
| `LoanFullyRepaid` | Loan paid off |
| `LoanLiquidated` | Loan was liquidated |
| `CollateralWithdrawn` | Pass returned to borrower |
| `HarvestExecuted` | Keeper harvested rewards |
| `LiquidityDeposited` | Admin added liquidity |
| `LiquidityWithdrawn` | Admin removed liquidity |
| `VaultPaused` | Vault paused/unpaused |

## Security Considerations

### Access Control

| Function | Access Level |
|----------|--------------|
| `borrow()` | Anyone with SupporterPass |
| `repay()` | Anyone (receipt holder benefits) |
| `harvest_and_repay()` | Anyone (keeper model) |
| `withdraw_collateral()` | Receipt holder only |
| `liquidate()` | Anyone (if loan unhealthy) |
| Admin functions | AdminCap required |

### Invariants

1. Pass MUST remain in LoanVault until loan resolved
2. Each pass can have at most one active loan
3. All rewards from collateralized pass go to loan repayment
4. Loan status transitions are unidirectional: Active → Repaid or Active → Liquidated

### Protection Mechanisms

- **Conservative LTV (50%)**: Large buffer before liquidation
- **Insurance Fund (20%)**: Portion of fees covers losses
- **No Oracle Dependency**: Uses original deposit value for collateral
- **Permissionless Liquidation**: Anyone can trigger to keep system healthy

## Build & Test

```bash
cd contracts/loans

# Build
sui move build

# Test
sui move test

# Test with coverage
sui move test --coverage
```

## Future: DeepBook Integration — ⏸️ DEFERRED

DeepBook integration is **deferred** until the protocol reaches scale:

**Current approach (v1):**
- Treasury-funded loans (simple, works for 1-2 issuers)
- Fixed 5% APR (predictable for borrowers)
- Standard liquidations (rarely needed with self-paying loans)

**When to revisit DeepBook:**
- Treasury consistently 50%+ utilized
- 3+ issuers onboarded
- User demand for dynamic rates

See [spec/deepbook-integration-v1.md](./spec/deepbook-integration-v1.md) for the full specification (when ready to implement).

## Related Documentation

- [Main README](./README.md) - Protocol overview
- [Self-Paying Loans Spec](./spec/self-paying-loans-v2.md) - Full technical specification
- [DeepBook Integration Spec](./spec/deepbook-integration-v1.md) - Flash loans & dynamic rates (planned)
- [Tide Core v1 Spec](./spec/tide-core-v1.md) - Core protocol specification
