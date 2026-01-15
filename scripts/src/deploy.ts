/**
 * Tide Protocol Deployment Script
 * 
 * Usage:
 *   # Set environment variables
 *   export DEPLOYER_PRIVATE_KEY="your_private_key_hex"
 *   export SUI_NETWORK="testnet"  # or "mainnet"
 *   
 *   # Run deployment
 *   npm run deploy:testnet
 *   npm run deploy:mainnet
 */

import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

type Network = 'testnet' | 'mainnet' | 'devnet' | 'localnet';

interface DeploymentResult {
  network: string;
  deployedAt: string;
  deployer: string;
  digest: string;
  packageId: string;
  objects: {
    tide?: string;
    adminCap?: string;
    councilCap?: string;
    councilConfig?: string;
    registry?: string;
  };
}

async function deploy(): Promise<void> {
  const network = (process.env.SUI_NETWORK || 'testnet') as Network;
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  
  if (!privateKey) {
    console.error('Error: DEPLOYER_PRIVATE_KEY environment variable is required');
    console.error('Generate a keypair with: sui keytool generate ed25519');
    console.error('Then export the private key hex');
    process.exit(1);
  }
  
  // Initialize client
  const client = new SuiClient({ url: getFullnodeUrl(network) });
  
  // Load deployer keypair
  const keypair = Ed25519Keypair.fromSecretKey(Buffer.from(privateKey, 'hex'));
  const deployerAddress = keypair.toSuiAddress();
  
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║                  Tide Protocol Deployment                     ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log();
  console.log(`Network:  ${network}`);
  console.log(`Deployer: ${deployerAddress}`);
  console.log();
  
  // Check balance
  const balance = await client.getBalance({ owner: deployerAddress });
  const suiBalance = BigInt(balance.totalBalance) / BigInt(1_000_000_000);
  console.log(`Balance:  ${suiBalance} SUI`);
  
  if (suiBalance < 1n) {
    console.error('Error: Insufficient balance. Need at least 1 SUI for deployment.');
    if (network === 'testnet') {
      console.log('Get testnet SUI: sui client faucet');
    }
    process.exit(1);
  }
  
  console.log();
  console.log('Building tide_core package...');
  
  // Build the package
  const corePath = path.resolve(__dirname, '../../contracts/core');
  
  let buildOutput: { modules: string[]; dependencies: string[] };
  try {
    const output = execSync('sui move build --dump-bytecode-as-base64', {
      cwd: corePath,
      encoding: 'utf-8',
    });
    buildOutput = JSON.parse(output);
  } catch (error) {
    console.error('Error building package:', error);
    process.exit(1);
  }
  
  console.log('Publishing tide_core...');
  
  // Create publish transaction
  const tx = new Transaction();
  const [upgradeCap] = tx.publish({
    modules: buildOutput.modules,
    dependencies: buildOutput.dependencies,
  });
  
  // Transfer upgrade cap to deployer
  tx.transferObjects([upgradeCap], deployerAddress);
  
  // Execute
  const result = await client.signAndExecuteTransaction({
    signer: keypair,
    transaction: tx,
    options: {
      showObjectChanges: true,
      showEffects: true,
    },
  });
  
  if (result.effects?.status?.status !== 'success') {
    console.error('Deployment failed:', result.effects?.status?.error);
    process.exit(1);
  }
  
  console.log();
  console.log('✅ Deployment successful!');
  console.log(`Transaction: ${result.digest}`);
  console.log();
  
  // Parse created objects
  const createdObjects = result.objectChanges?.filter(o => o.type === 'created') || [];
  const publishedPackage = result.objectChanges?.find(o => o.type === 'published');
  
  const deployment: DeploymentResult = {
    network,
    deployedAt: new Date().toISOString(),
    deployer: deployerAddress,
    digest: result.digest,
    packageId: publishedPackage?.type === 'published' ? publishedPackage.packageId : '',
    objects: {},
  };
  
  // Extract object IDs by type
  for (const obj of createdObjects) {
    if (obj.type !== 'created') continue;
    
    const objectType = obj.objectType;
    const objectId = obj.objectId;
    
    if (objectType.includes('::tide::Tide')) {
      deployment.objects.tide = objectId;
    } else if (objectType.includes('::tide::AdminCap')) {
      deployment.objects.adminCap = objectId;
    } else if (objectType.includes('::council::CouncilCap')) {
      deployment.objects.councilCap = objectId;
    } else if (objectType.includes('::council::CouncilConfig')) {
      deployment.objects.councilConfig = objectId;
    } else if (objectType.includes('::registry::ListingRegistry')) {
      deployment.objects.registry = objectId;
    }
  }
  
  console.log('Created Objects:');
  console.log('─────────────────────────────────────────────────────────');
  console.log(`Package ID:     ${deployment.packageId}`);
  console.log(`Tide:           ${deployment.objects.tide || 'N/A'}`);
  console.log(`AdminCap:       ${deployment.objects.adminCap || 'N/A'}`);
  console.log(`CouncilCap:     ${deployment.objects.councilCap || 'N/A'}`);
  console.log(`CouncilConfig:  ${deployment.objects.councilConfig || 'N/A'}`);
  console.log(`Registry:       ${deployment.objects.registry || 'N/A'}`);
  console.log('─────────────────────────────────────────────────────────');
  
  // Save deployment artifacts
  const deploymentsDir = path.resolve(__dirname, `../../deployments/${network}`);
  fs.mkdirSync(deploymentsDir, { recursive: true });
  
  const deploymentPath = path.join(deploymentsDir, 'tide_core.json');
  fs.writeFileSync(deploymentPath, JSON.stringify(deployment, null, 2));
  
  console.log();
  console.log(`Saved deployment to: ${deploymentPath}`);
  console.log();
  console.log('Next steps:');
  console.log('1. Deploy faith_router adapter');
  console.log('2. Create FAITH listing (Listing #1)');
  console.log('3. Transfer CouncilCap to multisig');
  console.log('4. Activate the listing');
}

deploy().catch((error) => {
  console.error('Deployment error:', error);
  process.exit(1);
});
