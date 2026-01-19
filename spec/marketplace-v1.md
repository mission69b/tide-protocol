# Tide Marketplace Specification v1

> **Status**: ✅ IMPLEMENTED  
> **Author**: Tide Protocol Team  
> **Created**: 2026-01-19  
> **Target**: Sui Mainnet  

---

## 1. Overview

### 1.1 Purpose

The Tide Marketplace is a minimal, Sui-native marketplace for trading SupporterPass NFTs. It provides a yield-aware trading experience that generic NFT marketplaces cannot offer, while generating protocol revenue through seller fees.

### 1.2 Goals

1. **Simple Trading** - List, buy, delist with minimal friction
2. **Protocol Revenue** - 5% seller fee on all trades → TreasuryVault
3. **Yield Visibility** - Surface pending rewards and share data
4. **Decentralized** - Fully on-chain, permissionless trading

### 1.3 Non-Goals (v1)

- Auctions or bidding
- Offers/counteroffers
- Bundle sales
- Price oracles or fair value calculations
- Cross-listing aggregation

---

## 2. Architecture

### 2.1 Package Structure

```
contracts/
├── core/                    # tide_core (existing)
│   └── sources/
│       ├── supporter_pass.move
│       ├── reward_vault.move
│       ├── treasury_vault.move
│       └── ...
│
└── marketplace/             # tide_marketplace (NEW)
    ├── Move.toml
    ├── sources/
    │   └── marketplace.move
    └── tests/
        └── marketplace_tests.move
```

### 2.2 Dependencies

```toml
[dependencies]
tide_core = { local = "../core" }
Sui = { ... }
```

The marketplace depends on `tide_core` for:
- `SupporterPass` type and accessors
- `TreasuryVault` for fee deposits
- `Listing` for validation (optional)

### 2.3 Design Principles

1. **Escrow Model** - Passes are held by the SaleListing object, not the seller
2. **Shared Listings** - Each SaleListing is a shared object for atomic purchases
3. **No Central Registry** - Listings discovered via events/indexing
4. **Seller Pays Fee** - 5% deducted from proceeds, buyer pays listed price

---

## 3. Data Structures

### 3.1 MarketplaceConfig

Global configuration object (shared, singleton).

```move
struct MarketplaceConfig has key {
    id: UID,
    
    // Fee configuration
    fee_bps: u64,                    // 500 = 5% (immutable for trust)
    treasury_vault: ID,              // Where fees are sent
    
    // Admin
    admin: address,                  // Can pause marketplace
    paused: bool,                    // Emergency pause
    
    // Stats (for transparency)
    total_volume_sui: u64,           // Lifetime trading volume
    total_fees_collected_sui: u64,   // Lifetime fees
    total_sales_count: u64,          // Number of completed sales
    active_listings_count: u64,      // Current open listings
}
```

### 3.2 SaleListing

Individual listing object (shared).

```move
struct SaleListing has key {
    id: UID,
    
    // Ownership
    seller: address,
    
    // The NFT (escrowed)
    pass: SupporterPass,
    
    // Pricing
    price_sui: u64,                  // Asking price in MIST (1 SUI = 1e9 MIST)
    
    // Cached pass data (for indexing/display)
    tide_listing_id: ID,             // Which Tide listing this pass belongs to
    shares: u64,                     // Number of shares
    pass_number: u64,                // Original mint number
    
    // Metadata
    listed_at_epoch: u64,            // When listed
    updated_at_epoch: u64,           // Last price update
}
```

### 3.3 PurchaseReceipt

Returned to buyer on successful purchase (for composability).

```move
struct PurchaseReceipt has key, store {
    id: UID,
    listing_id: ID,                  // Original SaleListing ID
    pass_id: ID,                     // The SupporterPass purchased
    buyer: address,
    seller: address,
    price_paid: u64,
    fee_paid: u64,
    purchased_at_epoch: u64,
}
```

---

## 4. Core Functions

### 4.1 Initialization

```move
/// Called once on package publish
fun init(ctx: &mut TxContext) {
    let config = MarketplaceConfig {
        id: object::new(ctx),
        fee_bps: 500,  // 5% - hardcoded for trust
        treasury_vault: @treasury_vault_id,  // Set via migration or constant
        admin: ctx.sender(),
        paused: false,
        total_volume_sui: 0,
        total_fees_collected_sui: 0,
        total_sales_count: 0,
        active_listings_count: 0,
    };
    transfer::share_object(config);
}
```

### 4.2 Seller Functions

#### list_for_sale

```move
/// List a SupporterPass for sale
/// 
/// # Arguments
/// - `config`: Marketplace configuration
/// - `pass`: The SupporterPass to sell (transferred to listing)
/// - `price_sui`: Asking price in MIST
/// 
/// # Returns
/// - Creates a shared SaleListing object
/// 
/// # Access
/// - Permissionless (anyone with a SupporterPass)
public fun list_for_sale(
    config: &mut MarketplaceConfig,
    pass: SupporterPass,
    price_sui: u64,
    ctx: &mut TxContext,
): ID
```

