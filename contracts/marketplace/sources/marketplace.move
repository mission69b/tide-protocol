/// Tide Marketplace - Native marketplace for SupporterPass NFTs.
/// 
/// Features:
/// - List SupporterPass for sale (escrow model)
/// - Buy with atomic fee collection (5% seller fee)
/// - Delist to recover escrowed pass
/// - Update listing price
/// 
/// Fee Structure:
/// - 5% (500 bps) seller fee on all sales
/// - Fees deposited to TreasuryVault
module tide_marketplace::marketplace;

use sui::sui::SUI;
use sui::coin::Coin;
use sui::event;

use tide_core::supporter_pass::SupporterPass;
use tide_core::treasury_vault::TreasuryVault;

// === Error Codes ===

const EMarketplacePaused: u64 = 1;
const ENotSeller: u64 = 2;
const EInsufficientPayment: u64 = 3;
const EZeroPrice: u64 = 4;
const EPriceTooLow: u64 = 5;

// === Constants ===

/// 5% fee in basis points (500 / 10000 = 5%)
const FEE_BPS: u64 = 500;

/// Basis points denominator
const BPS_DENOMINATOR: u64 = 10000;

/// Minimum listing price (0.1 SUI = 100_000_000 MIST)
const MIN_PRICE: u64 = 100_000_000;

// === Structs ===

/// Global marketplace configuration (shared, singleton).
public struct MarketplaceConfig has key {
    id: UID,
    /// Admin address (can pause/unpause).
    admin: address,
    /// Emergency pause flag.
    paused: bool,
    /// Total trading volume (MIST).
    total_volume: u64,
    /// Total fees collected (MIST).
    total_fees_collected: u64,
    /// Total completed sales.
    total_sales_count: u64,
    /// Current active listings count.
    active_listings_count: u64,
}

/// Individual sale listing (shared object).
public struct SaleListing has key {
    id: UID,
    /// Seller address.
    seller: address,
    /// Escrowed SupporterPass.
    pass: SupporterPass,
    /// Asking price in MIST.
    price: u64,
    /// Tide listing ID this pass belongs to.
    tide_listing_id: ID,
    /// Cached shares for indexing.
    shares: u128,
    /// Cached pass number for indexing.
    pass_number: u64,
    /// Epoch when listed.
    listed_at_epoch: u64,
    /// Epoch when price last updated.
    updated_at_epoch: u64,
}

/// Receipt returned to buyer on purchase (for composability).
public struct PurchaseReceipt has key, store {
    id: UID,
    /// Original SaleListing ID.
    listing_id: ID,
    /// The SupporterPass ID purchased.
    pass_id: ID,
    /// Buyer address.
    buyer: address,
    /// Seller address.
    seller: address,
    /// Price paid (MIST).
    price_paid: u64,
    /// Fee paid (MIST).
    fee_paid: u64,
    /// Epoch of purchase.
    purchased_at_epoch: u64,
}

// === Events ===

/// Emitted when a pass is listed for sale.
public struct ListingCreated has copy, drop {
    listing_id: ID,
    seller: address,
    pass_id: ID,
    tide_listing_id: ID,
    shares: u128,
    pass_number: u64,
    price: u64,
    epoch: u64,
}

/// Emitted when a listing is cancelled.
public struct ListingCancelled has copy, drop {
    listing_id: ID,
    seller: address,
    pass_id: ID,
    epoch: u64,
}

/// Emitted when price is updated.
public struct PriceUpdated has copy, drop {
    listing_id: ID,
    old_price: u64,
    new_price: u64,
    epoch: u64,
}

/// Emitted when a sale completes.
public struct SaleCompleted has copy, drop {
    listing_id: ID,
    pass_id: ID,
    seller: address,
    buyer: address,
    price: u64,
    fee: u64,
    seller_proceeds: u64,
    epoch: u64,
}

/// Emitted when marketplace is paused/unpaused.
public struct MarketplacePaused has copy, drop {
    paused: bool,
    admin: address,
    epoch: u64,
}

/// Emitted when admin is transferred.
public struct AdminTransferred has copy, drop {
    old_admin: address,
    new_admin: address,
    epoch: u64,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    let config = MarketplaceConfig {
        id: object::new(ctx),
        admin: ctx.sender(),
        paused: false,
        total_volume: 0,
        total_fees_collected: 0,
        total_sales_count: 0,
        active_listings_count: 0,
    };
    transfer::share_object(config);
}

// === Seller Functions ===

