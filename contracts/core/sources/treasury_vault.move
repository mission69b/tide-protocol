/// Protocol Treasury Vault for collecting and managing fees.
/// 
/// Holds all protocol-level fees:
/// - Raise fees (1% of capital raised)
/// - Staking reward treasury split (20% of staking rewards)
/// 
/// Features:
/// - Shared object for permissionless deposits
/// - Admin-gated withdrawals
/// - Full audit trail via events
module tide_core::treasury_vault;

use sui::sui::SUI;
use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};

use tide_core::events;

// === Structs ===

/// Treasury vault holding protocol fees.
public struct TreasuryVault has key {
    id: UID,
    /// Accumulated SUI balance.
    balance: Balance<SUI>,
    /// Total fees deposited (cumulative).
    total_deposited: u64,
    /// Total fees withdrawn (cumulative).
    total_withdrawn: u64,
}

// === Constructor ===

/// Create a new TreasuryVault (called during protocol init).
public(package) fun new(ctx: &mut TxContext): TreasuryVault {
    TreasuryVault {
        id: object::new(ctx),
        balance: balance::zero(),
        total_deposited: 0,
        total_withdrawn: 0,
    }
}

// === Deposit Functions ===

/// Deposit SUI into the treasury.
/// Callable by anyone (used by listing module for fee routing).
public fun deposit(
    self: &mut TreasuryVault,
    coin: Coin<SUI>,
) {
    let amount = coin.value();
    self.balance.join(coin.into_balance());
    self.total_deposited = self.total_deposited + amount;
    
    events::emit_treasury_deposit(self.id.to_inner(), amount, self.balance.value());
}

/// Deposit SUI with metadata about the source.
/// payment_type: 0 = raise fee, 1 = staking split
public fun deposit_with_type(
    self: &mut TreasuryVault,
    coin: Coin<SUI>,
    listing_id: ID,
    payment_type: u8,
) {
    let amount = coin.value();
    let vault_id = self.id.to_inner();
    self.balance.join(coin.into_balance());
    self.total_deposited = self.total_deposited + amount;
    
    events::emit_treasury_vault_deposit(listing_id, payment_type, amount, vault_id);
}

// === Withdraw Functions (Admin-Gated via Tide) ===

/// Withdraw SUI from treasury to a recipient.
/// This is package-private; the admin gate is in tide.move.
public(package) fun withdraw(
    self: &mut TreasuryVault,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    assert!(self.balance.value() >= amount, 0); // insufficient balance
    
    let coin = coin::from_balance(self.balance.split(amount), ctx);
    self.total_withdrawn = self.total_withdrawn + amount;
    
    events::emit_treasury_withdrawal(self.id.to_inner(), amount, recipient, self.balance.value());
    
    transfer::public_transfer(coin, recipient);
}

/// Withdraw all SUI from treasury.
public(package) fun withdraw_all(
    self: &mut TreasuryVault,
    recipient: address,
    ctx: &mut TxContext,
) {
    let amount = self.balance.value();
    if (amount == 0) return;
    
    let coin = coin::from_balance(self.balance.withdraw_all(), ctx);
    self.total_withdrawn = self.total_withdrawn + amount;
    
    events::emit_treasury_withdrawal(self.id.to_inner(), amount, recipient, 0);
    
    transfer::public_transfer(coin, recipient);
}

// === View Functions ===

/// Get vault ID.
public fun id(self: &TreasuryVault): ID {
    self.id.to_inner()
}

/// Get current balance.
public fun balance(self: &TreasuryVault): u64 {
    self.balance.value()
}

/// Get total deposited (cumulative).
public fun total_deposited(self: &TreasuryVault): u64 {
    self.total_deposited
}

/// Get total withdrawn (cumulative).
public fun total_withdrawn(self: &TreasuryVault): u64 {
    self.total_withdrawn
}

// === Share Function ===

/// Share the treasury vault object.
public fun share(vault: TreasuryVault) {
    transfer::share_object(vault);
}

// === Test Helpers ===

#[test_only]
public fun new_for_testing(ctx: &mut TxContext): TreasuryVault {
    new(ctx)
}

#[test_only]
public fun destroy_for_testing(vault: TreasuryVault) {
    let TreasuryVault { id, balance, total_deposited: _, total_withdrawn: _ } = vault;
    id.delete();
    balance.destroy_for_testing();
}

#[test_only]
public fun deposit_for_testing(
    self: &mut TreasuryVault,
    amount: u64,
    ctx: &mut TxContext,
) {
    let coin = coin::mint_for_testing<SUI>(amount, ctx);
    self.deposit(coin);
}
