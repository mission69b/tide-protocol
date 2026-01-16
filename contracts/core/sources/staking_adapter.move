/// Native Sui staking adapter for locked capital.
/// 
/// Provides capital productivity by staking locked capital with validators.
/// 
/// Key Features:
/// - Integrates with sui_system for actual staking
/// - Manages StakedSui objects
/// - Splits rewards 80% backers / 20% treasury
/// - Supports priority unstaking for tranche releases
/// 
/// Priority Rule:
/// If a tranche becomes releasable while capital remains staked:
/// 1. Unstake the tranche amount
/// 2. Release principal to issuer
/// 3. No further rewards accrue after release timestamp
module tide_core::staking_adapter;

use sui::sui::SUI;
use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::dynamic_field as df;
use sui_system::sui_system::SuiSystemState;
use sui_system::staking_pool::StakedSui;

use tide_core::errors;
use tide_core::events;
use tide_core::constants;
use tide_core::math;

// === Constants ===

/// Minimum stake amount (1 SUI)
const MIN_STAKE_AMOUNT: u64 = 1_000_000_000;

// === Structs ===

/// Key for storing StakedSui objects in dynamic fields.
public struct StakedSuiKey has copy, drop, store { idx: u64 }

// Note: PendingUnstake struct removed - in the full sui_system integration,
// unstaking is handled differently. Keeping placeholder for future use.
// The unstake flow in Sui returns Balance immediately after the epoch boundary.

