# Tide Protocol

A non-custodial, deterministic capital formation primitive for Sui.

Tide enables projects to raise capital **after product-market fit** without selling tokens, issuing equity, or introducing discretionary fund control. Capital is released on a fixed schedule while backers earn rewards from real protocol revenue and native staking yield.

## Why Tide?

| Traditional Funding | Tide |
|---------------------|----------|
| Token sales dilute holders | No token issuance |
| VCs want control | Non-custodial, on-chain logic only |
| Revenue sharing is discretionary | Enforceable on-chain routing |
| Complex legal structures | Deterministic smart contracts |
| Locked capital is idle | Native staking while locked |

## Core Concepts

### Actors

- **Backers** — Contribute SUI, receive a transferable economic position (SupporterPass), claim rewards
- **Issuer** — Receives released capital on schedule, routes protocol revenue on-chain
- **Listing Council** — 3-5 key multisig that gates listing creation, activation, and pause
- **Tide Treasury** — Receives protocol fees (1% raise fee + 20% of staking rewards)

### Key Objects

| Object | Type | Purpose |
|--------|------|---------|
| `Tide` | Shared | Global configuration, pause flag, version |
| `ListingRegistry` | Shared | Registry of all listings, council-gated creation |
| `CouncilCap` | Owned | Capability for council-gated operations |
| `Listing` | Shared | Capital raise parameters, lifecycle state, release schedule |
| `CapitalVault` | Shared | Holds contributed SUI, manages tranche releases |
| `RewardVault` | Shared | Holds rewards, maintains cumulative index for fair distribution |
| `SupporterPass` | Owned (NFT) | Backer's transferable position with fixed shares and claim cursor |

## How It Works

### Capital Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                             TIDE PROTOCOL                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────┐         ┌─────────────────┐         ┌──────────────┐    │
│   │  Backer  │ ──SUI──▶│  CapitalVault   │ ─────── │   Staking    │    │
│   └──────────┘         │  (locked SUI)   │ ◀────── │   Adapter    │    │
│        │               └────────┬────────┘         └──────────────┘    │
│        │                        │                         │             │
│        │ receives               │ releases on             │ yields      │
│        ▼                        │ schedule                ▼             │
│   ┌──────────────┐              │                  ┌─────────────┐     │
│   │ SupporterPass│              ▼                  │ RewardVault │     │
│   │  (NFT)       │         ┌─────────┐             │   (SUI)     │     │
│   └──────────────┘         │  Issuer │             └──────┬──────┘     │
│        │                   └─────────┘                    │             │
│        │                        │                         │             │
│        │                        │ routes revenue          │             │
│        │                        └─────────────────────────┘             │
│        │                                                  │             │
│        └─────────────────── claims ──────────────────────▶│             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Reward Sources (v1)

1. **Protocol Revenue** — Fixed percentage routed from issuer (e.g., 10% of FAITH fees)
2. **Staking Yield** — Native Sui staking rewards on locked capital

## Deposit Flow

```mermaid
sequenceDiagram
    participant B as Backer
    participant L as Listing
    participant CV as CapitalVault
    participant SP as SupporterPass

    B->>L: deposit(coin<SUI>)
    L->>L: assert state == Active
    L->>L: assert !paused
    L->>CV: accept_deposit(coin)
    CV->>CV: update total_principal
    CV->>CV: calculate shares (fixed-point)
    CV->>SP: mint SupporterPass
    SP->>B: transfer pass
    L->>L: emit Deposited event
```

### Deposit Step-by-Step

1. **Backer calls `deposit()`** with SUI coin (minimum 1 SUI)
2. **Listing validates state** — Must be `Active`, not paused
3. **CapitalVault accepts deposit** — Validates minimum, adds to total principal
4. **Shares calculated** — `shares = deposit_amount * PRECISION / total_principal_at_deposit`
5. **SupporterPass minted** — NFT with fixed shares and claim cursor at current index
6. **Pass transferred to backer** — Fully owned, transferable

## Withdrawal Flow (Reward Claims)

```mermaid
sequenceDiagram
    participant B as Backer
    participant SP as SupporterPass
    participant RV as RewardVault
    participant L as Listing

    B->>L: claim(supporter_pass)
    L->>RV: get global_index
    L->>SP: get pass_index, shares
    L->>L: claimable = shares × (global_index - pass_index)
    alt claimable > 0
        RV->>RV: withdraw(claimable)
        RV->>B: transfer SUI
        SP->>SP: update pass_index = global_index
        L->>L: emit Claimed event
    else claimable == 0
        L->>L: no-op (or abort)
    end
```

