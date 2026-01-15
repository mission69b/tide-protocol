/// Native Sui staking adapter for locked capital.
/// 
/// Provides limited capital productivity by staking locked capital.
/// 
/// Priority Rule:
/// If a tranche becomes releasable while capital remains staked:
/// 1. Unstake the tranche amount
/// 2. Release principal to issuer
/// 3. No further rewards accrue after release timestamp
/// 
/// Note: Sui staking is epoch-based. Unstaking requires waiting for
/// the epoch boundary before funds are available.
module tide_core::staking_adapter;

use sui::sui::SUI;
use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};

use tide_core::errors;
use tide_core::events;

// === Structs ===

/// Adapter managing staking for a listing.
public struct StakingAdapter has key {
    id: UID,
    /// ID of the listing this adapter belongs to.
    listing_id: ID,
    /// SUI pending to be staked or unstaked.
    pending_balance: Balance<SUI>,
    /// Amount currently staked (tracked, actual stake is in StakedSui).
    staked_amount: u64,
    /// Amount pending unstake (waiting for epoch).
    pending_unstake: u64,
    /// Preferred validator address.
    validator: address,
    /// Whether staking is enabled.
    enabled: bool,
}

// === Package Functions ===

/// Create a new StakingAdapter for a listing.
public(package) fun new(
    listing_id: ID,
    validator: address,
    ctx: &mut TxContext,
): StakingAdapter {
    StakingAdapter {
        id: object::new(ctx),
        listing_id,
        pending_balance: balance::zero(),
        staked_amount: 0,
        pending_unstake: 0,
        validator,
        enabled: true,
    }
}

/// Deposit SUI for staking.
public(package) fun deposit(
    self: &mut StakingAdapter,
    coin: Coin<SUI>,
) {
    self.pending_balance.join(coin.into_balance());
}

/// Request unstake of specified amount.
/// Note: Actual unstaking is epoch-based in Sui.
public(package) fun request_unstake(
    self: &mut StakingAdapter,
    amount: u64,
) {
    assert!(self.staked_amount >= amount, errors::insufficient_balance());
    self.pending_unstake = self.pending_unstake + amount;
    self.staked_amount = self.staked_amount - amount;
}

/// Withdraw available (unstaked) funds.
public(package) fun withdraw(
    self: &mut StakingAdapter,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(self.pending_balance.value() >= amount, errors::insufficient_balance());
    coin::from_balance(self.pending_balance.split(amount), ctx)
}

/// Enable or disable staking.
public(package) fun set_enabled(
    self: &mut StakingAdapter,
    enabled: bool,
) {
    self.enabled = enabled;
}

// === Staking Operations ===
// Note: Full staking integration requires sui_system module.
// These are placeholder implementations for v1.

/// Stake pending balance with validator.
/// 
/// TODO: Integrate with sui_system::request_add_stake
/// For v1, this is a simplified version that tracks amounts.
public fun stake(
    self: &mut StakingAdapter,
    _ctx: &mut TxContext,
) {
    if (!self.enabled) return;
    
    let amount = self.pending_balance.value();
    if (amount == 0) return;
    
    // In full implementation:
    // 1. Call sui_system::request_add_stake(wrapper, coin, validator, ctx)
    // 2. Store returned StakedSui object
    
    // For now, just track the amount
    self.staked_amount = self.staked_amount + amount;
    
    // Note: In real implementation, balance would be consumed by staking
    // self.pending_balance would be zero after staking
    
    events::emit_staked(self.listing_id, amount, self.validator);
}

/// Process pending unstake requests.
/// 
/// TODO: Integrate with sui_system::request_withdraw_stake
/// Unstaking is epoch-based; funds available after epoch boundary.
public fun process_unstake(
    self: &mut StakingAdapter,
    _ctx: &mut TxContext,
) {
    if (self.pending_unstake == 0) return;
    
    // In full implementation:
    // 1. Call sui_system::request_withdraw_stake
    // 2. Wait for epoch boundary
    // 3. Receive SUI back
    
    let amount = self.pending_unstake;
    self.pending_unstake = 0;
    
    // In real implementation, balance would be restored from unstaking
    // For now, this is a no-op since we didn't actually stake
    
    events::emit_unstaked(self.listing_id, amount);
}

