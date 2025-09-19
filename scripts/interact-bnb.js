// npx hardhat console --network bnb

require("dotenv").config()
const RESET = "\x1b[0m"
const GREEN = "\x1b[32m"

const tellerFactory = await ethers.getContractFactory("Teller")
const teller = await upgrades.deployProxy(tellerFactory, [
  process.env.ADDRESS_ADMIN, process.env.BNB_STC, process.env.BNB_ORACLE_BTCUSD,
])
console.log(`Teller deployed to: ${GREEN}${await teller.getAddress()}${RESET}`)

const dcaFactory = await ethers.getContractFactory("DCA")
const dca = await upgrades.deployProxy(dcaFactory, [
  await teller.getAddress(), process.env.ADDRESS_ADMIN, process.env.ADDRESS_ADMIN,
])
console.log(`DCA deployed to: ${GREEN}${await dca.getAddress()}${RESET}`)