### Claim Step-by-Step

1. **Backer calls `claim()`** with their SupporterPass
2. **Fetch global reward index** from RewardVault
3. **Calculate claimable amount** — `shares × (global_index - pass_index)`
4. **Withdraw from RewardVault** — Deduct from vault balance
5. **Transfer SUI to backer** — Direct transfer
6. **Update pass cursor** — Set `pass_index = global_index` to prevent double-claim

### Why This is Transfer-Safe

When a SupporterPass is transferred:
- New owner inherits the current `pass_index`
- They can only claim rewards accrued **after** the last claim
- Previous owner cannot claim again (no longer owns the pass)
- No coordination or approval needed

## Deterministic Capital Release

Capital is released on a **fixed, immutable schedule** computed at listing finalization:

| Phase | Timing | Amount |
|-------|--------|--------|
| Initial | At finalization | 20% of net capital (after 1% fee) |
| Month 1-12 | 30 days apart | 6.67% each (80% ÷ 12) |

**Key Properties:**
- **Pull-based** — Anyone can call `release_tranche()` once time passes
- **Non-discretionary** — Issuer cannot accelerate, delay, or reorder
- **Immutable** — Schedule locked at finalization
- **Independent** — Revenue or performance doesn't affect releases

## Capital Release Flow

```mermaid
sequenceDiagram
    participant T as Time/Keeper
    participant L as Listing
    participant CV as CapitalVault
    participant SA as StakingAdapter
    participant I as Issuer

    T->>L: release_tranche()
    L->>L: assert tranche is releasable
    L->>CV: get tranche amount
    alt capital is staked
        CV->>SA: request_unstake(amount)
        SA->>SA: queue for epoch boundary
        Note over SA: Wait for unstake completion
        SA->>CV: return unstaked SUI
    end
    CV->>CV: deduct from principal
    CV->>I: transfer released SUI
    L->>L: emit TrancheReleased event
    L->>L: update release state
```

### Release Step-by-Step

1. **Keeper/crank calls `release_tranche()`**
2. **Validate release conditions** — Timestamp, tranche not already released
3. **Check staking status** — If capital is staked, initiate unstake
4. **Wait for unstake** — Epoch boundary for Sui staking (may require separate tx)
5. **Transfer to issuer** — Principal flows to issuer address
6. **Update tranche state** — Mark released, no further rewards accrue

## Revenue Routing Flow

```mermaid
sequenceDiagram
    participant P as Protocol (FAITH)
    participant A as Adapter
    participant RV as RewardVault

    P->>A: route_revenue(coin<SUI>)
    A->>A: validate source
    A->>RV: deposit_rewards(coin)
    RV->>RV: add to balance
    RV->>RV: update global_index
    RV->>RV: emit RouteIn event
```

### Routing Step-by-Step

1. **Protocol calls adapter** with revenue SUI
2. **Adapter validates** — Checks capability/authorization
3. **Deposit to RewardVault** — Adds to reward pool
4. **Update global index** — `new_index = old_index + (amount / total_shares)`
5. **Emit RouteIn event** — Standardized event for tracking

## Reward Accounting

### Core Formula

```
claimable = shares × (global_index - pass_index)
```

Where:
- `shares` — Fixed at deposit time, stored in SupporterPass
- `global_index` — Cumulative reward-per-share in RewardVault
- `pass_index` — Last claimed index, stored in SupporterPass

### Properties

| Property | Guarantee |
|----------|-----------|
| Transfer-safe | Ownership = full entitlement |
| No double-claim | Cursor updates atomically |
| Deterministic gas | O(1) claim regardless of history |
| Late joiner fair | Only earn from rewards after deposit |

## Lifecycle States

```
┌─────────┐     activate()     ┌────────┐     finalize()     ┌───────────┐     complete()     ┌───────────┐
│  Draft  │ ─────────────────▶ │ Active │ ─────────────────▶ │ Finalized │ ─────────────────▶ │ Completed │
└─────────┘                    └────────┘                    └───────────┘                    └───────────┘
     │                              │                              │                               │
     │ Config editable              │ Deposits accepted            │ No new deposits               │ Terminal
     │ No deposits                  │ Releases scheduled           │ Releases continue             │ All released
     │                              │                              │ Revenue routing               │ Claims only
```

