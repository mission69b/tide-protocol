/// Capability-gated admin actions.
/// 
/// Admin module provides:
/// - Listing creation (requires AdminCap)
/// - Route capability management
/// - Emergency controls
module tide_core::admin;

use tide_core::tide::{Tide, AdminCap};
use tide_core::listing::{Self, Listing, ListingCap};
use tide_core::capital_vault::CapitalVault;
use tide_core::reward_vault::{RewardVault, RouteCapability};
use tide_core::staking_adapter::StakingAdapter;

// === Admin Functions ===

/// Create a new listing. Requires AdminCap.
/// 
/// For v1, this creates the single FAITH listing.
/// Returns all objects for the caller to share/transfer.
/// 
/// Note: In Sui, `share_object` and `transfer` can only be called from
/// the defining module, so we return the objects for the caller to handle,
/// or this should be called from listing module.
public fun create_listing(
    _tide: &Tide,
    _cap: &AdminCap,
    issuer: address,
    validator: address,
    tranche_amounts: vector<u64>,
    tranche_times: vector<u64>,
    ctx: &mut TxContext,
): (Listing, CapitalVault, RewardVault, StakingAdapter, ListingCap, RouteCapability) {
    listing::new(issuer, validator, tranche_amounts, tranche_times, ctx)
}

/// Convenience wrapper for pause.
public fun pause_protocol(
    tide: &mut Tide,
    cap: &AdminCap,
    ctx: &TxContext,
) {
    tide.pause(cap, ctx);
}

/// Convenience wrapper for unpause.
public fun unpause_protocol(
    tide: &mut Tide,
    cap: &AdminCap,
    ctx: &TxContext,
) {
    tide.unpause(cap, ctx);
}
