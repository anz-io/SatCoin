// npx hardhat console --network bnb

require("dotenv").config()
let RESET = "\x1b[0m"
let GREEN = "\x1b[32m"

let tellerFactory = await ethers.getContractFactory("Teller")
let teller = await upgrades.deployProxy(tellerFactory, [
  process.env.ADDRESS_ADMIN, process.env.BNB_STC, process.env.BNB_ORACLE_BTCUSD,
])
console.log(`Teller deployed to: ${GREEN}${await teller.getAddress()}${RESET}`)

let dcaFactory = await ethers.getContractFactory("DCA")
let dca = await upgrades.deployProxy(dcaFactory, [
  await teller.getAddress(), process.env.ADDRESS_ADMIN, process.env.ADDRESS_ADMIN,
])
console.log(`DCA deployed to: ${GREEN}${await dca.getAddress()}${RESET}`)

let safe = await ethers.getContractAt("Safe", process.env.BNB_SAFE_0)
console.log(await safe.modules("0x0000000000000000000000000000000000000001"))
