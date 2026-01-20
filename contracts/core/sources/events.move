/// Standardized events for Tide Core.
/// 
/// All events are designed to be:
/// - Sufficient for off-chain indexing and dashboards
/// - Reproducible by independent indexers
/// - Complete for audit trails
/// 
/// Normative: Any dashboard or reporting surface representing Tide data
/// MUST be reproducible by an independent indexer using only on-chain events.
module tide_core::events;

use sui::event::emit;

// === Listing Lifecycle Events ===

/// Emitted when a new listing is created.
public struct ListingCreated has copy, drop {
    listing_id: ID,
    listing_number: u64,
    /// Address that manages the listing (receives RouteCapability, ListingCap)
    issuer: address,
    /// Address that receives capital tranches (the artist/creator)
    release_recipient: address,
    config_hash: vector<u8>,
    min_deposit: u64,
    raise_fee_bps: u64,
    staking_backer_bps: u64,
}

public fun emit_listing_created(
    listing_id: ID,
    listing_number: u64,
    issuer: address,
    release_recipient: address,
    config_hash: vector<u8>,
    min_deposit: u64,
    raise_fee_bps: u64,
    staking_backer_bps: u64,
) {
    emit(ListingCreated { 
        listing_id, 
        listing_number, 
        issuer, 
        release_recipient,
        config_hash, 
        min_deposit,
        raise_fee_bps,
        staking_backer_bps,
    });
}

/// Emitted when a listing is activated (starts accepting deposits).
public struct ListingActivated has copy, drop {
    listing_id: ID,
    activation_time: u64,
}

public fun emit_listing_activated(listing_id: ID, activation_time: u64) {
    emit(ListingActivated { listing_id, activation_time });
}

/// Emitted when a listing is finalized and release schedule is locked.
public struct ListingFinalized has copy, drop {
    listing_id: ID,
    finalization_time: u64,
    total_raised: u64,
    total_backers: u64,
    total_shares: u128,
    num_tranches: u64,
}

public fun emit_listing_finalized(
    listing_id: ID,
    finalization_time: u64,
    total_raised: u64,
    total_backers: u64,
    total_shares: u128,
    num_tranches: u64,
) {
    emit(ListingFinalized { 
        listing_id, 
        finalization_time, 
        total_raised, 
        total_backers,
        total_shares,
        num_tranches,
    });
}

/// Emitted when a listing is completed (all tranches released).
public struct ListingCompleted has copy, drop {
    listing_id: ID,
    total_released: u64,
    total_distributed_rewards: u64,
}

public fun emit_listing_completed(
    listing_id: ID,
    total_released: u64,
    total_distributed_rewards: u64,
) {
    emit(ListingCompleted { listing_id, total_released, total_distributed_rewards });
}

// === Deposit Events ===

/// Emitted when a backer deposits SUI into a listing.
public struct Deposited has copy, drop {
    listing_id: ID,
    backer: address,
    amount: u64,
    shares: u128,
    pass_id: ID,
    /// Running total of deposits for the listing
    total_raised: u64,
    /// Total number of SupporterPasses minted
    total_passes: u64,
    /// Epoch when deposit occurred
    epoch: u64,
}

public fun emit_deposited(
    listing_id: ID,
    backer: address,
    amount: u64,
    shares: u128,
    pass_id: ID,
    total_raised: u64,
    total_passes: u64,
    epoch: u64,
) {
    emit(Deposited { listing_id, backer, amount, shares, pass_id, total_raised, total_passes, epoch });
}

// === Claim Events ===

/// Emitted when a backer claims rewards.
public struct Claimed has copy, drop {
    listing_id: ID,
    pass_id: ID,
    backer: address,
    amount: u64,
    /// Backer's shares (for verification)
    shares: u128,
    /// The claim index before this claim
    old_claim_index: u128,
    /// The claim index after this claim
    new_claim_index: u128,
    /// Epoch when claim occurred
    epoch: u64,
}

public fun emit_claimed(
    listing_id: ID,
    pass_id: ID,
    backer: address,
    amount: u64,
    shares: u128,
    old_claim_index: u128,
    new_claim_index: u128,
    epoch: u64,
) {
    emit(Claimed { listing_id, pass_id, backer, amount, shares, old_claim_index, new_claim_index, epoch });
}

