/// Global protocol configuration for Tide Core.
/// 
/// Tide is a singleton shared object that holds:
/// - Treasury vault ID (for protocol fees)
/// - Global pause flag
/// - Protocol version
/// 
/// Tide holds no capital directly - fees flow to TreasuryVault.
module tide_core::tide;

use sui::package;

use tide_core::constants;
use tide_core::display;
use tide_core::events;
use tide_core::treasury_vault::{Self, TreasuryVault};

// === Structs ===

/// One-time witness for module initialization.
public struct TIDE has drop {}

/// Admin capability for protocol-level actions.
public struct AdminCap has key, store {
    id: UID,
}

/// Global protocol configuration (shared singleton).
public struct Tide has key {
    id: UID,
    /// Admin wallet address (receives withdrawals from treasury).
    admin_wallet: address,
    /// Global pause flag.
    paused: bool,
    /// Protocol version for upgrade compatibility.
    version: u64,
}

// === Init ===

fun init(otw: TIDE, ctx: &mut TxContext) {
    // Claim publisher for Display creation
    let publisher = package::claim(otw, ctx);
    
    // Create admin capability
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };
    
    // Create global config
    let tide = Tide {
        id: object::new(ctx),
        admin_wallet: ctx.sender(),
        paused: false,
        version: constants::version!(),
    };
    
    // Create treasury vault
    let treasury_vault = treasury_vault::new(ctx);
    
    // Create SupporterPass display using publisher
    let supporter_pass_display = display::setup_supporter_pass_display(&publisher, ctx);
    
    // Transfer admin cap to deployer
    transfer::transfer(admin_cap, ctx.sender());
    
    // Transfer publisher to deployer (for future display updates)
    transfer::public_transfer(publisher, ctx.sender());
    
    // Transfer display to deployer (for future updates)
    transfer::public_transfer(supporter_pass_display, ctx.sender());
    
    // Share tide as singleton
    transfer::share_object(tide);
    
    // Share treasury vault
    treasury_vault::share(treasury_vault);
}

// === Admin Functions ===

/// Pause the protocol. Requires AdminCap.
public fun pause(
    self: &mut Tide,
    _cap: &AdminCap,
    ctx: &TxContext,
) {
    self.paused = true;
    events::emit_paused(ctx.sender());
}

/// Unpause the protocol. Requires AdminCap.
public fun unpause(
    self: &mut Tide,
    _cap: &AdminCap,
    ctx: &TxContext,
) {
    self.paused = false;
    events::emit_unpaused(ctx.sender());
}

/// Update admin wallet address. Requires AdminCap.
public fun set_admin_wallet(
    self: &mut Tide,
    _cap: &AdminCap,
    new_wallet: address,
    _ctx: &mut TxContext,
) {
    let old_wallet = self.admin_wallet;
    self.admin_wallet = new_wallet;
    events::emit_treasury_updated(old_wallet, new_wallet);
}

/// Withdraw SUI from treasury vault to admin wallet. Requires AdminCap.
public fun withdraw_from_treasury(
    self: &Tide,
    _cap: &AdminCap,
    treasury_vault: &mut TreasuryVault,
    amount: u64,
    ctx: &mut TxContext,
) {
    treasury_vault::withdraw(treasury_vault, amount, self.admin_wallet, ctx);
}

/// Withdraw all SUI from treasury vault to admin wallet. Requires AdminCap.
public fun withdraw_all_from_treasury(
    self: &Tide,
    _cap: &AdminCap,
    treasury_vault: &mut TreasuryVault,
    ctx: &mut TxContext,
) {
    treasury_vault::withdraw_all(treasury_vault, self.admin_wallet, ctx);
}

/// Withdraw SUI from treasury vault to a custom recipient. Requires AdminCap.
public fun withdraw_treasury_to(
    _self: &Tide,
    _cap: &AdminCap,
    treasury_vault: &mut TreasuryVault,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    treasury_vault::withdraw(treasury_vault, amount, recipient, ctx);
}

