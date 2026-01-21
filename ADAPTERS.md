# Tide Protocol Adapters

This document explains the **adapter pattern** for integrating external protocols with Tide.

---

## Overview

When a protocol (e.g., FAITH) wants to share revenue with its backers through Tide, it uses an **adapter contract** as the integration layer.

```
                              ┌─────────────────────────────────────────┐
                              │           FaithRouter (Adapter)          │
                              │                                         │
┌─────────────────┐           │  ┌───────────────────────────────────┐  │           ┌─────────────────┐
│    Protocol     │  route()  │  │      RouteCapability (stored)     │  │           │   RewardVault   │
│   (e.g. FAITH)  │ ────────→ │  └───────────────────────────────────┘  │ ────────→ │   (Tide Core)   │
└─────────────────┘           │                    │                    │           └─────────────────┘
                              │      ┌─────────────┴─────────────┐      │
                              │      ▼                           ▼      │
                              │  route()              harvest_and_route()
                              │  (protocol revenue)   (staking rewards) │
                              └─────────────────────────────────────────┘
```

**Key principle**: The protocol doesn't interact with Tide directly. The adapter handles all Tide integration logic, including:
- **Protocol revenue routing** via `route()`
- **Staking reward harvesting** via `harvest_and_route()`

---

## Why Use Adapters?

| Benefit | Description |
|---------|-------------|
| **Clean Separation** | Protocol code doesn't import Tide modules |
| **Upgradeable** | Swap/upgrade the adapter without touching protocol code |
| **Protocol-Specific Logic** | Each adapter can implement custom revenue logic |
| **On-Chain Stats** | Adapters track `total_routed` for frontend queries |
| **Authorization** | Adapter holds the `RouteCapability`, not the protocol |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              TIDE CORE                                       │
│                                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                     │
│  │  Listing 1  │    │  Listing 2  │    │  Listing 3  │                     │
│  │  (FAITH)    │    │  (Proto X)  │    │  (Proto Y)  │                     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘                     │
│         │                  │                  │                            │
│  ┌──────▼──────┐    ┌──────▼──────┐    ┌──────▼──────┐                     │
│  │RewardVault 1│    │RewardVault 2│    │RewardVault 3│                     │
│  └──────▲──────┘    └──────▲──────┘    └──────▲──────┘                     │
└─────────┼───────────────────┼───────────────────┼──────────────────────────┘
          │                   │                   │
          │ deposit_rewards() │                   │
          │                   │                   │
┌─────────┼───────────────────┼───────────────────┼──────────────────────────┐
│         │    ADAPTER LAYER  │                   │                          │
│  ┌──────┴──────┐    ┌───────┴─────┐    ┌───────┴─────┐                     │
│  │FaithRouter  │    │ProtoXRouter │    │ProtoYRouter │                     │
│  │(holds cap)  │    │(holds cap)  │    │(holds cap)  │                     │
│  └──────▲──────┘    └──────▲──────┘    └──────▲──────┘                     │
└─────────┼───────────────────┼───────────────────┼──────────────────────────┘
          │ route()           │ route()           │ route()
          │                   │                   │
┌─────────┼───────────────────┼───────────────────┼──────────────────────────┐
│         │  PROTOCOL LAYER   │                   │                          │
│  ┌──────┴──────┐    ┌───────┴─────┐    ┌───────┴─────┐                     │
│  │   FAITH     │    │  Proto X    │    │  Proto Y    │                     │
│  │  Protocol   │    │  Protocol   │    │  Protocol   │                     │
│  └─────────────┘    └─────────────┘    └─────────────┘                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Integration Flow

### Step 1: Tide Council Creates Listing

The Tide council creates a listing for the protocol:

```bash
sui client ptb \
  --move-call "tide_core::listing::new" registry council_cap issuer validator ... \
  --assign result \
  # ... share objects ...
  --transfer-objects "[result.4, result.5]" protocol_team
```

**Returns to protocol team:**
- `ListingCap` - capability to manage the listing
- `RouteCapability` - authorization to route revenue

### Step 2: Protocol Deploys Adapter

The protocol team deploys their adapter, consuming the `RouteCapability`:

```bash
# Build and publish the adapter package
cd contracts/adapters/my_router
sui client publish --gas-budget 100000000

# Create the router instance
sui client ptb \
  --move-call "my_router::new" route_cap revenue_bps \
  --assign result \
  --move-call "my_router::share" result.0 \
  --move-call "my_router::transfer_cap" result.1 protocol_admin
```

### Step 3: Protocol Routes Revenue

When the protocol collects fees, it routes a portion to Tide:

