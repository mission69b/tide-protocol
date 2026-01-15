/// Holds and distributes rewards to backers.
/// 
/// RewardVault maintains a cumulative reward-per-share index that
/// enables O(1) reward claims regardless of reward history.
/// 
/// Reward sources (v1):
/// 1. Protocol revenue routed from issuer
/// 2. Native Sui staking rewards
module tide_core::reward_vault;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;

use tide_core::errors;
use tide_core::events;
use tide_core::math;

// === Structs ===

/// Capability to route rewards into a vault.
public struct RouteCapability has key, store {
    id: UID,
    listing_id: ID,
}

/// Vault holding rewards for distribution.
public struct RewardVault has key {
    id: UID,
    /// ID of the listing this vault belongs to.
    listing_id: ID,
    /// SUI balance available for claims.
    balance: Balance<SUI>,
    /// Cumulative reward-per-share index (monotonically increasing).
    global_index: u128,
    /// Total shares in the system (mirrored from CapitalVault).
    total_shares: u128,
    /// Lifetime distributed amount (claims).
    total_distributed: u64,
    /// Lifetime deposited amount (revenue routed in).
    total_deposited: u64,
}

// === Package Functions ===

/// Create a new RewardVault for a listing.
public(package) fun new(
    listing_id: ID,
    ctx: &mut TxContext,
): RewardVault {
    RewardVault {
        id: object::new(ctx),
        listing_id,
        balance: balance::zero(),
        global_index: 0,
        total_shares: 0,
        total_distributed: 0,
        total_deposited: 0,
    }
}

/// Create a RouteCapability for this vault.
public(package) fun create_route_capability(
    listing_id: ID,
    ctx: &mut TxContext,
): RouteCapability {
    RouteCapability {
        id: object::new(ctx),
        listing_id,
    }
}

/// Update total shares (called when deposits are made).
public(package) fun set_total_shares(
    self: &mut RewardVault,
    total_shares: u128,
) {
    self.total_shares = total_shares;
}

/// Withdraw rewards for a claim.
public(package) fun withdraw(
    self: &mut RewardVault,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(self.balance.value() >= amount, errors::insufficient_balance());
    self.total_distributed = self.total_distributed + amount;
    coin::from_balance(self.balance.split(amount), ctx)
}

// === Public Functions ===

/// Deposit rewards into the vault. Requires RouteCapability.
public fun deposit_rewards(
    self: &mut RewardVault,
    cap: &RouteCapability,
    coin: Coin<SUI>,
    ctx: &TxContext,
) {
    assert!(cap.listing_id == self.listing_id, errors::not_authorized());
    
    let amount = coin.value();
    assert!(amount > 0, errors::invalid_amount());
    
    // Update index before adding balance
    let old_index = self.global_index;
    if (self.total_shares > 0) {
        self.global_index = math::calculate_new_index(
            self.global_index,
            amount,
            self.total_shares,
        );
    };
    
    // Add to balance and track cumulative deposits
    self.balance.join(coin.into_balance());
    self.total_deposited = self.total_deposited + amount;
    
    // Emit events
    events::emit_route_in(
        self.listing_id, 
        ctx.sender(), 
        amount, 
        self.total_deposited,
        self.global_index,
    );
    if (self.global_index != old_index) {
        events::emit_reward_index_updated(self.listing_id, old_index, self.global_index);
    };
}

// === View Functions ===

/// Get vault ID.
public fun id(self: &RewardVault): ID {
    self.id.to_inner()
}

/// Get listing ID.
public fun listing_id(self: &RewardVault): ID {
    self.listing_id
}

/// Get current balance.
public fun balance(self: &RewardVault): u64 {
    self.balance.value()
}

/// Get global reward index.
public fun global_index(self: &RewardVault): u128 {
    self.global_index
}

/// Get total shares.
public fun total_shares(self: &RewardVault): u128 {
    self.total_shares
}

/// Get total distributed (claims).
public fun total_distributed(self: &RewardVault): u64 {
    self.total_distributed
}

/// Get total deposited (revenue routed in).
public fun total_deposited(self: &RewardVault): u64 {
    self.total_deposited
}

/// Calculate claimable amount for given shares and claim index.
public fun calculate_claimable(
    self: &RewardVault,
    shares: u128,
    claim_index: u128,
): u64 {
    math::calculate_claimable(shares, self.global_index, claim_index)
}

/// Get RouteCapability listing ID.
public fun route_cap_listing_id(cap: &RouteCapability): ID {
    cap.listing_id
}

// === Share/Transfer Functions ===

/// Share the reward vault object.
public fun share(vault: RewardVault) {
    transfer::share_object(vault);
}

/// Transfer route capability to recipient.
public fun transfer_route_cap(cap: RouteCapability, recipient: address) {
    transfer::public_transfer(cap, recipient);
}

// === Test Helpers ===

#[test_only]
public fun new_for_testing(
    listing_id: ID,
    ctx: &mut TxContext,
): RewardVault {
    new(listing_id, ctx)
}

#[test_only]
public fun create_route_cap_for_testing(
    listing_id: ID,
    ctx: &mut TxContext,
): RouteCapability {
    create_route_capability(listing_id, ctx)
}

#[test_only]
public fun destroy_for_testing(vault: RewardVault) {
    let RewardVault { id, balance, .. } = vault;
    id.delete();
    balance.destroy_zero();
}