/// Transfer AdminCap to a new holder (admin rotation).
/// This is a one-way transfer - the sender loses admin rights.
public fun transfer_admin_cap(
    cap: AdminCap,
    new_admin: address,
    ctx: &TxContext,
) {
    sui::event::emit(AdminCapTransferred {
        from: ctx.sender(),
        to: new_admin,
    });
    transfer::public_transfer(cap, new_admin);
}

/// Event emitted when AdminCap is transferred.
public struct AdminCapTransferred has copy, drop {
    from: address,
    to: address,
}

// === View Functions ===

/// Check if protocol is paused.
public fun is_paused(self: &Tide): bool {
    self.paused
}

/// Get admin wallet address.
public fun admin_wallet(self: &Tide): address {
    self.admin_wallet
}

/// Get admin wallet address (legacy alias).
public fun treasury(self: &Tide): address {
    self.admin_wallet
}

/// Get protocol version.
public fun version(self: &Tide): u64 {
    self.version
}

/// Assert protocol is not paused.
public fun assert_not_paused(self: &Tide) {
    assert!(!self.paused, tide_core::errors::paused());
}

// === Test Helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(TIDE {}, ctx);
}

#[test_only]
public fun new_admin_cap_for_testing(ctx: &mut TxContext): AdminCap {
    AdminCap { id: object::new(ctx) }
}

#[test_only]
public fun new_tide_for_testing(ctx: &mut TxContext): Tide {
    Tide {
        id: object::new(ctx),
        admin_wallet: ctx.sender(),
        paused: false,
        version: constants::version!(),
    }
}

#[test_only]
public fun destroy_admin_cap_for_testing(cap: AdminCap) {
    let AdminCap { id } = cap;
    object::delete(id);
}

#[test_only]
public fun destroy_tide_for_testing(tide: Tide) {
    let Tide { id, admin_wallet: _, paused: _, version: _ } = tide;
    object::delete(id);
}

// === Unit Tests ===

#[test_only]
const EPAUSED: u64 = 1;

#[test]
fun test_pause_unpause() {
    let mut ctx = tx_context::dummy();
    let mut tide = new_tide_for_testing(&mut ctx);
    let cap = new_admin_cap_for_testing(&mut ctx);
    
    // Initially not paused
    assert!(!tide.is_paused());
    
    // Pause
    tide.pause(&cap, &ctx);
    assert!(tide.is_paused());
    
    // Unpause
    tide.unpause(&cap, &ctx);
    assert!(!tide.is_paused());
    
    // Cleanup
    destroy_admin_cap_for_testing(cap);
    destroy_tide_for_testing(tide);
}

#[test]
fun test_admin_wallet_update() {
    let mut ctx = tx_context::dummy();
    let mut tide = new_tide_for_testing(&mut ctx);
    let cap = new_admin_cap_for_testing(&mut ctx);
    
    let new_wallet = @0xCAFE;
    tide.set_admin_wallet(&cap, new_wallet, &mut ctx);
    
    assert!(tide.admin_wallet() == new_wallet);
    // Also test legacy alias
    assert!(tide.treasury() == new_wallet);
    
    // Cleanup
    destroy_admin_cap_for_testing(cap);
    destroy_tide_for_testing(tide);
}

#[test]
fun test_version() {
    let mut ctx = tx_context::dummy();
    let tide = new_tide_for_testing(&mut ctx);
    
    assert!(tide.version() == constants::version!());
    
    destroy_tide_for_testing(tide);
}

#[test]
fun test_assert_not_paused_when_not_paused() {
    let mut ctx = tx_context::dummy();
    let tide = new_tide_for_testing(&mut ctx);
    
    // Should not abort
    tide.assert_not_paused();
    
    destroy_tide_for_testing(tide);
}

#[test]
#[expected_failure(abort_code = EPAUSED)]
fun test_assert_not_paused_aborts_when_paused() {
    let mut ctx = tx_context::dummy();
    let mut tide = new_tide_for_testing(&mut ctx);
    let cap = new_admin_cap_for_testing(&mut ctx);
    
    tide.pause(&cap, &ctx);
    
    // Should abort
    tide.assert_not_paused();
    
    // Cleanup (won't reach here)
    destroy_admin_cap_for_testing(cap);
    destroy_tide_for_testing(tide);
}