**Validation:**
- `price_sui > 0` (no free listings)
- `!config.paused`

**Effects:**
1. Create `SaleListing` with escrowed pass
2. Increment `active_listings_count`
3. Emit `ListingCreated` event
4. Share the listing object
5. Return listing ID

---

#### delist

```move
/// Cancel a listing and return the pass to seller
/// 
/// # Arguments
/// - `config`: Marketplace configuration
/// - `listing`: The listing to cancel (consumed)
/// 
/// # Returns
/// - SupporterPass returned to seller
/// 
/// # Access
/// - Seller only
public fun delist(
    config: &mut MarketplaceConfig,
    listing: SaleListing,
    ctx: &mut TxContext,
): SupporterPass
```

**Validation:**
- `ctx.sender() == listing.seller`

**Effects:**
1. Decrement `active_listings_count`
2. Emit `ListingCancelled` event
3. Delete listing object
4. Return pass to caller

---

#### update_price

```move
/// Update the asking price of a listing
/// 
/// # Access
/// - Seller only
public fun update_price(
    listing: &mut SaleListing,
    new_price_sui: u64,
    ctx: &mut TxContext,
)
```

**Validation:**
- `ctx.sender() == listing.seller`
- `new_price_sui > 0`

**Effects:**
1. Update `price_sui`
2. Update `updated_at_epoch`
3. Emit `PriceUpdated` event

---

### 4.3 Buyer Functions

#### buy

```move
/// Purchase a listed SupporterPass
/// 
/// # Arguments
/// - `config`: Marketplace configuration
/// - `treasury_vault`: TreasuryVault to receive fees
/// - `listing`: The listing to purchase (consumed)
/// - `payment`: SUI coin (must be >= listing price)
/// 
/// # Returns
/// - (SupporterPass, PurchaseReceipt, Coin<SUI>) - pass, receipt, change
/// 
/// # Access
/// - Permissionless (anyone with sufficient SUI)
public fun buy(
    config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    listing: SaleListing,
    payment: Coin<SUI>,
    ctx: &mut TxContext,
): (SupporterPass, PurchaseReceipt, Coin<SUI>)
```

**Validation:**
- `!config.paused`
- `payment.value() >= listing.price_sui`

**Fee Calculation:**
```
fee = (price * fee_bps) / 10000
seller_proceeds = price - fee
```

**Effects:**
1. Calculate fee (5% of price)
2. Deposit fee to `TreasuryVault`
3. Transfer proceeds to seller
4. Update config stats:
   - `total_volume_sui += price`
   - `total_fees_collected_sui += fee`
   - `total_sales_count += 1`
   - `active_listings_count -= 1`
5. Emit `SaleCompleted` event
6. Delete listing object
7. Return pass, receipt, and any change

---

### 4.4 View Functions

```move
/// Get listing price
public fun price(listing: &SaleListing): u64

/// Get seller address
public fun seller(listing: &SaleListing): address

/// Get the pass ID (without consuming)
public fun pass_id(listing: &SaleListing): ID

/// Get cached share count
public fun shares(listing: &SaleListing): u64

/// Get the Tide listing this pass belongs to
public fun tide_listing_id(listing: &SaleListing): ID

/// Calculate fee for a given price
public fun calculate_fee(config: &MarketplaceConfig, price: u64): u64

/// Get marketplace stats
public fun stats(config: &MarketplaceConfig): (u64, u64, u64, u64)
// Returns: (volume, fees, sales_count, active_count)
```

---

### 4.5 Admin Functions

```move
/// Pause the marketplace (emergency only)
/// Prevents new listings and purchases, but allows delisting
public fun pause(
    config: &mut MarketplaceConfig,
    ctx: &TxContext,
)

/// Unpause the marketplace
public fun unpause(
    config: &mut MarketplaceConfig,
    ctx: &TxContext,
)

/// Transfer admin rights
public fun transfer_admin(
    config: &mut MarketplaceConfig,
    new_admin: address,
    ctx: &TxContext,
)
```

**Access:** `ctx.sender() == config.admin`

---

## 5. Events

### 5.1 Event Definitions

