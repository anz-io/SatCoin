import "dotenv/config"
import { upgradeContract } from "./utils"

async function main() {
  // await upgradeContract(process.env.SEPOLIA_POR!, "ProofOfReserve", true)
  await upgradeContract(process.env.POL_NFT!, "SatCoinNFTTest", true)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

