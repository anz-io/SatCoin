import "dotenv/config"
import { deployContract, deployUpgradeableContract } from "./utils"
import { ethers } from "hardhat";

async function main() {
  const [admin] = await ethers.getSigners()
  
  // await deployUpgradeableContract("ProofOfReserve", [], true)
  // await deployUpgradeableContract("SatCoin", [], true)
  // await deployUpgradeableContract("SatCoinNFTTest", [
  //   "SatCoin NFT - Test 2", "SatCoin NFT - Test 2", admin.address, admin.address,
  // ], true)

  await deployUpgradeableContract("SubscriptionGuard", [admin.address], true)
  await deployUpgradeableContract("SpendingPolicyModule", [], true)
  await deployContract("WalletInitializer", [], true)

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