/// List a SupporterPass for sale.
/// The pass is escrowed in a shared SaleListing object.
/// 
/// # Arguments
/// - `config`: Marketplace configuration
/// - `pass`: The SupporterPass to sell (transferred to listing)
/// - `price`: Asking price in MIST (minimum 0.1 SUI)
/// 
/// # Returns
/// - ID of the created SaleListing
public fun list_for_sale(
    config: &mut MarketplaceConfig,
    pass: SupporterPass,
    price: u64,
    ctx: &mut TxContext,
): ID {
    // Validate
    assert!(!config.paused, EMarketplacePaused);
    assert!(price > 0, EZeroPrice);
    assert!(price >= MIN_PRICE, EPriceTooLow);
    
    let pass_id = pass.id();
    let tide_listing_id = pass.listing_id();
    let shares = pass.shares();
    let pass_number = pass.pass_number();
    let epoch = ctx.epoch();
    let seller = ctx.sender();
    
    let listing = SaleListing {
        id: object::new(ctx),
        seller,
        pass,
        price,
        tide_listing_id,
        shares,
        pass_number,
        listed_at_epoch: epoch,
        updated_at_epoch: epoch,
    };
    
    let listing_id = object::id(&listing);
    
    // Update stats
    config.active_listings_count = config.active_listings_count + 1;
    
    // Emit event
    event::emit(ListingCreated {
        listing_id,
        seller,
        pass_id,
        tide_listing_id,
        shares,
        pass_number,
        price,
        epoch,
    });
    
    // Share the listing
    transfer::share_object(listing);
    
    listing_id
}

/// Cancel a listing and return the pass to seller.
/// Only the original seller can delist.
/// 
/// # Arguments
/// - `config`: Marketplace configuration
/// - `listing`: The listing to cancel (consumed)
/// 
/// # Returns
/// - SupporterPass returned to caller
public fun delist(
    config: &mut MarketplaceConfig,
    listing: SaleListing,
    ctx: &mut TxContext,
): SupporterPass {
    // Validate seller
    assert!(ctx.sender() == listing.seller, ENotSeller);
    
    let SaleListing {
        id,
        seller,
        pass,
        price: _,
        tide_listing_id: _,
        shares: _,
        pass_number: _,
        listed_at_epoch: _,
        updated_at_epoch: _,
    } = listing;
    
    let listing_id = id.to_inner();
    let pass_id = pass.id();
    
    // Update stats
    config.active_listings_count = config.active_listings_count - 1;
    
    // Emit event
    event::emit(ListingCancelled {
        listing_id,
        seller,
        pass_id,
        epoch: ctx.epoch(),
    });
    
    // Delete listing
    id.delete();
    
    pass
}

/// Update the asking price of a listing.
/// Only the seller can update.
/// 
/// # Arguments
/// - `listing`: The listing to update
/// - `new_price`: New asking price in MIST
public fun update_price(
    listing: &mut SaleListing,
    new_price: u64,
    ctx: &mut TxContext,
) {
    // Validate
    assert!(ctx.sender() == listing.seller, ENotSeller);
    assert!(new_price > 0, EZeroPrice);
    assert!(new_price >= MIN_PRICE, EPriceTooLow);
    
    let old_price = listing.price;
    listing.price = new_price;
    listing.updated_at_epoch = ctx.epoch();
    
    // Emit event
    event::emit(PriceUpdated {
        listing_id: object::id(listing),
        old_price,
        new_price,
        epoch: ctx.epoch(),
    });
}

// === Buyer Functions ===

/// Purchase a listed SupporterPass.
/// 5% fee is deducted from proceeds and sent to TreasuryVault.
/// 
/// # Arguments
/// - `config`: Marketplace configuration
/// - `treasury_vault`: TreasuryVault to receive fees
/// - `listing`: The listing to purchase (consumed)
/// - `payment`: SUI coin (must be >= listing price)
/// 
/// # Returns
/// - (SupporterPass, PurchaseReceipt, Coin<SUI>) - pass, receipt, change
public fun buy(
    config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    listing: SaleListing,
    mut payment: Coin<SUI>,
    ctx: &mut TxContext,
): (SupporterPass, PurchaseReceipt, Coin<SUI>) {
    // Validate
    assert!(!config.paused, EMarketplacePaused);
    assert!(payment.value() >= listing.price, EInsufficientPayment);
    
    let SaleListing {
        id,
        seller,
        pass,
        price,
        tide_listing_id: _,
        shares: _,
        pass_number: _,
        listed_at_epoch: _,
        updated_at_epoch: _,
    } = listing;
    
    let listing_id = id.to_inner();
    let pass_id = pass.id();
    let buyer = ctx.sender();
    let epoch = ctx.epoch();
    
    // Calculate fee (5%)
    let fee = calculate_fee_internal(price);
    let seller_proceeds = price - fee;
    
    // Split payment
    let fee_coin = payment.split(fee, ctx);
    let seller_coin = payment.split(seller_proceeds, ctx);
    let change = payment; // Remaining is change
    
    // Deposit fee to treasury
    treasury_vault.deposit(fee_coin);
    
    // Transfer proceeds to seller
    transfer::public_transfer(seller_coin, seller);
    
    // Update stats
    config.total_volume = config.total_volume + price;
    config.total_fees_collected = config.total_fees_collected + fee;
    config.total_sales_count = config.total_sales_count + 1;
    config.active_listings_count = config.active_listings_count - 1;
    
    // Emit event
    event::emit(SaleCompleted {
        listing_id,
        pass_id,
        seller,
        buyer,
        price,
        fee,
        seller_proceeds,
        epoch,
    });
    
    // Create receipt
    let receipt = PurchaseReceipt {
        id: object::new(ctx),
        listing_id,
        pass_id,
        buyer,
        seller,
        price_paid: price,
        fee_paid: fee,
        purchased_at_epoch: epoch,
    };
    
    // Delete listing
    id.delete();
    
    (pass, receipt, change)
}

