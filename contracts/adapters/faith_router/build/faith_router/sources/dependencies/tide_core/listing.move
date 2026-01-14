/// Listing lifecycle and orchestration of all vaults.
/// 
/// Listing represents a single capital raise with:
/// - Lifecycle state machine (Draft → Active → Finalized → Completed)
/// - References to CapitalVault, RewardVault, StakingAdapter
/// - Deterministic release schedule parameters
/// 
/// Invariants:
/// - State transitions are unidirectional
/// - Config immutable after activation
/// - Deposits only in Active state
module tide_core::listing;

use sui::clock::Clock;
use sui::coin::Coin;
use sui::sui::SUI;

use tide_core::tide::Tide;
use tide_core::capital_vault::{Self, CapitalVault};
use tide_core::reward_vault::{Self, RewardVault, RouteCapability};
use tide_core::staking_adapter::{Self, StakingAdapter};
use tide_core::supporter_pass::{Self, SupporterPass};
use tide_core::constants;
use tide_core::errors;
use tide_core::events;

// === Structs ===

/// Capability to manage a listing.
public struct ListingCap has key, store {
    id: UID,
    listing_id: ID,
}

/// Main listing object orchestrating the capital raise.
public struct Listing has key {
    id: UID,
    /// Issuer address receiving released capital.
    issuer: address,
    /// Current lifecycle state.
    state: u8,
    /// Hash of immutable config (set at activation).
    config_hash: vector<u8>,
    /// Timestamp when listing was activated.
    activation_time: u64,
    /// Total number of backers.
    total_backers: u64,
}

// === Constructor ===

/// Create a new listing in Draft state.
/// Returns Listing, CapitalVault, RewardVault, StakingAdapter, ListingCap, RouteCapability.
public fun new(
    issuer: address,
    validator: address,
    tranche_amounts: vector<u64>,
    tranche_times: vector<u64>,
    ctx: &mut TxContext,
): (Listing, CapitalVault, RewardVault, StakingAdapter, ListingCap, RouteCapability) {
    let listing_uid = object::new(ctx);
    let listing_id = listing_uid.to_inner();
    
    let listing = Listing {
        id: listing_uid,
        issuer,
        state: constants::state_draft!(),
        config_hash: vector::empty(),
        activation_time: 0,
        total_backers: 0,
    };
    
    let capital_vault = capital_vault::new(
        listing_id,
        issuer,
        tranche_amounts,
        tranche_times,
        ctx,
    );
    
    let reward_vault = reward_vault::new(listing_id, ctx);
    
    let staking_adapter = staking_adapter::new(listing_id, validator, ctx);
    
    let listing_cap = ListingCap {
        id: object::new(ctx),
        listing_id,
    };
    
    let route_cap = reward_vault::create_route_capability(listing_id, ctx);
    
    (listing, capital_vault, reward_vault, staking_adapter, listing_cap, route_cap)
}

// === Lifecycle Transitions ===

/// Activate the listing, enabling deposits.
/// Config becomes immutable after this.
public fun activate(
    self: &mut Listing,
    cap: &ListingCap,
    clock: &Clock,
    _ctx: &mut TxContext,
) {
    assert!(cap.listing_id == self.id.to_inner(), errors::not_authorized());
    assert!(self.state == constants::state_draft!(), errors::not_draft());
    
    let old_state = self.state;
    self.state = constants::state_active!();
    self.activation_time = clock.timestamp_ms();
    
    // TODO: Compute config hash from params
    
    events::emit_state_changed(self.id.to_inner(), old_state, self.state);
}

/// Finalize the listing, stopping new deposits.
public fun finalize(
    self: &mut Listing,
    cap: &ListingCap,
    _ctx: &mut TxContext,
) {
    assert!(cap.listing_id == self.id.to_inner(), errors::not_authorized());
    assert!(self.state == constants::state_active!(), errors::not_active());
    
    let old_state = self.state;
    self.state = constants::state_finalized!();
    
    events::emit_state_changed(self.id.to_inner(), old_state, self.state);
}

/// Complete the listing after all tranches released.
public fun complete(
    self: &mut Listing,
    cap: &ListingCap,
    capital_vault: &CapitalVault,
    _ctx: &mut TxContext,
) {
    assert!(cap.listing_id == self.id.to_inner(), errors::not_authorized());
    assert!(self.state == constants::state_finalized!(), errors::invalid_state());
    assert!(capital_vault.all_released(), errors::invalid_state());
    
    let old_state = self.state;
    self.state = constants::state_completed!();
    
    events::emit_state_changed(self.id.to_inner(), old_state, self.state);
}

