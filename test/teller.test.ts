import { expect } from "chai"
import { ethers, upgrades } from "hardhat"
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers"
import { deployContract, deployUpgradeableContract } from "../scripts/utils"
import { MockOracle, MockUSDC, SatCoin, Teller } from "../typechain-types"
import { formatEther, formatUnits, parseEther, parseUnits } from "ethers"

describe("Teller", function () {

  async function deployContracts() {
    const [admin, user] = await ethers.getSigners()

    const mockusdc = await deployContract("MockUSDC", []) as MockUSDC
    const satcoin = await deployUpgradeableContract("SatCoin", []) as SatCoin

    const oracle = await deployContract("MockOracle", []) as MockOracle
    const teller = await deployUpgradeableContract("Teller", [
      admin.address, await satcoin.getAddress(), await oracle.getAddress(),
    ]) as Teller

    return { satcoin, mockusdc, admin, user, oracle, teller }
  }


  it("should deploy the contract correctly", async function () {
    const { oracle } = await loadFixture(deployContracts)
    expect((await oracle.latestRoundData())[1]).to.equal(0)
  })


  it("should buy and sell correctly", async function () {
    const { satcoin, mockusdc, admin, user, oracle, teller } = await loadFixture(deployContracts)

    const tellerAddress = await teller.getAddress()
    const satcoinAddress = await satcoin.getAddress()
    const mockusdcAddress = await mockusdc.getAddress()

    // Mint SatCoin and USDC
    await satcoin.mint(admin.address, parseUnits("100", 8 + 18))
    await mockusdc.mint(admin.address, parseUnits("1000000", 6))
    await mockusdc.mint(user.address, parseUnits("10000", 6))
    
    // Prepare tokens for Teller
    await satcoin.approve(tellerAddress, parseUnits("100", 8 + 18))
    await mockusdc.approve(tellerAddress, parseUnits("1000000", 6))
    await teller.deposit(satcoinAddress, parseUnits("100", 8 + 18))
    await teller.deposit(mockusdcAddress, parseUnits("1000000", 6))

    // Config in Teller
    await teller.setFeeRate(parseUnits("0.01", 18))
    await teller.addSupportedToken(mockusdcAddress)
    await oracle.setPrice(parseUnits("115000", 8))

    /**
     * Buy using exact 1150 USDC: 
     *  - Bitcoin amount (ideal): 0.01 BTC
     *  - Slippage: 0.1% * 1% = 0.001%
     *  - Fee Rate: 1%
     *  - SatCoin amount (after fees) 
     *      = 0.01 BTC * 10^8 sats/BTC * (1 - 0.001%) * (1 - 1%) 
     *      = 989990.1 sats
     */
    let balanceBefore = await satcoin.balanceOf(user.address)
    await mockusdc.connect(user).approve(tellerAddress, parseUnits("1150", 6))
    await teller.connect(user).buyExactIn(parseUnits("1150", 6), mockusdcAddress, 0)
    let balanceAfter = await satcoin.balanceOf(user.address)
    expect(balanceAfter).to.equal(balanceBefore + parseEther("989990.1"))

    /**
     * Buy for exact 0.01 BTC:
     *  - Bitcoin amount (ideal): 0.01 BTC
     *  - After fee: 0.01 BTC / (1 - 1%) = 0.01010101 ~ 1010101.0101 sats
     *  - Slippage: 0.1% * 1.0101% ~ 0.010101%
     *  - After slippage: 1010101.0101 sats / (1 - 0.010101%) = 1010203.0507 sats
     *  - USDC amount: 1010203.0507 * 115000 / 10^8 = 1161.7335 USDC
     */
    balanceBefore = await mockusdc.balanceOf(user.address)
    await mockusdc.connect(user).approve(tellerAddress, parseUnits("1250", 6))
    await teller.connect(user).buyExactOut(
      parseUnits("0.01", 8 + 18), mockusdcAddress, parseUnits("1250", 6)
    )
    balanceAfter = await mockusdc.balanceOf(user.address)
    expect(balanceAfter).to.be.closeTo(
      balanceBefore - parseUnits("1161.7335", 6), parseUnits("1", 6),
    )

    /**
     * Sell using exact 1000 SatCoin:
     *  - Before fee: 1000 sats -> 1.15 USDC
     *  - After fee: 1.15 USDC * (1 - 1%) = 1.1385 USDC
     *  - Slippage can be ignored (too small)
     */
    balanceBefore = await mockusdc.balanceOf(user.address)
    await satcoin.connect(user).approve(tellerAddress, parseUnits("1000", 18))
    await teller.connect(user).sellExactIn(parseUnits("1000", 18), mockusdcAddress, 0)
    balanceAfter = await mockusdc.balanceOf(user.address)
    expect(balanceAfter).to.be.closeTo(
      balanceBefore + parseUnits("1.1385", 6), parseUnits("0.0001", 6),
    )

    /**
     * Sell for exact 1.15 USDC:
     *  - After fee: 1.15 USDC / (1 - 1%) = 1.161616 USDC
     *  - Slippage can be ignored (too small)
     *  - SatCoin amount: 1.161616 * 10^6 / 1150 = 1010.1009 sats
     */
    balanceBefore = await satcoin.balanceOf(user.address)
    await satcoin.connect(user).approve(tellerAddress, parseUnits("1100", 18))
    await teller.connect(user).sellExactOut(
      parseUnits("1.15", 6), mockusdcAddress, parseUnits("1100", 18)
    )
    balanceAfter = await satcoin.balanceOf(user.address)
    expect(balanceAfter).to.be.closeTo(
      balanceBefore - parseUnits("1010.1009", 18), parseUnits("0.0010", 18),
    )


  })


})