/// Standardized events for Tide Core.
module tide_core::events;

use sui::event::emit;

// === Deposit Events ===

/// Emitted when a backer deposits SUI into a listing.
public struct Deposited has copy, drop {
    listing_id: ID,
    backer: address,
    amount: u64,
    shares: u128,
    pass_id: ID,
}

public fun emit_deposited(
    listing_id: ID,
    backer: address,
    amount: u64,
    shares: u128,
    pass_id: ID,
) {
    emit(Deposited { listing_id, backer, amount, shares, pass_id });
}

// === Claim Events ===

/// Emitted when a backer claims rewards.
public struct Claimed has copy, drop {
    listing_id: ID,
    pass_id: ID,
    backer: address,
    amount: u64,
}

public fun emit_claimed(
    listing_id: ID,
    pass_id: ID,
    backer: address,
    amount: u64,
) {
    emit(Claimed { listing_id, pass_id, backer, amount });
}

// === Release Events ===

/// Emitted when a tranche is released to the issuer.
public struct TrancheReleased has copy, drop {
    listing_id: ID,
    tranche_idx: u64,
    amount: u64,
    recipient: address,
}

public fun emit_tranche_released(
    listing_id: ID,
    tranche_idx: u64,
    amount: u64,
    recipient: address,
) {
    emit(TrancheReleased { listing_id, tranche_idx, amount, recipient });
}

// === Revenue Events ===

/// Emitted when revenue is routed into the RewardVault.
public struct RouteIn has copy, drop {
    listing_id: ID,
    source: address,
    amount: u64,
}

public fun emit_route_in(
    listing_id: ID,
    source: address,
    amount: u64,
) {
    emit(RouteIn { listing_id, source, amount });
}

/// Emitted when the reward index is updated.
public struct RewardIndexUpdated has copy, drop {
    listing_id: ID,
    old_index: u128,
    new_index: u128,
}

public fun emit_reward_index_updated(
    listing_id: ID,
    old_index: u128,
    new_index: u128,
) {
    emit(RewardIndexUpdated { listing_id, old_index, new_index });
}

// === Staking Events ===

/// Emitted when capital is staked.
public struct Staked has copy, drop {
    listing_id: ID,
    amount: u64,
    validator: address,
}

public fun emit_staked(
    listing_id: ID,
    amount: u64,
    validator: address,
) {
    emit(Staked { listing_id, amount, validator });
}

/// Emitted when capital is unstaked.
public struct Unstaked has copy, drop {
    listing_id: ID,
    amount: u64,
}

public fun emit_unstaked(listing_id: ID, amount: u64) {
    emit(Unstaked { listing_id, amount });
}

// === Lifecycle Events ===

/// Emitted when listing state changes.
public struct StateChanged has copy, drop {
    listing_id: ID,
    old_state: u8,
    new_state: u8,
}

public fun emit_state_changed(
    listing_id: ID,
    old_state: u8,
    new_state: u8,
) {
    emit(StateChanged { listing_id, old_state, new_state });
}

// === Admin Events ===

/// Emitted when protocol is paused.
public struct Paused has copy, drop {
    paused_by: address,
}

public fun emit_paused(paused_by: address) {
    emit(Paused { paused_by });
}

/// Emitted when protocol is unpaused.
public struct Unpaused has copy, drop {
    unpaused_by: address,
}

public fun emit_unpaused(unpaused_by: address) {
    emit(Unpaused { unpaused_by });
}

// === Listing Pause Events ===

/// Emitted when a listing's pause state changes.
public struct ListingPauseChanged has copy, drop {
    listing_id: ID,
    paused: bool,
}

public fun emit_pause_changed(listing_id: ID, paused: bool) {
    emit(ListingPauseChanged { listing_id, paused });
}

// === Fee Events ===

/// Emitted when raise fee is collected from a listing.
/// Happens before first tranche release.
public struct RaiseFeeCollected has copy, drop {
    listing_id: ID,
    fee_amount: u64,
    treasury: address,
    total_raised: u64,
    fee_bps: u64,
}

public fun emit_raise_fee_collected(
    listing_id: ID,
    fee_amount: u64,
    treasury: address,
    total_raised: u64,
    fee_bps: u64,
) {
    emit(RaiseFeeCollected { listing_id, fee_amount, treasury, total_raised, fee_bps });
}

/// Emitted when staking rewards are split between backers and treasury.
public struct StakingRewardSplit has copy, drop {
    listing_id: ID,
    total_rewards: u64,
    backer_amount: u64,
    treasury_amount: u64,
    backer_bps: u64,
}

public fun emit_staking_reward_split(
    listing_id: ID,
    total_rewards: u64,
    backer_amount: u64,
    treasury_amount: u64,
    backer_bps: u64,
) {
    emit(StakingRewardSplit { listing_id, total_rewards, backer_amount, treasury_amount, backer_bps });
}
