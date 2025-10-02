// npx hardhat console --network polygon

require("dotenv").config()

const [admin] = await ethers.getSigners()
const nft = await ethers.getContractAt("SatCoinNFT", process.env.POL_NFT)

// await nft.setTypeInfo(1, "Holders NFT", "https://png.pngtree.com/png-vector/20220718/ourmid/pngtree-non-fungible-token-logo-design-nft-icon-gradient-hexagonal-png-image_6005258.png")
// await nft.setTypeInfo(2, "DCA NFT", "https://cdn3d.iconscout.com/3d/premium/thumb/nft-3d-icon-png-download-6479000.png")

let typeId, traits, message, signature

// typeId = 1
// traits = [
//   { key: "Amount", value: "1000.000000", displayType: "number" },
//   { key: "Duration", value: "500", displayType: "" },   // 500 days
// ]
// traits = [
//   { key: "Amount", value: "4000.000000", displayType: "number" },
//   { key: "Duration", value: "200", displayType: "" },   // 200 days
// ]

typeId = 2
traits = [
  { key: "Count", value: "3", displayType: "number" },
  { key: "TotalAmount", value: "10000.000000", displayType: "number" },
]

message = await nft.constructMessage(admin.address, typeId, traits)
signature = await admin.signMessage(message)
await nft.mint(admin.address, typeId, traits, signature)

