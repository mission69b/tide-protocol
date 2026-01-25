# Tide Marketplace

A native, Sui-powered marketplace for trading SupporterPass NFTs with integrated yield visibility.

## Overview

The Tide Marketplace enables peer-to-peer trading of SupporterPass NFTs with:
- **5% seller fee** → Protocol TreasuryVault
- **Minimum listing price** of 0.1 SUI
- **Escrow model** for trustless atomic trades
- **Full yield visibility** (shares, pending rewards, earning history)

Unlike generic NFT marketplaces, Tide Marketplace understands SupporterPass economics and can surface:
- Current claimable rewards
- Share percentage of the listing
- Historical yield (total_claimed)
- Original backer provenance

## Quick Start

### List a Pass for Sale

```bash
sui client call \
  --package $MARKETPLACE_PKG \
  --module marketplace \
  --function list_for_sale \
  --args $CONFIG_ID $PASS_ID $PRICE_MIST
```

### Buy a Listed Pass

```bash
sui client call \
  --package $MARKETPLACE_PKG \
  --module marketplace \
  --function buy_and_take \
  --args $CONFIG_ID $TREASURY_VAULT_ID $LISTING_ID $PAYMENT_COIN_ID
```

### Cancel a Listing

```bash
sui client call \
  --package $MARKETPLACE_PKG \
  --module marketplace \
  --function delist \
  --args $CONFIG_ID $LISTING_ID
```

## Architecture

### Package Structure

```
contracts/marketplace/
├── Move.toml              # Package config (depends on tide_core)
├── sources/
│   └── marketplace.move   # Core marketplace logic (~500 lines)
└── tests/
    └── marketplace_tests.move  # 18 comprehensive tests
```

### Key Objects

| Object | Type | Purpose |
|--------|------|---------|
| `MarketplaceConfig` | Shared | Global config, stats, admin, pause flag |
| `SaleListing` | Shared | Individual listing with escrowed pass |
| `PurchaseReceipt` | Owned | Proof of purchase (for composability) |

### Dependencies

The marketplace depends on `tide_core` for:
- `SupporterPass` type and accessors
- `TreasuryVault` for fee deposits

```toml
[dependencies]
tide_core = { local = "../core" }
```

## Core Functions

### Seller Functions

| Function | Description | Access |
|----------|-------------|--------|
| `list_for_sale(pass, price)` | List a SupporterPass for sale | Anyone with pass |
| `delist(listing)` | Cancel listing, return pass | Seller only |
| `update_price(listing, price)` | Change asking price | Seller only |

### Buyer Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `buy(listing, payment)` | Purchase pass | (SupporterPass, PurchaseReceipt, Coin change) |
| `buy_and_take(listing, payment)` | Buy + transfer to sender | (void) |

### Admin Functions

| Function | Description |
|----------|-------------|
| `pause()` | Emergency pause (blocks list/buy, allows delist) |
| `unpause()` | Resume normal operations |
| `transfer_admin()` | Transfer admin rights |

### View Functions

| Function | Returns |
|----------|---------|
| `price(listing)` | Asking price in MIST |
| `seller(listing)` | Seller address |
| `shares(listing)` | Cached share count |
| `calculate_fee(price)` | Fee for given price |
| `stats(config)` | (volume, fees, sales, active) |
| `fee_bps()` | 500 (5%) |
| `min_price()` | 100_000_000 (0.1 SUI) |

## Fee Structure

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Seller Fee** | 5% (500 bps) | Deducted from sale proceeds |
| **Buyer Fee** | 0% | Buyer pays listed price only |
| **Listing Fee** | 0 | Free to list |
| **Delist Fee** | 0 | Free to cancel |
| **Minimum Price** | 0.1 SUI | Prevents dust listings |

### Fee Example

```
Listed Price:    100 SUI
─────────────────────────
Seller Receives:  95 SUI  (100 - 5%)
Protocol Fee:      5 SUI  → TreasuryVault
Buyer Pays:      100 SUI
```

### Revenue Projections

| Monthly Volume | 5% Fee Revenue |
|----------------|----------------|
| 10,000 SUI | 500 SUI |
| 50,000 SUI | 2,500 SUI |
| 100,000 SUI | 5,000 SUI |
| 500,000 SUI | 25,000 SUI |
| 1,000,000 SUI | 50,000 SUI |

## User Flows

### Listing a Pass

```
┌─────────────────────────────────────────────────────────────────┐
│                     SELLER LISTS PASS                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Seller owns SupporterPass                                   │
│           │                                                     │
│           ▼                                                     │
│  2. Call marketplace::list_for_sale(pass, price)                │
│           │                                                     │
│           ▼                                                     │
│  3. Pass escrowed in SaleListing (shared object)                │
│           │                                                     │
│           ▼                                                     │
│  4. ListingCreated event emitted                                │
│           │                                                     │
│           ▼                                                     │
│  5. Indexer picks up listing for UI display                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Buying a Pass

```
┌─────────────────────────────────────────────────────────────────┐
│                     BUYER PURCHASES PASS                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Buyer browses listings (via indexer/UI)                     │
│           │                                                     │
│           ▼                                                     │
│  2. Call marketplace::buy(listing, payment_coin)                │
│           │                                                     │
│           ├──────────────────────────────────────┐              │
│           │                                      │              │
│           ▼                                      ▼              │
│  3a. Fee (5%) deposited           3b. Proceeds (95%)            │
│      to TreasuryVault                 sent to seller            │
│           │                                      │              │
│           └──────────────────────────────────────┘              │
│                          │                                      │
│                          ▼                                      │
│  4. SupporterPass transferred to buyer                          │
│           │                                                     │
│           ▼                                                     │
│  5. SaleCompleted event emitted                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Events

