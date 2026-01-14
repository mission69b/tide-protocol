/// Transferable NFT representing a backer's economic position.
/// 
/// SupporterPass stores:
/// - Fixed shares (immutable after mint)
/// - Claim cursor (last claimed reward index)
/// - Original deposit amount and timestamp (for display)
/// 
/// Ownership defines full reward entitlement - when transferred,
/// claim rights move atomically with the NFT.
module tide_core::supporter_pass;

use tide_core::errors;

// === Structs ===

/// Backer's economic position as transferable NFT.
public struct SupporterPass has key, store {
    id: UID,
    /// ID of the listing this pass belongs to.
    listing_id: ID,
    /// Fixed shares calculated at deposit time (immutable).
    shares: u128,
    /// Last claimed reward index (updated on claim).
    claim_index: u128,
    /// Original deposit amount in SUI (for display).
    deposited_amount: u64,
    /// Timestamp when deposit was made (for display).
    deposited_at: u64,
}

// === Package Functions ===

/// Mint a new SupporterPass. Only callable from listing module.
public(package) fun mint(
    listing_id: ID,
    shares: u128,
    current_index: u128,
    deposited_amount: u64,
    deposited_at: u64,
    ctx: &mut TxContext,
): SupporterPass {
    SupporterPass {
        id: object::new(ctx),
        listing_id,
        shares,
        claim_index: current_index,
        deposited_amount,
        deposited_at,
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

/// Get original deposit amount.
public fun deposited_amount(self: &SupporterPass): u64 {
    self.deposited_amount
}

/// Get deposit timestamp.
public fun deposited_at(self: &SupporterPass): u64 {
    self.deposited_at
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
    deposited_amount: u64,
    deposited_at: u64,
    ctx: &mut TxContext,
): SupporterPass {
    mint(listing_id, shares, current_index, deposited_amount, deposited_at, ctx)
}

#[test_only]
public fun destroy_for_testing(pass: SupporterPass) {
    let SupporterPass { id, .. } = pass;
    id.delete();
}
