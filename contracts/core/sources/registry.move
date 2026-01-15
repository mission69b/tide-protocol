/// Listing Registry for Tide Core.
/// 
/// Maintains a registry of all listings with monotonically increasing IDs.
/// Creation is gated via CouncilCap.
/// 
/// v1 constraint: Only FAITH Listing #1 is configured and surfaced.
/// 
/// Invariant: Registry holds no capital and cannot redirect funds.
module tide_core::registry;

use tide_core::council::CouncilCap;

// === Structs ===

/// One-time witness for module initialization.
public struct REGISTRY has drop {}

/// Registry of all listings (shared singleton).
public struct ListingRegistry has key {
    id: UID,
    /// Total number of listings created (monotonically increasing).
    listing_count: u64,
    /// IDs of all registered listings.
    listings: vector<ID>,
    /// Version marker for upgrades.
    version: u64,
}

// === Events ===

/// Emitted when a new listing is registered.
public struct ListingRegistered has copy, drop {
    listing_id: ID,
    listing_number: u64,
    issuer: address,
}

// === Init ===

fun init(_otw: REGISTRY, ctx: &mut TxContext) {
    let registry = ListingRegistry {
        id: object::new(ctx),
        listing_count: 0,
        listings: vector::empty(),
        version: 1,
    };
    
    transfer::share_object(registry);
}

// === Council-Gated Functions ===

/// Register a new listing. Requires CouncilCap.
/// Returns the new listing number (1-indexed for human readability).
public fun register_listing(
    self: &mut ListingRegistry,
    _cap: &CouncilCap,
    listing_id: ID,
    issuer: address,
): u64 {
    self.listing_count = self.listing_count + 1;
    self.listings.push_back(listing_id);
    
    sui::event::emit(ListingRegistered {
        listing_id,
        listing_number: self.listing_count,
        issuer,
    });
    
    self.listing_count
}

// === View Functions ===

/// Get the registry ID.
public fun id(self: &ListingRegistry): ID {
    self.id.to_inner()
}

/// Get total listing count.
public fun listing_count(self: &ListingRegistry): u64 {
    self.listing_count
}

/// Get listing ID by index (0-indexed).
public fun listing_at(self: &ListingRegistry, index: u64): ID {
    self.listings[index]
}

/// Check if a listing is registered.
public fun is_registered(self: &ListingRegistry, listing_id: ID): bool {
    let mut i = 0;
    while (i < self.listings.length()) {
        if (self.listings[i] == listing_id) {
            return true
        };
        i = i + 1;
    };
    false
}

/// Get all listing IDs.
public fun all_listings(self: &ListingRegistry): &vector<ID> {
    &self.listings
}

/// Get version.
public fun version(self: &ListingRegistry): u64 {
    self.version
}

// === Test Helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(REGISTRY {}, ctx);
}

#[test_only]
public fun new_for_testing(ctx: &mut TxContext): ListingRegistry {
    ListingRegistry {
        id: object::new(ctx),
        listing_count: 0,
        listings: vector::empty(),
        version: 1,
    }
}

#[test_only]
public fun destroy_for_testing(registry: ListingRegistry) {
    let ListingRegistry { id, listings, .. } = registry;
    let _ = listings;
    id.delete();
}