| Event | When Emitted | Key Fields |
|-------|--------------|------------|
| `ListingCreated` | Pass listed for sale | listing_id, seller, pass_id, price, shares |
| `ListingCancelled` | Listing cancelled | listing_id, seller, pass_id |
| `PriceUpdated` | Price changed | listing_id, old_price, new_price |
| `SaleCompleted` | Purchase completed | listing_id, buyer, seller, price, fee |
| `MarketplacePaused` | Pause toggled | paused, admin |
| `AdminTransferred` | Admin changed | old_admin, new_admin |

## Security

### Access Control

| Function | Access | Enforced By |
|----------|--------|-------------|
| `list_for_sale` | Anyone with SupporterPass | Ownership transfer |
| `delist` | Seller only | `assert!(sender == seller)` |
| `update_price` | Seller only | `assert!(sender == seller)` |
| `buy` | Anyone with SUI | Payment verification |
| `pause/unpause` | Admin only | `assert!(sender == admin)` |

### Escrow Safety

- Pass is **moved** into SaleListing, not borrowed
- Only two exits: `buy()` or `delist()`
- Pass cannot be accessed while listed
- No reentrancy possible (Move's ownership model)

### Paused State Behavior

| Function | When Paused |
|----------|-------------|
| `list_for_sale` | ❌ Blocked |
| `delist` | ✅ Allowed (seller protection) |
| `update_price` | ✅ Allowed |
| `buy` | ❌ Blocked |

## Error Codes

| Code | Constant | Meaning |
|------|----------|---------|
| 1 | `EMarketplacePaused` | Marketplace is paused |
| 2 | `ENotSeller` | Caller is not the seller |
| 3 | `EInsufficientPayment` | Payment less than price |
| 4 | `EZeroPrice` | Price cannot be zero |
| 5 | `EPriceTooLow` | Price below minimum (0.1 SUI) |

## Build & Test

```bash
cd contracts/marketplace

# Build
sui move build

# Run all tests
sui move test

# Run specific test
sui move test test_buy
```

### Test Coverage (18 tests)

- ✅ Basic operations (list, delist, buy, update_price)
- ✅ Fee calculation (5% verified)
- ✅ Change handling (overpayment returns change)
- ✅ Admin operations (pause, unpause, transfer_admin)
- ✅ Error cases (insufficient payment, wrong seller, paused, zero price, below minimum)
- ✅ Edge cases (delist when paused)

## Deployment

### 1. Build the Package

```bash
cd contracts/marketplace
sui move build
```

### 2. Publish

```bash
sui client publish --gas-budget 500000000
```

### 3. Record Object IDs

After publish, note:
- `MarketplaceConfig` object ID (shared)
- `Package ID`
- `UpgradeCap` ID

### 4. Update Move.toml

```toml
published-at = "0x<PACKAGE_ID>"
```

## Integration with Core

The marketplace integrates with `tide_core` in two ways:

### 1. SupporterPass Accessors

The marketplace uses public accessors from `SupporterPass`:
- `pass.shares()` - For display/indexing
- `pass.listing_id()` - To group by Tide listing
- `pass.pass_number()` - For collectibility display
- `pass.id()` - Object identification

### 2. TreasuryVault Fee Deposit

Fees are deposited using the public `deposit()` function:
```move
treasury_vault.deposit(fee_coin);
```

This emits a `TreasuryDeposit` event for tracking.

## Future Enhancements (v2)

| Feature | Priority | Description |
|---------|----------|-------------|
| Offers/Bids | Medium | Allow buyers to make offers |
| Auctions | Low | Time-limited bidding |
| Bundle Sales | Low | Sell multiple passes together |
| TransferPolicy | High | Ecosystem-wide royalty enforcement |
| Yield Display | High | Show pending rewards on UI |

## Future: Marketplace v2 (Bid System) — Deferred

A bid system was considered to enable:
- **Buy Orders** - Buyers place standing bids with escrowed funds
- **Instant Sell** - Sellers match against best bid
- **Flash Liquidations** - Capital-free liquidations via DeepBook

**Status:** ⏸️ **DEFERRED** — Flash Liquidate + Keep provides 90% of value without requiring a bid system.

See [spec/marketplace-v2.md](./spec/marketplace-v2.md) for the specification (when revisiting).

## Related Documentation

- [spec/marketplace-v1.md](./spec/marketplace-v1.md) - Full technical specification (current)
- [spec/marketplace-v2.md](./spec/marketplace-v2.md) - Bid system specification (deferred)
- [README.md](./README.md) - Protocol overview
- [ADAPTERS.md](./ADAPTERS.md) - Revenue adapter integration
