# Tide Marketplace v2 Specification

> **Version:** v2.0
> **Status:** ⏸️ **DEFERRED** — Not required for initial DeepBook integration
> **Author:** Tide Protocol
> **Last Updated:** January 2026
> **Depends On:** marketplace-v1.md, deepbook-integration-v1.md

## Why Deferred?

**Flash Liquidate + Keep** (Phase 2 of DeepBook integration) provides 90% of the value without requiring this bid system. True "zero-capital" liquidations via Flash + Sell are deferred.

**When to revisit:** When there's proven demand for zero-capital liquidations.

---

## Executive Summary

Marketplace v2 extends the existing marketplace with a **Bid System** (Buy Orders) that enables:
1. **Buyers to place standing bids** with escrowed funds
2. **Instant selling** by matching against best bid
3. **Capital-free flash liquidations** via DeepBook integration

This upgrade would be required for Flash Liquidate + Sell (currently deferred).

---

## Table of Contents

1. [Motivation](#1-motivation)
2. [Architecture](#2-architecture)
3. [Data Structures](#3-data-structures)
4. [Core Functions](#4-core-functions)
5. [Matching Algorithm](#5-matching-algorithm)
6. [Events](#6-events)
7. [User Flows](#7-user-flows)
8. [Security Considerations](#8-security-considerations)
9. [Integration with Flash Liquidations](#9-integration-with-flash-liquidations)
10. [Migration Plan](#10-migration-plan)
11. [Testing Requirements](#11-testing-requirements)
12. [Appendix](#12-appendix)

---

## 1. Motivation

### 1.1 Current Limitations

The v1 marketplace only supports seller-initiated listings:

```
Seller lists at 100 SUI → Buyer sees listing → Buyer purchases

Problem: No way for buyers to express demand at lower prices
Problem: No instant liquidity for sellers who need to sell NOW
Problem: Flash liquidations cannot sell atomically
```

### 1.2 Why Bids Matter

| Use Case | v1 (Asks Only) | v2 (Asks + Bids) |
|----------|----------------|------------------|
| Seller wants instant cash | ❌ Must wait for buyer | ✅ Match against best bid |
| Buyer wants specific pass | ❌ Must check constantly | ✅ Place bid, get notified |
| Flash liquidation | ❌ Cannot sell atomically | ✅ instant_sell() to best bid |
| Price discovery | Poor (only ask prices) | Good (bid-ask spread visible) |
| Market depth | Hidden | Transparent |

### 1.3 Goals

1. **Add Buy Orders (Bids)** - Buyers can place standing orders with escrowed SUI
2. **Enable Instant Sell** - Sellers can immediately match against best bid
3. **Support Flash Liquidations** - Atomic liquidation + sale in one transaction
4. **Maintain Simplicity** - No complex order books or partial fills (v2)

### 1.4 Non-Goals (v2)

- Partial order fills (all-or-nothing for v2)
- Complex order types (limit/market/stop)
- Cross-listing arbitrage
- Automated market making

---

## 2. Architecture

### 2.1 High-Level Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       MARKETPLACE v2 ARCHITECTURE                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                        MarketplaceConfig                               │ │
│  │  (Shared - singleton)                                                  │ │
│  │                                                                        │ │
│  │  • fee_bps: 500 (5%)                                                  │ │
│  │  • stats (volume, fees, etc.)                                         │ │
│  │  • admin, paused                                                       │ │
│  │  • bid_stats: BidStats (NEW)                                          │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────┐        ┌─────────────────────────┐            │
│  │      SaleListing        │        │       BuyOrder          │            │
│  │    (Shared - per ask)   │        │   (Shared - per bid)    │            │
│  │                         │        │                         │            │
│  │  • seller               │        │  • buyer                │            │
│  │  • pass (escrowed)      │        │  • escrowed_sui         │            │
│  │  • price_sui (ask)      │        │  • bid_price            │            │
│  │  • shares, listing_id   │        │  • tide_listing_id      │            │
│  └────────────┬────────────┘        │  • min_shares           │            │
│               │                      └────────────┬────────────┘            │
│               │                                   │                          │
│               └───────────────┬───────────────────┘                          │
│                               │                                              │
│                               ▼                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                         MATCHING ENGINE                                │ │
│  │                                                                        │ │
│  │  buy() ─────────────────▶ Match SaleListing with Buyer's payment      │ │
│  │                                                                        │ │
│  │  instant_sell() ────────▶ Match SupporterPass with best BuyOrder      │ │
│  │                                                                        │ │
│  │  fill_buy_order() ──────▶ Execute matched trade (internal)            │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Module Structure

```
contracts/marketplace/
├── Move.toml
├── sources/
│   ├── marketplace.move      # Existing v1 code
│   ├── buy_order.move        # NEW: BuyOrder struct and functions
│   ├── instant_sell.move     # NEW: instant_sell logic
│   └── order_matching.move   # NEW: Matching utilities
└── tests/
    ├── marketplace_tests.move
    ├── buy_order_tests.move  # NEW
    └── instant_sell_tests.move  # NEW
```

---

## 3. Data Structures

### 3.1 BuyOrder (NEW)

A standing buy order with escrowed funds.

```move
/// A buy order (bid) with escrowed funds.
/// Created by buyers who want to purchase passes at a specific price.
public struct BuyOrder has key {
    id: UID,
    
    // === Ownership ===
    buyer: address,
    
    // === Targeting ===
    /// Which Tide listing's passes this order accepts
    tide_listing_id: ID,
    /// Minimum shares acceptable (0 = any)
    min_shares: u64,
    /// Maximum shares acceptable (0 = any)
    max_shares: u64,
    
    // === Pricing ===
    /// Maximum price willing to pay (in MIST)
    bid_price: u64,
    
    // === Escrowed Funds ===
    /// Locked SUI for this order
    escrowed: Balance<SUI>,
    
    // === Metadata ===
    created_at_epoch: u64,
    expires_at_epoch: u64,  // 0 = never expires
    
    // === Stats ===
    version: u64,
}
```

### 3.2 BidStats (NEW)

Track bid-side statistics in MarketplaceConfig.

```move
/// Bid system statistics (added to MarketplaceConfig)
public struct BidStats has store {
    /// Current number of open buy orders
    active_orders_count: u64,
    /// Total buy orders ever created
    total_orders_created: u64,
    /// Total buy orders filled
    total_orders_filled: u64,
    /// Total buy orders cancelled
    total_orders_cancelled: u64,
    /// Total volume through instant_sell
    total_instant_sell_volume: u64,
}
```

### 3.3 InstantSaleReceipt (NEW)

Returned after an instant sale.

```move
/// Receipt for an instant sale (for composability)
public struct InstantSaleReceipt has key, store {
    id: UID,
    pass_id: ID,
    order_id: ID,
    seller: address,
    buyer: address,
    price: u64,
    fee: u64,
    sold_at_epoch: u64,
}
```

### 3.4 MarketplaceConfig Updates

```move
public struct MarketplaceConfig has key {
    id: UID,
    
    // === Existing v1 fields ===
    fee_bps: u64,
    admin: address,
    paused: bool,
    total_volume_sui: u64,
    total_fees_collected_sui: u64,
    total_sales_count: u64,
    active_listings_count: u64,
    
    // === NEW v2 fields ===
    bid_stats: BidStats,
    /// Minimum bid amount (prevents dust)
    min_bid_amount: u64,  // 0.1 SUI = 100_000_000
    /// Maximum active orders per buyer (prevents spam)
    max_orders_per_buyer: u64,  // e.g., 100
    
    version: u64,
}
```

---

## 4. Core Functions

### 4.1 Buy Order Functions

#### create_buy_order

```move
/// Create a buy order with escrowed funds.
/// 
/// # Arguments
/// - `config`: Marketplace configuration
/// - `tide_listing_id`: Which Tide listing's passes to buy
/// - `bid_price`: Maximum price willing to pay
/// - `min_shares`: Minimum acceptable shares (0 = any)
/// - `max_shares`: Maximum acceptable shares (0 = any)
/// - `payment`: SUI to escrow (must equal bid_price)
/// - `expires_in_epochs`: How many epochs until expiry (0 = never)
/// 
/// # Returns
/// - Creates a shared BuyOrder object
/// - Returns the order ID
/// 
/// # Access
/// - Permissionless
public fun create_buy_order(
    config: &mut MarketplaceConfig,
    tide_listing_id: ID,
    bid_price: u64,
    min_shares: u64,
    max_shares: u64,
    payment: Coin<SUI>,
    expires_in_epochs: u64,
    ctx: &mut TxContext,
): ID
```

**Validation:**
- `!config.paused`
- `bid_price >= config.min_bid_amount`
- `payment.value() == bid_price`
- `max_shares == 0 || max_shares >= min_shares`
- User's active order count < `max_orders_per_buyer`

**Effects:**
1. Create `BuyOrder` with escrowed funds
2. Increment `bid_stats.active_orders_count`
3. Increment `bid_stats.total_orders_created`
4. Emit `BuyOrderCreated` event
5. Share the order object
6. Return order ID

---

#### cancel_buy_order

```move
/// Cancel a buy order and return escrowed funds.
/// 
/// # Access
/// - Order owner only
public fun cancel_buy_order(
    config: &mut MarketplaceConfig,
    order: BuyOrder,
    ctx: &mut TxContext,
): Coin<SUI>
```

**Validation:**
- `ctx.sender() == order.buyer`

**Effects:**
1. Decrement `bid_stats.active_orders_count`
2. Increment `bid_stats.total_orders_cancelled`
3. Emit `BuyOrderCancelled` event
4. Delete order object
5. Return escrowed funds

---

#### update_bid_price

```move
/// Update the bid price (and escrow if needed).
/// 
/// # Arguments
/// - `order`: The order to update
/// - `new_price`: New bid price
/// - `additional_funds`: Extra SUI if increasing price (can be zero-value coin)
/// 
/// # Returns
/// - Refund coin if price decreased
/// 
/// # Access
/// - Order owner only
public fun update_bid_price(
    order: &mut BuyOrder,
    new_price: u64,
    additional_funds: Coin<SUI>,
    ctx: &mut TxContext,
): Coin<SUI>
```

---

### 4.2 Instant Sell Functions

#### instant_sell

```move
/// Instantly sell a SupporterPass to the best matching buy order.
/// 
/// # Arguments
/// - `config`: Marketplace configuration
/// - `treasury_vault`: For fee deposit
/// - `order`: The buy order to fill
/// - `pass`: The SupporterPass to sell
/// 
/// # Returns
/// - (Coin<SUI>, InstantSaleReceipt) - proceeds (after fee) and receipt
/// 
/// # Access
/// - Anyone with a matching SupporterPass
public fun instant_sell(
    config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    order: BuyOrder,
    pass: SupporterPass,
    ctx: &mut TxContext,
): (Coin<SUI>, InstantSaleReceipt)
```

**Validation:**
- `!config.paused`
- `pass.listing_id() == order.tide_listing_id`
- `order.min_shares == 0 || pass.shares() >= order.min_shares`
- `order.max_shares == 0 || pass.shares() <= order.max_shares`
- Order not expired

**Fee Calculation:**
```
fee = (order.bid_price * config.fee_bps) / 10000
seller_proceeds = order.bid_price - fee
```

**Effects:**
1. Validate pass matches order criteria
2. Calculate fee (5%)
3. Deposit fee to TreasuryVault
4. Transfer pass to buyer
5. Update stats:
   - `total_volume_sui += order.bid_price`
   - `total_fees_collected_sui += fee`
   - `total_sales_count += 1`
   - `bid_stats.active_orders_count -= 1`
   - `bid_stats.total_orders_filled += 1`
   - `bid_stats.total_instant_sell_volume += order.bid_price`
6. Emit `InstantSaleCompleted` event
7. Delete order object
8. Return proceeds and receipt

---

#### instant_sell_to_buyer

```move
/// Convenience function: instant_sell + auto transfer to seller.
public fun instant_sell_to_buyer(
    config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    order: BuyOrder,
    pass: SupporterPass,
    ctx: &mut TxContext,
)
```

---

### 4.3 Internal Functions

#### fill_buy_order (package-private)

```move
/// Internal function to fill a buy order.
/// Used by instant_sell and flash_liquidate_and_sell.
public(package) fun fill_buy_order(
    config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    order: BuyOrder,
    pass: SupporterPass,
    ctx: &mut TxContext,
): Coin<SUI>
```

This is the core matching logic, exposed as `public(package)` for the loans package to use during flash liquidations.

---

### 4.4 View Functions

```move
/// Get bid price
public fun bid_price(order: &BuyOrder): u64

/// Get buyer address
public fun buyer(order: &BuyOrder): address

/// Get target listing
public fun tide_listing_id(order: &BuyOrder): ID

/// Get share requirements
public fun share_requirements(order: &BuyOrder): (u64, u64)  // (min, max)

/// Check if order is expired
public fun is_expired(order: &BuyOrder, ctx: &TxContext): bool

/// Check if pass matches order criteria
public fun matches_order(order: &BuyOrder, pass: &SupporterPass): bool

/// Get bid stats
public fun bid_stats(config: &MarketplaceConfig): &BidStats
```

---

## 5. Matching Algorithm

### 5.1 Simple Matching (v2)

For v2, we use simple exact matching:

```
1. Seller has pass with:
   - listing_id: X
   - shares: 100

2. Seller finds best BuyOrder where:
   - order.tide_listing_id == X
   - order.min_shares <= 100 <= order.max_shares (or 0 = any)
   - order.expires_at_epoch == 0 || order.expires_at_epoch > current_epoch
   
3. Seller calls instant_sell(order, pass)

4. Trade executes at order.bid_price
```

### 5.2 Best Bid Discovery (Off-Chain)

Since buy orders are individual shared objects, finding the best bid happens off-chain:

```typescript
// Indexer maintains sorted bid book
const bids = await indexer.getBidsForListing(listingId);
const sortedBids = bids.sort((a, b) => b.bidPrice - a.bidPrice);

// Find best matching bid for a pass
function findBestBid(passShares: number): BuyOrder | null {
  for (const bid of sortedBids) {
    if (bid.minShares <= passShares && 
        (bid.maxShares === 0 || bid.maxShares >= passShares)) {
      return bid;
    }
  }
  return null;
}
```

### 5.3 On-Chain Validation

The contract validates the match but doesn't search:

```move
// instant_sell validates but doesn't search
public fun instant_sell(
    config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    order: BuyOrder,  // Caller provides the order to fill
    pass: SupporterPass,
    ctx: &mut TxContext,
): (Coin<SUI>, InstantSaleReceipt) {
    // Validate match
    assert!(pass.listing_id() == order.tide_listing_id, EMismatchedListing);
    assert!(
        order.min_shares == 0 || pass.shares() >= order.min_shares,
        ESharesTooLow,
    );
    assert!(
        order.max_shares == 0 || pass.shares() <= order.max_shares,
        ESharesTooHigh,
    );
    assert!(!is_expired(&order, ctx), EOrderExpired);
    
    // Execute trade...
}
```

### 5.4 Future: On-Chain Order Book (v3+)

For v3, we could add a proper on-chain order book using sorted linked lists or DeepBook integration.

---

## 6. Events

### 6.1 New Events

```move
/// Emitted when a buy order is created
public struct BuyOrderCreated has copy, drop {
    order_id: ID,
    buyer: address,
    tide_listing_id: ID,
    bid_price: u64,
    min_shares: u64,
    max_shares: u64,
    expires_at_epoch: u64,
    epoch: u64,
}

/// Emitted when a buy order is cancelled
public struct BuyOrderCancelled has copy, drop {
    order_id: ID,
    buyer: address,
    refund_amount: u64,
    epoch: u64,
}

/// Emitted when a buy order is filled via instant_sell
public struct InstantSaleCompleted has copy, drop {
    order_id: ID,
    pass_id: ID,
    buyer: address,
    seller: address,
    price: u64,
    fee: u64,
    seller_proceeds: u64,
    shares: u64,
    epoch: u64,
}

/// Emitted when bid price is updated
public struct BidPriceUpdated has copy, drop {
    order_id: ID,
    old_price: u64,
    new_price: u64,
    epoch: u64,
}

/// Emitted when an order expires (optional, for cleanup)
public struct BuyOrderExpired has copy, drop {
    order_id: ID,
    buyer: address,
    epoch: u64,
}
```

---

## 7. User Flows

### 7.1 Creating a Buy Order

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        BUYER CREATES BID                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. Buyer wants to buy FAITH passes at 10 SUI                               │
│           │                                                                  │
│           ▼                                                                  │
│  2. Buyer calls create_buy_order(                                           │
│         tide_listing_id: FAITH_LISTING,                                     │
│         bid_price: 10 SUI,                                                  │
│         min_shares: 0,      // Any shares OK                                │
│         max_shares: 0,      // Any shares OK                                │
│         payment: 10 SUI,    // Escrowed                                     │
│         expires_in_epochs: 0  // Never expires                              │
│     )                                                                        │
│           │                                                                  │
│           ▼                                                                  │
│  3. BuyOrder created (shared object)                                        │
│     SUI escrowed in order                                                    │
│           │                                                                  │
│           ▼                                                                  │
│  4. BuyOrderCreated event emitted                                           │
│     Indexer picks up for order book display                                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Instant Selling

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SELLER INSTANT SELLS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. Seller has FAITH SupporterPass (50 shares)                              │
│     Wants instant cash                                                       │
│           │                                                                  │
│           ▼                                                                  │
│  2. Query indexer for best bid:                                             │
│     - Order A: 12 SUI, min 100 shares (doesn't match)                      │
│     - Order B: 10 SUI, min 0 shares (MATCHES!)                             │
│     - Order C: 8 SUI, min 0 shares (lower price)                           │
│           │                                                                  │
│           ▼                                                                  │
│  3. Seller calls instant_sell(order_B, pass)                                │
│           │                                                                  │
│           ├──────────────────────────────────────┐                          │
│           │                                      │                          │
│           ▼                                      ▼                          │
│  4a. Fee (5%): 0.5 SUI              4b. Pass transferred                   │
│      → TreasuryVault                     → Buyer (order_B.buyer)            │
│           │                                      │                          │
│           └──────────────────────────────────────┘                          │
│                          │                                                   │
│                          ▼                                                   │
│  5. Seller receives: 9.5 SUI (10 - 0.5 fee)                                 │
│                                                                              │
│  6. InstantSaleCompleted event emitted                                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 7.3 Flash Liquidation with Instant Sell

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                   FLASH LIQUIDATION + INSTANT SELL                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Prerequisites:                                                              │
│  - Unhealthy loan exists (owed: 50 SUI, collateral pass worth ~65 SUI)     │
│  - Buy order exists: 60 SUI bid for FAITH passes                           │
│                                                                              │
│  Liquidator calls flash_liquidate_and_sell() - ALL IN ONE TX:               │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ Step 1: Flash borrow 50 SUI from DeepBook                             │ │
│  │         (fee: ~0.3 SUI)                                               │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                               │                                              │
│                               ▼                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ Step 2: Liquidate Tide loan with 50 SUI                               │ │
│  │         → Receive SupporterPass (65 SUI collateral value)             │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                               │                                              │
│                               ▼                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ Step 3: Instant sell pass to buy order (60 SUI bid)                   │ │
│  │         Fee (5%): 3 SUI → Treasury                                    │ │
│  │         Proceeds: 57 SUI                                              │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                               │                                              │
│                               ▼                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ Step 4: Repay flash loan                                              │ │
│  │         Amount: 50 SUI + 0.3 SUI = 50.3 SUI                          │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                               │                                              │
│                               ▼                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ Step 5: Profit to liquidator                                          │ │
│  │         57 SUI - 50.3 SUI = 6.7 SUI profit!                          │ │
│  │         (Capital required: 0 SUI, just gas)                           │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 8. Security Considerations

### 8.1 Access Control

| Function | Access | Enforced By |
|----------|--------|-------------|
| `create_buy_order` | Anyone with SUI | Escrow requirement |
| `cancel_buy_order` | Order owner only | `assert!(sender == buyer)` |
| `update_bid_price` | Order owner only | `assert!(sender == buyer)` |
| `instant_sell` | Anyone with matching pass | Pass ownership |
| `fill_buy_order` | `tide_loans` package only | `public(package)` |

### 8.2 Escrow Safety

- Funds are **moved** into BuyOrder, not borrowed
- Only three exits: `instant_sell()`, `cancel_buy_order()`, or expiry cleanup
- Funds cannot be accessed by anyone except owner (cancel) or seller (fill)

### 8.3 Front-Running Considerations

**Risk:** Bot front-runs a large sell by creating a lower bid

**Mitigations:**
- Seller chooses which bid to fill
- Off-chain bid discovery means seller sees current best bid
- Minimal profit opportunity (just the spread difference)

### 8.4 Spam Prevention

| Protection | Value | Purpose |
|------------|-------|---------|
| `min_bid_amount` | 0.1 SUI | Prevent dust orders |
| `max_orders_per_buyer` | 100 | Limit order spam |
| Expiry cleanup | Optional | Remove stale orders |

### 8.5 Griefing Vectors

**Attack:** Create many buy orders to inflate stats
**Mitigation:** Gas costs + escrow lock makes this expensive

**Attack:** Cancel order right before fill
**Mitigation:** Atomic transactions - either full fill or nothing

---

## 9. Integration with Flash Liquidations

### 9.1 Cross-Package Access

The loans package needs to call `fill_buy_order`. We expose this via `public(package)`:

```move
// In marketplace.move
public(package) fun fill_buy_order(
    config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    order: BuyOrder,
    pass: SupporterPass,
    ctx: &mut TxContext,
): Coin<SUI>
```

But wait - `public(package)` only works within the same package!

**Solution:** Re-export via a friend function:

```move
// In marketplace.move
// Allow tide_loans to call our internal function
public fun fill_buy_order_for_liquidation(
    config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    order: BuyOrder,
    pass: SupporterPass,
    _liquidation_proof: &LiquidationProof,  // Capability from loans package
    ctx: &mut TxContext,
): Coin<SUI> {
    // Validate this is a legitimate liquidation
    // ... then call internal fill logic
}
```

Or simpler - just use `public` and let the loans package call `instant_sell` directly!

### 9.2 Flash Liquidation Integration

```move
// In tide_loans::flash_liquidator

public fun flash_liquidate_and_sell(
    // Loan objects
    loan_vault: &mut LoanVault,
    loan_id: ID,
    listing: &Listing,
    capital_vault: &CapitalVault,
    // DeepBook objects
    pool: &mut Pool<SUI, USDC>,
    // Marketplace objects
    marketplace_config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    buy_order: BuyOrder,
    ctx: &mut TxContext,
): Coin<SUI> {
    // 1. Validate bid covers loan + flash fee
    let payoff = loan_vault.outstanding_balance(loan_id);
    let flash_fee = pool.flash_loan_fee(payoff);
    let marketplace_fee = marketplace_config.calculate_fee(buy_order.bid_price());
    
    assert!(
        buy_order.bid_price() >= payoff + flash_fee + marketplace_fee,
        EBidTooLow,
    );
    
    // 2. Flash borrow
    let (flash_loan, borrowed) = pool.flash_loan(payoff, ctx);
    
    // 3. Liquidate
    let pass = loan_vault.liquidate(
        loan_id, listing, capital_vault, borrowed, ctx
    );
    
    // 4. Instant sell to the buy order
    let (proceeds, _receipt) = marketplace::instant_sell(
        marketplace_config,
        treasury_vault,
        buy_order,
        pass,
        ctx,
    );
    
    // 5. Repay flash loan
    let repay_amount = payoff + flash_fee;
    let repay_coin = proceeds.split(repay_amount, ctx);
    pool.repay_flash_loan(flash_loan, repay_coin);
    
    // 6. Return profit
    proceeds
}
```

---

## 10. Migration Plan

### 10.1 Upgrade Path

Since `MarketplaceConfig` needs new fields, we have two options:

**Option A: Add as Dynamic Fields (Recommended)**
```move
// Add bid_stats as dynamic field to existing config
dynamic_field::add(&mut config.id, b"bid_stats", BidStats { ... });
```

**Option B: Package Upgrade with Migration**
```move
// Migrate to new config struct
public fun migrate_config(
    old_config: MarketplaceConfigV1,
    admin_cap: &AdminCap,
    ctx: &mut TxContext,
): MarketplaceConfigV2
```

### 10.2 Backward Compatibility

- All v1 functions continue to work unchanged
- New functions are additive
- Events are new types (no conflicts)

### 10.3 Rollout Plan

| Phase | Action | Timeline |
|-------|--------|----------|
| 1 | Deploy marketplace v2 to testnet | Week 1 |
| 2 | Integration testing with flash liquidator | Week 2 |
| 3 | Upgrade mainnet marketplace (if already deployed) | Week 3 |
| 4 | Enable flash liquidations | Week 4 |

---

## 11. Testing Requirements

### 11.1 Unit Tests

**Buy Order Tests:**
- [ ] `test_create_buy_order`
- [ ] `test_create_buy_order_below_minimum_fails`
- [ ] `test_create_buy_order_wrong_amount_fails`
- [ ] `test_cancel_buy_order`
- [ ] `test_cancel_buy_order_wrong_owner_fails`
- [ ] `test_update_bid_price_increase`
- [ ] `test_update_bid_price_decrease`
- [ ] `test_order_expiry`

**Instant Sell Tests:**
- [ ] `test_instant_sell_success`
- [ ] `test_instant_sell_wrong_listing_fails`
- [ ] `test_instant_sell_shares_too_low_fails`
- [ ] `test_instant_sell_shares_too_high_fails`
- [ ] `test_instant_sell_expired_order_fails`
- [ ] `test_instant_sell_fee_calculation`
- [ ] `test_instant_sell_when_paused_fails`

**Matching Tests:**
- [ ] `test_matches_order_any_shares`
- [ ] `test_matches_order_min_shares`
- [ ] `test_matches_order_max_shares`
- [ ] `test_matches_order_range`

### 11.2 Integration Tests

- [ ] Full flow: create order → instant sell → verify balances
- [ ] Multiple orders: best bid selection
- [ ] Flash liquidation with instant sell

### 11.3 E2E Tests

- [ ] `test_e2e_create_bid_instant_sell_claim`
- [ ] `test_e2e_flash_liquidate_with_bid`
- [ ] `test_e2e_multi_bid_marketplace`

---

## 12. Appendix

### A. Error Codes

```move
// Existing v1 errors
const EMarketplacePaused: u64 = 1;
const ENotSeller: u64 = 2;
const EInsufficientPayment: u64 = 3;
const EZeroPrice: u64 = 4;
const EPriceTooLow: u64 = 5;

// New v2 errors
const ENotBuyer: u64 = 10;
const EBidTooLow: u64 = 11;
const EWrongEscrowAmount: u64 = 12;
const EOrderExpired: u64 = 13;
const EMismatchedListing: u64 = 14;
const ESharesTooLow: u64 = 15;
const ESharesTooHigh: u64 = 16;
const EMaxOrdersExceeded: u64 = 17;
```

### B. Gas Estimates

| Operation | Estimated Gas |
|-----------|---------------|
| `create_buy_order` | ~1,500 |
| `cancel_buy_order` | ~800 |
| `instant_sell` | ~2,500 |
| `update_bid_price` | ~600 |
| `flash_liquidate_and_sell` | ~5,000 |

### C. CLI Commands

```bash
# Create a buy order
sui client call \
  --package $MARKETPLACE_PKG \
  --module buy_order \
  --function create_buy_order \
  --args $CONFIG $TIDE_LISTING_ID $BID_PRICE 0 0 $PAYMENT_COIN 0 \
  --gas-budget 50000000

# Cancel a buy order
sui client call \
  --package $MARKETPLACE_PKG \
  --module buy_order \
  --function cancel_buy_order \
  --args $CONFIG $ORDER_ID \
  --gas-budget 50000000

# Instant sell
sui client call \
  --package $MARKETPLACE_PKG \
  --module marketplace \
  --function instant_sell_to_buyer \
  --args $CONFIG $TREASURY_VAULT $ORDER_ID $PASS_ID \
  --gas-budget 50000000
```

---

*End of Specification*
