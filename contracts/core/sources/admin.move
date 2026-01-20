/// Admin actions for Tide Core.
/// 
/// This module provides:
/// - Global protocol pause (via AdminCap)
/// - Admin rotation (transfer AdminCap)
/// - Treasury management
/// - Council configuration updates
/// - Convenience wrappers for emergency controls
/// 
/// Note: Listing creation is now council-gated via listing::new().
/// Most admin operations are now handled by CouncilCap.
module tide_core::admin;

use tide_core::tide::{Self, Tide, AdminCap};
use tide_core::council::{Self, CouncilCap, CouncilConfig};
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

/// Update the admin wallet address (for treasury withdrawals).
public fun update_admin_wallet(
    tide: &mut Tide,
    cap: &AdminCap,
    new_wallet: address,
    ctx: &mut TxContext,
) {
    tide.set_admin_wallet(cap, new_wallet, ctx);
}

/// Transfer AdminCap to a new admin (admin rotation).
/// WARNING: This is irreversible - the sender loses admin rights.
public fun rotate_admin(
    cap: AdminCap,
    new_admin: address,
    ctx: &TxContext,
) {
    tide::transfer_admin_cap(cap, new_admin, ctx);
}

// === Council Management ===

/// Transfer CouncilCap to a new holder (e.g., multisig).
/// WARNING: This is irreversible - the sender loses council control.
public fun rotate_council(
    cap: CouncilCap,
    new_holder: address,
    ctx: &TxContext,
) {
    council::transfer_cap(cap, new_holder, ctx);
}

/// Update council configuration (threshold and member count).
/// Used to reflect changes in the multisig setup.
public fun update_council_config(
    config: &mut CouncilConfig,
    cap: &CouncilCap,
    new_threshold: u64,
    new_members: u64,
) {
    council::update_config(config, cap, new_threshold, new_members);
}

// === Council-Gated Functions ===

/// Create a new listing. Requires CouncilCap.
/// 
/// This is the canonical way to create listings in the registry-first architecture.
/// Returns all objects for the caller to share/transfer appropriately.
/// 
/// Parameters:
/// - issuer: Address that manages the listing (receives RouteCapability, ListingCap)
/// - release_recipient: Address that receives capital tranches (the artist/creator)
public fun create_listing(
    registry: &mut ListingRegistry,
    council_cap: &CouncilCap,
    issuer: address,
    release_recipient: address,
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
        release_recipient,
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

// === Staking Configuration (Council-Gated) ===

/// Enable staking for a listing.
public fun enable_staking(
    listing: &Listing,
    tide: &tide_core::tide::Tide,
    council_cap: &CouncilCap,
    staking_adapter: &mut tide_core::staking_adapter::StakingAdapter,
) {
    listing.set_staking_enabled(tide, council_cap, staking_adapter, true);
}

/// Disable staking for a listing.
public fun disable_staking(
    listing: &Listing,
    tide: &tide_core::tide::Tide,
    council_cap: &CouncilCap,
    staking_adapter: &mut tide_core::staking_adapter::StakingAdapter,
) {
    listing.set_staking_enabled(tide, council_cap, staking_adapter, false);
}

/// Update the validator for a listing's staking adapter.
public fun update_validator(
    listing: &Listing,
    tide: &tide_core::tide::Tide,
    council_cap: &CouncilCap,
    staking_adapter: &mut tide_core::staking_adapter::StakingAdapter,
    new_validator: address,
) {
    listing.set_staking_validator(tide, council_cap, staking_adapter, new_validator);
}
