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
    self.treasury = new_treasury;
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
