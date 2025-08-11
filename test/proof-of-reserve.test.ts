import { expect } from "chai"
import { ethers, upgrades } from "hardhat"
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers"
import { deployUpgradeableContract } from "../scripts/utils"
import { ProofOfReserve } from "../typechain-types"

describe("ProofOfReserve", function () {

  async function deployContracts() {
    const [admin, user] = await ethers.getSigners()
    const por = (await deployUpgradeableContract("ProofOfReserve", [])) as ProofOfReserve

    return { por, admin, user }
  }


  it("should deploy the contract correctly", async function () {
    const { por } = await loadFixture(deployContracts)
    expect(await por.getEntriesCount()).to.equal(0)
    expect(await por.getTotalReserve()).to.equal(0)
  })


  it("should add reserve entry correctly", async function () {
    const { por, admin } = await loadFixture(deployContracts)
    
    const btcTxHash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    const timestamp = Math.floor(Date.now() / 1000)
    const btcBlockHeight = 800000
    const btcBalance = 1000000 // 0.01 BTC in satoshis
    const btcAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
    
    // Add reserve entry
    await por.connect(admin).addReserveEntry(
      btcTxHash,
      timestamp,
      btcBlockHeight,
      btcBalance,
      btcAddress
    )
    
    // Check total reserve
    expect(await por.getTotalReserve()).to.equal(btcBalance)
    
    // Check entries count
    expect(await por.getEntriesCount()).to.equal(1)
    
    // Get entry by index
    const entry = await por.getEntryByIndex(0)
    const entries = await por.getEntries(0, 1)
    expect(entries[0]).deep.equal(entry)
    
    // Get entry by BTC address
    const entryByAddress = await por.getEntryByBtcAddress(btcAddress)
    expect(entryByAddress.btcTxHash).to.equal(btcTxHash)
    expect(entryByAddress.btcBalance).to.equal(btcBalance)
  })


  it("should not allow adding duplicate BTC address", async function () {
    const { por, admin } = await loadFixture(deployContracts)
    
    const btcAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
    
    // Add first entry
    await por.connect(admin).addReserveEntry(
      "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
      1000,
      800000,
      1000000,
      btcAddress
    )
    
    // Try to add duplicate address
    await expect(
      por.connect(admin).addReserveEntry(
        "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        2000,
        800001,
        2000000,
        btcAddress
      )
    ).to.be.revertedWith("PoR: btcAddress already exists")
  })


  it("should modify reserve entry correctly", async function () {
    const { por, admin } = await loadFixture(deployContracts)
    
    const btcAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
    const initialBalance = 1000000
    const newBalance = 1500000
    
    // Add initial entry
    await por.connect(admin).addReserveEntry(
      "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
      1000,
      800000,
      initialBalance,
      btcAddress
    )
    
    // Check initial total reserve
    expect(await por.getTotalReserve()).to.equal(initialBalance)
    
    // Modify the entry
    const newTxHash = "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
    const newTimestamp = 2000
    const newBlockHeight = 800001
    
    await por.connect(admin).modifyReserveEntry(
      newTxHash,
      newTimestamp,
      newBlockHeight,
      newBalance,
      btcAddress
    )
    
    // Check updated total reserve
    expect(await por.getTotalReserve()).to.equal(newBalance)
    
    // Verify the modification
    const modifiedEntry = await por.getEntryByBtcAddress(btcAddress)
    expect(modifiedEntry.btcTxHash).to.equal(newTxHash)
    expect(modifiedEntry.timestamp).to.equal(newTimestamp)
    expect(modifiedEntry.btcBlockHeight).to.equal(newBlockHeight)
    expect(modifiedEntry.btcBalance).to.equal(newBalance)
    expect(modifiedEntry.btcAddress).to.equal(btcAddress)
  })


  it("should not allow modifying non-existent BTC address", async function () {
    const { por, admin } = await loadFixture(deployContracts)
    
    const nonExistentAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
    
    await expect(
      por.connect(admin).modifyReserveEntry(
        "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        1000,
        800000,
        1000000,
        nonExistentAddress
      )
    ).to.be.revertedWith("PoR: btcAddress not found")
  })


  it("should handle multiple entries correctly", async function () {
    const { por, admin } = await loadFixture(deployContracts)
    
    // Add multiple entries
    const addresses = [
      "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
      "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wli",
      "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlj"
    ]
    
    for (let i = 0; i < 3; i++) {
      await por.connect(admin).addReserveEntry(
        `0x${i.toString().padStart(64, '0')}`,
        1000 + i,
        800000 + i,
        1000000 + i * 100000,
        addresses[i]
      )
    }
    
    // Check total entries
    expect(await por.getEntriesCount()).to.equal(3)
    
    // Check total reserve
    expect(await por.getTotalReserve()).to.equal(1000000 + 1100000 + 1200000)
    
    // Get entries by range
    const entries = await por.getEntries(0, 3)
    expect(entries.length).to.equal(3)
    expect(entries[0].btcBalance).to.equal(1000000)
    expect(entries[1].btcBalance).to.equal(1100000)
    expect(entries[2].btcBalance).to.equal(1200000)
  })


  it("should only allow owner to add/modify entries", async function () {
    const { por, user } = await loadFixture(deployContracts)
    
    const btcAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
    
    // Non-owner should not be able to add entry
    await expect(
      por.connect(user).addReserveEntry(
        "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        1000,
        800000,
        1000000,
        btcAddress
      )
    ).to.be.revertedWithCustomError(por, "OwnableUnauthorizedAccount")
    
    // Non-owner should not be able to modify entry
    await expect(
      por.connect(user).modifyReserveEntry(
        "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        1000,
        800000,
        1000000,
        btcAddress
      )
    ).to.be.revertedWithCustomError(por, "OwnableUnauthorizedAccount")
  })

})