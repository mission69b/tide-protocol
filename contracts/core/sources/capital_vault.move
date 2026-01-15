/// Holds contributed principal (SUI) and manages tranche releases.
/// 
/// CapitalVault:
/// - Accepts deposits while listing is active
/// - Tracks total principal and shares
/// - Releases capital to issuer on deterministic schedule
/// - Deducts raise fee (1%) before first tranche release
/// 
/// Invariants:
/// - Backers cannot withdraw principal
/// - Principal only flows to issuer via tranche release
/// - Principal never enters RewardVault
/// - Raise fee is immutable and collected exactly once
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
    /// Release tranches.
    tranches: vector<Tranche>,
    /// Index of next tranche to release.
    next_tranche_idx: u64,
    /// Raise fee in basis points (immutable after creation).
    raise_fee_bps: u64,
    /// Whether raise fee has been collected.
    raise_fee_collected: bool,
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
        next_tranche_idx: 0,
        raise_fee_bps: constants::raise_fee_bps!(),
        raise_fee_collected: false,
    }
}

/// Accept a deposit and calculate shares.
/// Returns the shares minted for this deposit.
public(package) fun accept_deposit(
    self: &mut CapitalVault,
    coin: Coin<SUI>,
): u128 {
    let amount = coin.value();
    assert!(amount > 0, errors::invalid_amount());
    
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
/// Must be called before first release_tranche.
public(package) fun collect_raise_fee(
    self: &mut CapitalVault,
    treasury: address,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(!self.raise_fee_collected, errors::already_released());
    assert!(self.next_tranche_idx == 0, errors::invalid_state()); // Must be before first release
    
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

/// Release the next tranche to the issuer.
/// Returns the amount released.
/// Raise fee must be collected before first release.
public(package) fun release_tranche(
    self: &mut CapitalVault,
    clock: &Clock,
    ctx: &mut TxContext,
): (u64, Coin<SUI>) {
    assert!(self.next_tranche_idx < self.tranches.length(), errors::all_tranches_released());
    
    // Ensure raise fee collected before first release
    if (self.next_tranche_idx == 0) {
        assert!(self.raise_fee_collected, errors::invalid_state());
    };
    
    let tranche = &mut self.tranches[self.next_tranche_idx];
    assert!(!tranche.released, errors::already_released());
    assert!(clock.timestamp_ms() >= tranche.release_time, errors::tranche_not_ready());
    
    let amount = tranche.amount;
    tranche.released = true;
    self.next_tranche_idx = self.next_tranche_idx + 1;
    
    // Calculate actual amount to release (may be less if not enough deposited)
    let release_amount = if (amount > self.balance.value()) {
        self.balance.value()
    } else {
        amount
    };
    
    let coin = coin::from_balance(self.balance.split(release_amount), ctx);
    
    (release_amount, coin)
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

/// Get next tranche index.
public fun next_tranche_idx(self: &CapitalVault): u64 {
    self.next_tranche_idx
}

/// Check if next tranche is ready for release.
public fun is_next_tranche_ready(self: &CapitalVault, clock: &Clock): bool {
    if (self.next_tranche_idx >= self.tranches.length()) {
        return false
    };
    let tranche = &self.tranches[self.next_tranche_idx];
    !tranche.released && clock.timestamp_ms() >= tranche.release_time
}

/// Get next tranche info.
public fun next_tranche(self: &CapitalVault): (u64, u64, bool) {
    if (self.next_tranche_idx >= self.tranches.length()) {
        return (0, 0, true)
    };
    let tranche = &self.tranches[self.next_tranche_idx];
    (tranche.amount, tranche.release_time, tranche.released)
}

/// Check if all tranches are released.
public fun all_released(self: &CapitalVault): bool {
    self.next_tranche_idx >= self.tranches.length()
}

/// Get raise fee in basis points.
public fun raise_fee_bps(self: &CapitalVault): u64 {
    self.raise_fee_bps
}

/// Check if raise fee has been collected.
public fun is_raise_fee_collected(self: &CapitalVault): bool {
    self.raise_fee_collected
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
