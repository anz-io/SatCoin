import "dotenv/config"
import { deployContract, deployUpgradeableContract } from "./utils"
import { ethers } from "hardhat";

async function main() {
  const [admin] = await ethers.getSigners()
  
  // await deployUpgradeableContract("ProofOfReserve", [], true)
  // await deployUpgradeableContract("SatCoin", [], true)
  // await deployUpgradeableContract("SatCoinNFT", [
  //   "SatCoin NFT - Test 3", "SatCoin NFT - Test 3", admin.address, admin.address,
  // ], true)

  // await deployUpgradeableContract("SubscriptionGuard", [admin.address], true)
  // await deployUpgradeableContract("SpendingPolicyModule", [], true)
  // await deployUpgradeableContract("WalletNameRegistry", [], true)
  
  await deployContract("WalletInitializer", [], true)

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