```move
// Inside protocol code
public fun collect_game_fees(router: &mut MyRouter, vault: &mut RewardVault, ...) {
    let total_fees = /* ... */;
    let revenue = router.calculate_revenue(total_fees);
    let revenue_coin = /* split from fees */;
    
    my_router::route(router, vault, revenue_coin, ctx);
}
```

Or via CLI/PTB:
```bash
sui client ptb \
  --split-coins gas "[100000000]" \
  --assign revenue \
  --move-call "my_router::route" router reward_vault "revenue.0"
```

### Step 4: Backers Claim Rewards

Backers claim their share of routed revenue:

```bash
sui client ptb \
  --move-call "tide_core::listing::claim" listing tide reward_vault supporter_pass \
  --assign claimed \
  --transfer-objects "[claimed]" me
```

---

## Adapter Template

Each adapter should implement this interface:

```move
module my_protocol_router::router;

use sui::coin::Coin;
use sui::sui::SUI;
use sui_system::sui_system::SuiSystemState;
use tide_core::reward_vault::{RewardVault, RouteCapability};
use tide_core::listing::Listing;
use tide_core::tide::Tide;
use tide_core::treasury_vault::TreasuryVault;
use tide_core::staking_adapter::StakingAdapter;
use tide_core::constants;

// === Errors ===
const EInvalidBps: u64 = 0;
const EZeroAmount: u64 = 1;

// === Structs ===

/// The router object (shared after creation)
public struct MyRouter has key {
    id: UID,
    /// ID of the Tide listing this router serves
    listing_id: ID,
    /// Revenue percentage in basis points (e.g., 1000 = 10%)
    revenue_bps: u64,
    /// Lifetime total SUI routed
    total_routed: u64,
    // RouteCapability stored as dynamic field
}

/// Capability to manage the router (held by protocol admin)
public struct MyRouterCap has key, store {
    id: UID,
}

// === Constructor ===

/// Create a new router. Consumes the RouteCapability.
public fun new(
    route_cap: RouteCapability,
    revenue_bps: u64,
    ctx: &mut TxContext,
): (MyRouter, MyRouterCap) {
    assert!(revenue_bps <= constants::max_bps!(), EInvalidBps);
    
    let listing_id = route_cap.route_cap_listing_id();
    let mut router_uid = object::new(ctx);
    
    // Store RouteCapability in dynamic field
    sui::dynamic_field::add(&mut router_uid, b"route_cap", route_cap);
    
    let router = MyRouter {
        id: router_uid,
        listing_id,
        revenue_bps,
        total_routed: 0,
    };
    
    let cap = MyRouterCap {
        id: object::new(ctx),
    };
    
    (router, cap)
}

// === Revenue Routing ===

/// Route revenue to the Tide RewardVault.
/// Called by the protocol when collecting fees.
public fun route(
    self: &mut MyRouter,
    reward_vault: &mut RewardVault,
    coin: Coin<SUI>,
    ctx: &TxContext,
) {
    let amount = coin.value();
    assert!(amount > 0, EZeroAmount);
    
    // Get the stored RouteCapability
    let route_cap = sui::dynamic_field::borrow<vector<u8>, RouteCapability>(
        &self.id,
        b"route_cap",
    );
    
    // Deposit to Tide RewardVault
    reward_vault.deposit_rewards(route_cap, coin, ctx);
    
    // Update lifetime stats
    self.total_routed = self.total_routed + amount;
}

// === Staking Integration ===

/// Harvest staking rewards and route backer share to RewardVault.
/// 
/// This function allows the adapter to handle staking reward distribution
/// using its stored RouteCapability. The rewards are split 80/20:
/// - 80% → RewardVault (for backers to claim)
/// - 20% → TreasuryVault
/// 
/// Should be called periodically (e.g., every epoch) by a keeper.
public fun harvest_and_route(
    self: &mut MyRouter,
    listing: &Listing,
    tide: &Tide,
    staking_adapter: &mut StakingAdapter,
    reward_vault: &mut RewardVault,
    treasury_vault: &mut TreasuryVault,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    // Borrow the stored RouteCapability
    let route_cap = sui::dynamic_field::borrow<vector<u8>, RouteCapability>(
        &self.id,
        b"route_cap",
    );
    
    // Call listing's harvest function which handles the 80/20 split
    tide_core::listing::harvest_staking_rewards(
        listing,
        tide,
        staking_adapter,
        reward_vault,
        treasury_vault,
        route_cap,
        system_state,
        ctx,
    );
}

// === Helpers ===

/// Calculate revenue amount from total fees.
/// Helper for the protocol to determine how much to route.
public fun calculate_revenue(self: &MyRouter, total_fees: u64): u64 {
    (((total_fees as u128) * (self.revenue_bps as u128)) 
        / (constants::max_bps!() as u128)) as u64
}

// === View Functions ===

public fun listing_id(self: &MyRouter): ID { self.listing_id }
public fun revenue_bps(self: &MyRouter): u64 { self.revenue_bps }
public fun total_routed(self: &MyRouter): u64 { self.total_routed }

// === Share/Transfer ===

public fun share(router: MyRouter) {
    sui::transfer::share_object(router);
}

public fun transfer_cap(cap: MyRouterCap, recipient: address) {
    sui::transfer::public_transfer(cap, recipient);
}
```

---

## Example: FaithRouter

The FAITH protocol adapter is located at:
```
contracts/adapters/faith_router/
├── Move.toml
└── sources/
    └── faith_router.move
```

**Key features:**
- `revenue_bps`: Set to 1000 (10% of FAITH fees)
- `total_routed`: Tracks lifetime revenue for frontend display
- `calculate_revenue()`: Helper for FAITH to compute the 10%
- `route()`: Routes protocol revenue to RewardVault
- `harvest_and_route()`: Harvests staking rewards and routes 80% to backers

**Deployment:**
```bash
# 1. Publish package
cd contracts/adapters/faith_router
sui client publish --gas-budget 100000000

# 2. Create router instance
sui client ptb \
  --assign pkg @<FAITH_ROUTER_PKG> \
  --assign route_cap @<ROUTE_CAP_FROM_LISTING> \
  --assign revenue_bps 1000u64 \
  --assign me @<YOUR_ADDRESS> \
  --move-call "pkg::faith_router::new" route_cap revenue_bps \
  --assign result \
  --move-call "pkg::faith_router::share" result.0 \
  --move-call "pkg::faith_router::transfer_cap" result.1 me \
  --gas-budget 50000000
```

**Harvest Staking Rewards:**
```bash
sui client ptb \
  --assign pkg @<FAITH_ROUTER_PKG> \
  --assign router @<FAITH_ROUTER_ID> \
  --assign listing @<LISTING_ID> \
  --assign tide @<TIDE_ID> \
  --assign staking_adapter @<STAKING_ADAPTER_ID> \
  --assign reward_vault @<REWARD_VAULT_ID> \
  --assign treasury_vault @<TREASURY_VAULT_ID> \
  --assign system_state @0x5 \
  --move-call "pkg::faith_router::harvest_and_route" router listing tide staking_adapter reward_vault treasury_vault system_state \
  --gas-budget 100000000
```

---

## Best Practices

### 1. One Adapter Per Protocol
Each protocol should have its own adapter, even if the logic is similar. This allows protocol-specific customization.

### 2. Store RouteCapability Securely
The `RouteCapability` is the authorization to deposit rewards. Store it in a dynamic field, not as a public field.

### 3. Track Statistics
Include `total_routed` for frontend queries. Consider adding:
- `last_routed_at: u64` (timestamp)
- `route_count: u64` (number of transactions)

### 4. Use Basis Points
Revenue percentages should use basis points (1 bp = 0.01%). Max is 10000 (100%).

### 5. Emit Events (Optional)
Consider emitting events for off-chain indexing:
```move
public struct RevenueRouted has copy, drop {
    router_id: ID,
    listing_id: ID,
    amount: u64,
    total_routed: u64,
}
```

### 6. Access Control (Optional)
If only the protocol should route (not anyone), add capability checks:
```move
public fun route(
    _cap: &MyRouterCap,  // Proves caller has authority
    self: &mut MyRouter,
    ...
) { ... }
```

---

## Directory Structure

```
contracts/
├── core/                    # Tide Core protocol
│   └── sources/
│       ├── listing.move
│       ├── reward_vault.move
│       └── ...
└── adapters/                # Protocol adapters
    ├── faith_router/        # FAITH protocol adapter
    │   ├── Move.toml
    │   └── sources/
    │       └── faith_router.move
    ├── proto_x_router/      # Future: Protocol X adapter
    └── proto_y_router/      # Future: Protocol Y adapter
```

---

## Checklist for New Adapters

- [ ] Create new directory under `contracts/adapters/`
- [ ] Copy template from `faith_router`
- [ ] Update module name and struct names
- [ ] Configure `revenue_bps` for the protocol
- [ ] Deploy package to testnet
- [ ] Create router instance with `RouteCapability`
- [ ] Test routing and claiming flow
- [ ] Deploy to mainnet
- [ ] Document the router object ID

---

## Questions?

For integration support, refer to:
- `spec/tide-core-v1.md` - Core protocol specification
- `DEPLOYMENT.md` - Deployment guide
- `README.md` - Project overview
