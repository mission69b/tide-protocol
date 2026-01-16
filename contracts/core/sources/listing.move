/// Listing lifecycle and orchestration of all vaults.
/// 
/// Listing represents a single capital raise with:
/// - Lifecycle state machine (Draft → Active → Finalized → Completed)
/// - Per-listing pause capability
/// - Immutable config hash (set at creation)
/// - References to CapitalVault, RewardVault, StakingAdapter
/// - Deterministic release schedule parameters
/// 
/// Invariants:
/// - State transitions are unidirectional
/// - Config hash and economics immutable after activation
/// - Deposits only in Active state (and not paused)
module tide_core::listing;

use std::hash;
use std::bcs;

use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui_system::sui_system::SuiSystemState;

use tide_core::tide::Tide;
use tide_core::registry::ListingRegistry;
use tide_core::council::CouncilCap;
use tide_core::capital_vault::{Self, CapitalVault};
use tide_core::reward_vault::{Self, RewardVault, RouteCapability};
use tide_core::staking_adapter::{Self, StakingAdapter};
use tide_core::supporter_pass::{Self, SupporterPass};
use tide_core::constants;
use tide_core::errors;
use tide_core::events;

// === Structs ===

/// Capability to manage a listing (held by issuer).
public struct ListingCap has key, store {
    id: UID,
    listing_id: ID,
}

/// Configuration parameters for a listing.
/// Used to compute the config hash.
/// All fee and limit parameters are disclosed here for transparency.
public struct ListingConfig has copy, drop, store {
    /// Issuer address.
    issuer: address,
    /// Validator for staking.
    validator: address,
    /// Tranche amounts (SUI, in MIST).
    tranche_amounts: vector<u64>,
    /// Tranche release times (Unix timestamp ms).
    tranche_times: vector<u64>,
    /// Revenue routing BPS (e.g., 1000 = 10%).
    revenue_bps: u64,
    /// Raise fee in basis points (1% = 100 bps).
    /// Deducted from total raised before first release.
    raise_fee_bps: u64,
    /// Staking reward split for backers in BPS (80% = 8000).
    /// Remaining goes to treasury.
    staking_backer_bps: u64,
    /// Minimum deposit amount in MIST (anti-spam).
    min_deposit: u64,
}

/// Main listing object orchestrating the capital raise.
public struct Listing has key {
    id: UID,
    /// Listing number in registry (1-indexed).
    listing_number: u64,
    /// Issuer address receiving released capital.
    issuer: address,
    /// Current lifecycle state.
    state: u8,
    /// Hash of immutable config (computed at creation, verified at activation).
    config_hash: vector<u8>,
    /// Full config (for transparency and verification).
    config: ListingConfig,
    /// Timestamp when listing was activated.
    activation_time: u64,
    /// Total number of backers.
    total_backers: u64,
    /// Per-listing pause flag.
    paused: bool,
}

// === Constructor ===

