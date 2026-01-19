# Tide Protocol Deployment Guide

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

---

## Step 1: Wallet Setup

### 1.1 Create Deployer Wallet

The deployer wallet publishes the contracts and receives the initial `AdminCap` and `CouncilCap`.

```bash
# Create new keypair for deployment
sui keytool generate ed25519

# Output:
# ╭─────────────────────────────────────────────────────────────────────╮
# │ Created new keypair for address: 0x1234...                          │
# │ Secret Recovery Phrase: word1 word2 word3 ... word12                │
# ╰─────────────────────────────────────────────────────────────────────╯
```

⚠️ **CRITICAL:** Save the recovery phrase securely! This controls the protocol.

```bash
# Import to Sui client
sui keytool import "word1 word2 ... word12" ed25519

# Set as active
sui client switch --address 0x1234...
```

### 1.2 Create Council Multisig (Recommended for Production)

For production, the `CouncilCap` should be transferred to a multisig wallet.

**Option A: Use Sui's Native Multisig**

```bash
# Generate 3-5 council member keys
sui keytool generate ed25519  # Council member 1
sui keytool generate ed25519  # Council member 2
sui keytool generate ed25519  # Council member 3
# ... etc

# Create multisig address (2-of-3 example)
sui keytool multi-sig-address \
  --pks <pk1> <pk2> <pk3> \
  --weights 1 1 1 \
  --threshold 2
```