// === Core Operations ===

/// Deposit SUI and receive a SupporterPass.
public fun deposit(
    self: &mut Listing,
    tide: &Tide,
    capital_vault: &mut CapitalVault,
    reward_vault: &mut RewardVault,
    coin: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): SupporterPass {
    // Validate state
    tide.assert_not_paused();
    assert!(self.state == constants::state_active!(), errors::not_active());
    
    let amount = coin.value();
    let listing_id = self.id.to_inner();
    
    // Accept deposit and get shares
    let shares = capital_vault.accept_deposit(coin);
    
    // Update reward vault with new total shares
    reward_vault.set_total_shares(capital_vault.total_shares());
    
    // Mint supporter pass
    let pass = supporter_pass::mint(
        listing_id,
        shares,
        reward_vault.global_index(),
        amount,
        clock.timestamp_ms(),
        ctx,
    );
    
    self.total_backers = self.total_backers + 1;
    
    events::emit_deposited(
        listing_id,
        ctx.sender(),
        amount,
        shares,
        pass.id(),
    );
    
    pass
}

/// Claim rewards for a SupporterPass.
public fun claim(
    self: &Listing,
    _tide: &Tide,
    reward_vault: &mut RewardVault,
    pass: &mut SupporterPass,
    ctx: &mut TxContext,
): Coin<SUI> {
    // Note: Claims allowed even when paused (per spec)
    pass.assert_listing(self.id.to_inner());
    
    let claimable = reward_vault.calculate_claimable(
        pass.shares(),
        pass.claim_index(),
    );
    
    assert!(claimable > 0, errors::nothing_to_claim());
    
    // Update pass cursor before withdrawal
    pass.update_claim_index(reward_vault.global_index());
    
    // Withdraw from vault
    let coin = reward_vault.withdraw(claimable, ctx);
    
    events::emit_claimed(
        self.id.to_inner(),
        pass.id(),
        ctx.sender(),
        claimable,
    );
    
    coin
}

/// Release the next tranche to the issuer.
public fun release_tranche(
    self: &Listing,
    tide: &Tide,
    capital_vault: &mut CapitalVault,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    tide.assert_not_paused();
    assert!(
        self.state == constants::state_active!() || 
        self.state == constants::state_finalized!(),
        errors::invalid_state()
    );
    
    let (amount, coin) = capital_vault.release_tranche(clock, ctx);
    
    // Transfer to issuer
    transfer::public_transfer(coin, self.issuer);
    
    events::emit_tranche_released(
        self.id.to_inner(),
        capital_vault.next_tranche_idx() - 1,
        amount,
        self.issuer,
    );
}

// === View Functions ===

/// Get listing ID.
public fun id(self: &Listing): ID {
    self.id.to_inner()
}

/// Get issuer address.
public fun issuer(self: &Listing): address {
    self.issuer
}

/// Get current state.
public fun state(self: &Listing): u8 {
    self.state
}

/// Get activation timestamp.
public fun activation_time(self: &Listing): u64 {
    self.activation_time
}

/// Get total backers.
public fun total_backers(self: &Listing): u64 {
    self.total_backers
}

/// Check if listing is active (accepting deposits).
public fun is_active(self: &Listing): bool {
    self.state == constants::state_active!()
}

/// Check if listing is completed.
public fun is_completed(self: &Listing): bool {
    self.state == constants::state_completed!()
}

/// Get ListingCap listing ID.
public fun cap_listing_id(cap: &ListingCap): ID {
    cap.listing_id
}

// === Share/Transfer Functions ===

/// Share the listing object.
public fun share(listing: Listing) {
    transfer::share_object(listing);
}

/// Transfer listing cap to recipient.
public fun transfer_cap(cap: ListingCap, recipient: address) {
    transfer::public_transfer(cap, recipient);
}

// === Test Helpers ===

#[test_only]
public fun new_for_testing(
    issuer: address,
    validator: address,
    tranche_amounts: vector<u64>,
    tranche_times: vector<u64>,
    ctx: &mut TxContext,
): (Listing, CapitalVault, RewardVault, StakingAdapter, ListingCap, RouteCapability) {
    new(issuer, validator, tranche_amounts, tranche_times, ctx)
}

#[test_only]
public fun destroy_for_testing(listing: Listing) {
    let Listing { id, .. } = listing;
    id.delete();
}

#[test_only]
public fun destroy_cap_for_testing(cap: ListingCap) {
    let ListingCap { id, .. } = cap;
    id.delete();
}