/// Emitted as a summary when multiple passes are claimed in one transaction.
/// Individual Claimed events are still emitted for each pass.
public struct BatchClaimed has copy, drop {
    /// Listing the passes belong to
    listing_id: ID,
    /// Address that claimed (current owner)
    backer: address,
    /// Number of passes that had rewards claimed
    passes_claimed: u64,
    /// Total amount claimed across all passes
    total_amount: u64,
    /// Epoch when batch claim occurred
    epoch: u64,
}

public fun emit_batch_claimed(
    listing_id: ID,
    backer: address,
    passes_claimed: u64,
    total_amount: u64,
    epoch: u64,
) {
    emit(BatchClaimed { listing_id, backer, passes_claimed, total_amount, epoch });
}

// === Release Events ===

/// Emitted when a tranche is released to the issuer.
public struct TrancheReleased has copy, drop {
    listing_id: ID,
    tranche_idx: u64,
    amount: u64,
    recipient: address,
    /// Total tranches in the schedule
    total_tranches: u64,
    /// Remaining tranches after this release
    remaining_tranches: u64,
    /// Cumulative amount released to issuer
    cumulative_released: u64,
    /// Timestamp when released
    release_time: u64,
}

public fun emit_tranche_released(
    listing_id: ID,
    tranche_idx: u64,
    amount: u64,
    recipient: address,
    total_tranches: u64,
    remaining_tranches: u64,
    cumulative_released: u64,
    release_time: u64,
) {
    emit(TrancheReleased { 
        listing_id, 
        tranche_idx, 
        amount, 
        recipient, 
        total_tranches,
        remaining_tranches,
        cumulative_released,
        release_time,
    });
}

// === Revenue Events ===

/// Emitted when revenue is routed into the RewardVault.
public struct RouteIn has copy, drop {
    listing_id: ID,
    source: address,
    amount: u64,
    /// Cumulative rewards distributed through this vault
    cumulative_distributed: u64,
    /// New global reward index after this deposit
    new_global_index: u128,
}

public fun emit_route_in(
    listing_id: ID,
    source: address,
    amount: u64,
    cumulative_distributed: u64,
    new_global_index: u128,
) {
    emit(RouteIn { listing_id, source, amount, cumulative_distributed, new_global_index });
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
    /// Total staked amount after this operation
    total_staked: u64,
}

public fun emit_staked(
    listing_id: ID,
    amount: u64,
    validator: address,
    total_staked: u64,
) {
    emit(Staked { listing_id, amount, validator, total_staked });
}

/// Emitted when capital is unstaked.
public struct Unstaked has copy, drop {
    listing_id: ID,
    amount: u64,
    /// Total staked amount after this operation
    total_staked: u64,
}

public fun emit_unstaked(listing_id: ID, amount: u64, total_staked: u64) {
    emit(Unstaked { listing_id, amount, total_staked });
}

/// Emitted when staking rewards are harvested.
public struct StakingRewardsHarvested has copy, drop {
    listing_id: ID,
    gross_rewards: u64,
    backer_rewards: u64,
    treasury_rewards: u64,
    new_reward_index: u128,
}

