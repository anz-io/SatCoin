import { ethers, network as hardhatNetwork } from "hardhat";
import Safe, { SafeAccountConfig, PredictedSafeProps } from "@safe-global/protocol-kit";

async function main() {
  const [admin] = await ethers.getSigners();

  console.log(`👤 Deployer address: ${admin.address}`);

  // Predicted Safe Address
  const protocolKit = await Safe.init({
    provider: (hardhatNetwork.config as any).url,
    signer: (hardhatNetwork.config.accounts as any)[0],
    predictedSafe: {
      safeAccountConfig: {
        owners: [
          admin.address,
          "0x7b7C993c3c283aaca86913e1c27DB054Ce5fA143",
        ],
        threshold: 2
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
  const txResponse = await admin.sendTransaction({
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