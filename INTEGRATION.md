# Tide Protocol Integration Guide

**For Partner Protocols Wanting to Share Revenue with Backers**

This guide walks through the complete process for a protocol to integrate with Tide, from initial partnership to live revenue routing.

---

## Table of Contents

1. [Overview](#overview)
2. [What You Get](#what-you-get)
3. [Prerequisites](#prerequisites)
4. [Integration Process](#integration-process)
5. [Step 1: Partnership Setup](#step-1-partnership-setup)
6. [Step 2: Listing Creation](#step-2-listing-creation)
7. [Step 3: Deploy Your Adapter](#step-3-deploy-your-adapter)
8. [Step 4: Create Router Instance](#step-4-create-router-instance)
9. [Step 5: Activate & Go Live](#step-5-activate--go-live)
10. [Step 6: Ongoing Operations](#step-6-ongoing-operations)
11. [Adapter Template](#adapter-template)
12. [Revenue Routing Options](#revenue-routing-options)
13. [Testing Checklist](#testing-checklist)
14. [FAQ](#faq)

---

## Overview

Tide Protocol allows protocols to raise capital from backers and share ongoing revenue with them. As a partner protocol, you:

1. **Raise Capital** — Backers deposit SUI, receive SupporterPass NFTs
2. **Receive Funds** — Capital is released to you on a fixed schedule
3. **Share Revenue** — Route a percentage of your protocol fees to backers
4. **Benefit from Staking** — Locked capital earns staking rewards (80% to backers, 20% to Tide)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          INTEGRATION OVERVIEW                              │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   ┌───────────────┐         ┌──────────────────┐         ┌─────────────┐ │
│   │ Your Protocol │ ──────▶ │ Your Adapter     │ ──────▶ │ Tide Core   │ │
│   │ (collects     │  route  │ (holds           │ deposit │ RewardVault │ │
│   │  fees)        │   $     │  RouteCapability)│  $      │ (for        │ │
│   └───────────────┘         └──────────────────┘         │  backers)   │ │
│                                                          └──────┬──────┘ │
│                                                                 │         │
│                                                           ┌─────▼─────┐  │
│                                                           │  Backers  │  │
│                                                           │  (claim)  │  │
│                                                           └───────────┘  │
│                                                                            │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## What You Get

When you integrate with Tide, you receive:

| Item | Type | Purpose |
|------|------|---------|
| **Listing** | Shared Object | Your fundraise configuration (schedule, fees, etc.) |
| **CapitalVault** | Shared Object | Holds backer deposits, releases on schedule |
| **RewardVault** | Shared Object | Holds rewards, backers claim from here |
| **StakingAdapter** | Shared Object | Manages staking of locked capital |
| **ListingCap** | Owned NFT | Capability to manage listing (held by you) |
| **RouteCapability** | Owned NFT | Authorization to deposit rewards (consumed by your adapter) |

---

## Prerequisites

Before integrating, ensure you have:

1. **Sui Wallet** — For receiving capitals and managing the adapter
2. **Sui CLI** — v1.60.0+ for deployments
3. **Move Development** — Ability to write/deploy Move packages (or use our template)
4. **Revenue Source** — A mechanism to collect and route protocol fees
5. **Capital Recipient Address** — The wallet that will receive capital releases

---

## Integration Process

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           INTEGRATION TIMELINE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  Week 1-2              Week 2-3              Week 3-4              Week 4+   │
│  ────────              ────────              ────────              ────────  │
│                                                                               │
│  ┌────────────┐       ┌────────────┐       ┌────────────┐       ┌──────────┐│
│  │ Partnership│──────▶│  Listing   │──────▶│  Adapter   │──────▶│ Go Live  ││
│  │   Setup    │       │  Created   │       │  Deployed  │       │          ││
│  └────────────┘       └────────────┘       └────────────┘       └──────────┘│
│                                                                               │
│  • Agreement          • Tide council       • Deploy package     • Activate   │
│  • Terms              • Creates listing    • Create router      • Accept     │
│  • Parameters         • Objects shared     • Test on testnet      deposits   │
│  • Addresses          • Caps transferred   • Verify routing     • Route $    │
│                                                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Partnership Setup

### 1.1 Define Terms

Work with the Tide team to define your listing parameters:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `issuer` | Protocol operator address (manages listing) | Your team's wallet |
| `release_recipient` | Capital recipient address | Artist/creator wallet |
| `validator` | Sui validator for staking | Active testnet/mainnet validator |
| `revenue_bps` | % of your fees to route | 1000 (10%) |
| `raise_fee_bps` | Fee Tide takes on raise | 100 (1%) - standard |
| `staking_backer_bps` | Staking rewards to backers | 8000 (80%) - standard |
| `min_deposit` | Minimum backer deposit | 1 SUI (1000000000 MIST) |

### 1.2 Prepare Addresses

You'll need two key addresses:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          ADDRESS ARCHITECTURE                              │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   Issuer (Protocol Operator)          Release Recipient (Artist/Creator)  │
│   ─────────────────────────           ─────────────────────────────────   │
│                                                                            │
│   • Your protocol team's wallet       • Where capital releases go         │
│   • Receives RouteCapability          • Could be artist, DAO treasury     │
│   • Receives ListingCap               • No capabilities needed            │
│   • Deploys and manages adapter       • Just receives SUI on schedule     │
│   • Routes revenue to backers                                              │
│                                                                            │
│   Examples:                            Examples:                           │
│   • Your ops wallet                    • Artist's personal wallet         │
│   • Protocol multisig                  • Label's treasury                 │
│   • Your Tide integration wallet       • Creator DAO treasury             │
│                                                                            │
└──────────────────────────────────────────────────────────────────────────┘
```

**Provide to Tide:**
```
Issuer Address:            0x... (your protocol team)
Release Recipient Address: 0x... (who gets the capital)
Preferred Validator:       0x... (or let Tide choose)
```

---

## Step 2: Listing Creation

**Tide Council** creates your listing. This is council-gated for security.

### What Tide Does:

```bash
# Tide creates your listing (you provide addresses)
sui client ptb \
  --assign pkg @$TIDE_CORE \
  --assign registry @$REGISTRY \
  --assign council_cap @$COUNCIL_CAP \
  --assign issuer @YOUR_ISSUER_ADDRESS \
  --assign release_recipient @YOUR_ARTIST_ADDRESS \
  --assign validator @$VALIDATOR \
  --move-call "pkg::listing::new" registry council_cap issuer release_recipient validator "vector[]" "vector[]" 1000u64 \
  --assign result \
  --move-call "pkg::listing::share" result.0 \
  --move-call "pkg::capital_vault::share" result.1 \
  --move-call "pkg::reward_vault::share" result.2 \
  --move-call "pkg::staking_adapter::share" result.3 \
  --transfer-objects "[result.4, result.5]" issuer \
  --gas-budget 100000000
```

### What You Receive:

After listing creation, you (the `issuer`) will receive:

| Object | ID | Purpose |
|--------|-----|---------|
| `ListingCap` | `0x...` | Manage your listing |
| `RouteCapability` | `0x...` | **Important:** Used to deploy your adapter |

**Also created (shared, you don't own):**

| Object | ID | Purpose |
|--------|-----|---------|
| `Listing` | `0x...` | Your listing configuration |
| `CapitalVault` | `0x...` | Holds backer deposits |
| `RewardVault` | `0x...` | Holds claimable rewards |
| `StakingAdapter` | `0x...` | Manages staking |

**Save all these IDs!** You'll need them for your adapter deployment.

---

## Step 3: Deploy Your Adapter

Your adapter is a Move package that:
1. Consumes the `RouteCapability` (stores it internally)
2. Provides a `route()` function for your protocol to call
3. Provides a `harvest_and_route()` function for staking rewards

### 3.1 Create Package Structure

```
your_protocol_router/
├── Move.toml
└── sources/
    └── router.move
```

### 3.2 Configure Move.toml

```toml
[package]
name = "your_protocol_router"
version = "1.0.0"
edition = "2024.beta"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }
tide_core = { local = "../../../core" }  # Adjust path

[addresses]
your_protocol_router = "0x0"
```

### 3.3 Write Your Router (Use Template)

See [Adapter Template](#adapter-template) below for the full code.

### 3.4 Build and Deploy

```bash
cd your_protocol_router

# Build
sui move build

# Test
sui move test

# Deploy to testnet first
sui client switch --env testnet
sui client publish --gas-budget 200000000
```

**Record:**
- `YOUR_ROUTER_PACKAGE_ID`

---

## Step 4: Create Router Instance

Now create your router, which consumes the `RouteCapability`:

```bash
# Set your variables
export ROUTER_PKG=0x...        # Your deployed router package
export ROUTE_CAP=0x...         # RouteCapability you received
export REVENUE_BPS=1000        # 10% of your fees go to backers
export ISSUER=0x...            # Your issuer address

# Create the router
sui client ptb \
  --assign pkg @$ROUTER_PKG \
  --assign route_cap @$ROUTE_CAP \
  --assign revenue_bps ${REVENUE_BPS}u64 \
  --assign issuer @$ISSUER \
  --move-call "pkg::router::new" route_cap revenue_bps \
  --assign result \
  --move-call "pkg::router::share" result.0 \
  --move-call "pkg::router::transfer_cap" result.1 issuer \
  --gas-budget 50000000
```

**Record:**
- `YOUR_ROUTER_ID` (result.0)
- `YOUR_ROUTER_CAP_ID` (result.1) - keep this safe!

---

## Step 5: Activate & Go Live

### 5.1 Activate Listing (Tide Does This)

Once you've deployed your adapter and are ready:

```bash
# Tide activates your listing
sui client ptb \
  --assign pkg @$TIDE_CORE \
  --assign listing @$YOUR_LISTING \
  --assign council_cap @$COUNCIL_CAP \
  --assign clock @0x6 \
  --move-call "pkg::listing::activate" listing council_cap clock \
  --gas-budget 50000000
```

### 5.2 Verify Setup

```bash
# Check your router
sui client object $YOUR_ROUTER_ID

# Check your listing
sui client object $YOUR_LISTING
```

### 5.3 Announce to Your Community

Your listing is now **Active**! Backers can deposit SUI.

---

## Step 6: Ongoing Operations

### Route Revenue

When your protocol collects fees, route a portion to backers:

```bash
# Split fees and route to backers
sui client ptb \
  --assign pkg @$ROUTER_PKG \
  --assign router @$YOUR_ROUTER_ID \
  --assign reward_vault @$REWARD_VAULT \
  --split-coins gas "[100000000]" \
  --assign revenue \
  --move-call "pkg::router::route" router reward_vault "revenue.0" \
  --gas-budget 50000000
```

Or integrate into your protocol's Move code:

```move
// In your protocol's fee collection
public fun collect_fees(
    router: &mut YourRouter,
    reward_vault: &mut RewardVault,
    fees: Coin<SUI>,
    ctx: &mut TxContext,
) {
    // Calculate backer share (e.g., 10%)
    let total = fees.value();
    let backer_share = router.calculate_revenue(total);
    
    // Split and route
    let revenue = fees.split(backer_share, ctx);
    router::route(router, reward_vault, revenue, ctx);
    
    // Keep the rest for your protocol
    transfer::public_transfer(fees, @your_treasury);
}
```

### Harvest Staking Rewards

Periodically harvest staking rewards (typically every epoch):

```bash
sui client ptb \
  --assign pkg @$ROUTER_PKG \
  --assign router @$YOUR_ROUTER_ID \
  --assign listing @$YOUR_LISTING \
  --assign tide @$TIDE \
  --assign staking_adapter @$STAKING_ADAPTER \
  --assign reward_vault @$REWARD_VAULT \
  --assign treasury_vault @$TREASURY_VAULT \
  --assign system_state @0x5 \
  --move-call "pkg::router::harvest_and_route" router listing tide staking_adapter reward_vault treasury_vault system_state \
  --gas-budget 100000000
```

**Recommendation:** Set up a cron job or keeper bot to do this automatically.

---

## Adapter Template

Here's the complete adapter template for your protocol:

```move
module your_protocol_router::router;

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
public struct YourRouter has key {
    id: UID,
    /// ID of the Tide listing this router serves
    listing_id: ID,
    /// Revenue percentage in basis points (e.g., 1000 = 10%)
    revenue_bps: u64,
    /// Lifetime total SUI routed
    total_routed: u64,
    // RouteCapability stored as dynamic field (key: b"route_cap")
}

/// Capability to manage the router (held by protocol admin)
public struct YourRouterCap has key, store {
    id: UID,
}

// === Constructor ===

/// Create a new router. Consumes the RouteCapability.
public fun new(
    route_cap: RouteCapability,
    revenue_bps: u64,
    ctx: &mut TxContext,
): (YourRouter, YourRouterCap) {
    assert!(revenue_bps <= constants::max_bps!(), EInvalidBps);
    
    let listing_id = route_cap.route_cap_listing_id();
    let mut router_uid = object::new(ctx);
    
    // Store RouteCapability in dynamic field (secure storage)
    sui::dynamic_field::add(&mut router_uid, b"route_cap", route_cap);
    
    let router = YourRouter {
        id: router_uid,
        listing_id,
        revenue_bps,
        total_routed: 0,
    };
    
    let cap = YourRouterCap {
        id: object::new(ctx),
    };
    
    (router, cap)
}

// === Revenue Routing ===

/// Route revenue to the Tide RewardVault.
/// Called by your protocol when collecting fees.
/// 
/// This is permissionless - anyone can route revenue.
/// For gated routing, add `_cap: &YourRouterCap` parameter.
public fun route(
    self: &mut YourRouter,
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
/// Split: 80% → RewardVault (backers), 20% → TreasuryVault (Tide)
/// 
/// Should be called periodically (every epoch) by a keeper.
public fun harvest_and_route(
    self: &mut YourRouter,
    listing: &Listing,
    tide: &Tide,
    staking_adapter: &mut StakingAdapter,
    reward_vault: &mut RewardVault,
    treasury_vault: &mut TreasuryVault,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    let route_cap = sui::dynamic_field::borrow<vector<u8>, RouteCapability>(
        &self.id,
        b"route_cap",
    );
    
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
/// Use this to determine how much to route.
public fun calculate_revenue(self: &YourRouter, total_fees: u64): u64 {
    (((total_fees as u128) * (self.revenue_bps as u128)) 
        / (constants::max_bps!() as u128)) as u64
}

// === View Functions ===

public fun listing_id(self: &YourRouter): ID { self.listing_id }
public fun revenue_bps(self: &YourRouter): u64 { self.revenue_bps }
public fun total_routed(self: &YourRouter): u64 { self.total_routed }

// === Share/Transfer ===

public fun share(router: YourRouter) {
    sui::transfer::share_object(router);
}

public fun transfer_cap(cap: YourRouterCap, recipient: address) {
    sui::transfer::public_transfer(cap, recipient);
}
```

---

## Revenue Routing Options

### Option A: Percentage of All Fees (Recommended)

Route X% of all protocol fees to backers.

```move
public fun collect_and_route(
    router: &mut YourRouter,
    reward_vault: &mut RewardVault,
    total_fees: Coin<SUI>,
    ctx: &mut TxContext,
) {
    let amount = total_fees.value();
    let backer_share = router.calculate_revenue(amount);  // e.g., 10%
    
    let revenue = total_fees.split(backer_share, ctx);
    router::route(router, reward_vault, revenue, ctx);
    
    // Keep the rest
    transfer::public_transfer(total_fees, @your_treasury);
}
```

### Option B: Fixed Monthly Revenue

Route a fixed amount monthly, regardless of actual revenue.

```bash
# Monthly keeper script
sui client ptb \
  --split-coins gas "[1000000000000]" \  # 1000 SUI
  --assign revenue \
  --move-call "pkg::router::route" router reward_vault "revenue.0" \
  --gas-budget 50000000
```

### Option C: Revenue Milestones

Route only when revenue exceeds thresholds.

```move
const REVENUE_THRESHOLD: u64 = 100_000_000_000;  // 100 SUI

public fun maybe_route(
    router: &mut YourRouter,
    reward_vault: &mut RewardVault,
    accumulated_fees: &mut Coin<SUI>,
    ctx: &mut TxContext,
) {
    if (accumulated_fees.value() >= REVENUE_THRESHOLD) {
        let to_route = accumulated_fees.split(REVENUE_THRESHOLD, ctx);
        router::route(router, reward_vault, to_route, ctx);
    }
}
```

---

## Testing Checklist

### Testnet Integration

- [ ] Received `RouteCapability` from Tide
- [ ] Deployed adapter package
- [ ] Created router instance (consumed `RouteCapability`)
- [ ] Router is shared
- [ ] Listing activated
- [ ] Test deposit works (as a backer)
- [ ] Test `route()` works (deposit to RewardVault)
- [ ] Test claim works (backer receives SUI)
- [ ] Test `harvest_and_route()` works (if staking)
- [ ] Set up keeper bot for harvesting

### Pre-Mainnet

- [ ] All testnet tests passing
- [ ] Keeper bot configured
- [ ] Revenue routing integrated with protocol
- [ ] Emergency contacts exchanged with Tide
- [ ] Runbook documented

---

## FAQ

### Q: Do I need Move development experience?

**A:** Minimal. You can use the template above with just configuration changes. For custom logic, basic Move knowledge helps.

### Q: What if I lose my RouteCapability?

**A:** The `RouteCapability` is consumed when creating your router. If you lose the `YourRouterCap`, you can no longer update the router (but routing still works).

### Q: Can I change the revenue percentage later?

**A:** The template doesn't include this, but you can add an `update_bps()` function gated by `YourRouterCap`.

### Q: Who calls `harvest_and_route()`?

**A:** Anyone can call it (permissionless). Typically you set up a keeper bot to do this every epoch. Tide may also run a backup keeper.

### Q: What happens if no one routes revenue?

**A:** Backers only earn from staking rewards. You should route revenue regularly to keep backers engaged.

### Q: Can backers withdraw their capital?

**A:** No. Capital is locked and released to the `release_recipient` on a fixed schedule. Backers can only claim *rewards*.

### Q: What if I need to cancel the listing?

**A:** Contact Tide. The council can cancel listings in Draft/Active state. Backers would then claim proportional refunds.

---

## Support

For integration support:

- **Email:** integrations@tide.am
- **Discord:** [Tide Protocol Discord]
- **Docs:**
  - [ADAPTERS.md](./ADAPTERS.md) — Technical adapter details
  - [DEPLOYMENT.md](./DEPLOYMENT.md) — Full deployment guide
  - [README.md](./README.md) — Protocol overview

---

## Quick Reference

```bash
# Your environment variables
export TIDE_CORE=0x...         # Tide Core package
export TIDE=0x...              # Tide object
export TREASURY_VAULT=0x...    # TreasuryVault
export YOUR_LISTING=0x...      # Your Listing
export CAPITAL_VAULT=0x...     # Your CapitalVault
export REWARD_VAULT=0x...      # Your RewardVault
export STAKING_ADAPTER=0x...   # Your StakingAdapter
export YOUR_ROUTER_PKG=0x...   # Your Router package
export YOUR_ROUTER=0x...       # Your Router object

# Route revenue
sui client ptb \
  --assign pkg @$YOUR_ROUTER_PKG \
  --assign router @$YOUR_ROUTER \
  --assign reward_vault @$REWARD_VAULT \
  --split-coins gas "[100000000]" \
  --assign revenue \
  --move-call "pkg::router::route" router reward_vault "revenue.0" \
  --gas-budget 50000000

# Harvest staking rewards
sui client ptb \
  --assign pkg @$YOUR_ROUTER_PKG \
  --assign router @$YOUR_ROUTER \
  --assign listing @$YOUR_LISTING \
  --assign tide @$TIDE \
  --assign staking_adapter @$STAKING_ADAPTER \
  --assign reward_vault @$REWARD_VAULT \
  --assign treasury_vault @$TREASURY_VAULT \
  --assign system_state @0x5 \
  --move-call "pkg::router::harvest_and_route" router listing tide staking_adapter reward_vault treasury_vault system_state \
  --gas-budget 100000000
```
