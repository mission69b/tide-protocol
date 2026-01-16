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

#[test_only]
public fun update_claim_index_for_testing(self: &mut SupporterPass, new_index: u128) {
    update_claim_index(self, new_index)
}

// === Unit Tests ===

#[test_only]
const EINVALID_STATE: u64 = 5;
#[test_only]
const EWRONG_LISTING: u64 = 10;

#[test]
fun test_mint_and_getters() {
    let mut ctx = tx_context::dummy();
    let listing_id = object::id_from_address(@0x1);
    let shares: u128 = 1_000_000_000; // 1 SUI worth of shares
    let current_index: u128 = 100_000_000_000_000_000; // Some index value (1e17)
    
    let pass = mint_for_testing(listing_id, shares, current_index, &mut ctx);
    
    assert!(pass.listing_id() == listing_id);
    assert!(pass.shares() == shares);
    assert!(pass.claim_index() == current_index);
    assert!(pass.created_epoch() == ctx.epoch());
    
    destroy_for_testing(pass);
}

#[test]
fun test_update_claim_index() {
    let mut ctx = tx_context::dummy();
    let listing_id = object::id_from_address(@0x1);
    
    let mut pass = mint_for_testing(listing_id, 1000, 100, &mut ctx);
    
    // Update to higher index
    pass.update_claim_index_for_testing(200);
    assert!(pass.claim_index() == 200);
    
    // Update to same index (should succeed)
    pass.update_claim_index_for_testing(200);
    assert!(pass.claim_index() == 200);
    
    destroy_for_testing(pass);
}

#[test]
#[expected_failure(abort_code = EINVALID_STATE)]
fun test_update_claim_index_cannot_decrease() {
    let mut ctx = tx_context::dummy();
    let listing_id = object::id_from_address(@0x1);
    
    let mut pass = mint_for_testing(listing_id, 1000, 200, &mut ctx);
    
    // Try to decrease index - should fail
    pass.update_claim_index_for_testing(100);
    
    destroy_for_testing(pass);
}

#[test]
fun test_assert_listing_correct() {
    let mut ctx = tx_context::dummy();
    let listing_id = object::id_from_address(@0x1);
    
    let pass = mint_for_testing(listing_id, 1000, 0, &mut ctx);
    
    // Should not abort
    pass.assert_listing(listing_id);
    
    destroy_for_testing(pass);
}

#[test]
#[expected_failure(abort_code = EWRONG_LISTING)]
fun test_assert_listing_wrong() {
    let mut ctx = tx_context::dummy();
    let listing_id = object::id_from_address(@0x1);
    let other_id = object::id_from_address(@0x2);
    
    let pass = mint_for_testing(listing_id, 1000, 0, &mut ctx);
    
    // Should abort - wrong listing
    pass.assert_listing(other_id);
    
    destroy_for_testing(pass);
}

#[test]
fun test_shares_immutability() {
    let mut ctx = tx_context::dummy();
    let listing_id = object::id_from_address(@0x1);
    let initial_shares: u128 = 999_999;
    
    let pass = mint_for_testing(listing_id, initial_shares, 0, &mut ctx);
    
    // Shares should remain unchanged
    assert!(pass.shares() == initial_shares);
    
    // Note: There's no way to change shares after mint - this is enforced by the struct design
    // (no public setter for shares)
    
    destroy_for_testing(pass);
}