```move
/// Emitted when a pass is listed for sale
struct ListingCreated has copy, drop {
    listing_id: ID,
    seller: address,
    pass_id: ID,
    tide_listing_id: ID,
    shares: u64,
    pass_number: u64,
    price_sui: u64,
    epoch: u64,
}

/// Emitted when a listing is cancelled
struct ListingCancelled has copy, drop {
    listing_id: ID,
    seller: address,
    pass_id: ID,
    epoch: u64,
}

/// Emitted when price is updated
struct PriceUpdated has copy, drop {
    listing_id: ID,
    old_price_sui: u64,
    new_price_sui: u64,
    epoch: u64,
}

/// Emitted when a sale completes
struct SaleCompleted has copy, drop {
    listing_id: ID,
    pass_id: ID,
    seller: address,
    buyer: address,
    price_sui: u64,
    fee_sui: u64,
    seller_proceeds_sui: u64,
    epoch: u64,
}

/// Emitted when marketplace is paused/unpaused
struct MarketplacePaused has copy, drop {
    paused: bool,
    admin: address,
    epoch: u64,
}
```

---

## 6. User Flows

### 6.1 Listing a Pass

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

### 6.2 Buying a Pass

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
│  5. PurchaseReceipt returned (optional composability)           │
│           │                                                     │
│           ▼                                                     │
│  6. SaleCompleted event emitted                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.3 Cancelling a Listing

