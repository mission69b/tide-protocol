# DeepBook Integration Specification

> **Version:** v1.0
> **Status:** 📝 DRAFT
> **Author:** Tide Protocol
> **Last Updated:** January 2026

## Executive Summary

This specification outlines the integration of [DeepBook V3](https://docs.sui.io/standards/deepbook) and [DeepBook Margin](https://docs.sui.io/standards/deepbook-margin) with Tide Protocol's Self-Paying Loans feature.

### Simplified Roadmap (3 Phases)

| Phase | Feature | User Impact | Timeline |
|-------|---------|-------------|----------|
| **1** | **DeepBook Integration** | Market rates + 10x capacity | 2-3 weeks |
| **2** | **Flash Liquidations** | Capital-efficient liquidations | 1 week |
| **3** | **DEEP Token Rewards** | Bonus yield for backers | 1-2 weeks |

**Total: 4-6 weeks** (reduced from 10+ weeks)

### Key Benefits

| Benefit | Impact |
|---------|--------|
| **10x+ lending capacity** | DeepBook liquidity via BalanceManager |
| **Market-driven interest rates** | Use DeepBook rates directly (no custom curves) |
| **Capital-efficient liquidations** | Flash loans reduce liquidator capital needs |
| **Additional yield** | DEEP tokens for backers (simplified distribution) |
| **Minimal code** | ~300 LOC total (down from ~800 LOC) |
| **Fast to ship** | 4-6 weeks (down from 10+ weeks) |

### What We Removed (Simplifications)

| Removed | Reason |
|---------|--------|
| Custom rate curves | Use DeepBook's `borrow_rate()` directly |
| Marketplace bid system | Deferred (Flash + Keep is sufficient) |
| Flash Liquidate + Sell | Deferred (requires bid system) |
| Complex DEEP tracking | Simplified to epoch-based snapshots |
| Margin trading | Removed (too complex, high risk) |

---

## Table of Contents

1. [Background](#1-background)
2. [Integration Architecture](#2-integration-architecture)
3. [Phase 1: DeepBook Integration](#3-phase-1-deepbook-integration) ⭐ (Overview + Rates)
4. [Phase 2: Flash Liquidations](#4-phase-2-flash-liquidations)
5. [Phase 1 (continued): DeepBook Liquidity](#5-phase-1-continued-deepbook-liquidity) (Technical Details)
6. [Phase 3: DEEP Token Rewards](#6-phase-3-deep-token-rewards-simplified)
7. [Removed/Deferred Features](#7-removeddeferred-features)
8. [Technical Implementation](#8-technical-implementation)
9. [Risk Analysis](#9-risk-analysis)
10. [Testing Requirements](#10-testing-requirements-simplified)
11. [Deployment Plan](#11-deployment-plan-simplified)
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

**Core Objects (from [DeepBook V3 Design](https://docs.sui.io/standards/deepbookv3/design)):**

| Object | Purpose |
|--------|---------|
| **Pool** | Shared object managing order book, users, stakes for one market |
| **PoolRegistry** | Prevents duplicate pools, manages versioning |
| **BalanceManager** | Sources user funds across all pools (single instance per user) |

**Pool Internal Architecture:**
```
Pool
├── Book     (order matching, BigVector for bids/asks)
├── State    (Governance, History, Account)
└── Vault    (balance settlement, DeepPrice conversion)
```

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
│   │  Features Used (Priority Order):                                      │ │
│   │  • Interest rate oracles (Phase 1) ⭐ HIGH VALUE                      │ │
│   │  • Liquidity pools (Phase 2) ⭐ HIGH VALUE                            │ │
│   │  • Flash loans (Phase 3)                                              │ │
│   │  • DEEP token integration (Phase 4)                                   │ │
│   │                                                                        │ │
│   └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 New Modules (Simplified)

| Module | Package | Phase | Purpose |
|--------|---------|-------|---------|
| `lending_pool.move` | `tide_loans` | Phase 1 | DeepBook BalanceManager + rates |
| `flash_liquidator.move` | `tide_loans` | Phase 2 | Flash loan liquidations (keep only) |
| `deep_rewards.move` | `tide_core` | Phase 3 | DEEP distribution (epoch-based) |

**Removed:**
- ~~`dynamic_rates.move`~~ — Use DeepBook's `borrow_rate()` directly
- ~~`buy_order.move`~~ — Deferred (bid system not needed for Phase 2)

### 2.3 Package Dependencies

```toml
# contracts/loans/Move.toml
[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/mainnet" }
tide_core = { local = "../core" }
deepbook = { git = "https://github.com/MystenLabs/deepbookv3", subdir = "packages/deepbook", rev = "main" }
```

---

## 3. Phase 1: DeepBook Integration ⭐

### 3.1 Overview

Integrate with DeepBook V3 for:
1. **Liquidity** — Use BalanceManager as the single fund source
2. **Interest Rates** — Use DeepBook's market rates directly (no custom curves)

This combines the original "Dynamic Rates" and "Hybrid Liquidity" phases into one simpler integration.

### 3.2 Why Use DeepBook Rates Directly?

| Approach | Complexity | Code | Maintenance |
|----------|------------|------|-------------|
| Custom rate curves | High | ~100 LOC | Update curves manually |
| **DeepBook rates** | **Low** | **1 LOC** | **Market-driven, automatic** |

```move
// Instead of custom calculation, just call DeepBook
public fun get_interest_rate(pool: &Pool<SUI, USDC>): u64 {
    pool::borrow_rate(pool)
}
```

### 3.3 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│               PHASE 1: DEEPBOOK INTEGRATION ARCHITECTURE                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌────────────┐                                                            │
│   │   Tide     │                                                            │
│   │  Treasury  │                                                            │
│   └──────┬─────┘                                                            │
│          │ deposit_liquidity()                                              │
│          ▼                                                                   │
│   ┌──────────────────────────────────────────────────────────────┐         │
│   │              TideLendingPool (tide_loans)                     │         │
│   │                                                               │         │
│   │   ┌─────────────────────────────────────────────────────┐    │         │
│   │   │     DeepBook BalanceManager (single fund source)     │    │         │
│   │   │                                                      │    │         │
│   │   │   • treasury_deposit: u64                           │    │         │
│   │   │   • outstanding: u64                                 │    │         │
│   │   │   • max_exposure: u64                               │    │         │
│   │   └─────────────────────────────────────────────────────┘    │         │
│   └────────┬──────────────────────────────────────────┬──────────┘         │
│            │ borrow()                                  │                    │
│            ▼                                           │ get_rate()         │
│   ┌────────────────┐                                   │                    │
│   │   Borrower     │                                   ▼                    │
│   │   (gets SUI)   │                          ┌─────────────────┐          │
│   └────────────────┘                          │  DeepBook Pool  │          │
│            │                                   │   borrow_rate() │          │
│            │ repay()                           └─────────────────┘          │
│            ▼                                                                 │
│   ┌──────────────────────────────────────────────────────────────┐         │
│   │                     Back to BalanceManager                    │         │
│   └──────────────────────────────────────────────────────────────┘         │
│                                                                              │
│  BENEFIT: Liquidator now owns a yield-bearing SupporterPass!                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.4 Technical Specification (TideLendingPool)

```move
module tide_loans::lending_pool;

use deepbook::balance_manager::{Self, BalanceManager};
use deepbook::pool::{Self, Pool};
use sui::coin::Coin;
use sui::sui::SUI;

// === Errors ===
const EPaused: u64 = 1;
const EExceedsExposure: u64 = 2;
const EInsufficientLiquidity: u64 = 3;
const EInsufficientProceeds: u64 = 3;
const EInsufficientRepayment: u64 = 4;
const EBidTooLow: u64 = 5;

// === Events ===

public struct FlashLiquidationKeep has copy, drop {
    loan_id: ID,
    liquidator: address,
    loan_amount: u64,
    flash_fee: u64,
    pass_id: ID,
    collateral_value: u64,
    epoch: u64,
}

public struct FlashLiquidationSell has copy, drop {
    loan_id: ID,
    liquidator: address,
    loan_amount: u64,
    flash_fee: u64,
    sale_price: u64,
    marketplace_fee: u64,
    profit: u64,
    epoch: u64,
}
```

#### 3.3.2 Phase 1A: Flash Liquidate + Keep

```move
/// Phase 1A: Flash liquidate and keep the SupporterPass.
/// 
/// The liquidator provides repayment funds and keeps the profitable pass.
/// This is the simpler version that requires NO marketplace changes.
/// 
/// # Economics Example
/// - Loan payoff: 50 SUI
/// - Flash fee: ~0.3 SUI
/// - Collateral value: 65 SUI
/// - Liquidator pays: 50.3 SUI
/// - Liquidator receives: Pass worth 65 SUI
/// - Instant profit: ~15 SUI (in yield-bearing asset!)
/// 
/// # Why Use Flash Loan?
/// - Liquidator may not have 50 SUI liquid
/// - Flash loan provides instant capital
/// - Atomic execution (no race conditions)
public fun flash_liquidate_and_keep(
    // Loan objects
    loan_vault: &mut LoanVault,
    loan_id: ID,
    listing: &Listing,
    capital_vault: &CapitalVault,
    // DeepBook objects
    pool: &mut Pool<SUI, USDC>,
    // Liquidator's repayment funds
    repayment: Coin<SUI>,
    ctx: &mut TxContext,
): SupporterPass {
    // 1. Calculate payoff amount
    let payoff = loan_vault.outstanding_balance(loan_id);
    let flash_fee = pool.flash_loan_fee(payoff);
    
    // 2. Validate liquidator has enough for repayment
    assert!(repayment.value() >= payoff + flash_fee, EInsufficientRepayment);
    
    // 3. Flash borrow (to have immediate capital)
    let (flash_loan, borrowed) = pool.flash_loan(payoff, ctx);
    
    // 4. Liquidate with borrowed funds
    let pass = loan_vault.liquidate(
        loan_id,
        listing,
        capital_vault,
        borrowed,
        ctx,
    );
    
    // 5. Repay flash loan with liquidator's funds
    let repay_coin = repayment.split(payoff + flash_fee, ctx);
    pool.repay_flash_loan(flash_loan, repay_coin);
    
    // 6. Return any excess repayment to liquidator
    if (repayment.value() > 0) {
        transfer::public_transfer(repayment, ctx.sender());
    } else {
        repayment.destroy_zero();
    };
    
    // 7. Emit event
    event::emit(FlashLiquidationKeep {
        loan_id,
        liquidator: ctx.sender(),
        loan_amount: payoff,
        flash_fee,
        pass_id: object::id(&pass),
        collateral_value: loan_vault.collateral_value(loan_id),
        epoch: ctx.epoch(),
    });
    
    // 8. Return pass to liquidator (they keep it!)
    pass
}
```

#### 3.3.3 Phase 1C: Flash Liquidate + Sell (Requires Marketplace v2)

```move
/// Phase 1C: Flash liquidate with instant sale to buy order.
/// TRULY CAPITAL-FREE - liquidator only needs gas!
/// 
/// # Requirements
/// - Marketplace v2 with Bid System deployed
/// - Matching BuyOrder exists with sufficient bid
/// 
/// # Economics Example
/// - Loan payoff: 50 SUI
/// - Flash fee: ~0.3 SUI
/// - Buy order bid: 60 SUI
/// - Marketplace fee (5%): 3 SUI
/// - Proceeds: 57 SUI
/// - Repay: 50.3 SUI
/// - Profit: 6.7 SUI (instant, liquid!)
public fun flash_liquidate_and_sell(
    // Loan objects
    loan_vault: &mut LoanVault,
    loan_id: ID,
    listing: &Listing,
    capital_vault: &CapitalVault,
    // DeepBook objects
    pool: &mut Pool<SUI, USDC>,
    // Marketplace objects (v2 required)
    marketplace_config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    buy_order: BuyOrder,  // Pre-found matching bid
    ctx: &mut TxContext,
): Coin<SUI> {
    // 1. Calculate costs
    let payoff = loan_vault.outstanding_balance(loan_id);
    let flash_fee = pool.flash_loan_fee(payoff);
    let marketplace_fee = marketplace_config.calculate_fee(buy_order.bid_price());
    
    // 2. Validate bid covers all costs
    let min_bid_needed = payoff + flash_fee + marketplace_fee;
    assert!(buy_order.bid_price() >= min_bid_needed, EBidTooLow);
    
    // 3. Flash borrow
    let (flash_loan, borrowed) = pool.flash_loan(payoff, ctx);
    
    // 4. Liquidate
    let pass = loan_vault.liquidate(
        loan_id,
        listing,
        capital_vault,
        borrowed,
        ctx,
    );
    
    // 5. Instant sell to the buy order
    let (mut proceeds, _receipt) = marketplace::instant_sell(
        marketplace_config,
        treasury_vault,
        buy_order,
        pass,
        ctx,
    );
    
    // 6. Repay flash loan from sale proceeds
    let repay_amount = payoff + flash_fee;
    let repay_coin = proceeds.split(repay_amount, ctx);
    pool.repay_flash_loan(flash_loan, repay_coin);
    
    // 7. Emit event
    event::emit(FlashLiquidationSell {
        loan_id,
        liquidator: ctx.sender(),
        loan_amount: payoff,
        flash_fee,
        sale_price: buy_order.bid_price(),
        marketplace_fee,
        profit: proceeds.value(),
        epoch: ctx.epoch(),
    });
    
    // 8. Return profit to liquidator
    proceeds
}
```

#### 3.3.4 View Functions

```move
// === View Functions ===

/// Calculate expected profit from flash_liquidate_and_keep.
public fun estimate_keep_profit(
    loan_vault: &LoanVault,
    loan_id: ID,
    pool: &Pool<SUI, USDC>,
): u64 {
    let payoff = loan_vault.outstanding_balance(loan_id);
    let flash_fee = pool.flash_loan_fee(payoff);
    let collateral_value = loan_vault.collateral_value(loan_id);
    
    // Profit = collateral value - (payoff + flash fee)
    // Note: This is "paper profit" locked in the pass
    if (collateral_value > payoff + flash_fee) {
        collateral_value - payoff - flash_fee
    } else {
        0
    }
}

/// Calculate expected profit from flash_liquidate_and_sell.
/// Returns None if no profitable bid exists.
public fun estimate_sell_profit(
    loan_vault: &LoanVault,
    loan_id: ID,
    pool: &Pool<SUI, USDC>,
    bid_price: u64,
    marketplace_fee_bps: u64,
): Option<u64> {
    let payoff = loan_vault.outstanding_balance(loan_id);
    let flash_fee = pool.flash_loan_fee(payoff);
    let marketplace_fee = (bid_price * marketplace_fee_bps) / 10000;
    
    let total_cost = payoff + flash_fee + marketplace_fee;
    
    if (bid_price > total_cost) {
        option::some(bid_price - total_cost)
    } else {
        option::none()
    }
}

/// Check if a liquidation would be profitable with a given bid.
public fun is_profitable_with_bid(
    loan_vault: &LoanVault,
    loan_id: ID,
    pool: &Pool<SUI, USDC>,
    bid_price: u64,
    marketplace_fee_bps: u64,
): bool {
    estimate_sell_profit(loan_vault, loan_id, pool, bid_price, marketplace_fee_bps).is_some()
}
```

#### 3.3.5 Marketplace v2 Dependency

For Phase 1C, the marketplace must support:

```move
// In tide_marketplace::marketplace (v2)

/// Instantly sell a SupporterPass to a matching buy order.
/// See spec/marketplace-v2.md for full specification.
public fun instant_sell(
    config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    order: BuyOrder,
    pass: SupporterPass,
    ctx: &mut TxContext,
): (Coin<SUI>, InstantSaleReceipt)
```

See **[spec/marketplace-v2.md](./marketplace-v2.md)** for the full Bid System specification.

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

## 4. Phase 2: Flash Liquidations

> **Simplified:** Only "Flash Liquidate + Keep" is implemented. Bid system and "Flash + Sell" are deferred.

### 4.1 Overview

Enable capital-efficient liquidations using DeepBook's flash loan feature.

| What's Implemented | What's Deferred |
|-------------------|-----------------|
| Flash Liquidate + Keep | Marketplace Bid System |
| Liquidator provides repayment | Flash Liquidate + Sell |
| Keeps profitable SupporterPass | Zero-capital liquidations |

### 4.2 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│               FLASH LIQUIDATION (KEEP PASS) - SIMPLIFIED                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐                                                            │
│  │ Liquidator  │ calls flash_liquidate_and_keep()                          │
│  │ (provides   │ + provides repayment funds                                │
│  │  repayment) │                                                            │
│  └──────┬──────┘                                                            │
│         │                                                                    │
│         ▼                                                                    │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ Step 1: Flash Borrow from DeepBook                              │       │
│  │ deepbook::pool::flash_loan(pool, loan_amount)                   │       │
│  └────────────────────────────┬────────────────────────────────────┘       │
│                               │                                             │
│                               ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ Step 2: Liquidate Tide Loan with borrowed funds                 │       │
│  │ loan_vault::liquidate(vault, loan_id, borrowed_sui)             │       │
│  │ → Returns: SupporterPass                                        │       │
│  └────────────────────────────┬────────────────────────────────────┘       │
│                               │                                             │
│                               ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ Step 3: Repay Flash Loan with LIQUIDATOR'S funds                │       │
│  │ Liquidator provides: loan_amount + flash_fee                    │       │
│  └────────────────────────────┬────────────────────────────────────┘       │
│                               │                                             │
│                               ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ Step 4: Liquidator KEEPS the SupporterPass                      │       │
│  │ Pass worth ~65 SUI → Profit locked in yield-bearing asset       │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.3 Technical Specification

```move
module tide_loans::flash_liquidator;

use sui::coin::Coin;
use sui::sui::SUI;
use deepbook::pool::{Pool, FlashLoan};

// === Errors ===
const ELoanStillHealthy: u64 = 1;
const EInsufficientRepayment: u64 = 2;

// === Events ===
public struct FlashLiquidation has copy, drop {
    loan_id: ID,
    liquidator: address,
    loan_amount: u64,
    flash_fee: u64,
    pass_id: ID,
    epoch: u64,
}

/// Flash liquidate and keep the SupporterPass.
/// Liquidator provides repayment funds, keeps the profitable pass.
public fun flash_liquidate_and_keep(
    loan_vault: &mut LoanVault,
    loan_id: ID,
    listing: &Listing,
    capital_vault: &CapitalVault,
    pool: &mut Pool<SUI, USDC>,
    repayment: Coin<SUI>,
    ctx: &mut TxContext,
): SupporterPass {
    // 1. Calculate payoff
    let payoff = loan_vault.outstanding_balance(loan_id);
    let flash_fee = pool.flash_loan_fee(payoff);
    
    // 2. Validate repayment covers costs
    assert!(repayment.value() >= payoff + flash_fee, EInsufficientRepayment);
    
    // 3. Flash borrow
    let (flash_loan, borrowed) = pool.flash_loan(payoff, ctx);
    
    // 4. Liquidate
    let pass = loan_vault.liquidate(loan_id, listing, capital_vault, borrowed, ctx);
    
    // 5. Repay flash loan
    let repay_coin = repayment.split(payoff + flash_fee, ctx);
    pool.repay_flash_loan(flash_loan, repay_coin);
    
    // 6. Return excess to liquidator
    if (repayment.value() > 0) {
        transfer::public_transfer(repayment, ctx.sender());
    } else {
        repayment.destroy_zero();
    };
    
    // 7. Emit event
    event::emit(FlashLiquidation {
        loan_id,
        liquidator: ctx.sender(),
        loan_amount: payoff,
        flash_fee,
        pass_id: object::id(&pass),
        epoch: ctx.epoch(),
    });
    
    pass
}

/// Estimate profit from keeping the pass.
public fun estimate_profit(
    loan_vault: &LoanVault,
    loan_id: ID,
    pool: &Pool<SUI, USDC>,
): u64 {
    let payoff = loan_vault.outstanding_balance(loan_id);
    let flash_fee = pool.flash_loan_fee(payoff);
    let collateral_value = loan_vault.collateral_value(loan_id);
    
    if (collateral_value > payoff + flash_fee) {
        collateral_value - payoff - flash_fee
    } else {
        0
    }
}
```

### 4.4 Benefits

| Metric | Before | After (Flash Liquidate + Keep) |
|--------|--------|--------------------------------|
| Capital Required | Full loan amount | Repayment amount only |
| Liquidator Pool | Capital-rich only | More accessible |
| Execution | Multi-step | Atomic (single tx) |
| Profit | Immediate SUI | Yield-bearing SupporterPass |

### 4.5 Deferred Features

The following are intentionally deferred:

| Feature | Why Deferred |
|---------|--------------|
| Marketplace Bid System | Significant new feature, not essential |
| Flash Liquidate + Sell | Requires bid system |
| Zero-capital liquidations | Flash + Keep is sufficient for now |

These can be revisited when there's proven demand.

---

## 5. Phase 1 (continued): DeepBook Liquidity

> **Note:** This section continues Phase 1 (DeepBook Integration) with the liquidity sourcing details.
> 
> See Section 3 for the combined Phase 1 overview.

### 5.1 Overview

Source ALL lending liquidity from DeepBook via a single `BalanceManager`.

> **Design Decision:** We chose DeepBook-Only over Hybrid (Treasury + DeepBook) for simplicity.

| Approach | Complexity | Code Size | Recommendation |
|----------|------------|-----------|----------------|
| Hybrid (Treasury + DeepBook) | High | ~500 LOC | ❌ Over-engineered |
| DeepBook-Only via BalanceManager | Low | ~200 LOC | ✅ **Recommended** |

**Why DeepBook-Only is Better:**
1. **Simpler architecture** — One fund source, one interface
2. **Less code** — No blending, no waterfall repayment logic
3. **Market-driven rates** — DeepBook handles rate calculation
4. **Scalable** — Grows with DeepBook's liquidity pools
5. **Battle-tested** — Leverages DeepBook's proven infrastructure

**Tide Treasury Role (Updated):**
- Tide deposits Treasury funds INTO the BalanceManager
- BalanceManager becomes the single source for all loans
- Treasury acts as "seed liquidity" that earns DeepBook rates
- Tide can withdraw from BalanceManager when needed

### 5.2 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              DEEPBOOK-ONLY LIQUIDITY (via BalanceManager)                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │                    SETUP (One-time)                             │       │
│  │                                                                  │       │
│  │  1. Tide creates BalanceManager on DeepBook                     │       │
│  │  2. Tide deposits Treasury funds → BalanceManager               │       │
│  │  3. BalanceManager is now the liquidity source                  │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │                    BORROW FLOW                                   │       │
│  │                                                                  │       │
│  │  User requests: 1000 SUI loan                                   │       │
│  │         │                                                        │       │
│  │         ▼                                                        │       │
│  │  ┌─────────────────────────────────────────────────────────┐   │       │
│  │  │ TideLendingPool (wrapper)                                │   │       │
│  │  │                                                          │   │       │
│  │  │ 1. Check BalanceManager has funds                       │   │       │
│  │  │ 2. balance_manager::withdraw(1000 SUI)                  │   │       │
│  │  │ 3. Issue loan to user                                   │   │       │
│  │  │ 4. Record loan details                                  │   │       │
│  │  └─────────────────────────────────────────────────────────┘   │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │                    REPAY FLOW                                    │       │
│  │                                                                  │       │
│  │  Rewards come in (from SupporterPass)                           │       │
│  │         │                                                        │       │
│  │         ▼                                                        │       │
│  │  ┌─────────────────────────────────────────────────────────┐   │       │
│  │  │ TideLendingPool                                          │   │       │
│  │  │                                                          │   │       │
│  │  │ 1. Calculate interest owed                               │   │       │
│  │  │ 2. balance_manager::deposit(repayment)                  │   │       │
│  │  │ 3. Update loan record                                   │   │       │
│  │  │                                                          │   │       │
│  │  │ → No waterfall, no blending. Just deposit and done.     │   │       │
│  │  └─────────────────────────────────────────────────────────┘   │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.3 Technical Specification (Simplified)

```move
module tide_loans::lending_pool;

use deepbook::balance_manager::{Self, BalanceManager};
use deepbook::pool::{Self, Pool};
use sui::coin::Coin;
use sui::sui::SUI;

// === Structs ===

/// Tide's wrapper around DeepBook BalanceManager
/// Single source of truth for all lending liquidity
public struct TideLendingPool has key {
    id: UID,
    /// DeepBook BalanceManager - single fund source
    balance_manager_id: ID,
    /// Total deposited by Tide Treasury
    treasury_deposit: u64,
    /// Total currently lent out
    outstanding: u64,
    /// Maximum lending exposure
    max_exposure: u64,
    /// Admin controls
    admin: address,
    /// Pause flag
    paused: bool,
}

/// Config for the lending pool
public struct LendingConfig has store {
    /// Minimum loan amount
    min_loan: u64,
    /// Maximum single loan amount  
    max_loan: u64,
    /// Interest rate (from DeepBook or override)
    rate_override: Option<u64>,
}

// === Admin Functions ===

/// Create lending pool with BalanceManager
public fun create_pool(
    admin_cap: &AdminCap,
    ctx: &mut TxContext,
): TideLendingPool {
    let balance_manager = balance_manager::new(ctx);
    let bm_id = object::id(&balance_manager);
    
    // Transfer BalanceManager to be managed by this module
    transfer::public_share_object(balance_manager);
    
    TideLendingPool {
        id: object::new(ctx),
        balance_manager_id: bm_id,
        treasury_deposit: 0,
        outstanding: 0,
        max_exposure: 1_000_000_000_000, // 1M SUI default
        admin: ctx.sender(),
        paused: false,
    }
}

/// Deposit Treasury funds for lending
public fun deposit_liquidity(
    pool: &mut TideLendingPool,
    balance_manager: &mut BalanceManager,
    admin_cap: &AdminCap,
    coin: Coin<SUI>,
) {
    let amount = coin.value();
    balance_manager::deposit(balance_manager, coin);
    pool.treasury_deposit = pool.treasury_deposit + amount;
}

/// Withdraw Treasury funds
public fun withdraw_liquidity(
    pool: &mut TideLendingPool,
    balance_manager: &mut BalanceManager,
    admin_cap: &AdminCap,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    // Can only withdraw unused funds
    let available = pool.treasury_deposit - pool.outstanding;
    assert!(amount <= available, EInsufficientLiquidity);
    
    pool.treasury_deposit = pool.treasury_deposit - amount;
    balance_manager::withdraw(balance_manager, amount, ctx)
}

// === Lending Functions ===

/// Borrow from the pool (called internally by LoanVault)
public(package) fun borrow(
    pool: &mut TideLendingPool,
    balance_manager: &mut BalanceManager,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(!pool.paused, EPaused);
    assert!(pool.outstanding + amount <= pool.max_exposure, EExceedsExposure);
    
    let coin = balance_manager::withdraw(balance_manager, amount, ctx);
    pool.outstanding = pool.outstanding + amount;
    coin
}

/// Repay to the pool
public(package) fun repay(
    pool: &mut TideLendingPool,
    balance_manager: &mut BalanceManager,
    coin: Coin<SUI>,
) {
    let amount = coin.value();
    balance_manager::deposit(balance_manager, coin);
    pool.outstanding = pool.outstanding - amount;
}

// === View Functions ===

/// Get available liquidity
public fun available_liquidity(pool: &TideLendingPool): u64 {
    pool.treasury_deposit - pool.outstanding
}

/// Get current utilization (0-10000 bps)
public fun utilization_bps(pool: &TideLendingPool): u64 {
    if (pool.treasury_deposit == 0) { return 0 };
    (pool.outstanding * 10000) / pool.treasury_deposit
}

/// Get interest rate (from DeepBook pool)
public fun get_rate(deepbook_pool: &Pool<SUI, USDC>): u64 {
    pool::borrow_rate(deepbook_pool)
}
```

**Key Simplifications:**
- No `DeepBookLoan` tracking per-loan source
- No `calculate_blended_rate` — just use DeepBook rate
- No waterfall repayment — single deposit destination
- ~120 LOC instead of ~500 LOC

### 5.4 Benefits

| Metric | Before (Treasury Only) | After (DeepBook via BalanceManager) |
|--------|------------------------|-------------------------------------|
| Max Lending Capacity | Limited to Treasury | Scales with Treasury deposit |
| Rate Calculation | Custom logic | DeepBook handles it |
| Code Complexity | Medium | **Low** |
| Capital Efficiency | Low | High (market rates) |
| Maintenance | Custom rate curves | Leverage DeepBook's battle-tested code |
| Dependency | None | DeepBook (acceptable tradeoff) |

### 5.5 Risk Mitigation

| Risk | Mitigation |
|------|------------|
| **DeepBook downtime** | Pause lending; loans continue with fixed rate |
| **Rate manipulation** | Rate cap in TideLendingPool |
| **Liquidity drain** | `max_exposure` limit |
| **Smart contract bug** | Deposit limits, gradual rollout |

---

## 6. Phase 3: DEEP Token Rewards (Simplified)

### 6.1 Overview

Distribute DEEP tokens to Tide backers as additional yield.

> **Simplified Design:** We use epoch-based snapshot distribution instead of complex cumulative tracking.

| Original Approach | Simplified Approach |
|-------------------|---------------------|
| Cumulative `deep_per_share` tracking | Epoch-based snapshots |
| Complex claim index per pass | Simple proportional claims |
| ~100 LOC | **~40 LOC** |

**DEEP Token Benefits (from [DeepBook Documentation](https://docs.sui.io/standards/deepbook)):**

| Benefit | Details |
|---------|---------|
| **Fee Discount** | 20% lower trading fees when paying with DEEP vs input tokens |
| **Taker Incentives** | Reduce fees to 0.25 bps (stable pairs) or 2.5 bps (volatile pairs) |
| **Maker Incentives** | Rebates based on maker volume generated |
| **Governance** | Propose and vote on trading parameters each epoch |

**Staking Requirements:**
- Users must stake DEEP to be eligible for taker/maker incentives
- Voting power formula: `V = min(S, Vc) + max(√S - √Vc, 0)` where Vc = 100,000 DEEP
- Quorum for proposals = 50% of total voting power

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

// === Structs (Simplified) ===

/// DEEP reward pool - epoch-based snapshot distribution
public struct DeepRewardsPool has key {
    id: UID,
    /// DEEP balance available for claims
    deep_balance: Balance<DEEP>,
    /// Amount to distribute this epoch
    distribution_amount: u64,
    /// Epoch when snapshot was taken
    snapshot_epoch: u64,
    /// Total shares at snapshot (for proportional claims)
    snapshot_total_shares: u64,
    /// Admin
    admin: address,
}

// === Functions (Simplified) ===

/// Admin deposits DEEP for distribution.
public fun deposit_deep(
    pool: &mut DeepRewardsPool,
    admin_cap: &AdminCap,
    deep: Coin<DEEP>,
    ctx: &TxContext,
) {
    let amount = deep.value();
    pool.deep_balance.join(deep.into_balance());
    
    event::emit(DeepDeposited {
        amount,
        new_balance: pool.deep_balance.value(),
        epoch: ctx.epoch(),
    });
}

/// Admin starts a distribution round (takes snapshot).
public fun start_distribution(
    pool: &mut DeepRewardsPool,
    capital_vault: &CapitalVault,
    amount: u64,
    admin_cap: &AdminCap,
    ctx: &TxContext,
) {
    assert!(pool.deep_balance.value() >= amount, EInsufficientBalance);
    
    pool.distribution_amount = amount;
    pool.snapshot_epoch = ctx.epoch();
    pool.snapshot_total_shares = capital_vault.total_shares();
}

/// Backer claims their proportional DEEP share.
public fun claim_deep(
    pool: &mut DeepRewardsPool,
    pass: &SupporterPass,
    ctx: &mut TxContext,
): Coin<DEEP> {
    // Calculate share: (pass.shares / total_shares) * distribution_amount
    let share_bps = (pass.shares * 10000) / pool.snapshot_total_shares;
    let claimable = (pool.distribution_amount * share_bps) / 10000;
    
    // Extract and return
    coin::from_balance(pool.deep_balance.split(claimable), ctx)
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

## 7. Removed/Deferred Features

The following features were removed from this specification to reduce complexity:

| Feature | Status | Reason | Can Revisit? |
|---------|--------|--------|--------------|
| Custom Rate Curves | **Removed** | Use DeepBook's `borrow_rate()` directly | No need |
| Marketplace Bid System | **Deferred** | Only needed for Flash + Sell | When demand exists |
| Flash Liquidate + Sell | **Deferred** | Requires bid system | After bid system |
| Margin Trading | **Removed** | High complexity, high risk | After 12+ months stable operation |
| Complex DEEP Tracking | **Simplified** | Epoch snapshots sufficient | If precision needed |

**Total Code Reduction:** ~500 LOC removed (from ~800 LOC to ~300 LOC)

---

## 8. Technical Implementation

### 8.1 Package Structure (Simplified)

```
contracts/loans/
├── Move.toml
├── sources/
│   ├── loan_vault.move          # Core (existing)
│   ├── lending_pool.move        # Phase 1: DeepBook liquidity + rates
│   └── flash_liquidator.move    # Phase 2: Flash loan liquidations
└── tests/
    ├── loan_vault_tests.move
    ├── lending_pool_tests.move
    ├── flash_liquidator_tests.move
    └── integration_tests.move

contracts/core/sources/
├── deep_rewards.move            # Phase 3: DEEP distribution (simplified)
```

**Removed Modules:**
- ~~`dynamic_rates.move`~~ — Use `pool::borrow_rate()` directly
- ~~`buy_order.move`~~ — Deferred (bid system not needed)

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

| DeepBook Function | Tide Usage | Phase |
|-------------------|------------|-------|
| `balance_manager::new()` | Create lending pool | Phase 1 |
| `balance_manager::deposit()` | Deposit treasury funds | Phase 1 |
| `balance_manager::withdraw()` | Lend to borrowers | Phase 1 |
| `pool::borrow_rate()` | Get market interest rate | Phase 1 |
| `pool::flash_loan()` | Borrow for liquidation | Phase 2 |
| `pool::repay_flash_loan()` | Repay after liquidation | Phase 2 |
| `deep::transfer()` | Distribute DEEP rewards | Phase 3 |

### 8.4 BalanceManager Integration

From the [DeepBook Design](https://docs.sui.io/standards/deepbookv3/design), the `BalanceManager` is a key concept:

```move
/// Tide's BalanceManager for DeepBook integration
/// One per deployment, used for all pool interactions
public struct TideBalanceManager has key {
    id: UID,
    /// DeepBook BalanceManager object ID
    balance_manager_id: ID,
    /// Authorized caller for operations
    admin: address,
}
```

**Usage Flow:**
1. **Create BalanceManager** (once, at integration deployment)
2. **Deposit** SUI/DEEP from Tide Treasury → BalanceManager
3. **Execute trades** via Pool (BalanceManager sources funds)
4. **Settle** after each operation (Vault updates BalanceManager)

**Important:** A single `BalanceManager` can be used across all DeepBook pools, simplifying fund management.

### 8.5 Flash Loan Mechanics

Flash loan flow from DeepBook (atomic within one transaction):

```
1. pool::flash_loan(pool, amount)
   → Returns (FlashLoan receipt, Coin<SUI>)

2. Use borrowed funds (liquidate Tide loan, etc.)

3. pool::repay_flash_loan(pool, flash_loan, repayment_coin)
   → Must repay amount + fee
   → FlashLoan receipt consumed (enforces repayment)
```

**Flash Loan Fee:** Determined by pool governance, typically ~0.05% - 0.1%

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

## 10. Testing Requirements (Simplified)

### 10.1 Unit Tests

**Phase 1: DeepBook Integration (Liquidity + Rates)**
- [ ] `test_create_lending_pool`
- [ ] `test_deposit_liquidity`
- [ ] `test_withdraw_liquidity`
- [ ] `test_borrow_from_pool`
- [ ] `test_repay_to_pool`
- [ ] `test_available_liquidity`
- [ ] `test_utilization_bps`
- [ ] `test_exposure_limits`
- [ ] `test_pause_lending`
- [ ] `test_get_rate_from_deepbook`

**Phase 2: Flash Liquidations (Keep Only)**
- [ ] `test_flash_liquidate_and_keep_success`
- [ ] `test_flash_liquidate_and_keep_insufficient_repayment_fails`
- [ ] `test_flash_liquidate_and_keep_healthy_loan_fails`
- [ ] `test_flash_liquidate_and_keep_returns_excess`
- [ ] `test_estimate_profit`

**Phase 3: DEEP Token Rewards (Simplified)**
- [ ] `test_deposit_deep`
- [ ] `test_start_distribution`
- [ ] `test_claim_deep_proportional`
- [ ] `test_claim_deep_multiple_backers`

### 10.2 Integration Tests

- [ ] Full lending pool lifecycle: deposit → borrow → repay → withdraw
- [ ] Flash liquidation with DeepBook pool
- [ ] DEEP reward distribution across multiple backers
- [ ] E2E: Borrow → rewards auto-repay → flash liquidation of unhealthy loan

### 10.3 Stress Tests

- [ ] High utilization scenario (>95%)
- [ ] Multiple concurrent flash liquidations
- [ ] DeepBook pool low liquidity handling

---

## 11. Deployment Plan (Simplified)

### 11.1 Timeline

| Phase | Feature | Duration | Dependencies | Status |
|-------|---------|----------|--------------|--------|
| **1** | DeepBook Integration | 2-3 weeks | DeepBook | 📋 Planned |
| **2** | Flash Liquidations | 1 week | Phase 1 | 📋 Planned |
| **3** | DEEP Token Rewards | 1-2 weeks | None | 📋 Planned |

**Total: 4-6 weeks** (reduced from 10+ weeks)

### 11.2 Rollout Strategy (Simplified)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      DEPLOYMENT ROLLOUT (SIMPLIFIED)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Week 1-3: Phase 1 - DeepBook Integration                                   │
│  ├── Create BalanceManager for Tide                                        │
│  ├── Implement lending_pool.move                                           │
│  ├── Integrate with pool::borrow_rate()                                    │
│  ├── Write unit tests                                                        │
│  └── Deploy to testnet                                                       │
│                                                                              │
│  Week 4: Phase 2 - Flash Liquidations                                       │
│  ├── Implement flash_liquidator.move (keep only)                           │
│  ├── Write unit tests                                                        │
│  └── Deploy to testnet                                                       │
│                                                                              │
│  Week 5-6: Phase 3 - DEEP Token Rewards                                     │
│  ├── Implement deep_rewards.move (simplified)                              │
│  ├── Write unit tests                                                        │
│  └── Deploy to testnet                                                       │
│                                                                              │
│  Week 7+: Mainnet Rollout                                                   │
│  ├── Day 1-3: Deploy with conservative limits                               │
│  ├── Day 4-7: Monitor, increase limits if stable                            │
│  └── Week 2+: Full rollout if no issues                                     │
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
| Design | https://docs.sui.io/standards/deepbookv3/design |
| Contract Information | https://docs.sui.io/standards/deepbookv3/contract-information |
| Indexer | https://docs.sui.io/standards/deepbookv3-indexer |
| SDK | https://docs.sui.io/standards/deepbookv3-sdk |
| Margin Documentation | https://docs.sui.io/standards/deepbook-margin |
| Margin Design | https://docs.sui.io/standards/deepbook-margin/design |
| Margin Contract Info | https://docs.sui.io/standards/deepbook-margin/contract-information |
| Margin Indexer | https://docs.sui.io/standards/deepbook-margin-indexer |
| Margin SDK | https://docs.sui.io/standards/deepbook-margin-sdk |
| GitHub Repository | https://github.com/MystenLabs/deepbookv3 |

### A.1 Related Tide Specifications

| Spec | Purpose |
|------|---------|
| [self-paying-loans-v2.md](./self-paying-loans-v2.md) | Current loans architecture |
| [tide-core-v1.md](./tide-core-v1.md) | Core protocol specification |
| [marketplace-v2.md](./marketplace-v2.md) | Bid System (deferred) |

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

### D. SDK & Indexer Integration

**DeepBook SDK (from [SDK docs](https://docs.sui.io/standards/deepbookv3-sdk)):**

The TypeScript SDK simplifies building PTBs for DeepBook interactions:

```typescript
import { DeepBookClient } from '@mysten/deepbook';

// Initialize client
const client = new DeepBookClient({
  address: TIDE_BALANCE_MANAGER,
  env: 'mainnet',
});

// Flash liquidation example
const tx = new Transaction();
const { flashLoan, coin } = client.flashLoan(tx, {
  poolKey: 'SUI_USDC',
  borrowAmount: loanPayoff,
});
// ... use coin for liquidation ...
client.repayFlashLoan(tx, { flashLoan, coin: repaymentCoin });
```

**DeepBook Indexer (from [Indexer docs](https://docs.sui.io/standards/deepbookv3-indexer)):**

Use the indexer for off-chain queries:

| Endpoint | Use Case |
|----------|----------|
| `/pools` | Get available pools for flash loans |
| `/pool/{id}/depth` | Check liquidity for large loans |
| `/pool/{id}/trades` | Historical price data |
| `/account/{address}/fills` | Track Tide's DeepBook activity |

**Keeper Integration:**
```typescript
// Keeper bot for flash liquidations
async function checkAndLiquidate() {
  // 1. Query Tide indexer for unhealthy loans
  const unhealthyLoans = await tideIndexer.getUnhealthyLoans();
  
  // 2. For each, check DeepBook liquidity
  for (const loan of unhealthyLoans) {
    const depth = await deepbookIndexer.getPoolDepth('SUI_USDC');
    if (depth.available >= loan.payoff) {
      // 3. Execute flash liquidation
      await executeFlashLiquidation(loan);
    }
  }
}
```

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

### E. Additional DeepBook Features for Future Consideration

Based on the [DeepBook V3 Design](https://docs.sui.io/standards/deepbookv3/design), these features could be leveraged in future iterations:

| Feature | Potential Use Case | Phase |
|---------|-------------------|-------|
| **BalanceManager** | Single fund source for all Tide-DeepBook interactions | Phase 1 ✅ |
| **Governance Participation** | Tide DAO votes on DeepBook fee parameters | Future |
| **Maker Rebates** | Tide earns rebates when providing liquidity | Future |
| **DeepPrice Oracle** | Use DeepBook's price data for collateral valuation | Future |
| **BigVector Order Book** | Direct market making on DeepBook with Tide treasury | Future |
| **Pool-Specific Staking** | Stake DEEP per pool for incentive eligibility | Future |
| **Whitelisted Pool** | Request whitelisted status for zero fees | Future |

**Governance Fee Bounds (from DeepBook docs):**

| Pool Type | Taker (bps) | Maker (bps) |
|-----------|-------------|-------------|
| Volatile | 1-10 | 0-5 |
| Stable | 0.1-1 | 0-0.5 |
| Whitelisted | 0 | 0 |

**Integration Consideration:** If Tide becomes a significant liquidity provider, we could apply for whitelisted pool status to eliminate trading fees entirely.

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
5. Join DeepBook Discord for technical support