/// Convenience function: buy and transfer pass directly to buyer.
/// Also burns the receipt (if not needed for composability).
#[allow(lint(self_transfer))]
public fun buy_and_take(
    config: &mut MarketplaceConfig,
    treasury_vault: &mut TreasuryVault,
    listing: SaleListing,
    payment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    let (pass, receipt, change) = buy(config, treasury_vault, listing, payment, ctx);
    
    let buyer = ctx.sender();
    
    // Transfer pass to buyer
    transfer::public_transfer(pass, buyer);
    
    // Burn receipt (or could transfer - design choice)
    let PurchaseReceipt {
        id,
        listing_id: _,
        pass_id: _,
        buyer: _,
        seller: _,
        price_paid: _,
        fee_paid: _,
        purchased_at_epoch: _,
    } = receipt;
    id.delete();
    
    // Return change if any
    if (change.value() > 0) {
        transfer::public_transfer(change, buyer);
    } else {
        change.destroy_zero();
    };
}

// === Admin Functions ===

/// Pause the marketplace (emergency only).
/// Prevents new listings and purchases, but allows delisting.
public fun pause(
    config: &mut MarketplaceConfig,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == config.admin, ENotSeller); // Reusing error
    config.paused = true;
    
    event::emit(MarketplacePaused {
        paused: true,
        admin: ctx.sender(),
        epoch: ctx.epoch(),
    });
}

/// Unpause the marketplace.
public fun unpause(
    config: &mut MarketplaceConfig,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == config.admin, ENotSeller);
    config.paused = false;
    
    event::emit(MarketplacePaused {
        paused: false,
        admin: ctx.sender(),
        epoch: ctx.epoch(),
    });
}

/// Transfer admin rights to a new address.
public fun transfer_admin(
    config: &mut MarketplaceConfig,
    new_admin: address,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == config.admin, ENotSeller);
    
    let old_admin = config.admin;
    config.admin = new_admin;
    
    event::emit(AdminTransferred {
        old_admin,
        new_admin,
        epoch: ctx.epoch(),
    });
}

// === View Functions ===

/// Get listing price.
public fun price(listing: &SaleListing): u64 {
    listing.price
}

/// Get seller address.
public fun seller(listing: &SaleListing): address {
    listing.seller
}

/// Get the escrowed pass ID.
public fun pass_id(listing: &SaleListing): ID {
    listing.pass.id()
}

/// Get cached share count.
public fun shares(listing: &SaleListing): u128 {
    listing.shares
}

/// Get the Tide listing this pass belongs to.
public fun tide_listing_id(listing: &SaleListing): ID {
    listing.tide_listing_id
}

/// Get pass number.
public fun pass_number(listing: &SaleListing): u64 {
    listing.pass_number
}

/// Get listed epoch.
public fun listed_at_epoch(listing: &SaleListing): u64 {
    listing.listed_at_epoch
}

/// Calculate fee for a given price.
public fun calculate_fee(price: u64): u64 {
    calculate_fee_internal(price)
}

/// Get marketplace statistics.
/// Returns: (total_volume, total_fees, sales_count, active_count)
public fun stats(config: &MarketplaceConfig): (u64, u64, u64, u64) {
    (
        config.total_volume,
        config.total_fees_collected,
        config.total_sales_count,
        config.active_listings_count,
    )
}

/// Check if marketplace is paused.
public fun is_paused(config: &MarketplaceConfig): bool {
    config.paused
}

/// Get admin address.
public fun admin(config: &MarketplaceConfig): address {
    config.admin
}

/// Get fee basis points (500 = 5%).
public fun fee_bps(): u64 {
    FEE_BPS
}

/// Get minimum listing price.
public fun min_price(): u64 {
    MIN_PRICE
}

// === Internal Functions ===

fun calculate_fee_internal(price: u64): u64 {
    (price * FEE_BPS) / BPS_DENOMINATOR
}

// === Test Helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun destroy_receipt_for_testing(receipt: PurchaseReceipt) {
    let PurchaseReceipt {
        id,
        listing_id: _,
        pass_id: _,
        buyer: _,
        seller: _,
        price_paid: _,
        fee_paid: _,
        purchased_at_epoch: _,
    } = receipt;
    id.delete();
}
