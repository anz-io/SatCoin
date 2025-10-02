import "dotenv/config"
import { deployUpgradeableContract } from "./utils"
import { ethers } from "hardhat";

async function main() {
  const [admin] = await ethers.getSigners()
  
  await deployUpgradeableContract("ProofOfReserve", [], true)
  await deployUpgradeableContract("SatCoin", [], true)
  await deployUpgradeableContract("SatCoinNFT", [
    "SatCoin NFT", "SatCoin NFT", admin.address, admin.address,
  ], true)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

