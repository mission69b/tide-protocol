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
module faith_router::faith_router;

use sui::coin::Coin;
use sui::sui::SUI;
use sui::transfer;

use tide_core::reward_vault::{RewardVault, RouteCapability};
use tide_core::constants;

// === Errors ===

/// Revenue percentage too high.
const EInvalidBps: u64 = 0;

/// Amount is zero.
const EZeroAmount: u64 = 1;

// === Structs ===

/// FAITH revenue router.
public struct FaithRouter has key {
    id: UID,
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

// === View Functions ===

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
    transfer::share_object(router);
}

/// Transfer the FaithRouterCap to a recipient.
public fun transfer_cap(cap: FaithRouterCap, recipient: address) {
    transfer::public_transfer(cap, recipient);
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
    let FaithRouter { mut id, .. } = router;
    let route_cap: RouteCapability = sui::dynamic_field::remove(&mut id, b"route_cap");
    tide_core::reward_vault::destroy_route_cap_for_testing(route_cap);
    id.delete();
}

#[test_only]
public fun destroy_cap_for_testing(cap: FaithRouterCap) {
    let FaithRouterCap { id } = cap;
    id.delete();
}