/// Create a new listing in Draft state (council-gated).
/// Returns Listing, CapitalVault, RewardVault, StakingAdapter, ListingCap, RouteCapability.
public fun new(
    registry: &mut ListingRegistry,
    council_cap: &CouncilCap,
    issuer: address,
    validator: address,
    tranche_amounts: vector<u64>,
    tranche_times: vector<u64>,
    revenue_bps: u64,
    ctx: &mut TxContext,
): (Listing, CapitalVault, RewardVault, StakingAdapter, ListingCap, RouteCapability) {
    // Create config with fee and limit disclosure
    let config = ListingConfig {
        issuer,
        validator,
        tranche_amounts: tranche_amounts,
        tranche_times: tranche_times,
        revenue_bps,
        // Fee and limit parameters from protocol constants (disclosed in config hash)
        raise_fee_bps: constants::raise_fee_bps!(),
        staking_backer_bps: constants::staking_backer_bps!(),
        min_deposit: constants::min_deposit!(),
    };
    let config_hash = compute_config_hash(&config);
    
    let listing_uid = object::new(ctx);
    let listing_id = listing_uid.to_inner();
    
    // Register with registry
    let listing_number = registry.register_listing(council_cap, listing_id, issuer);
    
    let listing = Listing {
        id: listing_uid,
        listing_number,
        issuer,
        state: constants::state_draft!(),
        config_hash,
        config,
        activation_time: 0,
        total_backers: 0,
        paused: false,
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

// === Lifecycle Transitions (Council-Gated) ===

/// Activate the listing, enabling deposits.
/// Config becomes immutable after this.
public fun activate(
    self: &mut Listing,
    _council_cap: &CouncilCap,
    clock: &Clock,
    _ctx: &mut TxContext,
) {
    assert!(self.state == constants::state_draft!(), errors::not_draft());
    assert!(!self.paused, errors::paused());
    
    let old_state = self.state;
    self.state = constants::state_active!();
    self.activation_time = clock.timestamp_ms();
    
    events::emit_state_changed(self.id.to_inner(), old_state, self.state);
}

/// Finalize the listing, stopping new deposits and computing release schedule.
/// This locks in the deterministic capital release schedule based on total raised.
public fun finalize(
    self: &mut Listing,
    _council_cap: &CouncilCap,
    capital_vault: &mut CapitalVault,
    clock: &Clock,
    _ctx: &mut TxContext,
) {
    assert!(self.state == constants::state_active!(), errors::not_active());
    
    // Compute and lock the release schedule
    capital_vault.finalize_schedule(clock);
    
    let old_state = self.state;
    self.state = constants::state_finalized!();
    
    events::emit_state_changed(self.id.to_inner(), old_state, self.state);
}

/// Finalize the listing and release the initial 20% tranche.
/// This is the canonical v1 flow:
/// 1. Stop accepting deposits
/// 2. Compute deterministic release schedule
/// 3. Collect raise fee (1%)
/// 4. Release initial 20% to issuer
public fun finalize_and_release_initial(
    self: &mut Listing,
    council_cap: &CouncilCap,
    tide: &Tide,
    capital_vault: &mut CapitalVault,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Finalize first
    finalize(self, council_cap, capital_vault, clock, ctx);
    
    // Collect raise fee
    collect_raise_fee(self, tide, capital_vault, ctx);
    
    // Release initial tranche (index 0 = 20%)
    release_tranche_at(self, tide, capital_vault, 0, clock, ctx);
}

/// Complete the listing after all tranches released.
public fun complete(
    self: &mut Listing,
    _council_cap: &CouncilCap,
    capital_vault: &CapitalVault,
    _ctx: &mut TxContext,
) {
    assert!(self.state == constants::state_finalized!(), errors::invalid_state());
    assert!(capital_vault.all_released(), errors::invalid_state());
    
    let old_state = self.state;
    self.state = constants::state_completed!();
    
    events::emit_state_changed(self.id.to_inner(), old_state, self.state);
}

// === Pause Control (Council-Gated) ===

/// Pause the listing.
public fun pause(
    self: &mut Listing,
    _council_cap: &CouncilCap,
) {
    self.paused = true;
    events::emit_pause_changed(self.id.to_inner(), true);
}

/// Resume the listing.
public fun resume(
    self: &mut Listing,
    _council_cap: &CouncilCap,
) {
    self.paused = false;
    events::emit_pause_changed(self.id.to_inner(), false);
}

// === Core Operations ===

/// Deposit SUI and receive a SupporterPass.
public fun deposit(
    self: &mut Listing,
    tide: &Tide,
    capital_vault: &mut CapitalVault,
    reward_vault: &mut RewardVault,
    coin: Coin<SUI>,
    _clock: &Clock, // Kept for API stability, may be used in future
    ctx: &mut TxContext,
): SupporterPass {
    // Validate state
    tide.assert_not_paused();
    assert!(!self.paused, errors::paused());
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
        ctx,
    );
    
    self.total_backers = self.total_backers + 1;
    
    events::emit_deposited(
        listing_id,
        ctx.sender(),
        amount,
        shares,
        pass.id(),
        capital_vault.total_principal(), // Running total from vault
        self.total_backers,
        ctx.epoch(),
    );
    
    pass
}

/// Claim rewards for a SupporterPass.
/// Note: Claims are allowed even when paused (per spec).
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
    
    // Capture old index for event
    let old_claim_index = pass.claim_index();
    let new_claim_index = reward_vault.global_index();
    
    // Update pass cursor before withdrawal
    pass.update_claim_index(new_claim_index);
    
    // Withdraw from vault
    let coin = reward_vault.withdraw(claimable, ctx);
    
    events::emit_claimed(
        self.id.to_inner(),
        pass.id(),
        ctx.sender(),
        claimable,
        pass.shares(),
        old_claim_index,
        new_claim_index,
        ctx.epoch(),
    );
    
    coin
}