**Option B: Use a Multisig Service**
- [Kraken Multisig](https://docs.sui.io/)
- [Safe-like solutions for Sui]

### 1.3 Treasury Wallet

Create a separate wallet for treasury fee collection:

```bash
sui keytool generate ed25519
# Save this as TREASURY_ADDRESS
```

---

## Step 2: Environment Configuration

### 2.1 Network Configuration

```bash
# Check available networks
sui client envs

# Switch to testnet
sui client switch --env testnet

# Or mainnet
sui client switch --env mainnet
```

### 2.2 Fund Deployer Wallet

**Testnet:**
```bash
# Request from faucet
sui client faucet
```

**Mainnet:**
- Transfer SUI from exchange or existing wallet
- Need ~1-2 SUI for deployment gas

---

## Step 3: Deploy tide_core Package

### 3.1 Build the Package

```bash
cd contracts/core
sui move build
```

### 3.2 Publish to Network

```bash
# Testnet
sui client publish --gas-budget 500000000

# The output will show:
# ╭──────────────────────────────────────────────────────────────────────╮
# │ Object Changes                                                        │
# ├──────────────────────────────────────────────────────────────────────┤
# │ Created Objects:                                                      │
# │  ┌──                                                                  │
# │  │ ObjectID: 0xPACKAGE_ID                                            │
# │  │ ObjectType: Package                                               │
# │  └──                                                                  │
# │  ┌──                                                                  │
# │  │ ObjectID: 0xTIDE_OBJECT_ID                                        │
# │  │ ObjectType: tide_core::tide::Tide                                 │
# │  └──                                                                  │
# │  ┌──                                                                  │
# │  │ ObjectID: 0xADMIN_CAP_ID                                          │
# │  │ ObjectType: tide_core::tide::AdminCap                             │
# │  └──                                                                  │
# │  ┌──                                                                  │
# │  │ ObjectID: 0xCOUNCIL_CAP_ID                                        │
# │  │ ObjectType: tide_core::council::CouncilCap                        │
# │  └──                                                                  │
# │  ┌──                                                                  │
# │  │ ObjectID: 0xREGISTRY_ID                                           │
# │  │ ObjectType: tide_core::registry::ListingRegistry                  │
# │  └──                                                                  │
# ╰──────────────────────────────────────────────────────────────────────╯
```

### 3.3 Save Deployment Artifacts

Create a deployment record:

```bash
# Create deployments directory
mkdir -p deployments/testnet
mkdir -p deployments/mainnet

# Save object IDs
cat > deployments/testnet/tide_core.json << EOF
{
  "network": "testnet",
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployer": "$(sui client active-address)",
  "package_id": "0xPACKAGE_ID",
  "objects": {
    "tide": "0xTIDE_OBJECT_ID",
    "admin_cap": "0xADMIN_CAP_ID",
    "council_cap": "0xCOUNCIL_CAP_ID",
    "registry": "0xREGISTRY_ID"
  }
}
EOF
```

---

## Step 4: Deploy faith_router Package

> **Note:** For detailed adapter architecture and integration patterns, see [ADAPTERS.md](./ADAPTERS.md).

### 4.1 Update Dependency

Edit `contracts/adapters/faith_router/Move.toml`:

```toml
[dependencies]
tide_core = { local = "../../core" }

# For published deployment, use:
# [dependencies.tide_core]
# git = "https://github.com/your-org/tide-protocol.git"
# subdir = "contracts/core"
# rev = "v1.0.0"
```

### 4.2 Publish Adapter

```bash
cd contracts/adapters/faith_router
sui client publish --gas-budget 200000000
```

---

## Step 5: Deploy tide_marketplace Package

> **Note:** For detailed marketplace documentation, see [MARKETPLACE.md](./MARKETPLACE.md).

### 5.1 Update Dependency

Edit `contracts/marketplace/Move.toml`:

```toml
[dependencies]
tide_core = { local = "../core" }

# For published deployment, use:
# [dependencies.tide_core]
# git = "https://github.com/your-org/tide-protocol.git"
# subdir = "contracts/core"
# rev = "v1.0.0"
```

### 5.2 Publish Marketplace

```bash
cd contracts/marketplace
sui client publish --gas-budget 200000000
```

**Expected output:**
```
╭─────────────────────────────────────────────────────────────────────────────╮
│ Object Changes                                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│ Created Objects:                                                             │
│  ┌──                                                                        │
│  │ ObjectID: 0x<MARKETPLACE_CONFIG_ID>                                       │
│  │ ObjectType: tide_marketplace::marketplace::MarketplaceConfig              │
│  └──                                                                        │
│  ┌──                                                                        │
│  │ ObjectID: 0x<UPGRADE_CAP_ID>                                              │
│  │ ObjectType: sui::package::UpgradeCap                                      │
│  └──                                                                        │
│ Published Objects:                                                           │
│  ┌──                                                                        │
│  │ ObjectID: 0x<MARKETPLACE_PACKAGE_ID>                                      │
│  │ ObjectType: sui::package::Package                                         │
│  └──                                                                        │
╰─────────────────────────────────────────────────────────────────────────────╯
```

Record:
- `MARKETPLACE_PACKAGE_ID`
- `MARKETPLACE_CONFIG_ID`
- `MARKETPLACE_UPGRADE_CAP_ID`

### 5.3 Update Move.toml with Published Address

```toml
published-at = "0x<MARKETPLACE_PACKAGE_ID>"
```

---

## Step 6: Initialize FAITH Listing (Listing #1)

### 6.1 Create the Listing

```bash
# Using Sui CLI with PTB (Programmable Transaction Block)
sui client ptb \
  --move-call tide_core::listing::new \
    @0xREGISTRY_ID \
    @0xCOUNCIL_CAP_ID \
    @ISSUER_ADDRESS \
    @VALIDATOR_ADDRESS \
    "[]" \
    "[]" \
    1000 \
  --gas-budget 100000000
```

Or use a TypeScript deployment script (see below).

### 6.2 Activate the Listing

```bash
sui client ptb \
  --move-call tide_core::listing::activate \
    @0xLISTING_ID \
    @0xCOUNCIL_CAP_ID \
    @0x6 \
  --gas-budget 50000000
```

Note: `@0x6` is the Sui Clock object.

---

## Step 7: Transfer Capabilities (Production)

### 7.1 Transfer CouncilCap to Multisig

```bash
sui client transfer \
  --object-id 0xCOUNCIL_CAP_ID \
  --to 0xMULTISIG_ADDRESS \
  --gas-budget 10000000
```

### 7.2 Transfer AdminCap (Optional)

For production, consider transferring AdminCap to a secure cold wallet or multisig:

```bash
sui client transfer \
  --object-id 0xADMIN_CAP_ID \
  --to 0xADMIN_MULTISIG_ADDRESS \
  --gas-budget 10000000
```

---

## Step 8: Verification

### 8.1 Verify Deployment

```bash
# Check Tide object
sui client object 0xTIDE_OBJECT_ID

# Check Registry
sui client object 0xREGISTRY_ID

# Check Listing
sui client object 0xLISTING_ID
```

### 8.2 Verify on Explorer

- **Testnet:** https://suiscan.xyz/testnet/object/0xPACKAGE_ID
- **Mainnet:** https://suiscan.xyz/mainnet/object/0xPACKAGE_ID

---

## Deployment Checklist

### Pre-Deployment

- [ ] All tests passing (`sui move test`)
- [ ] Build succeeds (`sui move build`)
- [ ] Wallet funded with sufficient SUI
- [ ] Recovery phrases securely stored
- [ ] Treasury address created

### Testnet Deployment

- [ ] Published tide_core package
- [ ] Published faith_router adapter
- [ ] Created FAITH listing (Listing #1)
- [ ] Activated listing
- [ ] Tested deposit flow
- [ ] Tested claim flow
- [ ] Saved deployment artifacts

### Pre-Mainnet

- [ ] Security audit completed
- [ ] Testnet testing period completed
- [ ] Council multisig configured
- [ ] Emergency procedures documented
- [ ] Monitoring/alerting setup

### Mainnet Deployment

- [ ] Published tide_core package
- [ ] Published faith_router adapter
- [ ] Created FAITH listing
- [ ] Transferred CouncilCap to multisig
- [ ] Activated listing
- [ ] Verified on explorer
- [ ] Announced to community

---

## Appendix: TypeScript Deployment Script

Create `scripts/deploy.ts`:

```typescript
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import { execSync } from 'child_process';
import * as fs from 'fs';

const NETWORK = process.env.SUI_NETWORK || 'testnet';

async function deploy() {
  // Initialize client
  const client = new SuiClient({ url: getFullnodeUrl(NETWORK as 'testnet' | 'mainnet') });
  
  // Load deployer keypair (from env or file)
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY!;
  const keypair = Ed25519Keypair.fromSecretKey(Buffer.from(privateKey, 'hex'));
  
  console.log(`Deploying to ${NETWORK}...`);
  console.log(`Deployer: ${keypair.toSuiAddress()}`);
  
  // Build and publish tide_core
  console.log('Publishing tide_core...');
  const { modules, dependencies } = JSON.parse(
    execSync('sui move build --dump-bytecode-as-base64 --path contracts/core', {
      encoding: 'utf-8'
    })
  );
  
  const tx = new Transaction();
  const [upgradeCap] = tx.publish({ modules, dependencies });
  tx.transferObjects([upgradeCap], keypair.toSuiAddress());
  
  const result = await client.signAndExecuteTransaction({
    signer: keypair,
    transaction: tx,
    options: { showObjectChanges: true }
  });
  
  console.log('Deployed!', result.digest);
  
  // Extract object IDs
  const createdObjects = result.objectChanges?.filter(o => o.type === 'created') || [];
  
  // Save deployment info
  const deployment = {
    network: NETWORK,
    digest: result.digest,
    packageId: createdObjects.find(o => o.objectType === 'package')?.objectId,
    objects: createdObjects.map(o => ({
      objectId: o.objectId,
      objectType: o.objectType
    }))
  };
  
  fs.writeFileSync(
    `deployments/${NETWORK}/tide_core.json`,
    JSON.stringify(deployment, null, 2)
  );
  
  console.log('Saved deployment info to deployments/' + NETWORK + '/tide_core.json');
}

deploy().catch(console.error);
```

---

## Emergency Procedures

### Global Pause

If a critical issue is discovered:

```bash
sui client ptb \
  --move-call tide_core::tide::pause \
    @0xTIDE_ID \
    @0xADMIN_CAP_ID \
  --gas-budget 10000000
```

### Per-Listing Pause

To pause a specific listing:

```bash
sui client ptb \
  --move-call tide_core::listing::pause \
    @0xLISTING_ID \
    @0xCOUNCIL_CAP_ID \
  --gas-budget 10000000
```

---

## Contact

For deployment support, contact the Tide team.
