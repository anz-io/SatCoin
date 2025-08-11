import "dotenv/config"
import { upgradeContract } from "./utils"

async function main() {
  await upgradeContract(process.env.USDC_ADDRESS!, "UpgradeableUSDC")
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