/// Collect staking rewards and split between backers and treasury.
/// 
/// TODO: Implement reward collection from StakedSui
/// 
/// Split: 80% to RewardVault (backers), 20% to Treasury
/// Returns (backer_coin, treasury_coin) for routing.
public fun collect_and_split_rewards(
    self: &mut StakingAdapter,
    ctx: &mut TxContext,
): (Option<Coin<SUI>>, Option<Coin<SUI>>) {
    // In full implementation:
    // 1. Check StakedSui for accumulated rewards
    // 2. Withdraw rewards portion
    // 3. Split 80/20
    
    // For v1, return none (no actual staking yet)
    // When implemented:
    // let total_rewards = ...get from StakedSui...;
    // let backer_amount = (total_rewards * STAKING_BACKER_BPS) / MAX_BPS;
    // let treasury_amount = total_rewards - backer_amount;
    
    let _ = self;
    let _ = ctx;
    
    (option::none(), option::none())
}

/// Split a reward amount according to protocol fee policy.
/// Returns (backer_amount, treasury_amount).
/// 
/// Split: 80% backers, 20% treasury
public fun calculate_reward_split(total_rewards: u64): (u64, u64) {
    use tide_core::constants;
    use tide_core::math;
    
    let backer_amount = math::mul_div(
        (total_rewards as u128),
        (constants::staking_backer_bps!() as u128),
        (constants::max_bps!() as u128),
    );
    let backer_amount_u64 = (backer_amount as u64);
    let treasury_amount = total_rewards - backer_amount_u64;
    
    (backer_amount_u64, treasury_amount)
}

/// Process staking rewards with split.
/// Takes raw rewards and returns split coins.
/// Emits StakingRewardSplit event.
public fun split_rewards(
    self: &StakingAdapter,
    mut rewards_coin: Coin<SUI>,
    ctx: &mut TxContext,
): (Coin<SUI>, Coin<SUI>) {
    use tide_core::constants;
    
    let total = rewards_coin.value();
    let (backer_amount, treasury_amount) = calculate_reward_split(total);
    
    // Split the coin
    let treasury_coin = rewards_coin.split(treasury_amount, ctx);
    let backer_coin = rewards_coin; // Remaining is backer portion
    
    // Emit event
    events::emit_staking_reward_split(
        self.listing_id,
        total,
        backer_amount,
        treasury_amount,
        constants::staking_backer_bps!(),
    );
    
    (backer_coin, treasury_coin)
}

/// Collect staking rewards (legacy signature for backwards compatibility).
/// 
/// TODO: Implement reward collection from StakedSui
/// Returns coin to be deposited in RewardVault.
public fun collect_rewards(
    _self: &mut StakingAdapter,
    _ctx: &mut TxContext,
): Option<Coin<SUI>> {
    // For v1, return none (no actual staking)
    option::none()
}

// === View Functions ===

/// Get adapter ID.
public fun id(self: &StakingAdapter): ID {
    self.id.to_inner()
}

/// Get listing ID.
public fun listing_id(self: &StakingAdapter): ID {
    self.listing_id
}

/// Get pending balance.
public fun pending_balance(self: &StakingAdapter): u64 {
    self.pending_balance.value()
}

/// Get staked amount.
public fun staked_amount(self: &StakingAdapter): u64 {
    self.staked_amount
}

/// Get pending unstake amount.
public fun pending_unstake(self: &StakingAdapter): u64 {
    self.pending_unstake
}

/// Get validator address.
public fun validator(self: &StakingAdapter): address {
    self.validator
}

/// Check if staking is enabled.
public fun is_enabled(self: &StakingAdapter): bool {
    self.enabled
}

/// Get total capital under management (pending + staked).
public fun total_capital(self: &StakingAdapter): u64 {
    self.pending_balance.value() + self.staked_amount
}

// === Share Function ===

/// Share the staking adapter object.
public fun share(adapter: StakingAdapter) {
    transfer::share_object(adapter);
}

// === Test Helpers ===

#[test_only]
public fun new_for_testing(
    listing_id: ID,
    validator: address,
    ctx: &mut TxContext,
): StakingAdapter {
    new(listing_id, validator, ctx)
}

#[test_only]
public fun destroy_for_testing(adapter: StakingAdapter) {
    let StakingAdapter { id, pending_balance, .. } = adapter;
    id.delete();
    pending_balance.destroy_for_testing();
}