/// Collect raise fee before first tranche release.
/// Must be called after finalization but before any tranche release.
/// Routes fee directly to Tide Treasury.
public fun collect_raise_fee(
    self: &Listing,
    tide: &Tide,
    capital_vault: &mut CapitalVault,
    ctx: &mut TxContext,
) {
    tide.assert_not_paused();
    assert!(!self.paused, errors::paused());
    assert!(
        self.state == constants::state_active!() || 
        self.state == constants::state_finalized!(),
        errors::invalid_state()
    );
    
    let treasury = tide.treasury();
    let fee_coin = capital_vault.collect_raise_fee(treasury, ctx);
    
    // Transfer fee to treasury
    transfer::public_transfer(fee_coin, treasury);
}

/// Release a specific tranche by index.
/// Pull-based: anyone can call once the tranche time has passed.
/// Raise fee must be collected before any release.
public fun release_tranche_at(
    self: &Listing,
    tide: &Tide,
    capital_vault: &mut CapitalVault,
    tranche_idx: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    tide.assert_not_paused();
    assert!(!self.paused, errors::paused());
    assert!(self.state == constants::state_finalized!(), errors::invalid_state());
    
    let (amount, coin) = capital_vault.release_tranche_at(tranche_idx, clock, ctx);
    
    // Transfer directly to issuer
    transfer::public_transfer(coin, self.issuer);
    
    let total_tranches = capital_vault.num_tranches();
    let remaining = total_tranches - capital_vault.tranches_released();
    
    events::emit_tranche_released(
        self.id.to_inner(),
        tranche_idx,
        amount,
        self.issuer,
        total_tranches,
        remaining,
        capital_vault.cumulative_released(),
        clock.timestamp_ms(),
    );
}

/// Release the next ready tranche.
/// Convenience function that finds and releases the first ready tranche.
public fun release_next_ready_tranche(
    self: &Listing,
    tide: &Tide,
    capital_vault: &mut CapitalVault,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    tide.assert_not_paused();
    assert!(!self.paused, errors::paused());
    assert!(self.state == constants::state_finalized!(), errors::invalid_state());
    
    let (tranche_idx, amount, coin) = capital_vault.release_next_ready_tranche(clock, ctx);
    
    // Transfer directly to issuer
    transfer::public_transfer(coin, self.issuer);
    
    let total_tranches = capital_vault.num_tranches();
    let remaining = total_tranches - capital_vault.tranches_released();
    
    events::emit_tranche_released(
        self.id.to_inner(),
        tranche_idx,
        amount,
        self.issuer,
        total_tranches,
        remaining,
        capital_vault.cumulative_released(),
        clock.timestamp_ms(),
    );
}

/// Release all tranches that are currently ready.
/// Convenience function that releases all accumulated ready tranches.
public fun release_all_ready_tranches(
    self: &Listing,
    tide: &Tide,
    capital_vault: &mut CapitalVault,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    tide.assert_not_paused();
    assert!(!self.paused, errors::paused());
    assert!(self.state == constants::state_finalized!(), errors::invalid_state());
    
    let (indices, total_amount, coin) = capital_vault.release_all_ready_tranches(clock, ctx);
    
    // Transfer combined amount directly to issuer
    transfer::public_transfer(coin, self.issuer);
    
    let total_tranches = capital_vault.num_tranches();
    let remaining = total_tranches - capital_vault.tranches_released();
    let cumulative = capital_vault.cumulative_released();
    let release_time = clock.timestamp_ms();
    
    // Emit events for each tranche
    let mut i = 0;
    while (i < indices.length()) {
        let idx = indices[i];
        let (tranche_amount, _, _) = capital_vault.tranche_at(idx);
        events::emit_tranche_released(
            self.id.to_inner(),
            idx,
            tranche_amount,
            self.issuer,
            total_tranches,
            remaining,
            cumulative,
            release_time,
        );
        i = i + 1;
    };
    
    let _ = total_amount;
    let _ = indices;
}

