# DeepBook Integration Specification

> **Version:** v1.0
> **Status:** 📝 DRAFT
> **Author:** Tide Protocol
> **Last Updated:** January 2026

## Executive Summary

This specification outlines the integration of [DeepBook V3](https://docs.sui.io/standards/deepbook) and [DeepBook Margin](https://docs.sui.io/standards/deepbook-margin) with Tide Protocol's Self-Paying Loans feature. The integration aims to:

1. **Increase lending capacity** via DeepBook liquidity pools
2. **Enable capital-free liquidations** via flash loans
3. **Implement dynamic interest rates** based on utilization
4. **Add DEEP token rewards** for Tide backers

**Key Benefits:**
- 10x+ increase in lending capacity
- Faster, more efficient liquidations
- Market-driven interest rates
- Additional yield for backers
- First-mover advantage as early DeepBook Margin adopter

---

## Table of Contents

1. [Background](#1-background)
2. [Integration Architecture](#2-integration-architecture)
3. [Phase 1: Flash Loan Liquidations](#3-phase-1-flash-loan-liquidations)
4. [Phase 2: Dynamic Interest Rates](#4-phase-2-dynamic-interest-rates)
5. [Phase 3: Hybrid Liquidity](#5-phase-3-hybrid-liquidity)
6. [Phase 4: DEEP Token Rewards](#6-phase-4-deep-token-rewards)
7. [Phase 5: Margin Trading Extension](#7-phase-5-margin-trading-extension)
8. [Technical Implementation](#8-technical-implementation)
9. [Risk Analysis](#9-risk-analysis)
10. [Testing Requirements](#10-testing-requirements)
11. [Deployment Plan](#11-deployment-plan)
12. [Appendix](#12-appendix)

---

## 1. Background

### 1.1 Current Tide Loans Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CURRENT TIDE LOANS (v2)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────┐      ┌─────────────┐      ┌─────────────┐               │
│   │ SupporterPass│ ───▶ │  LoanVault  │ ───▶ │    SUI      │               │
│   │ (collateral) │      │ (treasury   │      │  (to user)  │               │
│   └──────────────┘      │  liquidity) │      └─────────────┘               │
│                         └──────┬──────┘                                     │
│                                │                                             │
│   ┌──────────────┐             │                                             │
│   │   Rewards    │ ───────────▶│ (auto-repay)                               │
│   │ (from pass)  │             │                                             │
│   └──────────────┘             ▼                                             │
│                         ┌─────────────┐                                      │
│                         │  Repayment  │                                      │
│                         └─────────────┘                                      │
│                                                                              │
│   LIMITATIONS:                                                               │
│   • Liquidity capped by treasury allocation                                 │
│   • Fixed 5% APR (not market-driven)                                        │
│   • Liquidators need upfront capital                                        │
│   • Single yield source (SUI only)                                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 DeepBook V3 Overview

DeepBook V3 is Sui's native decentralized central limit order book (CLOB):

| Feature | Description |
|---------|-------------|
| **Order Book** | Fully on-chain order matching |
| **Flash Loans** | Borrow assets within single transaction |
| **DEEP Token** | Native token for fees, staking, governance |
| **Low Latency** | Leverages Sui's parallel execution |
| **SDK** | TypeScript + Rust SDKs available |

**Source:** [DeepBook V3 Repository](https://github.com/MystenLabs/deepbookv3)

### 1.3 DeepBook Margin Overview

DeepBook Margin extends DeepBook with leveraged trading:

| Feature | Description |
|---------|-------------|
| **Leveraged Positions** | Trade with borrowed funds |
| **Collateral Flexibility** | Multiple asset types supported |
| **Liquidation Engine** | Built-in on-chain liquidation |
| **Interest Accrual** | Transparent utilization-based rates |
| **Risk Management** | Maintenance margin requirements |

**Source:** [DeepBook Margin Documentation](https://docs.sui.io/standards/deepbook-margin)

---

## 2. Integration Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     TIDE + DEEPBOOK INTEGRATION                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌───────────────────────────────────────────────────────────────────────┐ │
│   │                          TIDE PROTOCOL                                 │ │
│   │                                                                        │ │
│   │  ┌──────────────┐    ┌─────────────┐    ┌────────────────────────┐   │ │
│   │  │ SupporterPass│───▶│  LoanVault  │───▶│ DeepBookAdapter (NEW) │   │ │
│   │  │ (collateral) │    │             │    │                        │   │ │
│   │  └──────────────┘    └──────┬──────┘    └───────────┬────────────┘   │ │
│   │                             │                       │                 │ │
│   │                             │                       │                 │ │
│   │                             ▼                       ▼                 │ │
│   │                      ┌─────────────────────────────────────┐         │ │
│   │                      │         DeepBookBridge (NEW)        │         │ │
│   │                      │  • Flash loan requests              │         │ │
│   │                      │  • Liquidity sourcing               │         │ │
│   │                      │  • Interest rate queries            │         │ │
│   │                      └─────────────────┬───────────────────┘         │ │
│   │                                        │                              │ │
│   └────────────────────────────────────────┼──────────────────────────────┘ │
│                                            │                                 │
│   ┌────────────────────────────────────────┼──────────────────────────────┐ │
│   │                         DEEPBOOK V3    │                               │ │
│   │                                        ▼                               │ │
│   │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐               │ │
│   │  │    Pool     │    │  Balance    │    │   Margin    │               │ │
│   │  │ (SUI/USDC)  │    │  Manager    │    │  Manager    │               │ │
│   │  └─────────────┘    └─────────────┘    └─────────────┘               │ │
│   │                                                                        │ │
│   │  Features Used:                                                        │ │
│   │  • Flash loans (Phase 1)                                              │ │
│   │  • Liquidity pools (Phase 3)                                          │ │
│   │  • Interest rate oracles (Phase 2)                                    │ │
│   │  • DEEP token integration (Phase 4)                                   │ │
│   │                                                                        │ │
│   └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 New Modules

| Module | Package | Purpose |
|--------|---------|---------|
| `deepbook_bridge.move` | `tide_loans` | Bridge to DeepBook for flash loans, liquidity |
| `flash_liquidator.move` | `tide_loans` | Capital-free liquidation using flash loans |
| `dynamic_rates.move` | `tide_loans` | Utilization-based interest rate calculation |
| `deep_rewards.move` | `tide_core` | DEEP token distribution to backers |

### 2.3 Package Dependencies

```toml
# contracts/loans/Move.toml
[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/mainnet" }
tide_core = { local = "../core" }
deepbook = { git = "https://github.com/MystenLabs/deepbookv3", subdir = "packages/deepbook", rev = "main" }

# Optional for Phase 5
deepbook_margin = { git = "https://github.com/MystenLabs/deepbookv3", subdir = "packages/deepbook_margin", rev = "main" }
```

---

## 3. Phase 1: Flash Loan Liquidations

### 3.1 Overview

Enable capital-free liquidations using DeepBook's flash loan feature.

**Current Flow:**
1. Liquidator needs upfront capital
2. Calls `liquidate()` with payment
3. Receives collateral (SupporterPass)
4. Sells on secondary market
5. Keeps profit

**New Flow with Flash Loans:**
1. Liquidator calls `flash_liquidate()` with NO capital
2. Contract flash borrows from DeepBook
3. Uses borrowed funds to liquidate
4. Sells SupporterPass on Tide Marketplace
5. Repays flash loan + fee
6. Liquidator keeps profit

### 3.2 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      FLASH LOAN LIQUIDATION FLOW                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐                                                            │
│  │ Liquidator  │ calls flash_liquidate()                                   │
│  │ (no capital)│                                                            │
│  └──────┬──────┘                                                            │
│         │                                                                    │
│         ▼                                                                    │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ Step 1: Flash Borrow from DeepBook                              │       │
│  │                                                                  │       │
│  │ deepbook::pool::flash_loan(pool, loan_amount)                   │       │
│  │ → Returns: FlashLoan { coin: Coin<SUI>, ... }                   │       │
│  └────────────────────────────┬────────────────────────────────────┘       │
│                               │                                             │
│                               ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ Step 2: Liquidate Tide Loan                                     │       │
│  │                                                                  │       │
│  │ loan_vault::liquidate(vault, loan_id, borrowed_sui)             │       │
│  │ → Returns: SupporterPass                                        │       │
│  └────────────────────────────┬────────────────────────────────────┘       │
│                               │                                             │
│                               ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ Step 3: Sell SupporterPass                                      │       │
│  │                                                                  │       │
│  │ marketplace::instant_sell(pass) OR                              │       │
│  │ liquidator takes pass (if profitable)                           │       │
│  │ → Returns: Coin<SUI> (proceeds)                                 │       │
│  └────────────────────────────┬────────────────────────────────────┘       │
│                               │                                             │
│                               ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ Step 4: Repay Flash Loan                                        │       │
│  │                                                                  │       │
│  │ deepbook::pool::repay_flash_loan(pool, flash_loan, proceeds)    │       │
│  │ → Must repay: loan_amount + flash_fee                           │       │
│  └────────────────────────────┬────────────────────────────────────┘       │
│                               │                                             │
│                               ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ Step 5: Profit to Liquidator                                    │       │
│  │                                                                  │       │
│  │ profit = proceeds - loan_amount - flash_fee                     │       │
│  │ transfer::public_transfer(profit, liquidator)                   │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Technical Specification

#### 3.3.1 FlashLiquidator Module

```move
module tide_loans::flash_liquidator;

use sui::coin::Coin;
use sui::sui::SUI;
use deepbook::pool::{Pool, FlashLoan};
use tide_loans::loan_vault::LoanVault;
use tide_marketplace::marketplace::MarketplaceConfig;
use tide_core::listing::Listing;
use tide_core::capital_vault::CapitalVault;

// === Errors ===
const EUnprofitableLiquidation: u64 = 1;
const ELoanStillHealthy: u64 = 2;
const EInsufficientProceeds: u64 = 3;

// === Events ===

public struct FlashLiquidationExecuted has copy, drop {
    loan_id: ID,
    liquidator: address,
    loan_amount: u64,
    flash_fee: u64,
    proceeds: u64,
    profit: u64,
    epoch: u64,
}

// === Core Functions ===

/// Execute a flash loan liquidation with instant marketplace sale.
/// Liquidator needs NO upfront capital.
/// 
/// Requirements:
/// - Loan must be unhealthy (health factor < 1.0)
/// - Pass must be sellable on marketplace
/// - Sale proceeds must cover loan + flash fee
public fun flash_liquidate_and_sell(
    // Tide objects
    loan_vault: &mut LoanVault,
    loan_id: ID,
    listing: &Listing,
    capital_vault: &CapitalVault,
    marketplace_config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    // DeepBook objects
    pool: &mut Pool<SUI, USDC>,  // Or appropriate pool
    // Context
    ctx: &mut TxContext,
): Coin<SUI> {
    // 1. Calculate loan payoff amount
    let payoff_amount = loan_vault.outstanding_balance(loan_id);
    
    // 2. Flash borrow from DeepBook
    let (flash_loan, borrowed_coin) = pool.flash_loan(payoff_amount, ctx);
    
    // 3. Liquidate the Tide loan
    let pass = loan_vault.liquidate(
        loan_id,
        listing,
        capital_vault,
        borrowed_coin,
        ctx,
    );
    
    // 4. Sell pass on Tide Marketplace (instant sale)
    let (proceeds, _receipt, _change) = marketplace_config.instant_sell(
        treasury_vault,
        pass,
        ctx,
    );
    
    // 5. Repay flash loan
    let flash_fee = pool.flash_loan_fee(payoff_amount);
    let repayment = proceeds.split(payoff_amount + flash_fee, ctx);
    pool.repay_flash_loan(flash_loan, repayment);
    
    // 6. Verify profitable
    assert!(proceeds.value() > 0, EUnprofitableLiquidation);
    
    // 7. Emit event
    event::emit(FlashLiquidationExecuted {
        loan_id,
        liquidator: ctx.sender(),
        loan_amount: payoff_amount,
        flash_fee,
        proceeds: proceeds.value() + payoff_amount + flash_fee,
        profit: proceeds.value(),
        epoch: ctx.epoch(),
    });
    
    // 8. Return profit to liquidator
    proceeds
}

/// Flash liquidate but keep the SupporterPass.
/// Useful when liquidator wants the pass (for yield).
public fun flash_liquidate_and_keep(
    loan_vault: &mut LoanVault,
    loan_id: ID,
    listing: &Listing,
    capital_vault: &CapitalVault,
    pool: &mut Pool<SUI, USDC>,
    repayment_source: Coin<SUI>,  // User provides repayment funds
    ctx: &mut TxContext,
): SupporterPass {
    // Similar flow but user repays flash loan from their funds
    // and keeps the SupporterPass
    // ...
}

// === View Functions ===

/// Calculate expected profit from flash liquidation.
/// Returns None if liquidation would be unprofitable.
public fun estimate_profit(
    loan_vault: &LoanVault,
    loan_id: ID,
    pool: &Pool<SUI, USDC>,
    marketplace_config: &MarketplaceConfig,
): Option<u64> {
    let payoff = loan_vault.outstanding_balance(loan_id);
    let flash_fee = pool.flash_loan_fee(payoff);
    let collateral_value = loan_vault.collateral_value(loan_id);
    let marketplace_fee = marketplace_config.seller_fee_amount(collateral_value);
    
    let total_cost = payoff + flash_fee + marketplace_fee;
    
    if (collateral_value > total_cost) {
        option::some(collateral_value - total_cost)
    } else {
        option::none()
    }
}
```

#### 3.3.2 Required Marketplace Extension

Add `instant_sell` function to marketplace:

```move
// In tide_marketplace::marketplace

/// Instantly sell a SupporterPass at floor price.
/// Used for flash liquidations.
public fun instant_sell(
    config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    pass: SupporterPass,
    ctx: &mut TxContext,
): (Coin<SUI>, PurchaseReceipt, Coin<SUI>) {
    // Get floor price from existing listings or oracle
    let floor_price = config.get_floor_price(pass.listing_id());
    
    // Match with highest bid or lowest ask
    // ...
}
```

### 3.4 Benefits

| Metric | Before | After |
|--------|--------|-------|
| Capital Required | Full loan amount | 0 (gas only) |
| Liquidator Pool | Capital-rich only | Anyone |
| Time to Liquidate | Depends on capital | Instant |
| MEV Protection | Low | Higher (atomic) |

### 3.5 Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Flash loan fee spikes | Cap max fee, fallback to manual liquidation |
| DeepBook pool depletion | Use multiple pools, fallback to treasury |
| Sandwich attacks | Use private mempool or commit-reveal |
| Pass unsellable | Require minimum marketplace liquidity |

---

## 4. Phase 2: Dynamic Interest Rates

### 4.1 Overview

Replace fixed 5% APR with utilization-based rates inspired by DeepBook Margin.

### 4.2 Rate Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      UTILIZATION-BASED INTEREST RATES                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Interest                                                                    │
│  Rate (%)                                                                    │
│      │                                                                       │
│  25% │                                          ●●●●●●●                     │
│      │                                     ●●●●●                            │
│  20% │                                  ●●●                                 │
│      │                                ●●   (Jump Rate)                      │
│  15% │                              ●●                                      │
│      │                            ●●                                        │
│  10% │                          ●●                                          │
│      │                        ●●                                            │
│   5% │       ●●●●●●●●●●●●●●●●●                                              │
│      │   ●●●●                     (Kink at 80%)                             │
│   2% │ ●● (Base Rate)                                                       │
│      │                                                                       │
│      └──────────────────────────────────────────────────────────────────────│
│          0%     20%    40%    60%    80%    90%   100%                      │
│                          Utilization                                         │
│                                                                              │
│  Formula:                                                                    │
│  • If utilization ≤ 80%: rate = 2% + (utilization × 3.75%)                 │
│  • If utilization > 80%: rate = 5% + ((utilization - 80%) × 100%)          │
│                                                                              │
│  Examples:                                                                   │
│  • 50% utilization → 2% + (0.5 × 3.75%) = 3.875%                           │
│  • 80% utilization → 2% + (0.8 × 3.75%) = 5%                               │
│  • 90% utilization → 5% + (0.1 × 100%) = 15%                               │
│  • 95% utilization → 5% + (0.15 × 100%) = 20%                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.3 Technical Specification

```move
module tide_loans::dynamic_rates;

// === Constants ===

/// Base interest rate (2% = 200 bps)
const BASE_RATE_BPS: u64 = 200;

/// Optimal utilization (80% = 8000 bps)
const OPTIMAL_UTILIZATION_BPS: u64 = 8000;

/// Slope before kink (3.75% per 100% utilization = 375 bps)
const SLOPE_1_BPS: u64 = 375;

/// Slope after kink (100% per 20% utilization = 50000 bps per 10000)
const SLOPE_2_BPS: u64 = 50000;

/// Maximum rate cap (50% = 5000 bps)
const MAX_RATE_BPS: u64 = 5000;

// === Functions ===

/// Calculate current interest rate based on utilization.
public fun calculate_interest_rate(
    total_borrowed: u64,
    total_liquidity: u64,
): u64 {
    if (total_liquidity == 0) {
        return BASE_RATE_BPS
    };
    
    let utilization_bps = (total_borrowed * 10000) / total_liquidity;
    
    if (utilization_bps <= OPTIMAL_UTILIZATION_BPS) {
        // Below kink: gentle slope
        BASE_RATE_BPS + (utilization_bps * SLOPE_1_BPS / 10000)
    } else {
        // Above kink: steep slope
        let base_at_kink = BASE_RATE_BPS + (OPTIMAL_UTILIZATION_BPS * SLOPE_1_BPS / 10000);
        let excess_utilization = utilization_bps - OPTIMAL_UTILIZATION_BPS;
        let jump_rate = (excess_utilization * SLOPE_2_BPS) / 10000;
        
        let rate = base_at_kink + jump_rate;
        
        // Cap at maximum
        if (rate > MAX_RATE_BPS) {
            MAX_RATE_BPS
        } else {
            rate
        }
    }
}

/// Calculate interest accrued over time period.
public fun calculate_accrued_interest(
    principal: u64,
    rate_bps: u64,
    time_elapsed_ms: u64,
): u64 {
    // interest = principal × rate × time
    // time in years = time_elapsed_ms / (365.25 × 24 × 60 × 60 × 1000)
    let ms_per_year: u128 = 31557600000; // 365.25 days
    
    let interest = ((principal as u128) * (rate_bps as u128) * (time_elapsed_ms as u128))
        / (10000 * ms_per_year);
    
    (interest as u64)
}

/// Get utilization ratio.
public fun get_utilization_bps(vault: &LoanVault): u64 {
    let liquidity = vault.total_liquidity();
    if (liquidity == 0) {
        return 0
    };
    (vault.total_borrowed() * 10000) / liquidity
}
```

### 4.4 Integration with LoanVault

Update `loan_vault.move` to use dynamic rates:

```move
// In loan_vault.move

/// Accrue interest on a loan using current dynamic rate.
public(package) fun accrue_interest(
    vault: &mut LoanVault,
    loan: &mut Loan,
    ctx: &TxContext,
) {
    let current_rate = dynamic_rates::calculate_interest_rate(
        vault.total_borrowed,
        vault.liquidity.value() + vault.total_borrowed,
    );
    
    let elapsed = ctx.epoch_timestamp_ms() - loan.last_update;
    let new_interest = dynamic_rates::calculate_accrued_interest(
        loan.outstanding_balance(),
        current_rate,
        elapsed,
    );
    
    loan.interest_accrued = loan.interest_accrued + new_interest;
    loan.last_update = ctx.epoch_timestamp_ms();
}
```

### 4.5 Benefits

| Aspect | Fixed Rate | Dynamic Rate |
|--------|------------|--------------|
| Capital Efficiency | Low (rate doesn't adapt) | High (incentivizes balance) |
| Borrower Cost | Fixed 5% always | Low when utilization low |
| Lender Yield | Fixed 5% always | High when utilization high |
| Market Alignment | None | Follows supply/demand |

---

## 5. Phase 3: Hybrid Liquidity

### 5.1 Overview

Source additional lending liquidity from DeepBook pools when Tide treasury is insufficient.

### 5.2 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         HYBRID LIQUIDITY MODEL                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  User requests: 1000 SUI loan                                               │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ LoanVault Liquidity Check                                       │       │
│  │                                                                  │       │
│  │ Tide Treasury: 200 SUI available                                │       │
│  │ Shortfall: 800 SUI needed                                       │       │
│  └────────────────────────────┬────────────────────────────────────┘       │
│                               │                                             │
│                               ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ DeepBook Liquidity Bridge                                       │       │
│  │                                                                  │       │
│  │ 1. Query DeepBook pools for best rate                           │       │
│  │ 2. Borrow 800 SUI from DeepBook                                 │       │
│  │ 3. Combine with Tide's 200 SUI                                  │       │
│  │ 4. Issue loan to user                                           │       │
│  └────────────────────────────┬────────────────────────────────────┘       │
│                               │                                             │
│                               ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ Loan Record                                                      │       │
│  │                                                                  │       │
│  │ • Total Principal: 1000 SUI                                     │       │
│  │ • Tide Portion: 200 SUI (earns Tide rate)                       │       │
│  │ • DeepBook Portion: 800 SUI (earns DB rate)                     │       │
│  │ • Blended Rate: weighted average                                │       │
│  └────────────────────────────┬────────────────────────────────────┘       │
│                               │                                             │
│                               ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ Repayment Distribution                                          │       │
│  │                                                                  │       │
│  │ When rewards come in:                                           │       │
│  │ 1. Pay DeepBook interest first (priority)                       │       │
│  │ 2. Pay DeepBook principal                                       │       │
│  │ 3. Pay Tide interest                                            │       │
│  │ 4. Pay Tide principal                                           │       │
│  │                                                                  │       │
│  │ → DeepBook gets repaid faster (reduces external debt)           │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.3 Technical Specification

```move
module tide_loans::deepbook_bridge;

use deepbook::pool::Pool;
use deepbook::balance_manager::BalanceManager;
use sui::coin::Coin;
use sui::sui::SUI;

// === Structs ===

/// Tracks liquidity borrowed from DeepBook
public struct DeepBookLoan has store {
    pool_id: ID,
    principal: u64,
    interest_accrued: u64,
    borrowed_at: u64,
    rate_at_borrow: u64,
}

/// Bridge configuration
public struct BridgeConfig has store {
    /// Maximum amount to borrow from DeepBook
    max_deepbook_exposure: u64,
    /// Preferred pools in order
    preferred_pools: vector<ID>,
    /// Minimum spread over DeepBook rate
    min_spread_bps: u64,
    /// Whether bridge is enabled
    enabled: bool,
}

// === Functions ===

/// Borrow liquidity from DeepBook to supplement Tide treasury.
public fun borrow_from_deepbook(
    vault: &mut LoanVault,
    pool: &mut Pool<SUI, USDC>,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(vault.bridge_config.enabled, EBridgeDisabled);
    assert!(
        vault.deepbook_exposure() + amount <= vault.bridge_config.max_deepbook_exposure,
        EExceedsMaxExposure,
    );
    
    // Get current DeepBook borrow rate
    let db_rate = pool.borrow_rate();
    
    // Borrow from DeepBook
    let borrowed = pool.borrow(amount, ctx);
    
    // Record the loan
    let db_loan = DeepBookLoan {
        pool_id: object::id(pool),
        principal: amount,
        interest_accrued: 0,
        borrowed_at: ctx.epoch_timestamp_ms(),
        rate_at_borrow: db_rate,
    };
    
    vault.deepbook_loans.push_back(db_loan);
    
    borrowed
}

/// Repay DeepBook loan when Tide loan is repaid.
public fun repay_to_deepbook(
    vault: &mut LoanVault,
    pool: &mut Pool<SUI, USDC>,
    amount: Coin<SUI>,
    ctx: &mut TxContext,
) {
    // Find matching DeepBook loan
    // Apply payment
    // ...
}

/// Calculate blended interest rate for a loan.
public fun calculate_blended_rate(
    tide_portion: u64,
    tide_rate: u64,
    deepbook_portion: u64,
    deepbook_rate: u64,
): u64 {
    let total = tide_portion + deepbook_portion;
    if (total == 0) {
        return 0
    };
    
    let weighted = ((tide_portion as u128) * (tide_rate as u128)
        + (deepbook_portion as u128) * (deepbook_rate as u128))
        / (total as u128);
    
    (weighted as u64)
}
```

### 5.4 Benefits

| Metric | Treasury Only | Hybrid |
|--------|---------------|--------|
| Max Lending Capacity | Treasury allocation | Essentially unlimited |
| Capital Efficiency | Low | High |
| Rate Competitiveness | Fixed | Market-competitive |
| Risk Diversification | Concentrated | Distributed |

---

## 6. Phase 4: DEEP Token Rewards

### 6.1 Overview

Distribute DEEP tokens to Tide backers as additional yield.

### 6.2 DEEP Acquisition Methods

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DEEP TOKEN ACQUISITION                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Method 1: Trading Volume Rebates                                           │
│  ─────────────────────────────────                                          │
│  • Tide routes trades through DeepBook                                      │
│  • Earns maker rebates in DEEP                                              │
│  • Rebates distributed to backers                                           │
│                                                                              │
│  Method 2: Protocol Partnership                                              │
│  ──────────────────────────────                                             │
│  • Partner with DeepBook for integration grant                              │
│  • Receive DEEP allocation for user incentives                              │
│  • Distribute to active Tide users                                          │
│                                                                              │
│  Method 3: Liquidity Mining                                                  │
│  ─────────────────────────────                                              │
│  • Stake Tide's DeepBook liquidity in their pools                           │
│  • Earn DEEP from liquidity mining                                          │
│  • Distribute to backers proportionally                                      │
│                                                                              │
│  Method 4: Direct Purchase                                                   │
│  ────────────────────────────                                               │
│  • Tide treasury buys DEEP                                                  │
│  • Uses as additional backer rewards                                        │
│  • Aligns Tide with DeepBook ecosystem                                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 6.3 Technical Specification

```move
module tide_core::deep_rewards;

use sui::coin::Coin;
use deepbook::deep::DEEP;

// === Structs ===

/// DEEP reward distribution configuration
public struct DeepRewardsConfig has key {
    id: UID,
    /// Total DEEP accumulated for distribution
    pending_deep: Balance<DEEP>,
    /// Distribution rate (per epoch)
    distribution_rate_bps: u64,
    /// Last distribution epoch
    last_distribution_epoch: u64,
    /// Total DEEP distributed lifetime
    total_distributed: u64,
}

/// Tracks DEEP rewards for a listing
public struct ListingDeepRewards has store {
    listing_id: ID,
    accumulated_deep: u64,
    deep_per_share: u128,  // Cumulative, similar to SUI rewards
    last_update: u64,
}

// === Functions ===

/// Deposit DEEP tokens for distribution to backers.
public fun deposit_deep(
    config: &mut DeepRewardsConfig,
    deep: Coin<DEEP>,
    ctx: &TxContext,
) {
    let amount = deep.value();
    config.pending_deep.join(deep.into_balance());
    
    event::emit(DeepDeposited {
        amount,
        new_balance: config.pending_deep.value(),
        depositor: ctx.sender(),
        epoch: ctx.epoch(),
    });
}

/// Distribute DEEP rewards to a listing's reward pool.
public fun distribute_deep_to_listing(
    config: &mut DeepRewardsConfig,
    listing_rewards: &mut ListingDeepRewards,
    capital_vault: &CapitalVault,
    amount: u64,
    ctx: &mut TxContext,
): Coin<DEEP> {
    let deep = config.pending_deep.split(amount);
    
    // Update cumulative index
    let total_shares = capital_vault.total_shares();
    if (total_shares > 0) {
        listing_rewards.deep_per_share = listing_rewards.deep_per_share 
            + (((amount as u128) * PRECISION) / total_shares);
    };
    
    listing_rewards.accumulated_deep = listing_rewards.accumulated_deep + amount;
    listing_rewards.last_update = ctx.epoch_timestamp_ms();
    
    coin::from_balance(deep, ctx)
}

/// Claim DEEP rewards for a SupporterPass holder.
public fun claim_deep(
    listing_rewards: &ListingDeepRewards,
    pass: &mut SupporterPass,
    ctx: &mut TxContext,
): Coin<DEEP> {
    let claimable = calculate_deep_claimable(listing_rewards, pass);
    
    // Update pass cursor (similar to SUI claim)
    pass.deep_claim_index = listing_rewards.deep_per_share;
    
    // Transfer DEEP to holder
    // ...
}
```

### 6.4 Benefits

| For | Benefit |
|-----|---------|
| **Backers** | Additional yield in DEEP token |
| **Tide** | Differentiated value proposition |
| **DeepBook** | Ecosystem growth, volume increase |
| **Marketing** | "Earn SUI + DEEP from your investment" |

---

## 7. Phase 5: Margin Trading Extension

### 7.1 Overview

Advanced integration allowing SupporterPass collateral to enable margin trading on DeepBook.

**Warning:** This is high-complexity and should only be considered after Phases 1-4 are stable.

### 7.2 Concept

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      MARGIN TRADING WITH SUPPORTERPASS                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  User Flow:                                                                  │
│                                                                              │
│  1. User deposits SupporterPass to Tide LoanVault                           │
│  2. User borrows SUI (standard self-paying loan)                            │
│  3. User deposits borrowed SUI to DeepBook BalanceManager                   │
│  4. User opens leveraged position on DeepBook                               │
│                                                                              │
│  ┌──────────────┐    ┌─────────────┐    ┌─────────────┐    ┌────────────┐ │
│  │SupporterPass │───▶│ Tide Loan   │───▶│  DeepBook   │───▶│  Margin    │ │
│  │ (100 SUI)    │    │ (50 SUI)    │    │ (50 SUI)    │    │  Trading   │ │
│  └──────────────┘    └─────────────┘    └─────────────┘    │  (2x-5x)   │ │
│                                                             └────────────┘ │
│                                                                              │
│  Example:                                                                    │
│  • Collateral: 100 SUI (SupporterPass)                                      │
│  • Borrow: 50 SUI (50% LTV)                                                 │
│  • Deposit to DeepBook: 50 SUI                                              │
│  • Open 3x long: 150 SUI exposure                                           │
│  • Total leverage: 1.5x on original 100 SUI                                 │
│                                                                              │
│  Repayment:                                                                  │
│  • Pass rewards auto-repay Tide loan                                        │
│  • Trading profits/losses separate                                          │
│  • If trading profitable: extra yield                                       │
│  • If trading losses: may need to top up or face Tide liquidation          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 7.3 Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Cascading Liquidations | High | Separate risk management |
| Complexity | High | Extensive testing |
| User Education | High | Clear documentation |
| Smart Contract Risk | High | Audits, gradual rollout |

### 7.4 Recommendation

**Defer Phase 5** until:
1. Phases 1-4 are production-stable for 6+ months
2. DeepBook Margin matures
3. User demand validates the feature
4. Dedicated audit for margin integration

---

## 8. Technical Implementation

### 8.1 Package Structure

```
contracts/loans/
├── Move.toml
├── sources/
│   ├── loan_vault.move          # Core (existing)
│   ├── flash_liquidator.move    # Phase 1: Flash loans
│   ├── dynamic_rates.move       # Phase 2: Utilization rates
│   ├── deepbook_bridge.move     # Phase 3: Hybrid liquidity
│   └── deep_rewards.move        # Phase 4: DEEP tokens
└── tests/
    ├── loan_vault_tests.move
    ├── flash_liquidator_tests.move
    ├── dynamic_rates_tests.move
    ├── deepbook_bridge_tests.move
    └── integration_tests.move
```

### 8.2 Dependencies

```toml
[package]
name = "tide_loans"
version = "2.0.0"
edition = "2024.beta"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/mainnet" }
tide_core = { local = "../core" }
tide_marketplace = { local = "../marketplace" }

# DeepBook dependencies
deepbook = { git = "https://github.com/MystenLabs/deepbookv3", subdir = "packages/deepbook", rev = "main" }

# Optional: Uncomment for Phase 5
# deepbook_margin = { git = "https://github.com/MystenLabs/deepbookv3", subdir = "packages/deepbook_margin", rev = "main" }

[addresses]
tide_loans = "0x0"
```

### 8.3 Key DeepBook Functions to Use

| DeepBook Function | Tide Usage |
|-------------------|------------|
| `pool::flash_loan()` | Phase 1: Borrow for liquidation |
| `pool::repay_flash_loan()` | Phase 1: Repay after liquidation |
| `pool::borrow_rate()` | Phase 2: Get market rate |
| `balance_manager::deposit()` | Phase 3: Deposit for borrowing |
| `balance_manager::withdraw()` | Phase 3: Withdraw after repay |
| `deep::transfer()` | Phase 4: Distribute DEEP rewards |

---

## 9. Risk Analysis

### 9.1 Smart Contract Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| DeepBook integration bug | Medium | High | Audit, testing, gradual rollout |
| Flash loan exploit | Low | Critical | Reentrancy guards, invariant checks |
| Interest miscalculation | Low | Medium | Extensive unit tests |
| Liquidity crunch | Medium | Medium | Exposure limits, fallbacks |

### 9.2 Economic Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| DeepBook rate spikes | Medium | Medium | Rate caps, circuit breakers |
| DEEP token volatility | High | Low | Only use for bonus rewards |
| Arbitrage against Tide | Medium | Medium | Align rates with market |
| Liquidity fragmentation | Low | Low | Primary liquidity stays in Tide |

### 9.3 Operational Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| DeepBook downtime | Low | High | Fallback to treasury-only mode |
| Keeper failures | Medium | Low | Redundant keepers |
| Admin key compromise | Low | Critical | Multisig, timelocks |

---

## 10. Testing Requirements

### 10.1 Unit Tests

**Phase 1: Flash Liquidations**
- [ ] `test_flash_liquidate_profitable`
- [ ] `test_flash_liquidate_unprofitable_fails`
- [ ] `test_flash_liquidate_healthy_loan_fails`
- [ ] `test_flash_loan_repayment`
- [ ] `test_estimate_profit_accuracy`

**Phase 2: Dynamic Rates**
- [ ] `test_rate_at_zero_utilization`
- [ ] `test_rate_at_optimal_utilization`
- [ ] `test_rate_above_optimal_utilization`
- [ ] `test_rate_at_max_utilization`
- [ ] `test_rate_cap`
- [ ] `test_interest_accrual_with_dynamic_rate`

**Phase 3: Hybrid Liquidity**
- [ ] `test_borrow_from_deepbook`
- [ ] `test_repay_to_deepbook`
- [ ] `test_blended_rate_calculation`
- [ ] `test_exposure_limits`
- [ ] `test_waterfall_repayment`

**Phase 4: DEEP Rewards**
- [ ] `test_deposit_deep`
- [ ] `test_distribute_deep_to_listing`
- [ ] `test_claim_deep`
- [ ] `test_deep_per_share_calculation`

### 10.2 Integration Tests

- [ ] Full flash liquidation with real DeepBook pool
- [ ] Borrow → harvest → repay with dynamic rates
- [ ] Hybrid loan with both Tide and DeepBook liquidity
- [ ] DEEP reward distribution across multiple backers

### 10.3 Stress Tests

- [ ] High utilization scenario (>95%)
- [ ] Multiple concurrent flash liquidations
- [ ] DeepBook pool depletion handling
- [ ] Rate spike handling

---

## 11. Deployment Plan

### 11.1 Timeline

| Phase | Duration | Status |
|-------|----------|--------|
| Phase 1: Flash Liquidations | 2-3 weeks | 📋 Planned |
| Phase 2: Dynamic Rates | 1-2 weeks | 📋 Planned |
| Phase 3: Hybrid Liquidity | 3-4 weeks | 📋 Planned |
| Phase 4: DEEP Rewards | 2-3 weeks | 📋 Planned |
| Phase 5: Margin Trading | 8+ weeks | 🔮 Future |

### 11.2 Rollout Strategy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DEPLOYMENT ROLLOUT                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Week 1-2: Development                                                       │
│  ├── Implement flash_liquidator.move                                        │
│  ├── Write unit tests                                                        │
│  └── Internal review                                                         │
│                                                                              │
│  Week 3: Testnet                                                             │
│  ├── Deploy to Sui testnet                                                   │
│  ├── Integration testing with DeepBook testnet pools                        │
│  └── Community testing (testnet)                                             │
│                                                                              │
│  Week 4: Audit                                                               │
│  ├── External audit (incremental)                                           │
│  ├── Fix findings                                                            │
│  └── Re-test                                                                 │
│                                                                              │
│  Week 5: Mainnet (Gradual)                                                   │
│  ├── Day 1-3: Deploy with low limits (10 SUI max flash loan)               │
│  ├── Day 4-7: Monitor, increase limits if stable                            │
│  └── Week 2+: Full rollout if no issues                                     │
│                                                                              │
│  Repeat for each phase...                                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 11.3 Feature Flags

```move
// In loan_vault.move

public struct LoanVault has key {
    // ... existing fields ...
    
    // Feature flags
    flash_liquidation_enabled: bool,
    dynamic_rates_enabled: bool,
    deepbook_bridge_enabled: bool,
    deep_rewards_enabled: bool,
}

// Admin functions to toggle features
public fun enable_flash_liquidations(vault: &mut LoanVault, admin_cap: &AdminCap) { ... }
public fun disable_flash_liquidations(vault: &mut LoanVault, admin_cap: &AdminCap) { ... }
// etc.
```

---

## 12. Appendix

### A. DeepBook V3 Resources

| Resource | Link |
|----------|------|
| Documentation | https://docs.sui.io/standards/deepbook |
| Margin Documentation | https://docs.sui.io/standards/deepbook-margin |
| GitHub Repository | https://github.com/MystenLabs/deepbookv3 |
| DeepBook Package | https://github.com/MystenLabs/deepbookv3/tree/main/packages/deepbook |
| Margin Package | https://github.com/MystenLabs/deepbookv3/tree/main/packages/deepbook_margin |

### B. Glossary

| Term | Definition |
|------|------------|
| **Flash Loan** | Borrow and repay in same transaction |
| **Utilization** | total_borrowed / total_liquidity |
| **Kink** | Utilization point where rate curve steepens |
| **DEEP** | DeepBook's native token |
| **BalanceManager** | DeepBook object for managing user funds |
| **LTV** | Loan-to-Value ratio |

### C. Estimated Gas Costs

| Operation | Estimated Gas |
|-----------|---------------|
| Flash Liquidation (simple) | ~100M MIST |
| Flash Liquidation (with sale) | ~200M MIST |
| Borrow with DeepBook liquidity | ~150M MIST |
| Claim DEEP rewards | ~50M MIST |

### D. Comparison with Competitors

| Feature | Tide + DeepBook | Aave | Compound | NFTfi |
|---------|-----------------|------|----------|-------|
| NFT Collateral | ✅ | ❌ | ❌ | ✅ |
| Self-Paying | ✅ | ❌ | ❌ | ❌ |
| Flash Liquidations | ✅ (Phase 1) | ✅ | ✅ | ❌ |
| Dynamic Rates | ✅ (Phase 2) | ✅ | ✅ | ❌ |
| Multi-Token Rewards | ✅ (Phase 4) | ✅ | ✅ | ❌ |
| Sui Native | ✅ | ❌ | ❌ | ❌ |

---

## Approval

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Author | | | |
| Technical Review | | | |
| Security Review | | | |
| Product Approval | | | |

---

**Next Steps:**
1. Review this specification
2. Prioritize phases
3. Begin Phase 1 implementation
4. Coordinate with DeepBook team for integration support
