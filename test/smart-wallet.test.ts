import { expect } from "chai"
import { ethers, upgrades } from "hardhat"
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers"
import { deployContract, deployUpgradeableContract } from "../scripts/utils"
import { SpendingPolicyModule, SubscriptionGuard, MockUSDC, Safe as SafeContract, WalletInitializer } from "../typechain-types"
import Safe, { SafeAccountConfig, ContractNetworksConfig } from '@safe-global/protocol-kit'
import { SafeTransactionDataPartial } from '@safe-global/safe-core-sdk-types'
import { Contract, Signer, ZeroAddress } from "ethers"

describe("SmartWallet", function () {

  async function deployContractsFixture() {
    const [admin, treasury, user1, user2, user3] = await ethers.getSigners()

    // Deploy Mock USDC for payments
    const mockUSDC = await deployContract("MockUSDC", []) as MockUSDC

    // Deploy our custom contracts
    const subscriptionGuard = await deployUpgradeableContract(
      "SubscriptionGuard", [treasury.address]
    ) as SubscriptionGuard

    const spendingPolicyModule = await deployUpgradeableContract(
      "SpendingPolicyModule", []
    ) as SpendingPolicyModule

    const walletInitializer = await deployContract(
      "WalletInitializer", []
    ) as WalletInitializer


    // Deploy Safe wallet
    const safeSingleton = await deployContract("Safe", []) as SafeContract
    const safeProxy = await deployContract(
      "SafeProxy", [await safeSingleton.getAddress()]
    )
    const safe = await ethers.getContractAt("Safe", safeProxy)

    const initializerCalldata = walletInitializer.interface.encodeFunctionData(
      "initialize",
      [await subscriptionGuard.getAddress(), await spendingPolicyModule.getAddress()]
    );

    await safe.setup(
      [user1.address, user2.address, user3.address],
      2,
      await walletInitializer.getAddress(),
      initializerCalldata,
      ZeroAddress,
      ZeroAddress,
      0,
      ZeroAddress,
    )

    return {
      subscriptionGuard, spendingPolicyModule, walletInitializer,
      mockUSDC, safe, admin, treasury, user1, user2, user3,
    }
  }

  describe("Deployment and Initial Setup", function () {
    it("Should correctly deploy a Safe wallet and set its Guard and Module", async function () {
      const { 
        safe, subscriptionGuard, spendingPolicyModule, user1, user2, user3 
      } = await loadFixture(deployContractsFixture)

      // 1. validate owners and threshold
      const owners = await safe.getOwners();
      const threshold = await safe.getThreshold();
      
      expect(owners).to.deep.equal([user1.address, user2.address, user3.address]);
      expect(threshold).to.equal(2);

      // 2. validate guard (using storage slot)
      const GUARD_STORAGE_SLOT = "0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8";
      const guardStorageValue = await ethers.provider.getStorage(await safe.getAddress(), GUARD_STORAGE_SLOT);
      const guardAddress = ethers.getAddress("0x" + guardStorageValue.slice(-40));
      expect(guardAddress).to.equal(await subscriptionGuard.getAddress());

      // 3. validate module is enabled
      const isModuleEnabled = await safe.isModuleEnabled(await spendingPolicyModule.getAddress());
      expect(isModuleEnabled).to.be.true;
    })
  })


});