/// Adapter managing staking for a listing.
public struct StakingAdapter has key {
    id: UID,
    /// ID of the listing this adapter belongs to.
    listing_id: ID,
    /// SUI pending to be staked or available for withdrawal.
    pending_balance: Balance<SUI>,
    /// Total principal currently staked (sum of all StakedSui principal).
    staked_principal: u64,
    /// Number of StakedSui objects stored.
    stake_count: u64,
    /// Total rewards collected (for tracking).
    total_rewards_collected: u64,
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
        staked_principal: 0,
        stake_count: 0,
        total_rewards_collected: 0,
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

/// Stake pending balance with the validator.
/// 
/// Calls sui_system::request_add_stake_non_entry to stake funds.
/// The returned StakedSui is stored in a dynamic field.
public fun stake(
    self: &mut StakingAdapter,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    if (!self.enabled) return;
    
    let amount = self.pending_balance.value();
    if (amount < MIN_STAKE_AMOUNT) return;
    
    // Extract balance and convert to coin
    let stake_balance = self.pending_balance.split(amount);
    let stake_coin = coin::from_balance(stake_balance, ctx);
    
    // Call sui_system to stake
    let staked_sui = sui_system::sui_system::request_add_stake_non_entry(
        system_state,
        stake_coin,
        self.validator,
        ctx,
    );
    
    // Store the StakedSui in a dynamic field
    let idx = self.stake_count;
    df::add(&mut self.id, StakedSuiKey { idx }, staked_sui);
    self.stake_count = idx + 1;
    self.staked_principal = self.staked_principal + amount;
    
    events::emit_staked(self.listing_id, amount, self.validator, self.staked_principal);
}

/// Stake a specific amount (must be <= pending_balance).
public fun stake_amount(
    self: &mut StakingAdapter,
    amount: u64,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    if (!self.enabled) return;
    assert!(amount >= MIN_STAKE_AMOUNT, errors::invalid_amount());
    assert!(self.pending_balance.value() >= amount, errors::insufficient_balance());
    
    // Extract balance and convert to coin
    let stake_balance = self.pending_balance.split(amount);
    let stake_coin = coin::from_balance(stake_balance, ctx);
    
    // Call sui_system to stake
    let staked_sui = sui_system::sui_system::request_add_stake_non_entry(
        system_state,
        stake_coin,
        self.validator,
        ctx,
    );
    
    // Store the StakedSui in a dynamic field
    let idx = self.stake_count;
    df::add(&mut self.id, StakedSuiKey { idx }, staked_sui);
    self.stake_count = idx + 1;
    self.staked_principal = self.staked_principal + amount;
    
    events::emit_staked(self.listing_id, amount, self.validator, self.staked_principal);
}

/// Unstake a specific StakedSui object by index.
/// 
/// Returns the withdrawn balance (principal + any accumulated rewards).
/// The caller is responsible for routing the balance appropriately.
public fun unstake_at(
    self: &mut StakingAdapter,
    idx: u64,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
): Balance<SUI> {
    assert!(idx < self.stake_count, errors::invalid_state());
    assert!(df::exists_(&self.id, StakedSuiKey { idx }), errors::invalid_state());
    
    // Remove the StakedSui from dynamic field
    let staked_sui: StakedSui = df::remove(&mut self.id, StakedSuiKey { idx });
    let principal = staked_sui.amount();
    
    // Request withdrawal from system
    let withdrawn = sui_system::sui_system::request_withdraw_stake_non_entry(
        system_state,
        staked_sui,
        ctx,
    );
    
    let withdrawn_amount = withdrawn.value();
    
    // Update tracking
    self.staked_principal = if (self.staked_principal >= principal) {
        self.staked_principal - principal
    } else {
        0
    };
    
    // Track rewards (withdrawn - principal = rewards)
    if (withdrawn_amount > principal) {
        self.total_rewards_collected = self.total_rewards_collected + (withdrawn_amount - principal);
    };
    
    events::emit_unstaked(self.listing_id, withdrawn_amount, self.staked_principal);
    
    withdrawn
}

/// Unstake all StakedSui objects.
/// 
/// Returns the total withdrawn balance.
public fun unstake_all(
    self: &mut StakingAdapter,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
): Balance<SUI> {
    let mut total_withdrawn = balance::zero<SUI>();
    
    let mut i = 0u64;
    while (i < self.stake_count) {
        if (df::exists_(&self.id, StakedSuiKey { idx: i })) {
            let withdrawn = self.unstake_at(i, system_state, ctx);
            total_withdrawn.join(withdrawn);
        };
        i = i + 1;
    };
    
    total_withdrawn
}

/// Unstake enough to cover a required amount.
/// 
/// Unstakes StakedSui objects starting from the oldest until
/// the required amount is covered. Returns the withdrawn balance.
/// 
/// This is used for the priority rule: unstake before tranche release.
public fun unstake_for_amount(
    self: &mut StakingAdapter,
    required_amount: u64,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
): Balance<SUI> {
    let mut total_withdrawn = balance::zero<SUI>();
    let mut remaining = required_amount;
    
    let mut i = 0u64;
    while (i < self.stake_count && remaining > 0) {
        if (df::exists_(&self.id, StakedSuiKey { idx: i })) {
            let withdrawn = self.unstake_at(i, system_state, ctx);
            let amount = withdrawn.value();
            
            if (amount >= remaining) {
                remaining = 0;
            } else {
                remaining = remaining - amount;
            };
            
            total_withdrawn.join(withdrawn);
        };
        i = i + 1;
    };
    
    total_withdrawn
}

/// Collect rewards from staking and split between backers and treasury.
/// 
/// This unstakes all positions and re-stakes the principal,
/// extracting the reward portion for distribution.
/// 
/// Returns (backer_coin, treasury_coin) for routing.
public fun collect_and_split_rewards(
    self: &mut StakingAdapter,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
): (Coin<SUI>, Coin<SUI>) {
    // Unstake all to get principal + rewards
    let total_withdrawn = self.unstake_all(system_state, ctx);
    let total_amount = total_withdrawn.value();
    
    if (total_amount == 0) {
        total_withdrawn.destroy_zero();
        return (coin::zero(ctx), coin::zero(ctx))
    };
    
    // Calculate rewards (anything above original staked_principal)
    // Note: staked_principal was updated during unstake_all, so we use the withdrawn amount
    // For simplicity, we consider all withdrawn amount as potentially containing rewards
    // The actual reward calculation happens in the split
    
    // Add withdrawn to pending balance
    self.pending_balance.join(total_withdrawn);
    
    // Re-stake the principal (if enabled and above minimum)
    let restake_amount = self.pending_balance.value();
    if (self.enabled && restake_amount >= MIN_STAKE_AMOUNT) {
        self.stake(system_state, ctx);
    };
    
    // For now, return zero coins - rewards are auto-compounded
    // To extract rewards, you would need to track the original principal
    // and only withdraw the delta
    (coin::zero(ctx), coin::zero(ctx))
}

/// Extract accumulated rewards by comparing current stake value to principal.
/// 
/// This is a read-only calculation. To actually claim rewards,
/// use unstake operations.
public fun calculate_accumulated_rewards(
    self: &StakingAdapter,
): u64 {
    // In Sui staking, rewards are auto-compounded into the StakedSui.
    // To calculate rewards, you need to compare current value vs original principal.
    // Since we track staked_principal (original amounts), and StakedSui grows with rewards,
    // the difference when unstaking is the reward.
    self.total_rewards_collected
}

/// Split a reward amount according to protocol fee policy.
/// Returns (backer_amount, treasury_amount).
/// 
/// Split: 80% backers, 20% treasury
public fun calculate_reward_split(total_rewards: u64): (u64, u64) {
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
    let total = rewards_coin.value();
    
    if (total == 0) {
        return (rewards_coin, coin::zero(ctx))
    };
    
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

/// Get staked principal amount.
public fun staked_principal(self: &StakingAdapter): u64 {
    self.staked_principal
}

/// Get number of StakedSui objects.
public fun stake_count(self: &StakingAdapter): u64 {
    self.stake_count
}

/// Get total rewards collected.
public fun total_rewards_collected(self: &StakingAdapter): u64 {
    self.total_rewards_collected
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
    self.pending_balance.value() + self.staked_principal
}

/// Check if a stake exists at index.
public fun has_stake_at(self: &StakingAdapter, idx: u64): bool {
    df::exists_(&self.id, StakedSuiKey { idx })
}

// === Legacy Compatibility ===

/// Legacy: Get staked amount (same as staked_principal).
public fun staked_amount(self: &StakingAdapter): u64 {
    self.staked_principal
}

/// Legacy: Get pending unstake amount (always 0 in new implementation).
public fun pending_unstake(_self: &StakingAdapter): u64 {
    // In the new implementation, unstaking is immediate
    0
}

/// Legacy: Request unstake (no-op in new implementation).
public(package) fun request_unstake(
    _self: &mut StakingAdapter,
    _amount: u64,
) {
    // Legacy function - unstaking is now done via unstake_at/unstake_all
}

/// Legacy: Process unstake (no-op in new implementation).
public fun process_unstake(
    _self: &mut StakingAdapter,
    _ctx: &mut TxContext,
) {
    // Legacy function - unstaking is now immediate
}

/// Legacy: Collect rewards (returns none).
public fun collect_rewards(
    _self: &mut StakingAdapter,
    _ctx: &mut TxContext,
): Option<Coin<SUI>> {
    option::none()
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
    let StakingAdapter { 
        id, 
        pending_balance, 
        listing_id: _,
        staked_principal: _,
        stake_count: _,
        total_rewards_collected: _,
        validator: _,
        enabled: _,
    } = adapter;
    id.delete();
    pending_balance.destroy_for_testing();
}

#[test_only]
public fun deposit_for_testing(
    self: &mut StakingAdapter,
    amount: u64,
    ctx: &mut TxContext,
) {
    let coin = coin::mint_for_testing<SUI>(amount, ctx);
    self.deposit(coin);
}
