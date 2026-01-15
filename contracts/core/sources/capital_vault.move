/// Holds contributed principal (SUI) and manages tranche releases.
/// 
/// CapitalVault:
/// - Accepts deposits while listing is active
/// - Tracks total principal and shares
/// - Releases capital to issuer on deterministic schedule
/// - Deducts raise fee (1%) before first tranche release
/// 
/// Deterministic Capital Release:
/// - 20% initial release at finalization
/// - 80% released evenly across 12 monthly tranches
/// - Schedule computed and locked at finalization
/// - Pull-based: anyone can call release once time passes
/// 
/// Invariants:
/// - Backers cannot withdraw principal
/// - Principal only flows to issuer via tranche release
/// - Principal never enters RewardVault
/// - Raise fee is immutable and collected exactly once
/// - Release schedule is immutable after finalization
module tide_core::capital_vault;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::clock::Clock;

use tide_core::errors;
use tide_core::math;
use tide_core::constants;
use tide_core::events;

// === Structs ===

/// Individual release tranche.
public struct Tranche has store, copy, drop {
    /// Amount of SUI in this tranche.
    amount: u64,
    /// Unix timestamp when tranche becomes releasable.
    release_time: u64,
    /// Whether tranche has been released.
    released: bool,
}

/// Vault holding contributed principal.
public struct CapitalVault has key {
    id: UID,
    /// ID of the listing this vault belongs to.
    listing_id: ID,
    /// SUI balance (principal).
    balance: Balance<SUI>,
    /// Total principal deposited.
    total_principal: u64,
    /// Total shares minted.
    total_shares: u128,
    /// Issuer address who receives released capital.
    issuer: address,
    /// Release tranches (computed at finalization).
    tranches: vector<Tranche>,
    /// Number of tranches released so far.
    tranches_released: u64,
    /// Raise fee in basis points (immutable after creation).
    raise_fee_bps: u64,
    /// Whether raise fee has been collected.
    raise_fee_collected: bool,
    /// Whether schedule has been finalized.
    schedule_finalized: bool,
    /// Timestamp when schedule was finalized.
    finalization_time: u64,
    /// Minimum deposit amount (anti-spam).
    min_deposit: u64,
}

// === Package Functions ===

/// Create a new CapitalVault for a listing.
public(package) fun new(
    listing_id: ID,
    issuer: address,
    tranche_amounts: vector<u64>,
    tranche_times: vector<u64>,
    ctx: &mut TxContext,
): CapitalVault {
    assert!(tranche_amounts.length() == tranche_times.length(), errors::invalid_state());
    
    let mut tranches = vector::empty<Tranche>();
    let mut i = 0;
    while (i < tranche_amounts.length()) {
        tranches.push_back(Tranche {
            amount: tranche_amounts[i],
            release_time: tranche_times[i],
            released: false,
        });
        i = i + 1;
    };
    
    CapitalVault {
        id: object::new(ctx),
        listing_id,
        balance: balance::zero(),
        total_principal: 0,
        total_shares: 0,
        issuer,
        tranches,
        tranches_released: 0,
        raise_fee_bps: constants::raise_fee_bps!(),
        raise_fee_collected: false,
        schedule_finalized: false,
        finalization_time: 0,
        min_deposit: constants::min_deposit!(),
    }
}

/// Create a CapitalVault with empty tranches (to be computed at finalization).
/// This is the canonical v1 approach - schedule computed based on actual raised amount.
public(package) fun new_with_deferred_schedule(
    listing_id: ID,
    issuer: address,
    ctx: &mut TxContext,
): CapitalVault {
    CapitalVault {
        id: object::new(ctx),
        listing_id,
        balance: balance::zero(),
        total_principal: 0,
        total_shares: 0,
        issuer,
        tranches: vector::empty(),
        tranches_released: 0,
        raise_fee_bps: constants::raise_fee_bps!(),
        raise_fee_collected: false,
        schedule_finalized: false,
        finalization_time: 0,
        min_deposit: constants::min_deposit!(),
    }
}

