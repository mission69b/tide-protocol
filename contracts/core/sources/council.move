/// Council capability and gating for Tide Core.
/// 
/// Provides minimal council gating for registry-first architecture.
/// Council is a 3-5 key multisig (capability-based).
/// 
/// Council MAY:
/// - Create/register new listings
/// - Activate or finalize listings
/// - Pause or resume listings
/// 
/// Council MUST NOT:
/// - Seize capital
/// - Redirect rewards
/// - Change live listing economics after activation
module tide_core::council;

// === Structs ===

/// One-time witness for module initialization.
public struct COUNCIL has drop {}

/// Council capability for gated operations.
/// Transferable - can be held by a multisig or single admin.
public struct CouncilCap has key, store {
    id: UID,
}

/// Configuration for council (shared, for transparency).
public struct CouncilConfig has key {
    id: UID,
    /// Number of required signatures (for documentation, actual enforcement in multisig).
    threshold: u64,
    /// Total council members (for documentation).
    members: u64,
    /// Version marker.
    version: u64,
}

// === Events ===

/// Emitted when council cap is transferred.
public struct CouncilCapTransferred has copy, drop {
    from: address,
    to: address,
}

// === Init ===

fun init(_otw: COUNCIL, ctx: &mut TxContext) {
    // Create council cap and transfer to deployer
    let cap = CouncilCap {
        id: object::new(ctx),
    };
    
    // Create council config
    let config = CouncilConfig {
        id: object::new(ctx),
        threshold: 2, // 2-of-3 default
        members: 3,
        version: 1,
    };
    
    transfer::share_object(config);
    transfer::transfer(cap, ctx.sender());
}

// === Council Cap Functions ===

/// Transfer council cap to new holder.
/// Typically used to transfer to a multisig address.
public fun transfer_cap(
    cap: CouncilCap,
    to: address,
    ctx: &TxContext,
) {
    sui::event::emit(CouncilCapTransferred {
        from: ctx.sender(),
        to,
    });
    transfer::public_transfer(cap, to);
}

// === View Functions ===

/// Get council config threshold.
public fun threshold(config: &CouncilConfig): u64 {
    config.threshold
}

/// Get council config members count.
public fun members(config: &CouncilConfig): u64 {
    config.members
}

/// Get council config version.
public fun config_version(config: &CouncilConfig): u64 {
    config.version
}

// === Test Helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(COUNCIL {}, ctx);
}

#[test_only]
public fun new_cap_for_testing(ctx: &mut TxContext): CouncilCap {
    CouncilCap { id: object::new(ctx) }
}

#[test_only]
public fun destroy_cap_for_testing(cap: CouncilCap) {
    let CouncilCap { id } = cap;
    id.delete();
}

#[test_only]
public fun new_config_for_testing(ctx: &mut TxContext): CouncilConfig {
    CouncilConfig {
        id: object::new(ctx),
        threshold: 2,
        members: 3,
        version: 1,
    }
}

#[test_only]
public fun destroy_config_for_testing(config: CouncilConfig) {
    let CouncilConfig { id, threshold: _, members: _, version: _ } = config;
    id.delete();
}

// === Unit Tests ===

#[test]
fun test_council_cap_creation() {
    let mut ctx = tx_context::dummy();
    let cap = new_cap_for_testing(&mut ctx);
    
    // Cap exists
    let _ = &cap;
    
    destroy_cap_for_testing(cap);
}

#[test]
fun test_council_config_values() {
    let mut ctx = tx_context::dummy();
    let config = new_config_for_testing(&mut ctx);
    
    assert!(config.threshold() == 2);
    assert!(config.members() == 3);
    assert!(config.config_version() == 1);
    
    destroy_config_for_testing(config);
}
