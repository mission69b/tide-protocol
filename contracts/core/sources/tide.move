/// Global protocol configuration for Tide Core.
/// 
/// Tide is a singleton shared object that holds:
/// - Treasury address (for future protocol fees)
/// - Global pause flag
/// - Protocol version
/// 
/// Tide holds no capital and cannot redirect funds.
module tide_core::tide;

use tide_core::constants;
use tide_core::events;

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
    /// Treasury address for protocol fees (unused in v1).
    treasury: address,
    /// Global pause flag.
    paused: bool,
    /// Protocol version for upgrade compatibility.
    version: u64,
}

// === Init ===

fun init(otw: TIDE, ctx: &mut TxContext) {
    let _ = otw;
    
    // Create admin capability
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };
    
    // Create global config
    let tide = Tide {
        id: object::new(ctx),
        treasury: ctx.sender(),
        paused: false,
        version: constants::version!(),
    };
    
    // Transfer admin cap to deployer
    transfer::transfer(admin_cap, ctx.sender());
    
    // Share tide as singleton
    transfer::share_object(tide);
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

/// Update treasury address. Requires AdminCap.
public fun set_treasury(
    self: &mut Tide,
    _cap: &AdminCap,
    new_treasury: address,
    _ctx: &mut TxContext,
) {
    let old_treasury = self.treasury;
    self.treasury = new_treasury;
    events::emit_treasury_updated(old_treasury, new_treasury);
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

/// Get treasury address.
public fun treasury(self: &Tide): address {
    self.treasury
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
        treasury: ctx.sender(),
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
    let Tide { id, treasury: _, paused: _, version: _ } = tide;
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
fun test_treasury_update() {
    let mut ctx = tx_context::dummy();
    let mut tide = new_tide_for_testing(&mut ctx);
    let cap = new_admin_cap_for_testing(&mut ctx);
    
    let new_treasury = @0xCAFE;
    tide.set_treasury(&cap, new_treasury, &mut ctx);
    
    assert!(tide.treasury() == new_treasury);
    
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