/// Finalize the release schedule based on actual raised amount.
/// Computes the canonical 20% + 12x(80%/12) schedule.
/// Must be called at listing finalization.
public(package) fun finalize_schedule(
    self: &mut CapitalVault,
    clock: &Clock,
) {
    assert!(!self.schedule_finalized, errors::invalid_state());
    assert!(self.total_principal > 0, errors::invalid_amount());
    
    let finalization_time = clock.timestamp_ms();
    self.finalization_time = finalization_time;
    
    // Calculate net capital after raise fee
    let fee_amount = math::mul_div(
        (self.total_principal as u128),
        (self.raise_fee_bps as u128),
        (constants::max_bps!() as u128),
    );
    let net_capital = self.total_principal - (fee_amount as u64);
    
    // Calculate initial release (20%)
    let initial_amount = math::mul_div(
        (net_capital as u128),
        (constants::initial_release_bps!() as u128),
        (constants::max_bps!() as u128),
    );
    
    // Calculate monthly tranche amount (80% / 12)
    let remaining = net_capital - (initial_amount as u64);
    let monthly_count = constants::monthly_tranche_count!();
    let monthly_amount = remaining / monthly_count;
    
    // Clear any existing tranches and build canonical schedule
    self.tranches = vector::empty();
    
    // Tranche 0: Initial release (20%) - immediately at finalization
    self.tranches.push_back(Tranche {
        amount: (initial_amount as u64),
        release_time: finalization_time,
        released: false,
    });
    
    // Tranches 1-12: Monthly releases (each ~6.67%)
    let tranche_interval = constants::tranche_interval_ms!();
    let mut i = 1u64;
    while (i <= monthly_count) {
        // Handle remainder in last tranche
        let tranche_amount = if (i == monthly_count) {
            remaining - (monthly_amount * (monthly_count - 1))
        } else {
            monthly_amount
        };
        
        self.tranches.push_back(Tranche {
            amount: tranche_amount,
            release_time: finalization_time + (i * tranche_interval),
            released: false,
        });
        i = i + 1;
    };
    
    self.schedule_finalized = true;
}

/// Accept a deposit and calculate shares.
/// Returns the shares minted for this deposit.
/// Enforces minimum deposit amount (1 SUI) to prevent spam.
public(package) fun accept_deposit(
    self: &mut CapitalVault,
    coin: Coin<SUI>,
): u128 {
    let amount = coin.value();
    assert!(amount > 0, errors::invalid_amount());
    assert!(amount >= self.min_deposit, errors::below_minimum());
    
    // Calculate shares before updating state
    let shares = math::to_shares(amount, self.total_principal, self.total_shares);
    
    // Update state
    self.total_principal = self.total_principal + amount;
    self.total_shares = self.total_shares + shares;
    
    // Add to balance
    self.balance.join(coin.into_balance());
    
    shares
}

/// Collect raise fee before first tranche release.
/// Returns fee coin to be sent to treasury.
/// Must be called after schedule finalization but before any release.
public(package) fun collect_raise_fee(
    self: &mut CapitalVault,
    treasury: address,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(!self.raise_fee_collected, errors::already_released());
    assert!(self.schedule_finalized, errors::invalid_state()); // Schedule must be finalized
    assert!(self.tranches_released == 0, errors::invalid_state()); // Must be before first release
    
    // Calculate fee: (total_principal * raise_fee_bps) / MAX_BPS
    let fee_amount = math::mul_div(
        (self.total_principal as u128),
        (self.raise_fee_bps as u128),
        (constants::max_bps!() as u128),
    );
    let fee_amount_u64 = (fee_amount as u64);
    
    // Cap fee to available balance
    let actual_fee = if (fee_amount_u64 > self.balance.value()) {
        self.balance.value()
    } else {
        fee_amount_u64
    };
    
    self.raise_fee_collected = true;
    
    // Emit event
    events::emit_raise_fee_collected(
        self.listing_id,
        actual_fee,
        treasury,
        self.total_principal,
        self.raise_fee_bps,
    );
    
    coin::from_balance(self.balance.split(actual_fee), ctx)
}

