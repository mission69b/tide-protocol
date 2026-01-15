/// Transferable NFT representing a backer's economic position.
/// 
/// SupporterPass stores economics only:
/// - Fixed shares (immutable after mint)
/// - Claim cursor (last claimed reward index)
/// - Created epoch (non-economic, for reference only)
/// 
/// Ownership defines full reward entitlement - when transferred,
/// claim rights move atomically with the NFT.
/// 
/// IMPORTANT: This module MUST NOT call sui::display.
/// Display is configured separately in display.move.
module tide_core::supporter_pass;

use tide_core::errors;

// === Structs ===

/// Backer's economic position as transferable NFT.
/// 
/// Economic fields:
/// - shares: determines reward entitlement (immutable)
/// - claim_index: tracks last claimed position (mutable)
/// 
/// Non-economic fields (for display/reference only):
/// - listing_id: parent listing reference
/// - created_epoch: when the pass was minted
public struct SupporterPass has key, store {
    id: UID,
    /// ID of the listing this pass belongs to.
    listing_id: ID,
    /// Fixed shares calculated at deposit time (immutable).
    /// Determines reward entitlement proportionally.
    shares: u128,
    /// Last claimed reward index (updated on claim).
    /// Used to calculate claimable rewards.
    claim_index: u128,
    /// Epoch when pass was created (non-economic, for display).
    created_epoch: u64,
}

// === Package Functions ===

/// Mint a new SupporterPass. Only callable from listing module.
public(package) fun mint(
    listing_id: ID,
    shares: u128,
    current_index: u128,
    ctx: &mut TxContext,
): SupporterPass {
    SupporterPass {
        id: object::new(ctx),
        listing_id,
        shares,
        claim_index: current_index,
        created_epoch: ctx.epoch(),
    }
}

/// Update claim index after rewards are claimed.
public(package) fun update_claim_index(
    self: &mut SupporterPass,
    new_index: u128,
) {
    assert!(new_index >= self.claim_index, errors::invalid_state());
    self.claim_index = new_index;
}

// === View Functions ===

/// Get the pass ID.
public fun id(self: &SupporterPass): ID {
    self.id.to_inner()
}

/// Get the listing ID this pass belongs to.
public fun listing_id(self: &SupporterPass): ID {
    self.listing_id
}

/// Get fixed share amount.
public fun shares(self: &SupporterPass): u128 {
    self.shares
}

/// Get current claim index.
public fun claim_index(self: &SupporterPass): u128 {
    self.claim_index
}

/// Get created epoch.
public fun created_epoch(self: &SupporterPass): u64 {
    self.created_epoch
}

/// Assert pass belongs to given listing.
public fun assert_listing(self: &SupporterPass, listing_id: ID) {
    assert!(self.listing_id == listing_id, errors::wrong_listing());
}

// === Test Helpers ===

#[test_only]
public fun mint_for_testing(
    listing_id: ID,
    shares: u128,
    current_index: u128,
    ctx: &mut TxContext,
): SupporterPass {
    mint(listing_id, shares, current_index, ctx)
}

#[test_only]
public fun destroy_for_testing(pass: SupporterPass) {
    let SupporterPass { id, .. } = pass;
    id.delete();
}
