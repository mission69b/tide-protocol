# Tide Protocol Frontend Specification

> **Version:** 1.0  
> **Status:** Draft  
> **Last Updated:** January 2026  
> **Target:** Web Application (React/Next.js)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [On-Chain Data Model](#3-on-chain-data-model)
4. [Events for Indexing](#4-events-for-indexing)
5. [API Specification](#5-api-specification)
6. [User Flows](#6-user-flows)
7. [Screen Specifications](#7-screen-specifications)
8. [Real-Time Updates](#8-real-time-updates)
9. [Wallet Integration](#9-wallet-integration)
10. [Error Handling](#10-error-handling)
11. [Security Considerations](#11-security-considerations)

---

## 1. Overview

### 1.1 Product Summary

Tide Protocol is a revenue-backed capital formation platform on Sui. Users can:
- **Back** projects by depositing SUI
- **Earn** rewards from project revenue and staking yield
- **Trade** SupporterPass NFTs on the marketplace
- **Borrow** against their SupporterPass NFTs

### 1.2 Core Packages

| Package | Description | Shared Objects |
|---------|-------------|----------------|
| `tide_core` | Core protocol | Tide, ListingRegistry, CouncilConfig, TreasuryVault, Listing, CapitalVault, RewardVault, StakingAdapter |
| `faith_router` | Revenue routing adapter | FaithRouter |
| `tide_marketplace` | NFT marketplace | MarketplaceConfig, SaleListing |
| `tide_loans` | Self-paying loans | LoanVault, Loan |

### 1.3 Key User Types

| User | Actions |
|------|---------|
| **Backer** | Deposit, claim rewards, sell pass, borrow |
| **Pass Holder** | Claim rewards, sell pass, borrow |
| **Buyer** | Buy pass on marketplace |
| **Borrower** | Borrow against pass, repay, withdraw |
| **Keeper** | Harvest and repay loans (bot) |
| **Admin/Council** | Manage listings, pause, configure |

---

## 2. Architecture

### 2.1 System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              FRONTEND                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │   Explore   │  │   My Pass   │  │ Marketplace │  │    Loans    │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                               API LAYER                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │  REST API       │  │  GraphQL API    │  │  WebSocket      │         │
│  │  /api/v1/*      │  │  /graphql       │  │  /ws            │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              INDEXER                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │  Event Listener │  │  State Indexer  │  │  Database       │         │
│  │  (Sui RPC)      │  │  (Object Sync)  │  │  (PostgreSQL)   │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           SUI BLOCKCHAIN                                 │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐            │
│  │tide_core  │  │faith_router│ │marketplace│  │  loans    │            │
│  └───────────┘  └───────────┘  └───────────┘  └───────────┘            │
└────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Technology Stack (Recommended)

| Layer | Technology |
|-------|------------|
| Frontend | Next.js 14+, React 18+, TypeScript |
| State Management | TanStack Query (React Query) |
| Styling | Tailwind CSS, shadcn/ui |
| Wallet | @mysten/dapp-kit |
| Charts | Recharts or Tremor |
| API | tRPC or REST |
| Indexer | Custom or TheGraph |
| Database | PostgreSQL + Prisma |
| Real-time | WebSockets or Server-Sent Events |

---

## 3. On-Chain Data Model

### 3.1 Core Objects

#### Tide (Global Config)

```typescript
interface Tide {
  id: string;                    // Object ID
  version: number;               // Protocol version
  admin_wallet: string;          // Admin address
  paused: boolean;               // Global pause flag
  treasury: string;              // TreasuryVault ID
}
```

#### ListingRegistry

```typescript
interface ListingRegistry {
  id: string;
  listing_count: number;         // Total listings created
  listings: string[];            // Array of Listing IDs
}
```

#### Listing

```typescript
interface Listing {
  id: string;
  listing_number: number;        // Sequential number (1, 2, 3...)
  issuer: string;                // Issuer address
  config_hash: string;           // Immutable config hash
  state: ListingState;           // Current lifecycle state
  paused: boolean;               // Per-listing pause
  
  // Vault references
  capital_vault_id: string;
  reward_vault_id: string;
  staking_adapter_id: string;
  
  // Config
  min_deposit: number;           // Minimum deposit (MIST)
  raise_fee_bps: number;         // Raise fee (basis points)
  staking_backer_bps: number;    // Staking reward split for backers
}

enum ListingState {
  Draft = 0,
  Active = 1,
  Finalized = 2,
  Completed = 3,
  Cancelled = 4
}
```

#### CapitalVault

```typescript
interface CapitalVault {
  id: string;
  listing_id: string;
  total_raised: number;          // Total SUI deposited (MIST)
  total_released: number;        // Total SUI released to issuer
  balance: number;               // Current balance
  
  // Tranches
  tranche_amounts: number[];     // Amount per tranche
  tranche_times: number[];       // Release times (ms)
  tranches_released: number;     // Count of released tranches
  
  // Stats
  total_backers: number;
  total_shares: string;          // u128 as string
  raise_fee_collected: boolean;
}
```

#### RewardVault

```typescript
interface RewardVault {
  id: string;
  listing_id: string;
  total_shares: string;          // u128 as string
  global_reward_index: string;   // u128 as string
  cumulative_distributed: number;
  balance: number;               // Current reward balance
}
```

#### SupporterPass (NFT)

```typescript
interface SupporterPass {
  id: string;
  listing_id: string;
  shares: string;                // u128 as string
  claim_index: string;           // u128 as string
  
  // Provenance (Tier 1)
  pass_number: number;           // Sequential mint number
  original_backer: string;       // Original depositor address
  total_claimed: number;         // Cumulative rewards claimed
  
  // Display
  name: string;
  description: string;
  image_url: string;
}
```

#### StakingAdapter

```typescript
interface StakingAdapter {
  id: string;
  listing_id: string;
  total_staked: number;          // Total SUI staked
  validator: string;             // Validator address
  staking_enabled: boolean;
}
```

#### TreasuryVault

```typescript
interface TreasuryVault {
  id: string;
  balance: number;               // Current balance (MIST)
  total_deposited: number;       // Lifetime deposits
  total_withdrawn: number;       // Lifetime withdrawals
}
```

### 3.2 Marketplace Objects

#### MarketplaceConfig

```typescript
interface MarketplaceConfig {
  id: string;
  admin: string;
  paused: boolean;
  fee_bps: number;               // 500 = 5%
  
  // Stats
  total_volume: number;          // Lifetime volume (MIST)
  total_fees_collected: number;
  total_sales_count: number;
  active_listings_count: number;
  
  version: number;
}
```

#### SaleListing

```typescript
interface SaleListing {
  id: string;
  seller: string;
  pass_id: string;
  tide_listing_id: string;
  shares: string;                // u128 as string
  price: number;                 // Price in MIST
  listed_at_epoch: number;
}
```

### 3.3 Loans Objects

#### LoanVault

```typescript
interface LoanVault {
  id: string;
  admin: string;
  paused: boolean;
  
  // Liquidity
  liquidity: number;             // Available to lend
  insurance_fund: number;        // Loss protection
  
  // Stats
  total_borrowed: number;
  total_repaid: number;
  total_fees_earned: number;
  active_loans: number;
  total_loans_created: number;
  
  // Config
  config: LoanConfig;
  version: number;
}

interface LoanConfig {
  max_ltv_bps: number;           // 5000 = 50%
  liquidation_threshold_bps: number; // 7500 = 75%
  interest_rate_bps: number;     // 500 = 5% APR
  origination_fee_bps: number;   // 100 = 1%
  liquidation_fee_bps: number;   // 500 = 5%
  keeper_tip_bps: number;        // 10 = 0.1%
  min_loan_amount: number;       // Minimum loan (MIST)
}
```

#### Loan (Dynamic Field)

```typescript
interface Loan {
  id: string;                    // loan_id
  borrower: string;
  pass_id: string;
  listing_id: string;
  
  // Amounts
  principal: number;             // Original loan amount
  interest_accrued: number;      // Accrued interest
  amount_repaid: number;         // Total repaid
  
  // Timing
  created_at_ms: number;
  last_update_ms: number;
  
  // Status
  status: LoanStatus;
}

enum LoanStatus {
  Active = 0,
  Repaid = 1,
  Liquidated = 2
}
```

#### LoanReceipt (Owned Object)

```typescript
interface LoanReceipt {
  id: string;
  loan_id: string;
  borrower: string;
  pass_id: string;
  principal: number;
}
```

---

## 4. Events for Indexing

### 4.1 Core Events

| Event | Package | Key Fields | Indexing Priority |
|-------|---------|------------|-------------------|
| `ListingCreated` | tide_core | listing_id, listing_number, issuer | High |
| `ListingActivated` | tide_core | listing_id, activation_time | High |
| `ListingFinalized` | tide_core | listing_id, total_raised, total_shares | High |
| `ListingCompleted` | tide_core | listing_id | High |
| `ListingCancelled` | tide_core | listing_id, total_refundable | High |
| `Deposited` | tide_core | listing_id, backer, amount, shares, pass_id | Critical |
| `Claimed` | tide_core | listing_id, pass_id, backer, amount | Critical |
| `BatchClaimed` | tide_core | listing_id, passes_claimed, total_amount | High |
| `RouteIn` | tide_core | listing_id, amount, cumulative_distributed | High |
| `TrancheReleased` | tide_core | listing_id, tranche_idx, amount | High |
| `Staked` | tide_core | listing_id, amount, validator | Medium |
| `Unstaked` | tide_core | listing_id, amount | Medium |
| `StakingRewardsHarvested` | tide_core | listing_id, gross_rewards, backer_rewards | High |
| `RefundClaimed` | tide_core | listing_id, pass_id, backer, amount | High |

### 4.2 Marketplace Events

| Event | Key Fields | Indexing Priority |
|-------|------------|-------------------|
| `ListingCreated` | listing_id, seller, pass_id, price | Critical |
| `ListingCancelled` | listing_id, seller, pass_id | Critical |
| `PriceUpdated` | listing_id, old_price, new_price | High |
| `SaleCompleted` | listing_id, pass_id, seller, buyer, price, fee | Critical |
| `MarketplacePaused` | paused, admin | High |

### 4.3 Loans Events

| Event | Key Fields | Indexing Priority |
|-------|------------|-------------------|
| `LoanCreated` | loan_id, borrower, pass_id, principal | Critical |
| `LoanRepayment` | loan_id, amount, source, remaining_balance | Critical |
| `LoanFullyRepaid` | loan_id, borrower, total_principal, total_interest | Critical |
| `HarvestExecuted` | loan_id, rewards_claimed, applied_to_loan, keeper_tip | High |
| `CollateralWithdrawn` | loan_id, borrower, pass_id | High |
| `LoanLiquidated` | loan_id, borrower, liquidator, amount_paid | Critical |
| `LiquidityDeposited` | amount, depositor, new_balance | Medium |
| `LiquidityWithdrawn` | amount, recipient, new_balance | Medium |
| `VaultPaused` | paused, admin | High |

### 4.4 Event Schemas (TypeScript)

```typescript
// Core Events
interface DepositedEvent {
  listing_id: string;
  backer: string;
  amount: string;              // u64 as string
  shares: string;              // u128 as string
  pass_id: string;
  total_raised: string;
  total_passes: string;
  epoch: string;
}

interface ClaimedEvent {
  listing_id: string;
  pass_id: string;
  backer: string;
  amount: string;
  shares: string;
  old_claim_index: string;
  new_claim_index: string;
  epoch: string;
}

interface RouteInEvent {
  listing_id: string;
  source: string;
  amount: string;
  cumulative_distributed: string;
  new_global_index: string;
}

// Marketplace Events
interface SaleCompletedEvent {
  listing_id: string;          // SaleListing ID
  pass_id: string;
  seller: string;
  buyer: string;
  price: string;
  fee: string;
  epoch: string;
}

// Loans Events
interface LoanCreatedEvent {
  loan_id: string;
  borrower: string;
  pass_id: string;
  listing_id: string;
  principal: string;
  origination_fee: string;
  ltv_bps: string;
  epoch: string;
}

interface LoanRepaymentEvent {
  loan_id: string;
  amount: string;
  source: number;              // 0 = harvest, 1 = manual
  remaining_balance: string;
  epoch: string;
}
```

---

## 5. API Specification

### 5.1 REST API Endpoints

#### Listings

```
GET /api/v1/listings
  Query: ?state=active&page=1&limit=20
  Response: { listings: Listing[], total: number, page: number }

GET /api/v1/listings/:id
  Response: ListingDetails (includes vaults, stats)

GET /api/v1/listings/:id/backers
  Query: ?page=1&limit=50
  Response: { backers: BackerInfo[], total: number }

GET /api/v1/listings/:id/tranches
  Response: { tranches: TrancheInfo[], nextRelease: number | null }

GET /api/v1/listings/:id/rewards
  Response: { totalDistributed: number, recentPayments: RewardPayment[] }
```

#### Passes

```
GET /api/v1/passes
  Query: ?owner=0x...&listing_id=0x...&page=1&limit=20
  Response: { passes: SupporterPass[], total: number }

GET /api/v1/passes/:id
  Response: PassDetails (includes pending rewards, value estimate)

GET /api/v1/passes/:id/history
  Response: { events: PassEvent[], total: number }

GET /api/v1/passes/:id/pending-rewards
  Response: { amount: number, lastClaimed: number | null }
```

#### Marketplace

```
GET /api/v1/marketplace/listings
  Query: ?listing_id=0x...&sort=price_asc&page=1&limit=20
  Response: { listings: SaleListing[], total: number }

GET /api/v1/marketplace/listings/:id
  Response: SaleListingDetails (includes pass info, pending rewards)

GET /api/v1/marketplace/stats
  Response: MarketplaceStats

GET /api/v1/marketplace/history
  Query: ?listing_id=0x...&page=1&limit=50
  Response: { sales: SaleRecord[], total: number }

GET /api/v1/marketplace/floor-price/:listing_id
  Response: { floorPrice: number | null, activeListings: number }
```

#### Loans

```
GET /api/v1/loans
  Query: ?borrower=0x...&status=active&page=1&limit=20
  Response: { loans: LoanInfo[], total: number }

GET /api/v1/loans/:id
  Response: LoanDetails (includes health factor, pending rewards)

GET /api/v1/loans/vault
  Response: LoanVaultStats

GET /api/v1/loans/estimate
  Query: ?pass_id=0x...
  Response: { maxLoan: number, ltv: number, collateralValue: number }

GET /api/v1/loans/liquidatable
  Response: { loans: LiquidatableLoan[], total: number }
```

#### User

```
GET /api/v1/users/:address/portfolio
  Response: UserPortfolio (passes, loans, marketplace listings)

GET /api/v1/users/:address/rewards
  Response: RewardsSummary (pending, claimed, history)

GET /api/v1/users/:address/activity
  Query: ?type=all&page=1&limit=50
  Response: { activities: Activity[], total: number }
```

#### Stats

```
GET /api/v1/stats/protocol
  Response: ProtocolStats

GET /api/v1/stats/treasury
  Response: TreasuryStats
```

### 5.2 Response Types

```typescript
interface ListingDetails {
  listing: Listing;
  capitalVault: CapitalVault;
  rewardVault: RewardVault;
  stakingAdapter: StakingAdapter;
  
  // Computed
  stats: {
    totalBackers: number;
    totalRaised: number;
    totalReleased: number;
    totalDistributed: number;
    avgDeposit: number;
    currentApy: number | null;
  };
  
  // Schedule
  tranches: TrancheInfo[];
  nextRelease: {
    amount: number;
    time: number;
    index: number;
  } | null;
}

interface PassDetails {
  pass: SupporterPass;
  listing: Listing;
  
  // Computed
  pendingRewards: number;
  estimatedValue: number;      // Based on shares + pending
  sharePercentage: number;     // Share of total
  
  // Status
  isListed: boolean;           // On marketplace
  isCollateralized: boolean;   // In loan
  listingId?: string;          // SaleListing ID if listed
  loanId?: string;             // Loan ID if collateralized
}

interface LoanDetails {
  loan: Loan;
  receipt?: LoanReceipt;       // If owned by user
  pass: SupporterPass;
  
  // Computed
  outstanding: number;         // principal + interest - repaid
  healthFactor: number;        // collateral / outstanding
  collateralValue: number;
  pendingRewards: number;      // Available for harvest
  
  // Liquidation
  isLiquidatable: boolean;
  liquidationPrice: number;
}

interface UserPortfolio {
  address: string;
  
  // Holdings
  passes: PassDetails[];
  totalPassValue: number;
  totalPendingRewards: number;
  
  // Marketplace
  activeListings: SaleListing[];
  
  // Loans
  activeLoans: LoanDetails[];
  totalBorrowed: number;
  totalRepaid: number;
  
  // Stats
  totalClaimed: number;
  totalDeposited: number;
}

interface ProtocolStats {
  // Overview
  totalListings: number;
  activeListings: number;
  
  // Capital
  totalRaised: number;
  totalReleased: number;
  totalLocked: number;
  totalStaked: number;
  
  // Rewards
  totalDistributed: number;
  totalClaimed: number;
  
  // Marketplace
  totalVolume: number;
  totalMarketplaceFees: number;
  activeMarketplaceListings: number;
  
  // Loans
  totalBorrowed: number;
  totalRepaid: number;
  activeLoans: number;
  totalLoanFees: number;
  
  // Treasury
  treasuryBalance: number;
}
```

### 5.3 GraphQL Schema (Optional)

```graphql
type Query {
  listing(id: ID!): Listing
  listings(state: ListingState, first: Int, after: String): ListingConnection
  
  pass(id: ID!): SupporterPass
  passes(owner: String, listingId: ID, first: Int, after: String): PassConnection
  
  marketplaceListings(
    listingId: ID
    sort: MarketplaceSort
    first: Int
    after: String
  ): SaleListingConnection
  
  loans(borrower: String, status: LoanStatus, first: Int, after: String): LoanConnection
  loan(id: ID!): Loan
  
  user(address: String!): User
  protocolStats: ProtocolStats
}

type Subscription {
  newDeposit(listingId: ID): DepositEvent
  newClaim(passId: ID): ClaimEvent
  newSale(listingId: ID): SaleEvent
  loanUpdated(loanId: ID): LoanEvent
  rewardsRouted(listingId: ID): RouteEvent
}
```

---

## 6. User Flows

### 6.1 Backer Flow: Deposit

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User visits Listing Page                                     │
│    └─ Show: progress bar, stats, tranche schedule              │
│                                                                 │
│ 2. User connects wallet                                         │
│    └─ Check: has sufficient SUI balance                        │
│                                                                 │
│ 3. User enters deposit amount                                   │
│    └─ Show: estimated shares, share %                          │
│    └─ Validate: >= min_deposit (1 SUI)                         │
│                                                                 │
│ 4. User clicks "Deposit"                                        │
│    └─ Build PTB: listing::deposit()                            │
│    └─ Sign & execute                                           │
│                                                                 │
│ 5. Transaction confirmed                                        │
│    └─ Show: success modal with SupporterPass preview           │
│    └─ Update: user portfolio, listing stats                    │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Backer Flow: Claim Rewards

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User visits My Passes page                                   │
│    └─ Show: list of passes with pending rewards                │
│                                                                 │
│ 2. User selects pass(es) to claim                               │
│    └─ Show: total pending rewards                              │
│    └─ Option: "Claim All" for multiple passes                  │
│                                                                 │
│ 3. User clicks "Claim"                                          │
│    └─ If single: listing::claim()                              │
│    └─ If multiple: listing::claim_many()                       │
│                                                                 │
│ 4. Transaction confirmed                                        │
│    └─ Show: claimed amount                                     │
│    └─ Update: pass claim_index, total_claimed                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.3 Marketplace Flow: List Pass

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User visits My Passes page                                   │
│    └─ Show: "List for Sale" button on each pass                │
│                                                                 │
│ 2. User clicks "List for Sale"                                  │
│    └─ Show: pass details, pending rewards                      │
│    └─ Show: floor price, recent sales                          │
│                                                                 │
│ 3. User enters price                                            │
│    └─ Show: implied yield based on price                       │
│    └─ Show: 5% seller fee calculation                          │
│    └─ Show: net proceeds                                       │
│                                                                 │
│ 4. User clicks "List"                                           │
│    └─ Build PTB: marketplace::list_for_sale()                  │
│    └─ Sign & execute                                           │
│                                                                 │
│ 5. Transaction confirmed                                        │
│    └─ Show: listing confirmation                               │
│    └─ Update: marketplace listings                             │
└─────────────────────────────────────────────────────────────────┘
```

### 6.4 Marketplace Flow: Buy Pass

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User visits Marketplace                                      │
│    └─ Show: listings sorted by price, yield, etc.              │
│    └─ Filter: by Tide listing, price range                     │
│                                                                 │
│ 2. User clicks on listing                                       │
│    └─ Show: pass details, shares, pending rewards              │
│    └─ Show: seller, price, listing time                        │
│    └─ Show: estimated APY based on price                       │
│                                                                 │
│ 3. User clicks "Buy"                                            │
│    └─ Check: has sufficient SUI                                │
│    └─ Show: confirmation modal                                 │
│                                                                 │
│ 4. User confirms purchase                                       │
│    └─ Build PTB: marketplace::buy_and_take()                   │
│    └─ Sign & execute                                           │
│                                                                 │
│ 5. Transaction confirmed                                        │
│    └─ Show: success, pass transferred to buyer                 │
│    └─ Update: portfolio, marketplace stats                     │
└─────────────────────────────────────────────────────────────────┘
```

### 6.5 Loans Flow: Borrow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User visits Loans page or pass detail                        │
│    └─ Show: "Borrow" option for eligible passes                │
│    └─ Check: pass not listed, not already collateralized       │
│                                                                 │
│ 2. User clicks "Borrow"                                         │
│    └─ Show: collateral value (based on shares)                 │
│    └─ Show: max loan (50% LTV)                                 │
│    └─ Show: interest rate (5% APR)                             │
│    └─ Show: origination fee (1%)                               │
│                                                                 │
│ 3. User enters loan amount                                      │
│    └─ Validate: <= max loan, >= min loan (1 SUI)               │
│    └─ Show: net received after fee                             │
│    └─ Show: estimated monthly interest                         │
│                                                                 │
│ 4. User clicks "Borrow"                                         │
│    └─ Build PTB: loan_vault::borrow()                          │
│    └─ Sign & execute                                           │
│                                                                 │
│ 5. Transaction confirmed                                        │
│    └─ Show: loan created, SUI received                         │
│    └─ Show: LoanReceipt in portfolio                           │
│    └─ Update: loan dashboard                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 6.6 Loans Flow: Repay

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User visits My Loans                                         │
│    └─ Show: active loans with outstanding balance              │
│    └─ Show: health factor for each loan                        │
│                                                                 │
│ 2. User clicks on loan                                          │
│    └─ Show: principal, interest accrued, amount repaid         │
│    └─ Show: outstanding balance                                │
│    └─ Show: pending rewards (can auto-repay)                   │
│                                                                 │
│ 3. User chooses repayment option:                               │
│    Option A: Manual Repay                                       │
│    └─ Enter amount to repay                                    │
│    └─ Build PTB: loan_vault::repay()                           │
│                                                                 │
│    Option B: Harvest Rewards (keeper can also do this)         │
│    └─ Uses pending rewards to repay                            │
│    └─ Build PTB: loan_vault::harvest_and_repay()               │
│                                                                 │
│ 4. Transaction confirmed                                        │
│    └─ Show: repayment amount                                   │
│    └─ If fully repaid: show "Withdraw Collateral" button       │
└─────────────────────────────────────────────────────────────────┘
```

### 6.7 Loans Flow: Withdraw Collateral

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User has fully repaid loan                                   │
│    └─ Show: "Withdraw Collateral" button                       │
│                                                                 │
│ 2. User clicks "Withdraw"                                       │
│    └─ Build PTB: loan_vault::withdraw_collateral()             │
│    └─ Sign & execute                                           │
│                                                                 │
│ 3. Transaction confirmed                                        │
│    └─ Show: SupporterPass returned to wallet                   │
│    └─ Update: portfolio                                        │
│    └─ Loan removed from active loans                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. Screen Specifications

### 7.1 Home / Explore

**Purpose:** Browse active listings, protocol overview

**Components:**
- Protocol stats banner (TVL, distributed, backers)
- Active listings grid/list
- Featured listing card
- Recent activity feed

**Data Requirements:**
- GET /api/v1/listings?state=active
- GET /api/v1/stats/protocol

### 7.2 Listing Detail

**Purpose:** View listing details, deposit

**Components:**
- Listing header (name, issuer, status badge)
- Progress bar (raised / goal)
- Stats grid (backers, avg deposit, APY)
- Tranche schedule timeline
- Deposit form
- Recent deposits list
- Reward history chart

**Data Requirements:**
- GET /api/v1/listings/:id
- GET /api/v1/listings/:id/backers
- GET /api/v1/listings/:id/rewards

### 7.3 My Passes (Portfolio)

**Purpose:** View owned passes, claim rewards

**Components:**
- Portfolio summary (total value, pending rewards)
- Pass grid/list with:
  - Pass image/number
  - Shares
  - Pending rewards
  - Quick actions (Claim, List, Borrow)
- Claim All button
- Activity history

**Data Requirements:**
- GET /api/v1/passes?owner={address}
- GET /api/v1/users/:address/portfolio

### 7.4 Pass Detail

**Purpose:** View pass details, actions

**Components:**
- Pass preview (NFT-style)
- Metadata (pass_number, original_backer, total_claimed)
- Pending rewards
- Share info (% of total, value estimate)
- Action buttons:
  - Claim Rewards
  - List for Sale
  - Borrow Against
- Transaction history

**Data Requirements:**
- GET /api/v1/passes/:id
- GET /api/v1/passes/:id/history

### 7.5 Marketplace

**Purpose:** Browse and buy SupporterPasses

**Components:**
- Stats bar (volume, floor, active listings)
- Filter/sort controls:
  - By Tide listing
  - Price range
  - Sort: price, shares, yield
- Listing grid/table:
  - Pass preview
  - Shares
  - Price
  - Implied yield
  - Pending rewards
  - Buy button
- Recent sales

**Data Requirements:**
- GET /api/v1/marketplace/listings
- GET /api/v1/marketplace/stats
- GET /api/v1/marketplace/history

### 7.6 Marketplace Listing Detail

**Purpose:** View listing, buy pass

**Components:**
- Pass preview (large)
- Price, shares, implied yield
- Seller address
- Pending rewards note
- Price chart (if history available)
- Buy button
- Similar listings

**Data Requirements:**
- GET /api/v1/marketplace/listings/:id

### 7.7 Loans Dashboard

**Purpose:** Manage loans

**Components:**
- Loan vault stats (liquidity, utilization, rates)
- My active loans:
  - Pass info
  - Outstanding balance
  - Health factor indicator
  - Action buttons
- Borrow CTA (select pass)
- Repayment calculator

**Data Requirements:**
- GET /api/v1/loans?borrower={address}
- GET /api/v1/loans/vault
- GET /api/v1/passes?owner={address}

### 7.8 Loan Detail

**Purpose:** View/manage specific loan

**Components:**
- Collateral (pass) preview
- Loan metrics:
  - Principal
  - Interest accrued
  - Amount repaid
  - Outstanding
  - Health factor
- Pending rewards (harvestable)
- Actions:
  - Repay (manual)
  - Harvest & Repay
  - Withdraw Collateral (if repaid)
- Loan history

**Data Requirements:**
- GET /api/v1/loans/:id

---

## 8. Real-Time Updates

### 8.1 WebSocket Events

```typescript
// Subscribe to events
ws.send(JSON.stringify({
  type: 'subscribe',
  channels: [
    'listing:0x...',        // Listing updates
    'pass:0x...',           // Pass updates
    'user:0x...',           // User activity
    'marketplace',          // All marketplace activity
    'loans',                // All loan activity
  ]
}));

// Event types
interface WSEvent {
  type: 'deposit' | 'claim' | 'route' | 'sale' | 'loan_created' | 'loan_repaid';
  data: any;
  timestamp: number;
}
```

### 8.2 Polling Fallback

For clients without WebSocket:

| Endpoint | Poll Interval | Trigger |
|----------|---------------|---------|
| Pending rewards | 30s | Pass detail view |
| Loan health | 30s | Loans dashboard |
| Marketplace floor | 60s | Marketplace view |
| Protocol stats | 60s | Home page |

### 8.3 Optimistic Updates

Show optimistic UI updates for:
- Deposit confirmation (show pass immediately)
- Claim confirmation (reset pending to 0)
- Marketplace listing (show in listings)
- Loan repayment (update outstanding)

Revert on transaction failure.

---

## 9. Wallet Integration

### 9.1 Supported Wallets

- Sui Wallet
- Suiet
- Ethos
- Martian
- OKX Wallet

### 9.2 Transaction Building

```typescript
import { Transaction } from '@mysten/sui/transactions';

// Deposit example
async function buildDepositTx(
  packageId: string,
  listingId: string,
  tideId: string,
  capitalVaultId: string,
  rewardVaultId: string,
  amount: bigint
) {
  const tx = new Transaction();
  
  const [depositCoin] = tx.splitCoins(tx.gas, [amount]);
  
  const [pass] = tx.moveCall({
    target: `${packageId}::listing::deposit`,
    arguments: [
      tx.object(listingId),
      tx.object(tideId),
      tx.object(capitalVaultId),
      tx.object(rewardVaultId),
      depositCoin,
      tx.object('0x6'), // Clock
    ],
  });
  
  tx.transferObjects([pass], tx.pure.address(userAddress));
  
  return tx;
}

// Claim example
async function buildClaimTx(
  packageId: string,
  listingId: string,
  tideId: string,
  rewardVaultId: string,
  passId: string
) {
  const tx = new Transaction();
  
  const [reward] = tx.moveCall({
    target: `${packageId}::listing::claim`,
    arguments: [
      tx.object(listingId),
      tx.object(tideId),
      tx.object(rewardVaultId),
      tx.object(passId),
    ],
  });
  
  tx.transferObjects([reward], tx.pure.address(userAddress));
  
  return tx;
}

// Marketplace buy example
async function buildBuyTx(
  marketplacePackageId: string,
  configId: string,
  treasuryVaultId: string,
  saleListingId: string,
  price: bigint
) {
  const tx = new Transaction();
  
  const [paymentCoin] = tx.splitCoins(tx.gas, [price]);
  
  tx.moveCall({
    target: `${marketplacePackageId}::marketplace::buy_and_take`,
    arguments: [
      tx.object(configId),
      tx.object(treasuryVaultId),
      tx.object(saleListingId),
      paymentCoin,
    ],
  });
  
  return tx;
}

// Borrow example
async function buildBorrowTx(
  loansPackageId: string,
  loanVaultId: string,
  listingId: string,
  tideId: string,
  capitalVaultId: string,
  passId: string,
  loanAmount: bigint
) {
  const tx = new Transaction();
  
  const [receipt, loanCoin] = tx.moveCall({
    target: `${loansPackageId}::loan_vault::borrow`,
    arguments: [
      tx.object(loanVaultId),
      tx.object(listingId),
      tx.object(tideId),
      tx.object(capitalVaultId),
      tx.object(passId),
      tx.pure.u64(loanAmount),
    ],
  });
  
  tx.transferObjects([receipt, loanCoin], tx.pure.address(userAddress));
  
  return tx;
}
```

---

## 10. Error Handling

### 10.1 Transaction Errors

| Error Code | Module | Meaning | User Message |
|------------|--------|---------|--------------|
| 0 | errors | EPAUSED | Protocol is paused |
| 1 | errors | ENOT_ACTIVE | Listing not accepting deposits |
| 2 | errors | EINVALID_STATE | Invalid operation for current state |
| 3 | errors | ENOTHING_TO_CLAIM | No rewards to claim |
| 4 | errors | ENotAValidator | Invalid validator address |
| 5 | errors | EUNAUTHORIZED | Unauthorized action |
| 14 | errors | EBELOW_MINIMUM | Deposit below minimum |
| 15 | errors | ENOT_CANCELLED | Refund only for cancelled listings |

### 10.2 Marketplace Errors

| Error Code | Meaning | User Message |
|------------|---------|--------------|
| 0 | EMarketplacePaused | Marketplace is paused |
| 1 | ENotSeller | Not your listing |
| 2 | EInsufficientPayment | Insufficient payment |
| 3 | EZeroPrice | Price must be > 0 |
| 4 | EBelowMinimum | Price below minimum |

### 10.3 Loans Errors

| Error Code | Meaning | User Message |
|------------|---------|--------------|
| 0 | ELoanVaultPaused | Loan vault is paused |
| 1 | EExceedsMaxLTV | Loan exceeds max LTV |
| 2 | EInsufficientLiquidity | Insufficient liquidity |
| 3 | ELoanNotActive | Loan is not active |
| 4 | ELoanNotRepaid | Loan not fully repaid |
| 5 | ENotBorrower | Not the borrower |
| 6 | ELoanHealthy | Loan is healthy (can't liquidate) |
| 7 | EInsufficientPayment | Payment too low |
| 8 | EBelowMinLoan | Loan below minimum |
| 9 | EZeroAmount | Amount must be > 0 |

### 10.3 Error Display

```typescript
function getErrorMessage(error: MoveError): string {
  const errorMap: Record<string, string> = {
    'tide_core::errors::EPAUSED': 'Protocol is temporarily paused',
    'tide_core::errors::ENOT_ACTIVE': 'Listing is not accepting deposits',
    'tide_core::errors::ENOTHING_TO_CLAIM': 'No rewards available to claim',
    'tide_core::errors::EBELOW_MINIMUM': 'Deposit must be at least 1 SUI',
    'tide_marketplace::marketplace::EMarketplacePaused': 'Marketplace is paused',
    'tide_loans::loan_vault::EExceedsMaxLTV': 'Loan exceeds maximum allowed',
    // ...
  };
  
  return errorMap[error.code] || 'Transaction failed. Please try again.';
}
```

---

## 11. Security Considerations

### 11.1 Frontend Security

- **Input validation:** Validate all amounts before transaction
- **Address validation:** Verify addresses are valid Sui addresses
- **Amount limits:** Enforce reasonable min/max amounts
- **Confirmation modals:** Require confirmation for high-value actions

### 11.2 API Security

- **Rate limiting:** Limit requests per IP/user
- **Input sanitization:** Sanitize all query parameters
- **CORS:** Restrict to known origins
- **Authentication:** (Optional) JWT for user-specific endpoints

### 11.3 Transaction Security

- **Simulation:** Simulate transactions before signing
- **Gas estimation:** Show estimated gas to user
- **Object verification:** Verify object types before operations
- **Fresh data:** Fetch fresh data before critical transactions

### 11.4 Display Considerations

- **MIST to SUI:** Always display SUI (1 SUI = 10^9 MIST)
- **Large numbers:** Format with thousands separators
- **Shares:** Display as percentage when appropriate
- **Addresses:** Truncate with ellipsis (0x1234...abcd)
- **Timestamps:** Show relative time (2h ago) + absolute on hover

---

## 12. Constants Reference

```typescript
const CONSTANTS = {
  // Network
  NETWORK: 'testnet', // or 'mainnet'
  
  // Amounts
  MIST_PER_SUI: 1_000_000_000n,
  MIN_DEPOSIT: 1_000_000_000n, // 1 SUI
  
  // Fees (basis points)
  BPS_DENOMINATOR: 10_000,
  RAISE_FEE_BPS: 100,           // 1%
  STAKING_BACKER_BPS: 8_000,    // 80%
  STAKING_TREASURY_BPS: 2_000,  // 20%
  MARKETPLACE_FEE_BPS: 500,     // 5%
  
  // Loans
  MAX_LTV_BPS: 5_000,           // 50%
  LIQUIDATION_THRESHOLD_BPS: 7_500, // 75%
  INTEREST_RATE_BPS: 500,       // 5% APR
  ORIGINATION_FEE_BPS: 100,     // 1%
  LIQUIDATION_FEE_BPS: 500,     // 5%
  KEEPER_TIP_BPS: 10,           // 0.1%
  
  // Lifecycle states
  STATE_DRAFT: 0,
  STATE_ACTIVE: 1,
  STATE_FINALIZED: 2,
  STATE_COMPLETED: 3,
  STATE_CANCELLED: 4,
  
  // Loan statuses
  LOAN_ACTIVE: 0,
  LOAN_REPAID: 1,
  LOAN_LIQUIDATED: 2,
  
  // Time
  MS_PER_YEAR: 31_536_000_000,
  SECONDS_PER_MONTH: 2_592_000,
  
  // System objects
  CLOCK_ID: '0x6',
  SYSTEM_STATE_ID: '0x5',
};
```

---

## 13. Package IDs (To Be Updated After Deployment)

```typescript
const PACKAGE_IDS = {
  testnet: {
    tide_core: '0x...', // Update after deploy
    faith_router: '0x...',
    tide_marketplace: '0x...',
    tide_loans: '0x...',
  },
  mainnet: {
    tide_core: '0x...',
    faith_router: '0x...',
    tide_marketplace: '0x...',
    tide_loans: '0x...',
  },
};

const SHARED_OBJECTS = {
  testnet: {
    tide: '0x...',
    registry: '0x...',
    treasury_vault: '0x...',
    marketplace_config: '0x...',
    loan_vault: '0x...',
    // Listing-specific
    faith_listing: '0x...',
    faith_capital_vault: '0x...',
    faith_reward_vault: '0x...',
    faith_staking_adapter: '0x...',
    faith_router: '0x...',
  },
  mainnet: {
    // ...
  },
};
```

---

## 14. SupporterPass API & Display

### 14.1 Minting (via Deposit)

SupporterPasses are **NOT minted directly** - they are created when a user deposits SUI into an active listing via `listing::deposit()`. The mint happens atomically with the deposit.

**Minting Flow:**
```
User deposits SUI → listing::deposit() → SupporterPass created → Transferred to user
```

**API Endpoint for Deposit/Mint:**

```
POST /api/v1/listings/:id/deposit
  Body: { amount: string }
  Response: {
    transaction: {
      packageId: string,
      target: string,
      arguments: TransactionArgument[]
    },
    estimatedShares: string,
    estimatedGas: string
  }
```

This endpoint returns the transaction data needed for the frontend to build and sign the deposit PTB.

### 14.2 Display Configuration

SupporterPass uses Sui's `Display` standard. There is **ONE global Display** for the `SupporterPass` type, which uses placeholder fields for multi-listing support.

**Display Fields:**

| Field | Template | Description |
|-------|----------|-------------|
| `name` | `"Tide Supporter Pass"` | Generic name |
| `description` | `"A transferable position representing {shares} shares..."` | Uses `{shares}` placeholder |
| `image_url` | `"https://api.tide.am/pass/{listing_id}/{id}/image.svg"` | Dynamic image |
| `link` | `"https://app.tide.am/listing/{listing_id}/pass/{id}"` | Link to app |
| `project_url` | `"https://tide.am"` | Project homepage |

**Sui Display Placeholders:**
- `{id}` → Object ID of the SupporterPass
- `{listing_id}` → Listing this pass belongs to
- `{shares}` → Number of shares (u128)

### 14.3 Display Setup Script

Run this after deploying `tide_core`:

```bash
# Setup Display for SupporterPass (requires Publisher object)
sui client ptb \
  --assign pkg @$PKG \
  --assign publisher @$PUBLISHER_ID \
  --move-call "pkg::display::create_and_keep_supporter_pass_display" publisher \
  --gas-budget 50000000
```

**Record:** The `Display<SupporterPass>` object ID for future updates.

### 14.4 Update Display URLs

```bash
# Update image URL
sui client ptb \
  --assign pkg @$PKG \
  --assign display @$DISPLAY_ID \
  --move-call "pkg::display::update_image_url" display "b\"https://new-api.tide.am/pass/{listing_id}/{id}/image.svg\"" \
  --gas-budget 50000000

# Update link
sui client ptb \
  --assign pkg @$PKG \
  --assign display @$DISPLAY_ID \
  --move-call "pkg::display::update_link" display "b\"https://new-app.tide.am/listing/{listing_id}/pass/{id}\"" \
  --gas-budget 50000000
```

### 14.5 Image Rendering API

The `image_url` field points to your rendering API. This API must:

1. Parse `listing_id` and `pass_id` from URL
2. Fetch listing metadata (name, issuer, branding)
3. Fetch pass data (shares, pass_number, original_backer, total_claimed)
4. Render SVG with dynamic data

**Endpoint:**

```
GET /api/v1/pass/{listing_id}/{pass_id}/image.svg
  Response: image/svg+xml

GET /api/v1/pass/{listing_id}/{pass_id}/image.png
  Response: image/png (rasterized)
```

**SVG Template Data:**

```typescript
interface PassImageData {
  // Listing info
  listingName: string;           // e.g., "FAITH Expansion Fund"
  listingNumber: number;         // e.g., 1
  issuerName: string;            // e.g., "FAITH Protocol"
  brandColor: string;            // e.g., "#6366f1"
  
  // Pass info
  passId: string;
  passNumber: number;            // e.g., 42
  shares: string;                // e.g., "1000000000000" (formatted as "1,000 SUI")
  sharePercentage: string;       // e.g., "0.05%"
  
  // Provenance
  originalBacker: string;        // Truncated address
  totalClaimed: string;          // Formatted SUI amount
  
  // Status
  isOriginalOwner: boolean;      // For badge
  tier?: 'bronze' | 'silver' | 'gold' | 'platinum'; // Based on shares
}
```

**Example SVG Structure:**

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 500">
  <!-- Background gradient based on brandColor -->
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#1a1a2e"/>
      <stop offset="100%" style="stop-color:#16213e"/>
    </linearGradient>
  </defs>
  <rect width="400" height="500" fill="url(#bg)" rx="20"/>
  
  <!-- Logo / Branding -->
  <text x="30" y="50" fill="#fff" font-size="24" font-weight="bold">
    {{listingName}}
  </text>
  
  <!-- Pass Number Badge -->
  <circle cx="350" cy="50" r="30" fill="{{brandColor}}"/>
  <text x="350" y="55" fill="#fff" text-anchor="middle" font-size="18">
    #{{passNumber}}
  </text>
  
  <!-- Shares Display -->
  <text x="200" y="200" fill="#fff" text-anchor="middle" font-size="48" font-weight="bold">
    {{formattedShares}} SUI
  </text>
  <text x="200" y="240" fill="#888" text-anchor="middle" font-size="18">
    {{sharePercentage}} of pool
  </text>
  
  <!-- Tier Badge (if applicable) -->
  <rect x="150" y="280" width="100" height="30" rx="15" fill="{{tierColor}}"/>
  <text x="200" y="300" fill="#fff" text-anchor="middle" font-size="14">
    {{tier}}
  </text>
  
  <!-- Stats -->
  <text x="30" y="400" fill="#888" font-size="14">Total Claimed</text>
  <text x="30" y="420" fill="#fff" font-size="18">{{totalClaimed}} SUI</text>
  
  <text x="30" y="460" fill="#888" font-size="14">Original Backer</text>
  <text x="30" y="480" fill="#fff" font-size="16">{{originalBacker}}</text>
  
  <!-- Original Owner Badge -->
  {{#if isOriginalOwner}}
  <rect x="280" y="450" width="90" height="25" rx="12" fill="#22c55e"/>
  <text x="325" y="467" fill="#fff" text-anchor="middle" font-size="11">ORIGINAL</text>
  {{/if}}
</svg>
```

### 14.6 Metadata API

Standard NFT metadata endpoint:

```
GET /api/v1/pass/{listing_id}/{pass_id}/metadata.json
  Response: {
    name: "FAITH Supporter Pass #42",
    description: "A transferable position representing 1,000 SUI worth of shares in the FAITH Expansion Fund. Entitles holder to claim rewards from protocol revenue and staking yield.",
    image: "https://api.tide.am/pass/{listing_id}/{pass_id}/image.svg",
    external_url: "https://app.tide.am/listing/{listing_id}/pass/{pass_id}",
    attributes: [
      { trait_type: "Listing", value: "FAITH Expansion Fund" },
      { trait_type: "Pass Number", value: 42 },
      { trait_type: "Shares", value: "1000000000000" },
      { trait_type: "Share Percentage", value: "0.05%" },
      { trait_type: "Original Backer", value: "0x1234...abcd" },
      { trait_type: "Total Claimed", value: "25.5 SUI" },
      { trait_type: "Tier", value: "Silver" }
    ]
  }
```

### 14.7 Listing Metadata API

For rendering, you need listing-specific metadata:

```
GET /api/v1/listings/{listing_id}/metadata
  Response: {
    id: string,
    number: number,
    name: string,
    issuer: {
      name: string,
      address: string,
      logo: string,
      website: string
    },
    branding: {
      primaryColor: string,
      secondaryColor: string,
      logo: string,
      backgroundImage?: string
    },
    description: string,
    created_at: string
  }
```

This is stored off-chain (in your database) and linked to the on-chain listing_id.

### 14.8 Tier System (Optional)

Define tiers based on share amount:

```typescript
const SHARE_TIERS = {
  platinum: 100_000_000_000_000n,  // 100,000+ SUI worth
  gold: 10_000_000_000_000n,       // 10,000+ SUI worth
  silver: 1_000_000_000_000n,      // 1,000+ SUI worth
  bronze: 0n,                       // Any amount
};

function getTier(shares: bigint): string {
  if (shares >= SHARE_TIERS.platinum) return 'platinum';
  if (shares >= SHARE_TIERS.gold) return 'gold';
  if (shares >= SHARE_TIERS.silver) return 'silver';
  return 'bronze';
}

const TIER_COLORS = {
  platinum: '#e5e4e2',
  gold: '#ffd700',
  silver: '#c0c0c0',
  bronze: '#cd7f32',
};
```

### 14.9 Pass Endpoints Summary

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/pass/{listing_id}/{pass_id}/image.svg` | GET | Dynamic SVG image |
| `/api/v1/pass/{listing_id}/{pass_id}/image.png` | GET | Rasterized PNG (for social) |
| `/api/v1/pass/{listing_id}/{pass_id}/metadata.json` | GET | NFT metadata |
| `/api/v1/passes` | GET | List passes (with filters) |
| `/api/v1/passes/{id}` | GET | Pass details with computed values |
| `/api/v1/passes/{id}/pending-rewards` | GET | Current pending rewards |
| `/api/v1/passes/{id}/history` | GET | Transaction history |

---

## Appendix A: Indexer Schema

### PostgreSQL Tables

```sql
-- Listings
CREATE TABLE listings (
  id TEXT PRIMARY KEY,
  listing_number INTEGER NOT NULL,
  issuer TEXT NOT NULL,
  state INTEGER NOT NULL DEFAULT 0,
  paused BOOLEAN NOT NULL DEFAULT false,
  capital_vault_id TEXT NOT NULL,
  reward_vault_id TEXT NOT NULL,
  staking_adapter_id TEXT NOT NULL,
  min_deposit BIGINT NOT NULL,
  raise_fee_bps INTEGER NOT NULL,
  staking_backer_bps INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Capital Vaults
CREATE TABLE capital_vaults (
  id TEXT PRIMARY KEY,
  listing_id TEXT NOT NULL REFERENCES listings(id),
  total_raised BIGINT NOT NULL DEFAULT 0,
  total_released BIGINT NOT NULL DEFAULT 0,
  balance BIGINT NOT NULL DEFAULT 0,
  total_backers INTEGER NOT NULL DEFAULT 0,
  total_shares TEXT NOT NULL DEFAULT '0',
  raise_fee_collected BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Reward Vaults
CREATE TABLE reward_vaults (
  id TEXT PRIMARY KEY,
  listing_id TEXT NOT NULL REFERENCES listings(id),
  total_shares TEXT NOT NULL DEFAULT '0',
  global_reward_index TEXT NOT NULL DEFAULT '0',
  cumulative_distributed BIGINT NOT NULL DEFAULT 0,
  balance BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Supporter Passes
CREATE TABLE supporter_passes (
  id TEXT PRIMARY KEY,
  listing_id TEXT NOT NULL REFERENCES listings(id),
  owner TEXT NOT NULL,
  shares TEXT NOT NULL,
  claim_index TEXT NOT NULL DEFAULT '0',
  pass_number INTEGER NOT NULL,
  original_backer TEXT NOT NULL,
  total_claimed BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_passes_owner ON supporter_passes(owner);
CREATE INDEX idx_passes_listing ON supporter_passes(listing_id);

-- Tranches
CREATE TABLE tranches (
  id SERIAL PRIMARY KEY,
  listing_id TEXT NOT NULL REFERENCES listings(id),
  index INTEGER NOT NULL,
  amount BIGINT NOT NULL,
  release_time BIGINT NOT NULL,
  released BOOLEAN NOT NULL DEFAULT false,
  released_at TIMESTAMPTZ,
  UNIQUE(listing_id, index)
);

-- Deposits
CREATE TABLE deposits (
  id SERIAL PRIMARY KEY,
  tx_digest TEXT NOT NULL,
  listing_id TEXT NOT NULL REFERENCES listings(id),
  backer TEXT NOT NULL,
  amount BIGINT NOT NULL,
  shares TEXT NOT NULL,
  pass_id TEXT NOT NULL,
  epoch BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_deposits_listing ON deposits(listing_id);
CREATE INDEX idx_deposits_backer ON deposits(backer);

-- Claims
CREATE TABLE claims (
  id SERIAL PRIMARY KEY,
  tx_digest TEXT NOT NULL,
  listing_id TEXT NOT NULL REFERENCES listings(id),
  pass_id TEXT NOT NULL,
  backer TEXT NOT NULL,
  amount BIGINT NOT NULL,
  epoch BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_claims_pass ON claims(pass_id);
CREATE INDEX idx_claims_backer ON claims(backer);

-- Revenue Routes
CREATE TABLE revenue_routes (
  id SERIAL PRIMARY KEY,
  tx_digest TEXT NOT NULL,
  listing_id TEXT NOT NULL REFERENCES listings(id),
  source TEXT NOT NULL,
  amount BIGINT NOT NULL,
  new_global_index TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Marketplace Sales
CREATE TABLE marketplace_listings (
  id TEXT PRIMARY KEY,
  seller TEXT NOT NULL,
  pass_id TEXT NOT NULL,
  tide_listing_id TEXT NOT NULL,
  shares TEXT NOT NULL,
  price BIGINT NOT NULL,
  listed_at_epoch BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mkt_listings_seller ON marketplace_listings(seller);
CREATE INDEX idx_mkt_listings_tide ON marketplace_listings(tide_listing_id);
CREATE INDEX idx_mkt_listings_status ON marketplace_listings(status);

CREATE TABLE marketplace_sales (
  id SERIAL PRIMARY KEY,
  tx_digest TEXT NOT NULL,
  listing_id TEXT NOT NULL,
  pass_id TEXT NOT NULL,
  seller TEXT NOT NULL,
  buyer TEXT NOT NULL,
  price BIGINT NOT NULL,
  fee BIGINT NOT NULL,
  epoch BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Loans
CREATE TABLE loans (
  id TEXT PRIMARY KEY,
  borrower TEXT NOT NULL,
  pass_id TEXT NOT NULL,
  listing_id TEXT NOT NULL,
  principal BIGINT NOT NULL,
  interest_accrued BIGINT NOT NULL DEFAULT 0,
  amount_repaid BIGINT NOT NULL DEFAULT 0,
  status INTEGER NOT NULL DEFAULT 0,
  created_at_ms BIGINT NOT NULL,
  last_update_ms BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_loans_borrower ON loans(borrower);
CREATE INDEX idx_loans_status ON loans(status);

CREATE TABLE loan_repayments (
  id SERIAL PRIMARY KEY,
  tx_digest TEXT NOT NULL,
  loan_id TEXT NOT NULL REFERENCES loans(id),
  amount BIGINT NOT NULL,
  source INTEGER NOT NULL,
  remaining_balance BIGINT NOT NULL,
  epoch BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Protocol Stats (materialized/cached)
CREATE TABLE protocol_stats (
  id INTEGER PRIMARY KEY DEFAULT 1,
  total_listings INTEGER NOT NULL DEFAULT 0,
  active_listings INTEGER NOT NULL DEFAULT 0,
  total_raised BIGINT NOT NULL DEFAULT 0,
  total_released BIGINT NOT NULL DEFAULT 0,
  total_distributed BIGINT NOT NULL DEFAULT 0,
  total_marketplace_volume BIGINT NOT NULL DEFAULT 0,
  total_borrowed BIGINT NOT NULL DEFAULT 0,
  treasury_balance BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## Appendix B: Calculations

### Pending Rewards

```typescript
function calculatePendingRewards(
  passShares: bigint,
  passClaimIndex: bigint,
  globalRewardIndex: bigint
): bigint {
  if (globalRewardIndex <= passClaimIndex) {
    return 0n;
  }
  
  const indexDelta = globalRewardIndex - passClaimIndex;
  return (passShares * indexDelta) / PRECISION;
}

const PRECISION = 1_000_000_000_000n; // 10^12
```

### Implied Yield (Marketplace)

```typescript
function calculateImpliedYield(
  price: bigint,
  annualRevenueEstimate: bigint,
  shares: bigint,
  totalShares: bigint
): number {
  // Share of annual revenue
  const annualShareRevenue = (annualRevenueEstimate * shares) / totalShares;
  
  // APY = (annual revenue / price) * 100
  return Number((annualShareRevenue * 10000n) / price) / 100;
}
```

### Loan Health Factor

```typescript
function calculateHealthFactor(
  collateralValue: bigint,
  outstanding: bigint,
  liquidationThresholdBps: bigint
): number {
  if (outstanding === 0n) {
    return Infinity;
  }
  
  // health = (collateral * threshold) / outstanding
  const numerator = collateralValue * liquidationThresholdBps;
  const denominator = outstanding * 10000n;
  
  return Number(numerator * 100n / denominator) / 100;
}
```

### Collateral Value (for Loans)

```typescript
function calculateCollateralValue(
  passShares: bigint,
  totalShares: bigint,
  totalPrincipal: bigint
): bigint {
  // Conservative: use original deposit proportion
  return (totalPrincipal * passShares) / totalShares;
}
```

---

## Appendix C: Display Utilities

```typescript
// Format SUI amount
function formatSui(mist: bigint, decimals = 2): string {
  const sui = Number(mist) / 1e9;
  return sui.toLocaleString(undefined, {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}

// Format large numbers
function formatNumber(n: number): string {
  if (n >= 1_000_000) {
    return (n / 1_000_000).toFixed(2) + 'M';
  }
  if (n >= 1_000) {
    return (n / 1_000).toFixed(2) + 'K';
  }
  return n.toFixed(2);
}

// Format address
function formatAddress(address: string, chars = 4): string {
  return `${address.slice(0, chars + 2)}...${address.slice(-chars)}`;
}

// Format percentage
function formatPercent(bps: number): string {
  return (bps / 100).toFixed(2) + '%';
}

// Format relative time
function formatRelativeTime(timestamp: number): string {
  const now = Date.now();
  const diff = now - timestamp;
  
  if (diff < 60_000) return 'Just now';
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h ago`;
  if (diff < 604_800_000) return `${Math.floor(diff / 86_400_000)}d ago`;
  
  return new Date(timestamp).toLocaleDateString();
}

// Format countdown
function formatCountdown(targetMs: number): string {
  const now = Date.now();
  const diff = targetMs - now;
  
  if (diff <= 0) return 'Now';
  
  const days = Math.floor(diff / 86_400_000);
  const hours = Math.floor((diff % 86_400_000) / 3_600_000);
  const minutes = Math.floor((diff % 3_600_000) / 60_000);
  
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}
```

---

*End of Frontend Specification*