```
┌─────────────────────────────────────────────────────────────────┐
│                     SELLER DELISTS                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Seller calls marketplace::delist(listing)                   │
│           │                                                     │
│           ▼                                                     │
│  2. Verify sender == listing.seller                             │
│           │                                                     │
│           ▼                                                     │
│  3. SupporterPass returned to seller                            │
│           │                                                     │
│           ▼                                                     │
│  4. SaleListing object deleted                                  │
│           │                                                     │
│           ▼                                                     │
│  5. ListingCancelled event emitted                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. Fee Economics

### 7.1 Fee Structure

| Parameter | Value | Notes |
|-----------|-------|-------|
| Seller Fee | 5% (500 bps) | Deducted from sale proceeds |
| Buyer Fee | 0% | Buyer pays listed price only |
| Listing Fee | 0 | Free to list |
| Delist Fee | 0 | Free to cancel |

### 7.2 Fee Example

```
Listed Price:    100 SUI
─────────────────────────
Seller Receives:  95 SUI  (100 - 5%)
Protocol Fee:      5 SUI  → TreasuryVault
Buyer Pays:      100 SUI
```

### 7.3 Revenue Projections

| Monthly Volume | 5% Fee Revenue |
|----------------|----------------|
| 10,000 SUI | 500 SUI |
| 50,000 SUI | 2,500 SUI |
| 100,000 SUI | 5,000 SUI |
| 500,000 SUI | 25,000 SUI |
| 1,000,000 SUI | 50,000 SUI |

---

## 8. Security Considerations

### 8.1 Access Control Matrix

| Function | Access | Enforced By |
|----------|--------|-------------|
| `list_for_sale` | Anyone with SupporterPass | Ownership transfer |
| `delist` | Seller only | `assert!(sender == seller)` |
| `update_price` | Seller only | `assert!(sender == seller)` |
| `buy` | Anyone with SUI | Payment verification |
| `pause/unpause` | Admin only | `assert!(sender == admin)` |
| `transfer_admin` | Admin only | `assert!(sender == admin)` |

### 8.2 Escrow Safety

- Pass is **moved** into SaleListing, not borrowed
- Only two exits: `buy()` or `delist()`
- Pass cannot be accessed while listed
- No reentrancy possible (Move's ownership model)

### 8.3 Payment Safety

- Exact payment enforced: `payment.value() >= price`
- Change returned to buyer
- Seller proceeds calculated after fee deduction
- Fee deposited atomically with purchase

### 8.4 Front-Running Considerations

- **Price sniping**: Buyer might front-run price updates
  - Mitigation: Seller can delist instead of updating
- **Race conditions**: Multiple buyers for same listing
  - Only one succeeds (Sui's object model)
  - Others fail gracefully

### 8.5 Paused State Behavior

| Function | When Paused |
|----------|-------------|
| `list_for_sale` | ❌ Blocked |
| `delist` | ✅ Allowed (seller protection) |
| `update_price` | ✅ Allowed |
| `buy` | ❌ Blocked |

---

## 9. Integration Points

### 9.1 TreasuryVault Integration

The marketplace needs to deposit fees to `TreasuryVault`. Options:

**Option A: Public Deposit Function (Recommended)**
```move
// In treasury_vault.move
public fun deposit_marketplace_fee(
    self: &mut TreasuryVault,
    coin: Coin<SUI>,
    ctx: &TxContext,
)
```

**Option B: MarketplaceCap**
```move
// Capability held by marketplace package
struct MarketplaceCap has key, store { id: UID }
```

### 9.2 SupporterPass Accessors

Marketplace uses these existing public accessors:
- `pass.shares()` - For display
- `pass.listing_id()` - For filtering
- `pass.pass_number()` - For display
- `pass.claim_index()` - For yield calculation (optional)

### 9.3 Indexer Requirements

Events needed for full indexer support:
- `ListingCreated` - Add to listings index
- `ListingCancelled` - Remove from listings index
- `PriceUpdated` - Update listing price
- `SaleCompleted` - Update ownership, add to sales history

---

## 10. Future Enhancements (v2+)

### 10.1 Potential Features

| Feature | Priority | Complexity |
|---------|----------|------------|
| Offers/Bids | Medium | Medium |
| Auctions | Low | High |
| Bundle Sales | Low | Medium |
| Collection Offers | Medium | Medium |
| Price History | High | Low (indexer) |
| Floor Price Tracking | High | Low (indexer) |
| TransferPolicy Royalty | High | Medium |

### 10.2 TransferPolicy Integration

For ecosystem-wide royalties (works on any Kiosk marketplace):

```move
/// Add 5% royalty rule to SupporterPass transfers
public fun setup_royalty_policy(
    publisher: &Publisher,
    ctx: &mut TxContext,
) {
    let (policy, cap) = transfer_policy::new<SupporterPass>(publisher, ctx);
    
    // Add royalty rule
    royalty_rule::add<SupporterPass>(
        &mut policy,
        &cap,
        500,  // 5% in basis points
        0,    // no minimum
    );
    
    transfer::public_share_object(policy);
    transfer::public_transfer(cap, ctx.sender());
}
```

### 10.3 Yield-Aware Pricing (v2)

```move
/// Calculate "fair value" based on pending rewards
public fun calculate_fair_value(
    listing: &SaleListing,
    reward_vault: &RewardVault,
): u64 {
    let pending = reward_vault.calculate_claimable(
        listing.shares,
        listing.claim_index,
    );
    listing.price_sui + pending
}
```

---

## 11. Implementation Plan

### Phase 1: Core Marketplace (v1) ✅ COMPLETE
- [x] Create `contracts/marketplace/` package
- [x] Implement `MarketplaceConfig` and `SaleListing`
- [x] Implement `list_for_sale`, `delist`, `buy`, `update_price`
- [x] Implement admin functions (`pause`, `unpause`, `transfer_admin`)
- [x] Add events (ListingCreated, SaleCompleted, ListingCancelled, etc.)
- [x] Write unit tests (20 tests)
- [x] Add versioning (VERSION constant + version field)
- [ ] Deploy to testnet

### Phase 2: Integration ✅ COMPLETE
- [x] Add `deposit_marketplace_fee` to `TreasuryVault` (uses existing `deposit()`)
- [x] E2E testing with core (3 E2E tests)
- [ ] Deploy with core integration

### Phase 3: Indexer & UI
- [ ] Build indexer for marketplace events
- [ ] Create marketplace UI
- [ ] Price history and analytics

---

## 12. Testing Checklist

### Unit Tests ✅ (20 tests)
- [x] `test_list_for_sale` - Basic listing
- [x] `test_delist` - Cancel listing
- [x] `test_buy` - Successful purchase
- [x] `test_fee_calculation` - Verify 5% fee
- [x] `test_update_price` - Price updates
- [x] `test_buy_insufficient_payment_fails` - Should fail
- [x] `test_delist_wrong_seller_fails` - Should fail
- [x] `test_buy_when_paused_fails` - Should fail
- [x] `test_delist_when_paused` - Should succeed
- [x] `test_pause_wrong_caller_fails` - Access control
- [x] `test_transfer_admin_wrong_caller_fails` - Access control
- [x] Additional: init, buy_with_change, list_zero_price, list_below_minimum, etc.

### E2E Tests ✅ (3 tests)
- [x] `test_e2e_deposit_list_buy_claim` - Full flow: deposit → list → buy → claim rewards
- [x] `test_e2e_list_delist` - List → delist → claim
- [x] `test_e2e_multi_seller_marketplace` - Multiple sellers scenario

---

## 13. Open Questions

1. **Should pending rewards be claimable while listed?**
   - Option A: No - rewards accumulate, buyer gets them
   - Option B: Yes - seller can claim anytime (more complex)

2. **Minimum listing price?**
   - Prevents dust attacks
   - Suggested: 0.1 SUI minimum

3. **Maximum active listings per seller?**
   - Prevents spam
   - Or rely on gas costs as natural limiter

4. **Should we show "implied yield" on listings?**
   - Requires RewardVault read access
   - Great for UX but adds complexity

---

## Appendix A: Error Codes

```move
const EMarketplacePaused: u64 = 1;
const ENotSeller: u64 = 2;
const EInsufficientPayment: u64 = 3;
const EZeroPrice: u64 = 4;
const EPriceTooLow: u64 = 5;  // If minimum enforced
```

---

## Appendix B: Gas Estimates

| Operation | Estimated Gas |
|-----------|---------------|
| `list_for_sale` | ~1,500 |
| `delist` | ~800 |
| `buy` | ~2,000 |
| `update_price` | ~500 |

---

*End of Specification*
