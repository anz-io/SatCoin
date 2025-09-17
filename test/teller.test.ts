import { expect } from "chai"
import { ethers, upgrades } from "hardhat"
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers"
import { deployContract, deployUpgradeableContract } from "../scripts/utils"
import { MockBUSD, MockOracle, MockUSDC, SatCoin, Teller } from "../typechain-types"
import { parseUnits, ZeroAddress } from "ethers"

describe("Teller", function () {

  async function deployContracts() {
    const [admin, user] = await ethers.getSigners()

    const mockusdc = await deployContract("MockUSDC", []) as MockUSDC
    const mockbusd = await deployContract("MockBUSD", []) as MockBUSD
    const satcoin = await deployUpgradeableContract("SatCoin", []) as SatCoin

    const oracle = await deployContract("MockOracle", []) as MockOracle
    const teller = await deployUpgradeableContract("Teller", [
      admin.address, await satcoin.getAddress(), await oracle.getAddress(),
    ]) as Teller

    return { satcoin, mockusdc, mockbusd, admin, user, oracle, teller }
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
    await teller.connect(user).buyExactIn(
      parseUnits("1150", 6), mockusdcAddress, 0, ZeroAddress
    )
    let balanceAfter = await satcoin.balanceOf(user.address)
    expect(balanceAfter).to.equal(balanceBefore + parseUnits("989990.1", 18))

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
      parseUnits("0.01", 8 + 18), mockusdcAddress, parseUnits("1250", 6), ZeroAddress
    )
    balanceAfter = await mockusdc.balanceOf(user.address)
    expect(balanceAfter).to.be.closeTo(
      balanceBefore - parseUnits("1161.7335", 6), parseUnits("1", 6),
    )

    await teller.setSlippageCoefficient(10000001n)    // a bit different from 1e7

    /**
     * Sell using exact 1000 SatCoin:
     *  - Before fee: 1000 sats -> 1.15 USDC
     *  - After fee: 1.15 USDC * (1 - 1%) = 1.1385 USDC
     *  - Slippage can be ignored (too small)
     */
    balanceBefore = await mockusdc.balanceOf(user.address)
    await satcoin.connect(user).approve(tellerAddress, parseUnits("1000", 18))
    await teller.connect(user).sellExactIn(
      parseUnits("1000", 18), mockusdcAddress, 0, ZeroAddress
    )
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
      parseUnits("1.15", 6), mockusdcAddress, parseUnits("1100", 18), ZeroAddress
    )
    balanceAfter = await satcoin.balanceOf(user.address)
    expect(balanceAfter).to.be.closeTo(
      balanceBefore - parseUnits("1010.1009", 18), parseUnits("0.0010", 18),
    )
  })


  it("should pass admin functions in Teller", async function () {
    const { satcoin, mockusdc, admin, teller } = await loadFixture(deployContracts)

    await satcoin.mint(admin.address, parseUnits("100", 8 + 18))
    await mockusdc.mint(admin.address, parseUnits("1000000", 6))

    await satcoin.approve(await teller.getAddress(), parseUnits("100", 8 + 18))
    await teller.deposit(await satcoin.getAddress(), parseUnits("100", 8 + 18))
    
    await expect(teller.withdraw(await satcoin.getAddress(), parseUnits("101", 8 + 18)))
      .to.be.revertedWith("Teller: Insufficient balance")
    await teller.withdraw(await satcoin.getAddress(), parseUnits("100", 8 + 18))

    await teller.addSupportedToken(await mockusdc.getAddress())
    await teller.removeSupportedToken(await mockusdc.getAddress())
    await expect(teller.previewBuyExactIn(parseUnits("100", 6), await mockusdc.getAddress()))
      .to.be.revertedWith("Teller: Token not supported")
  })


  it("should pass oracle functions", async function () {
    const { oracle } = await loadFixture(deployContracts)
    await oracle.setPrice(parseUnits("115000", 8))
    
    expect(await oracle.description()).to.be.equal("Mock oracle for testing.")
    expect(await oracle.version()).to.be.equal(1)
    await expect(oracle.getRoundData(0))
      .to.be.revertedWith("not available")
  })


  it("should buy correctly with 18-decimals stablecoin", async function () {
    const { satcoin, mockbusd, admin, user, oracle, teller } = await loadFixture(deployContracts)

    const tellerAddress = await teller.getAddress()
    const satcoinAddress = await satcoin.getAddress()
    const mockbusdAddress = await mockbusd.getAddress()

    // Mint SatCoin and BUSD
    await satcoin.mint(admin.address, parseUnits("100", 8 + 18))
    await mockbusd.mint(admin.address, parseUnits("1000000", 18))
    await mockbusd.mint(user.address, parseUnits("10000", 18))
    
    // Prepare tokens for Teller
    await satcoin.approve(tellerAddress, parseUnits("100", 8 + 18))
    await mockbusd.approve(tellerAddress, parseUnits("1000000", 18))
    await teller.deposit(satcoinAddress, parseUnits("100", 8 + 18))
    await teller.deposit(mockbusdAddress, parseUnits("1000000", 18))

    // Config in Teller
    await teller.setFeeRate(parseUnits("0.01", 18))
    await teller.addSupportedToken(mockbusdAddress)
    await oracle.setPrice(parseUnits("115000", 8))

    /**
     * Buy using exact 1150 BUSD: 
     *  - Bitcoin amount (ideal): 0.01 BTC
     *  - Slippage: 0.1% * 1% = 0.001%
     *  - Fee Rate: 1%
     *  - SatCoin amount (after fees) 
     *      = 0.01 BTC * 10^8 sats/BTC * (1 - 0.001%) * (1 - 1%) 
     *      = 989990.1 sats
     */
    let balanceBefore = await satcoin.balanceOf(user.address)
    await mockbusd.connect(user).approve(tellerAddress, parseUnits("1150", 18))
    await teller.connect(user).buyExactIn(
      parseUnits("1150", 18), mockbusdAddress, 0, ZeroAddress
    )
    let balanceAfter = await satcoin.balanceOf(user.address)
    expect(balanceAfter).to.equal(balanceBefore + parseUnits("989990.1", 18))
  })


})