/// Admin actions for Tide Core.
/// 
/// This module provides:
/// - Global protocol pause (via AdminCap)
/// - Convenience wrappers for emergency controls
/// 
/// Note: Listing creation is now council-gated via listing::new().
/// Most admin operations are now handled by CouncilCap.
module tide_core::admin;

use tide_core::tide::{Tide, AdminCap};
use tide_core::council::CouncilCap;
use tide_core::listing::{Self, Listing};
use tide_core::registry::ListingRegistry;
use tide_core::capital_vault::CapitalVault;
use tide_core::reward_vault::{RewardVault, RouteCapability};
use tide_core::staking_adapter::StakingAdapter;

// === Global Protocol Admin (AdminCap) ===

/// Pause the entire protocol (global emergency).
public fun pause_protocol(
    tide: &mut Tide,
    cap: &AdminCap,
    ctx: &TxContext,
) {
    tide.pause(cap, ctx);
}

/// Unpause the entire protocol.
public fun unpause_protocol(
    tide: &mut Tide,
    cap: &AdminCap,
    ctx: &TxContext,
) {
    tide.unpause(cap, ctx);
}

// === Council-Gated Functions ===

/// Create a new listing. Requires CouncilCap.
/// 
/// This is the canonical way to create listings in the registry-first architecture.
/// Returns all objects for the caller to share/transfer appropriately.
public fun create_listing(
    registry: &mut ListingRegistry,
    council_cap: &CouncilCap,
    issuer: address,
    validator: address,
    tranche_amounts: vector<u64>,
    tranche_times: vector<u64>,
    revenue_bps: u64,
    ctx: &mut TxContext,
): (Listing, CapitalVault, RewardVault, StakingAdapter, listing::ListingCap, RouteCapability) {
    listing::new(
        registry,
        council_cap,
        issuer,
        validator,
        tranche_amounts,
        tranche_times,
        revenue_bps,
        ctx,
    )
}

/// Pause a specific listing.
public fun pause_listing(
    listing: &mut Listing,
    council_cap: &CouncilCap,
) {
    listing.pause(council_cap);
}

/// Resume a specific listing.
public fun resume_listing(
    listing: &mut Listing,
    council_cap: &CouncilCap,
) {
    listing.resume(council_cap);
}
