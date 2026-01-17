/// FAITH revenue router adapter.
/// 
/// Routes a fixed percentage of FAITH protocol revenue to the
/// Tide RewardVault. This is a thin glue layer only.
/// 
/// Normative rules:
/// - Routes SUI revenue only
/// - Revenue percentage immutable after creation
/// - Emits standardized RouteIn events
/// - No FAITH gameplay logic
/// - Handles both protocol revenue AND staking reward harvesting
module faith_router::faith_router;

use sui::coin::Coin;
use sui::sui::SUI;
use sui_system::sui_system::SuiSystemState;

use tide_core::reward_vault::{RewardVault, RouteCapability};
use tide_core::listing::Listing;
use tide_core::tide::Tide;
use tide_core::staking_adapter::StakingAdapter;
use tide_core::constants;

// === Version ===

/// Adapter version for upgrade compatibility.
/// v1: Initial release with route() and harvest_and_route()
const VERSION: u64 = 1;

// === Errors ===

/// Revenue percentage too high.
const EInvalidBps: u64 = 0;

/// Amount is zero.
const EZeroAmount: u64 = 1;

/// Version mismatch (adapter upgraded, requires migration).
const EVersionMismatch: u64 = 2;

// === Structs ===

/// FAITH revenue router.
public struct FaithRouter has key {
    id: UID,
    /// Adapter version for upgrade compatibility.
    version: u64,
    /// ID of the listing this router serves.
    listing_id: ID,
    /// Revenue percentage in basis points (e.g., 1000 = 10%).
    revenue_bps: u64,
    /// Total SUI routed lifetime.
    total_routed: u64,
}

/// Capability to manage the router (held by FAITH).
public struct FaithRouterCap has key, store {
    id: UID,
}

// === Constructor ===

/// Create a new FAITH router with RouteCapability.
/// Revenue BPS is immutable after creation.
public fun new(
    route_cap: RouteCapability,
    revenue_bps: u64,
    ctx: &mut TxContext,
): (FaithRouter, FaithRouterCap) {
    assert!(revenue_bps <= constants::max_bps!(), EInvalidBps);
    
    let listing_id = route_cap.route_cap_listing_id();
    
    // Store route_cap as dynamic field or transfer to router
    // For simplicity, we'll transfer it to be stored with router
    let mut router_uid = object::new(ctx);
    
    // Store route capability in dynamic field
    sui::dynamic_field::add(&mut router_uid, b"route_cap", route_cap);
    
    let router = FaithRouter {
        id: router_uid,
        version: VERSION,
        listing_id,
        revenue_bps,
        total_routed: 0,
    };
    
    let cap = FaithRouterCap {
        id: object::new(ctx),
    };
    
    (router, cap)
}

// === Routing ===

/// Route revenue to the RewardVault.
/// 
/// This is called by FAITH protocol when collecting fees.
/// The full amount is routed (FAITH pre-calculates the percentage).
public fun route(
    self: &mut FaithRouter,
    reward_vault: &mut RewardVault,
    coin: Coin<SUI>,
    ctx: &TxContext,
) {
    assert!(self.version == VERSION, EVersionMismatch);
    let amount = coin.value();
    assert!(amount > 0, EZeroAmount);
    
    // Get route capability
    let route_cap = sui::dynamic_field::borrow<vector<u8>, RouteCapability>(
        &self.id,
        b"route_cap",
    );
    
    // Deposit to vault
    reward_vault.deposit_rewards(route_cap, coin, ctx);
    
    // Update stats
    self.total_routed = self.total_routed + amount;
}

/// Calculate the revenue amount from total fees.
/// Helper for FAITH to determine how much to route.
public fun calculate_revenue(self: &FaithRouter, total_fees: u64): u64 {
    (((total_fees as u128) * (self.revenue_bps as u128)) / (constants::max_bps!() as u128)) as u64
}

// === Staking Integration ===

/// Harvest staking rewards and route backer share to RewardVault.
/// 
/// This function allows the adapter to handle staking reward distribution
/// using its stored RouteCapability. The rewards are split 80/20:
/// - 80% → RewardVault (for backers to claim)
/// - 20% → Treasury
/// 
/// Should be called periodically (e.g., every epoch) by a keeper.
public fun harvest_and_route(
    self: &mut FaithRouter,
    listing: &Listing,
    tide: &Tide,
    staking_adapter: &mut StakingAdapter,
    reward_vault: &mut RewardVault,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    assert!(self.version == VERSION, EVersionMismatch);
    
    // Borrow the stored RouteCapability
    let route_cap = sui::dynamic_field::borrow<vector<u8>, RouteCapability>(
        &self.id,
        b"route_cap",
    );
    
    // Call listing's harvest function which handles the 80/20 split
    tide_core::listing::harvest_staking_rewards(
        listing,
        tide,
        staking_adapter,
        reward_vault,
        route_cap,
        system_state,
        ctx,
    );
}

// === View Functions ===

/// Get adapter version.
public fun version(self: &FaithRouter): u64 {
    self.version
}

/// Get current package version constant.
public fun current_version(): u64 {
    VERSION
}

/// Get router ID.
public fun id(self: &FaithRouter): ID {
    self.id.to_inner()
}

/// Get listing ID.
public fun listing_id(self: &FaithRouter): ID {
    self.listing_id
}

/// Get revenue percentage in basis points.
public fun revenue_bps(self: &FaithRouter): u64 {
    self.revenue_bps
}

/// Get total routed amount.
public fun total_routed(self: &FaithRouter): u64 {
    self.total_routed
}

// === Share/Transfer Functions ===

/// Share the FaithRouter object.
public fun share(router: FaithRouter) {
    sui::transfer::share_object(router);
}

/// Transfer the FaithRouterCap to a recipient.
public fun transfer_cap(cap: FaithRouterCap, recipient: address) {
    sui::transfer::public_transfer(cap, recipient);
}

// === Test Helpers ===

#[test_only]
public fun new_for_testing(
    route_cap: RouteCapability,
    revenue_bps: u64,
    ctx: &mut TxContext,
): (FaithRouter, FaithRouterCap) {
    new(route_cap, revenue_bps, ctx)
}

#[test_only]
public fun destroy_for_testing(router: FaithRouter) {
    let FaithRouter { mut id, version: _, listing_id: _, revenue_bps: _, total_routed: _ } = router;
    let route_cap: RouteCapability = sui::dynamic_field::remove(&mut id, b"route_cap");
    tide_core::reward_vault::destroy_route_cap_for_testing(route_cap);
    id.delete();
}

#[test_only]
public fun destroy_cap_for_testing(cap: FaithRouterCap) {
    let FaithRouterCap { id } = cap;
    id.delete();
}
