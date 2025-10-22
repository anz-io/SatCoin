import "dotenv/config"
import { upgradeContract } from "./utils"

async function main() {
  await upgradeContract(process.env.BNB_TELLER!, "Teller", true)
  await upgradeContract(process.env.BNB_DCA!, "DCA", true)

  // await upgradeContract(process.env.SEPOLIA_POR!, "ProofOfReserve", true)
  // await upgradeContract(process.env.POL_NFT!, "SatCoinNFTTest", true)
  // await upgradeContract(process.env.BNB_STC!, "SatCoin", true)

  // await upgradeContract(process.env.BNB_SPM!, "SpendingPolicyModule", true)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