/// Release a specific tranche by index.
/// Tranches can be released in any order once their time has passed.
/// Returns the amount released.
/// Raise fee must be collected before any release.
public(package) fun release_tranche_at(
    self: &mut CapitalVault,
    tranche_idx: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (u64, Coin<SUI>) {
    assert!(self.schedule_finalized, errors::invalid_state());
    assert!(self.raise_fee_collected, errors::invalid_state());
    assert!(tranche_idx < self.tranches.length(), errors::all_tranches_released());
    
    let tranche = &mut self.tranches[tranche_idx];
    assert!(!tranche.released, errors::already_released());
    assert!(clock.timestamp_ms() >= tranche.release_time, errors::tranche_not_ready());
    
    let amount = tranche.amount;
    tranche.released = true;
    self.tranches_released = self.tranches_released + 1;
    
    // Calculate actual amount to release (may be less if not enough in balance)
    let release_amount = if (amount > self.balance.value()) {
        self.balance.value()
    } else {
        amount
    };
    
    let coin = coin::from_balance(self.balance.split(release_amount), ctx);
    
    (release_amount, coin)
}

/// Release the next unreleased tranche that is ready.
/// Convenience function that finds and releases the first ready tranche.
/// Returns (tranche_idx, amount, coin).
public(package) fun release_next_ready_tranche(
    self: &mut CapitalVault,
    clock: &Clock,
    ctx: &mut TxContext,
): (u64, u64, Coin<SUI>) {
    assert!(self.schedule_finalized, errors::invalid_state());
    assert!(self.raise_fee_collected, errors::invalid_state());
    
    // Find first unreleased tranche that is ready
    let mut i = 0;
    let len = self.tranches.length();
    while (i < len) {
        let tranche = &self.tranches[i];
        if (!tranche.released && clock.timestamp_ms() >= tranche.release_time) {
            let (amount, coin) = release_tranche_at(self, i, clock, ctx);
            return (i, amount, coin)
        };
        i = i + 1;
    };
    
    // No tranche ready
    abort errors::tranche_not_ready()
}

/// Release all tranches that are currently ready.
/// Returns vector of (tranche_idx, amount) pairs and combined coin.
public(package) fun release_all_ready_tranches(
    self: &mut CapitalVault,
    clock: &Clock,
    ctx: &mut TxContext,
): (vector<u64>, u64, Coin<SUI>) {
    assert!(self.schedule_finalized, errors::invalid_state());
    assert!(self.raise_fee_collected, errors::invalid_state());
    
    let mut released_indices = vector::empty<u64>();
    let mut total_released = 0u64;
    let mut combined_balance = balance::zero<SUI>();
    
    let mut i = 0;
    let len = self.tranches.length();
    while (i < len) {
        let tranche = &self.tranches[i];
        if (!tranche.released && clock.timestamp_ms() >= tranche.release_time) {
            let (amount, coin) = release_tranche_at(self, i, clock, ctx);
            released_indices.push_back(i);
            total_released = total_released + amount;
            combined_balance.join(coin.into_balance());
        };
        i = i + 1;
    };
    
    (released_indices, total_released, coin::from_balance(combined_balance, ctx))
}

// === View Functions ===

/// Get vault ID.
public fun id(self: &CapitalVault): ID {
    self.id.to_inner()
}

/// Get listing ID.
public fun listing_id(self: &CapitalVault): ID {
    self.listing_id
}

/// Get current balance.
public fun balance(self: &CapitalVault): u64 {
    self.balance.value()
}

/// Get total principal deposited.
public fun total_principal(self: &CapitalVault): u64 {
    self.total_principal
}

/// Get total shares minted.
public fun total_shares(self: &CapitalVault): u128 {
    self.total_shares
}

/// Get issuer address.
public fun issuer(self: &CapitalVault): address {
    self.issuer
}

/// Get number of tranches.
public fun num_tranches(self: &CapitalVault): u64 {
    self.tranches.length()
}

/// Get number of tranches released.
public fun tranches_released(self: &CapitalVault): u64 {
    self.tranches_released
}

/// Check if schedule has been finalized.
public fun is_schedule_finalized(self: &CapitalVault): bool {
    self.schedule_finalized
}

/// Get finalization timestamp.
public fun finalization_time(self: &CapitalVault): u64 {
    self.finalization_time
}

/// Get tranche info by index.
public fun tranche_at(self: &CapitalVault, idx: u64): (u64, u64, bool) {
    if (idx >= self.tranches.length()) {
        return (0, 0, true)
    };
    let tranche = &self.tranches[idx];
    (tranche.amount, tranche.release_time, tranche.released)
}

/// Check if a specific tranche is ready for release.
public fun is_tranche_ready(self: &CapitalVault, idx: u64, clock: &Clock): bool {
    if (idx >= self.tranches.length()) {
        return false
    };
    let tranche = &self.tranches[idx];
    !tranche.released && clock.timestamp_ms() >= tranche.release_time
}

/// Count how many tranches are currently ready to release.
public fun count_ready_tranches(self: &CapitalVault, clock: &Clock): u64 {
    let mut count = 0u64;
    let mut i = 0;
    while (i < self.tranches.length()) {
        let tranche = &self.tranches[i];
        if (!tranche.released && clock.timestamp_ms() >= tranche.release_time) {
            count = count + 1;
        };
        i = i + 1;
    };
    count
}

/// Calculate cumulative amount released to issuer.
public fun cumulative_released(self: &CapitalVault): u64 {
    let mut total = 0u64;
    let mut i = 0;
    while (i < self.tranches.length()) {
        let tranche = &self.tranches[i];
        if (tranche.released) {
            total = total + tranche.amount;
        };
        i = i + 1;
    };
    total
}

/// Check if all tranches are released.
public fun all_released(self: &CapitalVault): bool {
    self.tranches_released >= self.tranches.length()
}

/// Get total amount still locked (not yet released).
public fun total_locked(self: &CapitalVault): u64 {
    let mut locked = 0u64;
    let mut i = 0;
    while (i < self.tranches.length()) {
        let tranche = &self.tranches[i];
        if (!tranche.released) {
            locked = locked + tranche.amount;
        };
        i = i + 1;
    };
    locked
}

/// Get total amount already released.
public fun total_released_amount(self: &CapitalVault): u64 {
    let mut released = 0u64;
    let mut i = 0;
    while (i < self.tranches.length()) {
        let tranche = &self.tranches[i];
        if (tranche.released) {
            released = released + tranche.amount;
        };
        i = i + 1;
    };
    released
}

/// Get raise fee in basis points.
public fun raise_fee_bps(self: &CapitalVault): u64 {
    self.raise_fee_bps
}

/// Check if raise fee has been collected.
public fun is_raise_fee_collected(self: &CapitalVault): bool {
    self.raise_fee_collected
}

/// Get minimum deposit amount.
public fun min_deposit(self: &CapitalVault): u64 {
    self.min_deposit
}

// === Share Function ===

/// Share the capital vault object.
public fun share(vault: CapitalVault) {
    transfer::share_object(vault);
}

// === Test Helpers ===

#[test_only]
public fun new_for_testing(
    listing_id: ID,
    issuer: address,
    tranche_amounts: vector<u64>,
    tranche_times: vector<u64>,
    ctx: &mut TxContext,
): CapitalVault {
    new(listing_id, issuer, tranche_amounts, tranche_times, ctx)
}

#[test_only]
public fun destroy_for_testing(vault: CapitalVault) {
    let CapitalVault { id, balance, tranches, .. } = vault;
    id.delete();
    balance.destroy_for_testing();
    let _ = tranches;
}
