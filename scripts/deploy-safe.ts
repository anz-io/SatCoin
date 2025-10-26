import { ethers, network as hardhatNetwork } from "hardhat";
import Safe from "@safe-global/protocol-kit";

import "dotenv/config";
import { SpendingPolicyModule, SubscriptionGuard, WalletInitializer, WalletNameRegistry } from "../typechain-types";

async function main() {
  
  // Load signers and contract addresses
  const [user0, user1] = await ethers.getSigners();
  console.log(`👤 Deployer address: ${user0.address}\n`);

  const walletInitializer = await ethers.getContractAt(
    "WalletInitializer", process.env.BNB_WI!
  ) as WalletInitializer
  const subscriptionGuard = await ethers.getContractAt(
    "SubscriptionGuard", process.env.BNB_SG!
  ) as SubscriptionGuard
  const spendingPolicyModule = await ethers.getContractAt(
    "SpendingPolicyModule", process.env.BNB_SPM!
  ) as SpendingPolicyModule
  const walletNameRegistry = await ethers.getContractAt(
    "WalletNameRegistry", process.env.BNB_WNR!
  ) as WalletNameRegistry
  console.log(`🔮 Wallet Initializer address: ${await walletInitializer.getAddress()}`);
  console.log(`🔮 Subscription Guard address: ${await subscriptionGuard.getAddress()}`);
  console.log(`🔮 Spending Policy Module address: ${await spendingPolicyModule.getAddress()}\n`);

  // Predicted Safe Address
  const walletInitializeData = walletInitializer.interface.encodeFunctionData(
    "initializeSafe",
    [
      await subscriptionGuard.getAddress(), 
      await spendingPolicyModule.getAddress(),
      await walletNameRegistry.getAddress(),
      "My Safe Wallet",
    ]
  );
  const protocolKit = await Safe.init({
    provider: (hardhatNetwork.config as any).url,
    signer: (hardhatNetwork.config.accounts as any)[0],
    predictedSafe: {
      safeAccountConfig: {
        owners: [
          user0.address,
          user1.address,
        ],
        threshold: 2,
        to: process.env.BNB_WI!,    // wallet initializer contract address
        data: walletInitializeData,
      }
    },
  });
  const safeAddress = await protocolKit.getAddress();
  console.log(`🔮 SatCoin Smart Wallet Address: ${safeAddress}`);

  // Check if there is a contract on the address
  const code = await ethers.provider.getCode(safeAddress);
  if (code !== '0x') {
    console.log("⚠️  Warning: There is a contract on the address, it may have been deployed.");
    return;
  }

  // Create deployment transaction
  console.log("⏳ Creating deployment transaction...");
  const deploymentTransaction = await protocolKit.createSafeDeploymentTransaction();
  console.log("✅ Deployment transaction created!");

  // Send deployment transaction
  console.log(`⏳ Sending deployment transaction to ${hardhatNetwork.name} network...`);
  const txResponse = await user0.sendTransaction({
    to: deploymentTransaction.to,
    value: deploymentTransaction.value,
    data: deploymentTransaction.data,
  });

  console.log(`⛓️  Transaction hash: ${txResponse.hash}`);
  console.log("⏳ Waiting for transaction confirmation...");
  await txResponse.wait();
  console.log("✅ Transaction confirmed!");

  // Verify deployment
  const newProtocolKit = await protocolKit.connect({ safeAddress });

  const isSafeDeployed = await newProtocolKit.isSafeDeployed();
  const finalAddress = await newProtocolKit.getAddress();
  const owners = await newProtocolKit.getOwners();
  const threshold = await newProtocolKit.getThreshold();

  console.log("\n🎉🎉🎉 Deployment verified successfully! 🎉🎉🎉");
  console.log(`✨ SatCoin Smart Wallet Address: ${finalAddress}`);
  console.log(`    Is deployed: ${isSafeDeployed}`);
  console.log("    Owners:", owners);
  console.log(`    Threshold: ${threshold}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });