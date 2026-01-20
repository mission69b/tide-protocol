# Tide Protocol Deployment Guide

Complete deployment and operations guide for Tide Protocol v1.

---

## Table of Contents

1. [Environment Strategy](#environment-strategy)
2. [Prerequisites](#prerequisites)
3. [Wallet Setup](#step-1-wallet-setup)
4. [Environment Configuration](#step-2-environment-configuration)
5. [Deploy tide_core Package](#step-3-deploy-tide_core-package)
6. [Deploy faith_router Package](#step-4-deploy-faith_router-package)
7. [Deploy tide_marketplace Package](#step-5-deploy-tide_marketplace-package)
8. [Deploy tide_loans Package](#step-6-deploy-tide_loans-package)
9. [Setup SupporterPass Display](#step-7-setup-supporterpass-display)
10. [Initialize FAITH Listing](#step-8-initialize-faith-listing)
11. [Transfer Capabilities](#step-9-transfer-capabilities)
12. [Verification](#step-10-verification)
13. [Operations Guide](#operations-guide)
14. [Emergency Procedures](#emergency-procedures)
15. [Deployment Checklist](#deployment-checklist)

---

## Environment Strategy

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Development   │───▶│     Testnet     │───▶│     Mainnet     │
│   (local)       │    │   (staging)     │    │   (production)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
       │                       │                       │
   sui move test          Deploy & test          Final deploy
   Local devnet           with test SUI          with real SUI
```

| Environment | Network | Purpose | SUI |
|-------------|---------|---------|-----|
| Development | Local devnet | Unit tests, rapid iteration | Fake |
| Testnet | Sui Testnet | Integration testing, staging | Test SUI (faucet) |
| Mainnet | Sui Mainnet | Production | Real SUI |

---

## Prerequisites

1. **Sui CLI installed** (v1.60.0 or compatible)
   ```bash
   sui --version
   ```

2. **Active Sui wallet**
   ```bash
   sui client active-address
   ```

3. **All tests passing**
   ```bash
   cd contracts/core && sui move test
   cd ../adapters/faith_router && sui move test
   cd ../../marketplace && sui move test
   cd ../loans && sui move test
   ```

---

## Step 1: Wallet Setup

### 1.1 Create Deployer Wallet

```bash
# Create new keypair for deployment
sui keytool generate ed25519

# Import to Sui client
sui keytool import "word1 word2 ... word12" ed25519

# Set as active
sui client switch --address 0x1234...
```

⚠️ **CRITICAL:** Save the recovery phrase securely!

### 1.2 Create Council Multisig (Recommended for Production)

```bash
# Generate council member keys
sui keytool generate ed25519  # Council member 1
sui keytool generate ed25519  # Council member 2
sui keytool generate ed25519  # Council member 3

# Create multisig address (2-of-3 example)
sui keytool multi-sig-address \
  --pks <pk1> <pk2> <pk3> \
  --weights 1 1 1 \
  --threshold 2
```

---

## Step 2: Environment Configuration

### 2.1 Network Configuration

```bash
# Switch to testnet
sui client switch --env testnet

# Or mainnet
sui client switch --env mainnet
```

### 2.2 Fund Deployer Wallet

**Testnet:**
```bash
sui client faucet
```

**Mainnet:** Transfer ~2 SUI for deployment gas.

---

## Step 3: Deploy tide_core Package

### 3.1 Build and Publish

```bash
cd contracts/core
sui move build
sui client publish --gas-budget 500000000
```

### 3.2 Record Object IDs

After publishing, record these objects:
- `PACKAGE_ID` (tide_core)
- `TIDE` (Tide shared object)
- `REGISTRY` (ListingRegistry)
- `COUNCIL_CONFIG` (CouncilConfig)
- `ADMIN_CAP` (AdminCap - owned)
- `COUNCIL_CAP` (CouncilCap - owned)
- `TREASURY_VAULT` (TreasuryVault - shared)
- `UPGRADE_CAP` (UpgradeCap - owned)

### 3.3 Update Move.toml

```toml
published-at = "0x<PACKAGE_ID>"

[addresses]
tide_core = "0x<PACKAGE_ID>"
```

---

## Step 4: Deploy faith_router Package

### 4.1 Build and Publish

```bash
cd contracts/adapters/faith_router
sui move build
sui client publish --gas-budget 200000000
```

### 4.2 Record Object IDs

- `FAITH_PACKAGE_ID`
- `UPGRADE_CAP`

### 4.3 Update Move.toml

```toml
published-at = "0x<FAITH_PACKAGE_ID>"

[addresses]
faith_router = "0x<FAITH_PACKAGE_ID>"
```

---

## Step 5: Deploy tide_marketplace Package

### 5.1 Build and Publish

```bash
cd contracts/marketplace
sui move build
sui client publish --gas-budget 200000000
```

### 5.2 Record Object IDs

- `MARKETPLACE_PACKAGE_ID`
- `MARKETPLACE_CONFIG` (MarketplaceConfig - shared)
- `UPGRADE_CAP`

### 5.3 Update Move.toml

```toml
published-at = "0x<MARKETPLACE_PACKAGE_ID>"

[addresses]
tide_marketplace = "0x<MARKETPLACE_PACKAGE_ID>"
```

---

## Step 6: Deploy tide_loans Package

### 6.1 Build and Publish

```bash
cd contracts/loans
sui move build
sui client publish --gas-budget 200000000
```

### 6.2 Record Object IDs

- `LOANS_PACKAGE_ID`
- `LOAN_VAULT` (LoanVault - shared)
- `UPGRADE_CAP`

### 6.3 Update Move.toml

```toml
published-at = "0x<LOANS_PACKAGE_ID>"

[addresses]
tide_loans = "0x<LOANS_PACKAGE_ID>"
```

### 6.4 Add Liquidity to Loan Vault

```bash
# Admin deposits liquidity (e.g., 1000 SUI = 1000000000000 MIST)
# Requires AdminCap from tide_core
sui client ptb \
  --assign loans_pkg @$LOANS_PACKAGE_ID \
  --assign loan_vault @$LOAN_VAULT \
  --assign admin_cap @$ADMIN_CAP \
  --split-coins gas "[1000000000000]" \
  --assign liquidity \
  --move-call "loans_pkg::loan_vault::deposit_liquidity" loan_vault admin_cap "liquidity.0" \
  --gas-budget 100000000
```

---

## Step 7: Setup SupporterPass Display

After deploying `tide_core`, setup the Display for SupporterPass NFTs:

### 7.1 Create Display Object

```bash
sui client ptb \
  --assign pkg @$PACKAGE_ID \
  --assign publisher @$PUBLISHER_ID \
  --move-call "pkg::display::create_and_keep_supporter_pass_display" publisher \
  --gas-budget 50000000
```

**Record:** `DISPLAY_ID` (Display<SupporterPass> object)

### 7.2 Update Display URLs (Optional)

```bash
# Update image URL
sui client ptb \
  --assign pkg @$PACKAGE_ID \
  --assign display @$DISPLAY_ID \
  --move-call "pkg::display::update_image_url" display "b\"https://api.tide.am/pass/{listing_id}/{id}/image.svg\"" \
  --gas-budget 50000000

# Update link
sui client ptb \
  --assign pkg @$PACKAGE_ID \
  --assign display @$DISPLAY_ID \
  --move-call "pkg::display::update_link" display "b\"https://app.tide.am/listing/{listing_id}/pass/{id}\"" \
  --gas-budget 50000000
```

---

## Step 8: Initialize FAITH Listing

### 7.1 Create Listing

```bash
sui client ptb \
  --assign pkg @$PACKAGE_ID \
  --assign registry @$REGISTRY \
  --assign council_cap @$COUNCIL_CAP \
  --assign issuer @$ISSUER_ADDRESS \
  --assign validator @$VALIDATOR_ADDRESS \
  --move-call "pkg::listing::new" registry council_cap issuer validator "vector[]" "vector[]" 1000u64 \
  --assign result \
  --move-call "pkg::listing::share" result.0 \
  --move-call "pkg::capital_vault::share" result.1 \
  --move-call "pkg::reward_vault::share" result.2 \
  --move-call "pkg::staking_adapter::share" result.3 \
  --transfer-objects "[result.4, result.5]" issuer \
  --gas-budget 100000000
```

**Record:**
- `LISTING` (result.0)
- `CAPITAL_VAULT` (result.1)
- `REWARD_VAULT` (result.2)
- `STAKING_ADAPTER` (result.3)
- `LISTING_CAP` (result.4) - transferred to issuer
- `ROUTE_CAP` (result.5) - transferred to issuer

### 7.2 Activate Listing

```bash
sui client ptb \
  --assign pkg @$PACKAGE_ID \
  --assign listing @$LISTING \
  --assign council_cap @$COUNCIL_CAP \
  --assign clock @0x6 \
  --move-call "pkg::listing::activate" listing council_cap clock \
  --gas-budget 50000000
```

### 7.3 Create FaithRouter (Optional)

```bash
sui client ptb \
  --assign faith_pkg @$FAITH_PACKAGE_ID \
  --assign route_cap @$ROUTE_CAP \
  --assign revenue_bps 1000u64 \
  --assign issuer @$ISSUER_ADDRESS \
  --move-call "faith_pkg::faith_router::new" route_cap revenue_bps \
  --assign result \
  --move-call "faith_pkg::faith_router::share" result.0 \
  --move-call "faith_pkg::faith_router::transfer_cap" result.1 issuer \
  --gas-budget 50000000
```

**Record:** `FAITH_ROUTER` (result.0)

---

## Step 9: Transfer Capabilities

### 8.1 Transfer CouncilCap to Multisig

```bash
sui client transfer \
  --object-id $COUNCIL_CAP \
  --to $MULTISIG_ADDRESS \
  --gas-budget 10000000
```

### 8.2 Transfer AdminCap (Optional)

```bash
sui client transfer \
  --object-id $ADMIN_CAP \
  --to $ADMIN_MULTISIG_ADDRESS \
  --gas-budget 10000000
```

---

## Step 10: Verification

### 9.1 Verify Objects

```bash
# Check package
sui client object $PACKAGE_ID

# Check Tide
sui client object $TIDE

# Check Listing
sui client object $LISTING
```

### 9.2 Verify on Explorer

- **Testnet:** https://suiscan.xyz/testnet/object/$PACKAGE_ID
- **Mainnet:** https://suiscan.xyz/mainnet/object/$PACKAGE_ID

---

## Operations Guide

### Environment Variables

Set these after deployment:

```bash
# Core Package & Objects
export PKG=0x...                # tide_core package
export TIDE=0x...               # Tide shared object
export REGISTRY=0x...           # ListingRegistry
export COUNCIL_CAP=0x...        # CouncilCap
export TREASURY_VAULT=0x...     # TreasuryVault

# Listing Objects
export LISTING=0x...            # Listing
export CAPITAL_VAULT=0x...      # CapitalVault
export REWARD_VAULT=0x...       # RewardVault
export STAKING_ADAPTER=0x...    # StakingAdapter
export ROUTE_CAP=0x...          # RouteCapability

# Adapter Package
export FAITH_PKG=0x...          # faith_router package
export FAITH_ROUTER=0x...       # FaithRouter

# Marketplace Package
export MARKETPLACE_PKG=0x...     # tide_marketplace package
export MARKETPLACE_CONFIG=0x...  # MarketplaceConfig

# Loans Package
export LOANS_PKG=0x...          # tide_loans package
export LOAN_VAULT=0x...         # LoanVault

# Your Wallet
export ME=0x...                 # Your wallet address

# System Objects
export CLOCK=0x6
export SYSTEM_STATE=0x5

# Validator (get active validator)
export VALIDATOR=0x...          # Active testnet validator
```

---

### Backer Operations

#### Deposit SUI

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign capital_vault @$CAPITAL_VAULT \
  --assign reward_vault @$REWARD_VAULT \
  --assign clock @$CLOCK \
  --assign me @$ME \
  --assign deposit_coin @$DEPOSIT_COIN_ID \
  --move-call "pkg::listing::deposit" listing tide capital_vault reward_vault deposit_coin clock \
  --assign supporter_pass \
  --transfer-objects "[supporter_pass]" me \
  --gas-budget 50000000
```

#### Claim Rewards

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign reward_vault @$REWARD_VAULT \
  --assign supporter_pass @$SUPPORTER_PASS \
  --assign me @$ME \
  --move-call "pkg::listing::claim" listing tide reward_vault supporter_pass \
  --assign claimed_coin \
  --transfer-objects "[claimed_coin]" me \
  --gas-budget 50000000
```

#### Claim Many (Batch)

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign reward_vault @$REWARD_VAULT \
  --assign me @$ME \
  --make-move-vec "<tide_core::supporter_pass::SupporterPass>" "[@$PASS1, @$PASS2, @$PASS3]" \
  --assign passes \
  --move-call "pkg::listing::claim_many" listing tide reward_vault passes \
  --assign claimed_coin \
  --transfer-objects "[claimed_coin]" me \
  --gas-budget 100000000
```

#### Claim from Kiosk

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign reward_vault @$REWARD_VAULT \
  --assign kiosk @$KIOSK \
  --assign kiosk_cap @$KIOSK_CAP \
  --assign pass_id @$PASS_ID \
  --assign me @$ME \
  --move-call "pkg::kiosk_ext::claim_from_kiosk" listing tide reward_vault kiosk kiosk_cap pass_id \
  --assign claimed_coin \
  --transfer-objects "[claimed_coin]" me \
  --gas-budget 50000000
```

---

### Council Operations

#### Finalize Listing

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign council_cap @$COUNCIL_CAP \
  --assign capital_vault @$CAPITAL_VAULT \
  --assign clock @$CLOCK \
  --move-call "pkg::listing::finalize" listing council_cap capital_vault clock \
  --gas-budget 50000000
```

#### Collect Raise Fee (1%)

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign treasury_vault @$TREASURY_VAULT \
  --assign capital_vault @$CAPITAL_VAULT \
  --move-call "pkg::listing::collect_raise_fee" listing tide treasury_vault capital_vault \
  --gas-budget 50000000
```

#### Release Tranche

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign capital_vault @$CAPITAL_VAULT \
  --assign clock @$CLOCK \
  --move-call "pkg::listing::release_next_ready_tranche" listing tide capital_vault clock \
  --gas-budget 50000000
```

#### Stake Locked Capital

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign council_cap @$COUNCIL_CAP \
  --assign capital_vault @$CAPITAL_VAULT \
  --assign staking_adapter @$STAKING_ADAPTER \
  --assign system_state @$SYSTEM_STATE \
  --move-call "pkg::listing::stake_all_locked_capital" listing tide council_cap capital_vault staking_adapter system_state \
  --gas-budget 100000000
```

#### Unstake All

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign council_cap @$COUNCIL_CAP \
  --assign staking_adapter @$STAKING_ADAPTER \
  --assign system_state @$SYSTEM_STATE \
  --assign me @$ME \
  --move-call "pkg::listing::unstake_all" listing tide council_cap staking_adapter system_state \
  --assign unstaked_coin \
  --transfer-objects "[unstaked_coin]" me \
  --gas-budget 100000000
```

#### Update Validator

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign council_cap @$COUNCIL_CAP \
  --assign staking_adapter @$STAKING_ADAPTER \
  --assign new_validator @$NEW_VALIDATOR \
  --move-call "pkg::admin::update_validator" listing tide council_cap staking_adapter new_validator \
  --gas-budget 50000000
```

#### Cancel Listing (Refund Flow)

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign council_cap @$COUNCIL_CAP \
  --assign capital_vault @$CAPITAL_VAULT \
  --assign staking_adapter @$STAKING_ADAPTER \
  --move-call "pkg::listing::cancel_listing" listing tide council_cap capital_vault staking_adapter \
  --gas-budget 50000000
```

---

### Refund Operations (Cancelled Listings)

#### Claim Refund

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign capital_vault @$CAPITAL_VAULT \
  --assign pass @$SUPPORTER_PASS \
  --assign me @$ME \
  --move-call "pkg::listing::claim_refund" listing capital_vault pass \
  --assign refund_coin \
  --transfer-objects "[refund_coin]" me \
  --gas-budget 50000000
```

#### Claim Multiple Refunds

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign capital_vault @$CAPITAL_VAULT \
  --assign me @$ME \
  --make-move-vec "<tide_core::supporter_pass::SupporterPass>" "[@$PASS1, @$PASS2]" \
  --assign passes \
  --move-call "pkg::listing::claim_refunds" listing capital_vault passes \
  --assign refund_coin \
  --transfer-objects "[refund_coin]" me \
  --gas-budget 100000000
```

---

### Issuer Operations

#### Route Revenue via FaithRouter

```bash
sui client ptb \
  --assign faith_pkg @$FAITH_PKG \
  --assign faith_router @$FAITH_ROUTER \
  --assign reward_vault @$REWARD_VAULT \
  --assign revenue_coin @$REVENUE_COIN_ID \
  --move-call "faith_pkg::faith_router::route" faith_router reward_vault revenue_coin \
  --gas-budget 50000000
```

#### Harvest Staking Rewards via FaithRouter

```bash
sui client ptb \
  --assign faith_pkg @$FAITH_PKG \
  --assign faith_router @$FAITH_ROUTER \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign staking_adapter @$STAKING_ADAPTER \
  --assign reward_vault @$REWARD_VAULT \
  --assign treasury_vault @$TREASURY_VAULT \
  --assign system_state @$SYSTEM_STATE \
  --move-call "faith_pkg::faith_router::harvest_and_route" faith_router listing tide staking_adapter reward_vault treasury_vault system_state \
  --gas-budget 100000000
```

---

### Marketplace Operations

#### List SupporterPass for Sale

```bash
sui client ptb \
  --assign mkt_pkg @$MARKETPLACE_PKG \
  --assign config @$MARKETPLACE_CONFIG \
  --assign pass @$SUPPORTER_PASS \
  --assign price 10000000000u64 \
  --move-call "mkt_pkg::marketplace::list_for_sale" config pass price \
  --gas-budget 50000000
```

#### Buy SupporterPass

```bash
sui client ptb \
  --assign mkt_pkg @$MARKETPLACE_PKG \
  --assign config @$MARKETPLACE_CONFIG \
  --assign treasury_vault @$TREASURY_VAULT \
  --assign sale_listing @$SALE_LISTING_ID \
  --assign payment_coin @$PAYMENT_COIN_ID \
  --assign me @$ME \
  --move-call "mkt_pkg::marketplace::buy" config treasury_vault sale_listing payment_coin \
  --assign result \
  --transfer-objects "[result.0]" me \
  --transfer-objects "[result.2]" me \
  --gas-budget 50000000
```

Note: result.0 = SupporterPass, result.1 = PurchaseReceipt, result.2 = change Coin

#### Buy and Take (Simple)

```bash
sui client ptb \
  --assign mkt_pkg @$MARKETPLACE_PKG \
  --assign config @$MARKETPLACE_CONFIG \
  --assign treasury_vault @$TREASURY_VAULT \
  --assign sale_listing @$SALE_LISTING_ID \
  --assign payment_coin @$PAYMENT_COIN_ID \
  --move-call "mkt_pkg::marketplace::buy_and_take" config treasury_vault sale_listing payment_coin \
  --gas-budget 50000000
```

#### Delist

```bash
sui client ptb \
  --assign mkt_pkg @$MARKETPLACE_PKG \
  --assign config @$MARKETPLACE_CONFIG \
  --assign sale_listing @$SALE_LISTING_ID \
  --assign me @$ME \
  --move-call "mkt_pkg::marketplace::delist" config sale_listing \
  --assign pass \
  --transfer-objects "[pass]" me \
  --gas-budget 50000000
```

#### Update Price

```bash
sui client ptb \
  --assign mkt_pkg @$MARKETPLACE_PKG \
  --assign sale_listing @$SALE_LISTING_ID \
  --assign new_price 15000000000u64 \
  --move-call "mkt_pkg::marketplace::update_price" sale_listing new_price \
  --gas-budget 50000000
```

#### Pause Marketplace (Admin)

```bash
sui client ptb \
  --assign mkt_pkg @$MARKETPLACE_PKG \
  --assign config @$MARKETPLACE_CONFIG \
  --move-call "mkt_pkg::marketplace::pause" config \
  --gas-budget 50000000
```

---

### Loans Operations

#### Borrow Against SupporterPass

```bash
sui client ptb \
  --assign loans_pkg @$LOANS_PKG \
  --assign loan_vault @$LOAN_VAULT \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign capital_vault @$CAPITAL_VAULT \
  --assign pass @$SUPPORTER_PASS \
  --assign loan_amount 5000000000u64 \
  --assign me @$ME \
  --move-call "loans_pkg::loan_vault::borrow" loan_vault listing tide capital_vault pass loan_amount \
  --assign result \
  --transfer-objects "[result.0]" me \
  --transfer-objects "[result.1]" me \
  --gas-budget 100000000
```

Note: result.0 = LoanReceipt, result.1 = loan Coin

#### Repay Loan

```bash
sui client ptb \
  --assign loans_pkg @$LOANS_PKG \
  --assign loan_vault @$LOAN_VAULT \
  --assign receipt @$LOAN_RECEIPT \
  --assign payment_coin @$PAYMENT_COIN_ID \
  --assign me @$ME \
  --move-call "loans_pkg::loan_vault::repay" loan_vault receipt payment_coin \
  --assign refund \
  --transfer-objects "[refund]" me \
  --gas-budget 50000000
```

#### Harvest and Repay (Keeper)

```bash
sui client ptb \
  --assign loans_pkg @$LOANS_PKG \
  --assign loan_vault @$LOAN_VAULT \
  --assign loan_id @$LOAN_ID \
  --assign listing @$LISTING \
  --assign tide @$TIDE \
  --assign reward_vault @$REWARD_VAULT \
  --assign me @$ME \
  --move-call "loans_pkg::loan_vault::harvest_and_repay" loan_vault loan_id listing tide reward_vault \
  --assign keeper_tip \
  --transfer-objects "[keeper_tip]" me \
  --gas-budget 100000000
```

#### Withdraw Collateral (After Repayment)

```bash
sui client ptb \
  --assign loans_pkg @$LOANS_PKG \
  --assign loan_vault @$LOAN_VAULT \
  --assign receipt @$LOAN_RECEIPT \
  --assign me @$ME \
  --move-call "loans_pkg::loan_vault::withdraw_collateral" loan_vault receipt \
  --assign pass \
  --transfer-objects "[pass]" me \
  --gas-budget 50000000
```

#### Liquidate Loan

```bash
sui client ptb \
  --assign loans_pkg @$LOANS_PKG \
  --assign loan_vault @$LOAN_VAULT \
  --assign loan_id @$LOAN_ID \
  --assign capital_vault @$CAPITAL_VAULT \
  --assign payment_coin @$PAYMENT_COIN_ID \
  --assign me @$ME \
  --move-call "loans_pkg::loan_vault::liquidate" loan_vault loan_id capital_vault payment_coin \
  --assign pass \
  --transfer-objects "[pass]" me \
  --gas-budget 100000000
```

#### Deposit Liquidity (Admin)

```bash
sui client ptb \
  --assign loans_pkg @$LOANS_PKG \
  --assign loan_vault @$LOAN_VAULT \
  --assign admin_cap @$ADMIN_CAP \
  --assign liquidity_coin @$LIQUIDITY_COIN_ID \
  --move-call "loans_pkg::loan_vault::deposit_liquidity" loan_vault admin_cap liquidity_coin \
  --gas-budget 50000000
```

#### Withdraw Liquidity (Admin)

```bash
sui client ptb \
  --assign loans_pkg @$LOANS_PKG \
  --assign loan_vault @$LOAN_VAULT \
  --assign amount 1000000000u64 \
  --assign me @$ME \
  --move-call "loans_pkg::loan_vault::withdraw_liquidity" loan_vault amount \
  --assign withdrawn \
  --transfer-objects "[withdrawn]" me \
  --gas-budget 50000000
```

---

### Admin Operations

#### Withdraw from Treasury

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign tide @$TIDE \
  --assign admin_cap @$ADMIN_CAP \
  --assign treasury_vault @$TREASURY_VAULT \
  --assign amount 1000000000u64 \
  --assign me @$ME \
  --move-call "pkg::tide::withdraw_from_treasury" tide admin_cap treasury_vault amount \
  --assign withdrawn \
  --transfer-objects "[withdrawn]" me \
  --gas-budget 50000000
```

#### Get Active Validators

```bash
sui client call \
  --package 0x3 \
  --module sui_system \
  --function active_validator_addresses \
  --args 0x5 \
  --gas-budget 10000000
```

---

## Emergency Procedures

### Global Pause

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign tide @$TIDE \
  --assign admin_cap @$ADMIN_CAP \
  --move-call "pkg::tide::pause" tide admin_cap \
  --gas-budget 10000000
```

### Global Unpause

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign tide @$TIDE \
  --assign admin_cap @$ADMIN_CAP \
  --move-call "pkg::tide::unpause" tide admin_cap \
  --gas-budget 10000000
```

### Per-Listing Pause

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign council_cap @$COUNCIL_CAP \
  --move-call "pkg::listing::pause" listing council_cap \
  --gas-budget 10000000
```

### Per-Listing Unpause

```bash
sui client ptb \
  --assign pkg @$PKG \
  --assign listing @$LISTING \
  --assign council_cap @$COUNCIL_CAP \
  --move-call "pkg::listing::unpause" listing council_cap \
  --gas-budget 10000000
```

### Pause Marketplace

```bash
sui client ptb \
  --assign mkt_pkg @$MARKETPLACE_PKG \
  --assign config @$MARKETPLACE_CONFIG \
  --move-call "mkt_pkg::marketplace::pause" config \
  --gas-budget 10000000
```

### Pause Loans

```bash
sui client ptb \
  --assign loans_pkg @$LOANS_PKG \
  --assign loan_vault @$LOAN_VAULT \
  --move-call "loans_pkg::loan_vault::pause" loan_vault \
  --gas-budget 10000000
```

---

## Deployment Checklist

### Pre-Deployment
- [ ] All tests passing (`sui move test` for all packages)
- [ ] Build succeeds (`sui move build` for all packages)
- [ ] Wallet funded with sufficient SUI (~2 SUI for all packages)
- [ ] Recovery phrases securely stored
- [ ] Active validator address verified

### Testnet Deployment
- [ ] Published tide_core package
- [ ] Published faith_router adapter
- [ ] Published tide_marketplace package
- [ ] Published tide_loans package
- [ ] Created FAITH listing (Listing #1)
- [ ] Created FaithRouter
- [ ] Activated listing
- [ ] Tested deposit flow
- [ ] Tested claim flow
- [ ] Tested marketplace list/buy flow
- [ ] Tested loans borrow/repay flow
- [ ] Tested staking flow
- [ ] Added liquidity to LoanVault
- [ ] Saved deployment artifacts

### Pre-Mainnet
- [ ] Security audit completed
- [ ] Testnet testing period completed
- [ ] Council multisig configured
- [ ] Emergency procedures documented
- [ ] Monitoring/alerting setup

### Mainnet Deployment
- [ ] Published all packages
- [ ] Created FAITH listing
- [ ] Transferred CouncilCap to multisig
- [ ] Transferred AdminCap to cold storage
- [ ] Activated listing
- [ ] Verified on explorer
- [ ] Announced to community

---

## Function Signatures Reference

### Core Package (tide_core)

| Function | Signature |
|----------|-----------|
| `listing::new` | `(registry, council_cap, issuer, validator, tranche_amounts, tranche_times, revenue_bps)` |
| `listing::activate` | `(listing, council_cap, clock)` |
| `listing::finalize` | `(listing, council_cap, capital_vault, clock)` |
| `listing::deposit` | `(listing, tide, capital_vault, reward_vault, coin, clock) → SupporterPass` |
| `listing::claim` | `(listing, tide, reward_vault, pass) → Coin<SUI>` |
| `listing::claim_many` | `(listing, tide, reward_vault, passes) → Coin<SUI>` |
| `listing::collect_raise_fee` | `(listing, tide, treasury_vault, capital_vault)` |
| `listing::release_next_ready_tranche` | `(listing, tide, capital_vault, clock)` |
| `listing::stake_all_locked_capital` | `(listing, tide, council_cap, capital_vault, staking_adapter, system_state)` |
| `listing::unstake_all` | `(listing, tide, council_cap, staking_adapter, system_state) → Coin<SUI>` |
| `listing::cancel_listing` | `(listing, tide, council_cap, capital_vault, staking_adapter)` |
| `listing::claim_refund` | `(listing, capital_vault, pass) → Coin<SUI>` |
| `listing::claim_refunds` | `(listing, capital_vault, passes) → Coin<SUI>` |
| `kiosk_ext::claim_from_kiosk` | `(listing, tide, reward_vault, kiosk, kiosk_cap, pass_id) → Coin<SUI>` |
| `kiosk_ext::claim_many_from_kiosk` | `(listing, tide, reward_vault, kiosk, kiosk_cap, pass_ids) → Coin<SUI>` |

### Faith Router Package (faith_router)

| Function | Signature |
|----------|-----------|
| `faith_router::new` | `(route_cap, revenue_bps) → (FaithRouter, FaithRouterCap)` |
| `faith_router::route` | `(router, reward_vault, coin)` |
| `faith_router::harvest_and_route` | `(router, listing, tide, staking_adapter, reward_vault, treasury_vault, system_state)` |
| `faith_router::calculate_revenue` | `(router, total_fees) → u64` |

### Marketplace Package (tide_marketplace)

| Function | Signature |
|----------|-----------|
| `marketplace::list_for_sale` | `(config, pass, price) → ID` |
| `marketplace::delist` | `(config, sale_listing) → SupporterPass` |
| `marketplace::update_price` | `(sale_listing, new_price)` |
| `marketplace::buy` | `(config, treasury_vault, sale_listing, payment) → (SupporterPass, PurchaseReceipt, Coin<SUI>)` |
| `marketplace::buy_and_take` | `(config, treasury_vault, sale_listing, payment)` |
| `marketplace::pause` | `(config)` |
| `marketplace::unpause` | `(config)` |
| `marketplace::transfer_admin` | `(config, new_admin)` |

### Loans Package (tide_loans)

| Function | Signature |
|----------|-----------|
| `loan_vault::borrow` | `(vault, listing, tide, capital_vault, pass, loan_amount) → (LoanReceipt, Coin<SUI>)` |
| `loan_vault::repay` | `(vault, receipt, payment) → Coin<SUI>` |
| `loan_vault::harvest_and_repay` | `(vault, loan_id, listing, tide, reward_vault) → Coin<SUI>` |
| `loan_vault::withdraw_collateral` | `(vault, receipt) → SupporterPass` |
| `loan_vault::liquidate` | `(vault, loan_id, capital_vault, payment) → SupporterPass` |
| `loan_vault::deposit_liquidity` | `(vault, admin_cap, coin)` |
| `loan_vault::withdraw_liquidity` | `(vault, amount) → Coin<SUI>` |
| `loan_vault::pause` | `(vault)` |
| `loan_vault::unpause` | `(vault)` |
| `loan_vault::get_health_factor` | `(vault, loan_id, capital_vault) → (u64, u64)` |

---

## Contact

For deployment support, contact the Tide team.