## Fees & Treasury (v1)

| Fee Type | Rate | Destination | Timing |
|----------|------|-------------|--------|
| Raise Fee | 1% of total raised | Treasury | Before first tranche release |
| Staking Split | 20% of staking rewards | Treasury | On reward harvest |
| Revenue Skim | 0% (no fee) | N/A | N/A |

**Note:** All fee parameters are immutable and disclosed in the listing config hash.

## Pause Semantics

When paused:
- ❌ Capital releases STOP
- ❌ New deposits MAY be halted
- ✅ Staking MAY continue
- ✅ Revenue routing MAY continue
- ✅ Reward claims ENABLED

**Invariant:** Pause MUST NOT allow capital or reward redirection.

## Security Invariants

1. **Principal isolation** — Capital MUST ONLY flow to issuer via release schedule
2. **Principal/reward separation** — Principal MUST NEVER enter RewardVault
3. **Monotonic index** — Reward index MUST only increase
4. **Economics immutable** — Parameters MUST NOT change after activation
5. **Non-custodial** — No admin can redirect funds

## v1 Constraints

Tide v1 is intentionally minimal with a **registry-first architecture**:

| Feature | v1 Status |
|---------|-----------|
| Architecture | Registry-first (future-proof) |
| Listings | Only FAITH configured & surfaced (Listing #1) |
| Governance | Minimal council gating (3-5 key multisig) |
| Raise Fee | 1% of total raised (collected before first release) |
| Staking Split | 80% backers / 20% treasury |
| Min Deposit | 1 SUI per backer |
| Assets | SUI only |
| Staking | Native Sui only (placeholder in v1) |
| Marketplace | None |
| Refunds | None |

**Council MAY:** Create listings, activate/finalize, pause/resume

**Council MUST NOT:** Seize capital, redirect rewards, change live economics

## Repository Structure

```
tide-protocol/
├── CLAUDE.md                    # AI/development guidelines
├── README.md                    # This file
│
├── contracts/
│   ├── core/                    # Tide Core package
│   │   ├── Move.toml
│   │   ├── sources/
│   │   │   ├── tide.move              # Global config + pause
│   │   │   ├── registry.move          # Listing registry (council-gated)
│   │   │   ├── council.move           # Council capability
│   │   │   ├── listing.move           # Listing lifecycle
│   │   │   ├── capital_vault.move     # Principal custody
│   │   │   ├── reward_vault.move      # Reward distribution
│   │   │   ├── staking_adapter.move   # Native Sui staking
│   │   │   ├── supporter_pass.move    # Backer NFT position (economics only)
│   │   │   ├── display.move           # Display metadata (sui::display)
│   │   │   ├── math.move              # Fixed-point arithmetic
│   │   │   ├── admin.move             # Capability-gated admin
│   │   │   ├── constants.move         # Shared constants
│   │   │   ├── errors.move            # Error codes
│   │   │   └── events.move            # Event definitions
│   │   └── tests/
│   │       └── *.move
│   │
│   └── adapters/
│       └── faith_router/        # FAITH revenue adapter
│           ├── Move.toml
│           ├── sources/
│           │   └── faith_router.move
│           └── tests/
│
├── spec/
│   ├── tide-core-v1.md          # Locked specification
│   └── invariants.md            # Audit-ready invariant list
│
├── scripts/
│   ├── package.json
│   └── src/
│       ├── deploy_devnet.ts
│       ├── deploy_testnet.ts
│       └── deploy_mainnet.ts
│
└── LICENSE
```

## Build & Test

```bash
# Build core contracts
cd contracts/core
sui move build

# Run tests
sui move test

# Build adapter
cd ../adapters/faith_router
sui move build
```

## Deployment

See [DEPLOYMENT.md](./DEPLOYMENT.md) for:
- Environment strategy (testnet → mainnet)
- Wallet and multisig setup
- Step-by-step deployment guide
- Emergency procedures

Quick start:
```bash
# Install deployment scripts
cd scripts
npm install

# Deploy to testnet
export DEPLOYER_PRIVATE_KEY="your_private_key_hex"
npm run deploy:testnet
```

## License

[TBD]