// === Staking Functions ===

/// Stake all pending capital in the staking adapter.
/// Callable by anyone when staking is enabled.
/// Capital must be deposited to the staking adapter first via `deposit_for_staking`.
public fun stake_pending(
    self: &Listing,
    tide: &Tide,
    staking_adapter: &mut StakingAdapter,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    tide.assert_not_paused();
    assert!(!self.paused, errors::paused());
    assert!(staking_adapter.listing_id() == self.id.to_inner(), errors::invalid_state());
    
    staking_adapter.stake(system_state, ctx);
}

/// Deposit SUI for staking and stake immediately.
/// Council-gated function to add capital to the staking pool.
/// 
/// This is used to stake capital that's been raised. The capital
/// flows: caller → staking_adapter → validator.
public fun deposit_and_stake(
    self: &Listing,
    tide: &Tide,
    _council_cap: &CouncilCap,
    staking_adapter: &mut StakingAdapter,
    deposit: Coin<SUI>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    tide.assert_not_paused();
    assert!(!self.paused, errors::paused());
    assert!(staking_adapter.listing_id() == self.id.to_inner(), errors::invalid_state());
    
    // Deposit to staking adapter
    staking_adapter.deposit(deposit);
    
    // Stake with validator
    staking_adapter.stake(system_state, ctx);
}

/// Unstake a specific stake position by index.
/// Returns the withdrawn SUI to the caller.
public fun unstake_at(
    self: &Listing,
    tide: &Tide,
    _council_cap: &CouncilCap,
    staking_adapter: &mut StakingAdapter,
    stake_idx: u64,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
): Coin<SUI> {
    tide.assert_not_paused();
    assert!(!self.paused, errors::paused());
    assert!(staking_adapter.listing_id() == self.id.to_inner(), errors::invalid_state());
    
    let balance = staking_adapter.unstake_at(stake_idx, system_state, ctx);
    coin::from_balance(balance, ctx)
}

/// Unstake all staked positions.
/// Returns all SUI (principal + rewards) to the caller.
public fun unstake_all(
    self: &Listing,
    tide: &Tide,
    _council_cap: &CouncilCap,
    staking_adapter: &mut StakingAdapter,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
): Coin<SUI> {
    tide.assert_not_paused();
    assert!(!self.paused, errors::paused());
    assert!(staking_adapter.listing_id() == self.id.to_inner(), errors::invalid_state());
    
    let balance = staking_adapter.unstake_all(system_state, ctx);
    coin::from_balance(balance, ctx)
}

/// Harvest staking rewards and split between backers and treasury.
/// 
/// This function:
/// 1. Unstakes all positions
/// 2. Re-stakes the original principal
/// 3. Routes 80% of rewards to RewardVault (backers)
/// 4. Routes 20% of rewards to Treasury
/// 
/// Callable by anyone (permissionless harvesting).
public fun harvest_staking_rewards(
    self: &Listing,
    tide: &Tide,
    staking_adapter: &mut StakingAdapter,
    reward_vault: &mut RewardVault,
    route_cap: &RouteCapability,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    tide.assert_not_paused();
    assert!(!self.paused, errors::paused());
    assert!(staking_adapter.listing_id() == self.id.to_inner(), errors::invalid_state());
    
    // Get the original staked principal before unstaking
    let original_principal = staking_adapter.staked_principal();
    
    // Unstake all
    let total_withdrawn = staking_adapter.unstake_all(system_state, ctx);
    let total_amount = total_withdrawn.value();
    
    if (total_amount == 0) {
        total_withdrawn.destroy_zero();
        return
    };
    
    // Calculate rewards
    let rewards_amount = if (total_amount > original_principal) {
        total_amount - original_principal
    } else {
        0
    };
    
    // Convert to coin for handling
    let mut total_coin = coin::from_balance(total_withdrawn, ctx);
    
    if (rewards_amount > 0) {
        // Split out rewards
        let rewards_coin = total_coin.split(rewards_amount, ctx);
        
        // Split rewards: 80% backers, 20% treasury
        let (backer_coin, treasury_coin) = staking_adapter.split_rewards(rewards_coin, ctx);
        
        // Route backer rewards to RewardVault
        let backer_amount = backer_coin.value();
        let treasury_amount = treasury_coin.value();
        
        if (backer_amount > 0) {
            reward_vault.deposit_rewards(route_cap, backer_coin, ctx);
            
            events::emit_staking_rewards_harvested(
                self.id.to_inner(),
                rewards_amount,
                backer_amount,
                treasury_amount,
                reward_vault.global_index(),
            );
        } else {
            backer_coin.destroy_zero();
        };
        
        // Transfer treasury portion
        if (treasury_coin.value() > 0) {
            transfer::public_transfer(treasury_coin, tide.treasury());
        } else {
            treasury_coin.destroy_zero();
        };
    };
    
    // Re-stake the principal
    staking_adapter.deposit(total_coin);
    staking_adapter.stake(system_state, ctx);
}