public fun emit_staking_rewards_harvested(
    listing_id: ID,
    gross_rewards: u64,
    backer_rewards: u64,
    treasury_rewards: u64,
    new_reward_index: u128,
) {
    emit(StakingRewardsHarvested { 
        listing_id, 
        gross_rewards, 
        backer_rewards, 
        treasury_rewards, 
        new_reward_index,
    });
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

// === Schedule Events ===

/// Emitted when the deterministic release schedule is finalized.
public struct ScheduleFinalized has copy, drop {
    listing_id: ID,
    finalization_time: u64,
    total_principal: u64,
    initial_tranche_amount: u64,
    monthly_tranche_amount: u64,
    num_monthly_tranches: u64,
    first_monthly_release_time: u64,
    final_release_time: u64,
}

public fun emit_schedule_finalized(
    listing_id: ID,
    finalization_time: u64,
    total_principal: u64,
    initial_tranche_amount: u64,
    monthly_tranche_amount: u64,
    num_monthly_tranches: u64,
    first_monthly_release_time: u64,
    final_release_time: u64,
) {
    emit(ScheduleFinalized { 
        listing_id, 
        finalization_time, 
        total_principal,
        initial_tranche_amount,
        monthly_tranche_amount,
        num_monthly_tranches,
        first_monthly_release_time,
        final_release_time,
    });
}

// === Treasury Events ===

/// Emitted when treasury address is updated.
public struct TreasuryUpdated has copy, drop {
    old_treasury: address,
    new_treasury: address,
}

public fun emit_treasury_updated(old_treasury: address, new_treasury: address) {
    emit(TreasuryUpdated { old_treasury, new_treasury });
}

/// Emitted when fees are sent to treasury.
public struct TreasuryPayment has copy, drop {
    listing_id: ID,
    payment_type: u8, // 0 = raise fee, 1 = staking split
    amount: u64,
    treasury: address,
}

public fun emit_treasury_payment(
    listing_id: ID,
    payment_type: u8,
    amount: u64,
    treasury: address,
) {
    emit(TreasuryPayment { listing_id, payment_type, amount, treasury });
}

// === Staking Configuration Events ===

/// Emitted when staking is enabled or disabled for a listing.
public struct StakingEnabledChanged has copy, drop {
    listing_id: ID,
    enabled: bool,
}

public fun emit_staking_enabled_changed(listing_id: ID, enabled: bool) {
    emit(StakingEnabledChanged { listing_id, enabled });
}

/// Emitted when the validator address is updated for a listing.
public struct ValidatorUpdated has copy, drop {
    listing_id: ID,
    old_validator: address,
    new_validator: address,
}

public fun emit_validator_updated(listing_id: ID, old_validator: address, new_validator: address) {
    emit(ValidatorUpdated { listing_id, old_validator, new_validator });
}

// === Treasury Vault Events ===

/// Emitted when SUI is deposited into the treasury vault.
public struct TreasuryDeposit has copy, drop {
    vault_id: ID,
    amount: u64,
    new_balance: u64,
}

public fun emit_treasury_deposit(vault_id: ID, amount: u64, new_balance: u64) {
    emit(TreasuryDeposit { vault_id, amount, new_balance });
}

/// Emitted when fees are deposited to treasury vault (with listing context).
public struct TreasuryVaultDeposit has copy, drop {
    listing_id: ID,
    payment_type: u8, // 0 = raise fee, 1 = staking split
    amount: u64,
    vault_id: ID,
}

public fun emit_treasury_vault_deposit(listing_id: ID, payment_type: u8, amount: u64, vault_id: ID) {
    emit(TreasuryVaultDeposit { listing_id, payment_type, amount, vault_id });
}

/// Emitted when SUI is withdrawn from the treasury vault.
public struct TreasuryWithdrawal has copy, drop {
    vault_id: ID,
    amount: u64,
    recipient: address,
    remaining_balance: u64,
}

public fun emit_treasury_withdrawal(vault_id: ID, amount: u64, recipient: address, remaining_balance: u64) {
    emit(TreasuryWithdrawal { vault_id, amount, recipient, remaining_balance });
}

// === Cancellation & Refund Events ===

/// Emitted when a listing is cancelled.
public struct ListingCancelled has copy, drop {
    /// ID of the cancelled listing
    listing_id: ID,
    /// Address that triggered cancellation
    cancelled_by: address,
    /// Previous state before cancellation
    previous_state: u8,
    /// Total capital to be refunded
    total_refundable: u64,
    /// Number of passes eligible for refund
    total_passes: u64,
    /// Epoch when cancelled
    epoch: u64,
}

public fun emit_listing_cancelled(
    listing_id: ID,
    cancelled_by: address,
    previous_state: u8,
    total_refundable: u64,
    total_passes: u64,
    epoch: u64,
) {
    emit(ListingCancelled { listing_id, cancelled_by, previous_state, total_refundable, total_passes, epoch });
}

/// Emitted when a backer claims a refund.
public struct RefundClaimed has copy, drop {
    /// ID of the listing
    listing_id: ID,
    /// ID of the pass that was refunded
    pass_id: ID,
    /// Backer who received the refund
    backer: address,
    /// Refund amount in MIST
    amount: u64,
    /// Shares that were refunded
    shares: u128,
    /// Remaining refundable balance in vault
    remaining_balance: u64,
    /// Epoch when refund occurred
    epoch: u64,
}

public fun emit_refund_claimed(
    listing_id: ID,
    pass_id: ID,
    backer: address,
    amount: u64,
    shares: u128,
    remaining_balance: u64,
    epoch: u64,
) {
    emit(RefundClaimed { listing_id, pass_id, backer, amount, shares, remaining_balance, epoch });
}