#[test_only]
public fun destroy_route_cap_for_testing(cap: RouteCapability) {
    let RouteCapability { id, .. } = cap;
    id.delete();
}

#[test_only]
public fun set_total_shares_for_testing(self: &mut RewardVault, shares: u128) {
    set_total_shares(self, shares)
}

#[test_only]
public fun destroy_with_balance_for_testing(vault: RewardVault) {
    let RewardVault { id, balance, .. } = vault;
    id.delete();
    sui::test_utils::destroy(balance);
}

// === Unit Tests ===

#[test_only]
const ENOT_AUTHORIZED: u64 = 4;

#[test]
fun test_new_vault() {
    let mut ctx = tx_context::dummy();
    let listing_id = object::id_from_address(@0x1);
    
    let vault = new_for_testing(listing_id, &mut ctx);
    
    assert!(vault.listing_id() == listing_id);
    assert!(vault.global_index() == 0);
    assert!(vault.total_shares() == 0);
    assert!(vault.balance() == 0);
    assert!(vault.total_distributed() == 0);
    assert!(vault.total_deposited() == 0);
    
    destroy_for_testing(vault);
}

#[test]
fun test_deposit_rewards_updates_index() {
    use sui::coin;
    use sui::sui::SUI;
    
    let mut ctx = tx_context::dummy();
    let listing_id = object::id_from_address(@0x1);
    
    let mut vault = new_for_testing(listing_id, &mut ctx);
    let cap = create_route_cap_for_testing(listing_id, &mut ctx);
    
    // Set shares first
    vault.set_total_shares_for_testing(1_000_000_000_000); // 1e12
    
    // Deposit rewards
    let reward_coin = coin::mint_for_testing<SUI>(100_000_000, &mut ctx); // 0.1 SUI
    vault.deposit_rewards(&cap, reward_coin, &ctx);
    
    // Index should be updated
    assert!(vault.global_index() > 0);
    assert!(vault.balance() == 100_000_000);
    assert!(vault.total_deposited() == 100_000_000);
    
    // Cleanup
    destroy_route_cap_for_testing(cap);
    destroy_with_balance_for_testing(vault);
}

#[test]
fun test_index_monotonically_increases() {
    use sui::coin;
    use sui::sui::SUI;
    
    let mut ctx = tx_context::dummy();
    let listing_id = object::id_from_address(@0x1);
    
    let mut vault = new_for_testing(listing_id, &mut ctx);
    let cap = create_route_cap_for_testing(listing_id, &mut ctx);
    
    vault.set_total_shares_for_testing(1_000_000_000_000);
    
    // First deposit
    let coin1 = coin::mint_for_testing<SUI>(100_000_000, &mut ctx);
    vault.deposit_rewards(&cap, coin1, &ctx);
    let index_after_first = vault.global_index();
    
    // Second deposit
    let coin2 = coin::mint_for_testing<SUI>(200_000_000, &mut ctx);
    vault.deposit_rewards(&cap, coin2, &ctx);
    let index_after_second = vault.global_index();
    
    // Index should be monotonically increasing
    assert!(index_after_second > index_after_first);
    
    // Cleanup
    destroy_route_cap_for_testing(cap);
    destroy_with_balance_for_testing(vault);
}

#[test]
fun test_calculate_claimable() {
    use sui::coin;
    use sui::sui::SUI;
    
    let mut ctx = tx_context::dummy();
    let listing_id = object::id_from_address(@0x1);
    
    let mut vault = new_for_testing(listing_id, &mut ctx);
    let cap = create_route_cap_for_testing(listing_id, &mut ctx);
    
    // Setup: 1000 shares total, backer has 100 shares (10%)
    let total_shares: u128 = 1_000_000_000_000_000; // 1e15
    let backer_shares: u128 = 100_000_000_000_000;  // 1e14 (10%)
    
    vault.set_total_shares_for_testing(total_shares);
    
    // Deposit 1000 SUI worth of rewards
    let rewards = coin::mint_for_testing<SUI>(1_000_000_000_000, &mut ctx); // 1000 SUI
    vault.deposit_rewards(&cap, rewards, &ctx);
    
    // Backer claiming from index 0 should get ~10% of rewards (100 SUI)
    let claimable = vault.calculate_claimable(backer_shares, 0);
    
    // Should be approximately 100 SUI (100_000_000_000 MIST)
    // Allow for rounding
    assert!(claimable >= 99_000_000_000 && claimable <= 101_000_000_000);
    
    // Cleanup
    destroy_route_cap_for_testing(cap);
    destroy_with_balance_for_testing(vault);
}

#[test]
#[expected_failure(abort_code = ENOT_AUTHORIZED)]
fun test_deposit_wrong_cap() {
    use sui::coin;
    use sui::sui::SUI;
    
    let mut ctx = tx_context::dummy();
    let listing_id = object::id_from_address(@0x1);
    let other_listing_id = object::id_from_address(@0x2);
    
    let mut vault = new_for_testing(listing_id, &mut ctx);
    let wrong_cap = create_route_cap_for_testing(other_listing_id, &mut ctx);
    
    // Try deposit with wrong cap - should fail
    let coin = coin::mint_for_testing<SUI>(100, &mut ctx);
    vault.deposit_rewards(&wrong_cap, coin, &ctx);
    
    // Cleanup (won't reach)
    destroy_route_cap_for_testing(wrong_cap);
    destroy_for_testing(vault);
}
