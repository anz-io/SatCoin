import { UpgradeableUSDC } from "../typechain-types"
import "dotenv/config"
import { deployContract, deployUpgradeableContract } from "./utils"

async function main() {
  await deployUpgradeableContract(
    "UpgradeableUSDC", []
  )
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

