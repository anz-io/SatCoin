// npx hardhat console --network polygon

require("dotenv").config()


/* =============== Fee data & Tx replacement=============== */
let feeData, nonce
feeData = await ethers.provider.getFeeData()
nonce = await ethers.provider.getTransactionCount(admin.address, "pending")
await xxx.xxxx(xxxxxx, {
  nonce: nonce,
  maxFeePerGas: feeData.maxFeePerGas * BigInt(2), 
  maxPriorityFeePerGas: feeData.maxPriorityFeePerGas * BigInt(2),
})
/* ======================================================== */


let [admin] = await ethers.getSigners()
// let nft = await ethers.getContractAt("SatCoinNFT", process.env.POL_NFT)
let nft = await ethers.getContractAt("SatCoinNFTTest", process.env.POL_NFT)
// await nft.updateAllTokenURIs()

// let [url1, url2] = [
//   "https://satcoin-img.s3.ap-southeast-1.amazonaws.com/nft/Mantle.png",
//   "https://satcoin-img.s3.ap-southeast-1.amazonaws.com/nft/Mantle2.png",
// ]

let [url1, url2, url3, url4] = [
  "ipfs://bafybeihexwvk23i5cdfo7qzykl5llusv7wx7xz7p6u4vqwwqbwumnjwtlu/1.jpg", 
  "ipfs://bafybeihexwvk23i5cdfo7qzykl5llusv7wx7xz7p6u4vqwwqbwumnjwtlu/2.png",
  "ipfs://bafybeihexwvk23i5cdfo7qzykl5llusv7wx7xz7p6u4vqwwqbwumnjwtlu/3.png",
  "ipfs://bafybeihexwvk23i5cdfo7qzykl5llusv7wx7xz7p6u4vqwwqbwumnjwtlu/4.png",
]

await nft.setTypeInfo(1, "Holders NFT", url1)
await nft.setTypeInfo(2, "DCA NFT", url2)

let typeId, traits, message, signature

typeId = 1
traits = [
  { key: "Amount (Sats)", value: "1000", displayType: "number" },
  { key: "Duration (Days)", value: "600", displayType: "number" },   // 500 days
]
// traits = [
//   { key: "Amount", value: "4000.00", displayType: "" },
//   { key: "Duration (Days)", value: "200", displayType: "" },   // 200 days
// ]

// typeId = 2
// traits = [
//   { key: "Count", value: "4", displayType: "" },
//   { key: "TotalAmount", value: "10000.000000", displayType: "" },
// ]
// traits = [
//   { key: "Count", value: "6", displayType: "" },
//   { key: "TotalAmount (Sats)", value: "5000", displayType: "" },
// ]

message = await nft.constructMessage(admin.address, typeId, traits)
signature = await admin.signMessage(message)
await nft.mint(admin.address, typeId, traits, signature)

