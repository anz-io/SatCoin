import { expect } from "chai"
import { ethers, upgrades } from "hardhat"
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers"

describe("test the functions", function () {

  async function deployContracts() {
    return { }
  }

  it("should deploy the contract correctly", async function () {
    await loadFixture(deployContracts)
  })


  it("should finish user journey", async function () {
    const { } = await loadFixture(deployContracts)
    const [deployer, operator, user1, user2] = await ethers.getSigners()
  })
  
})