/// Withdraw pending (unstaked) balance from staking adapter.
/// Used after unstaking to retrieve funds.
public fun withdraw_staking_balance(
    self: &Listing,
    tide: &Tide,
    _council_cap: &CouncilCap,
    staking_adapter: &mut StakingAdapter,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    tide.assert_not_paused();
    assert!(!self.paused, errors::paused());
    assert!(staking_adapter.listing_id() == self.id.to_inner(), errors::invalid_state());
    
    staking_adapter.withdraw(amount, ctx)
}

// === View Functions ===

/// Get listing ID.
public fun id(self: &Listing): ID {
    self.id.to_inner()
}

/// Get listing number.
public fun listing_number(self: &Listing): u64 {
    self.listing_number
}

/// Get issuer address.
public fun issuer(self: &Listing): address {
    self.issuer
}

/// Get current state.
public fun state(self: &Listing): u8 {
    self.state
}

/// Get config hash.
public fun config_hash(self: &Listing): &vector<u8> {
    &self.config_hash
}

/// Get config.
public fun config(self: &Listing): &ListingConfig {
    &self.config
}

/// Get activation timestamp.
public fun activation_time(self: &Listing): u64 {
    self.activation_time
}

/// Get total backers.
public fun total_backers(self: &Listing): u64 {
    self.total_backers
}

/// Check if listing is paused.
public fun is_paused(self: &Listing): bool {
    self.paused
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

// === Config Getters ===

public fun config_issuer(config: &ListingConfig): address {
    config.issuer
}

public fun config_validator(config: &ListingConfig): address {
    config.validator
}

public fun config_tranche_amounts(config: &ListingConfig): &vector<u64> {
    &config.tranche_amounts
}

public fun config_tranche_times(config: &ListingConfig): &vector<u64> {
    &config.tranche_times
}

public fun config_revenue_bps(config: &ListingConfig): u64 {
    config.revenue_bps
}

public fun config_raise_fee_bps(config: &ListingConfig): u64 {
    config.raise_fee_bps
}

public fun config_staking_backer_bps(config: &ListingConfig): u64 {
    config.staking_backer_bps
}

public fun config_min_deposit(config: &ListingConfig): u64 {
    config.min_deposit
}

// === Helper Functions ===

/// Compute hash of listing config.
fun compute_config_hash(config: &ListingConfig): vector<u8> {
    let bytes = bcs::to_bytes(config);
    hash::sha2_256(bytes)
}

/// Verify a config matches the stored hash.
public fun verify_config_hash(self: &Listing, config: &ListingConfig): bool {
    let computed = compute_config_hash(config);
    computed == self.config_hash
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
    registry: &mut ListingRegistry,
    council_cap: &CouncilCap,
    issuer: address,
    validator: address,
    tranche_amounts: vector<u64>,
    tranche_times: vector<u64>,
    ctx: &mut TxContext,
): (Listing, CapitalVault, RewardVault, StakingAdapter, ListingCap, RouteCapability) {
    new(registry, council_cap, issuer, validator, tranche_amounts, tranche_times, 1000, ctx)
}

#[test_only]
public fun destroy_for_testing(listing: Listing) {
    let Listing { id, config, .. } = listing;
    let _ = config;
    id.delete();
}

#[test_only]
public fun destroy_cap_for_testing(cap: ListingCap) {
    let ListingCap { id, .. } = cap;
    id.delete();
}

#[test_only]
public fun set_state_for_testing(self: &mut Listing, state: u8) {
    self.state = state;
}
