import { expect } from "chai"
import { ethers } from "hardhat"
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers"
import { getBytes, parseEther, parseUnits, Signature, ZeroAddress } from "ethers"
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers"

import { deployContract, deployUpgradeableContract } from "../scripts/utils"
import {
  SpendingPolicyModule, SubscriptionGuard, MockUSDC,
  Safe as SafeContract, WalletInitializer,
} from "../typechain-types"


async function executeSafeTx(
  safe: SafeContract,
  to: string,
  value: string | bigint,
  data: string,
  signers: HardhatEthersSigner[]
) {
  const nonce = await safe.nonce();
  const operation = 0; // 0 for CALL
  const safeTxGas = 0;
  const baseGas = 0;
  const gasPrice = 0;
  const gasToken = ZeroAddress;
  const refundReceiver = ZeroAddress;

  const txHash = await safe.getTransactionHash(
    to, value, data, operation, safeTxGas, baseGas, 
    gasPrice, gasToken, refundReceiver, nonce,
  );

  let signatures = "0x";
  const sortedSigners = signers.sort(
    (a, b) => a.address.toLowerCase().localeCompare(b.address.toLowerCase())
  );

  for (const signer of sortedSigners) {
    const signature = await signer.signMessage(getBytes(txHash));
    const sig = Signature.from(signature);
    const adjustedV = sig.v + 4;
    const adjustedSig = sig.r.slice(2) + sig.s.slice(2) + adjustedV.toString(16).padStart(2, '0');
    signatures += adjustedSig;
  }

  const txResponse = await safe.execTransaction(
    to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, signatures
  );
  await txResponse.wait();
  return txResponse;
}


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
    const safeAddress = await safe.getAddress();

    const initializerCalldata = walletInitializer.interface.encodeFunctionData(
      "initializeSafe",
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

    // Setup subscription guard
    const subscriptionFee = parseUnits("2.99", 6);
    await subscriptionGuard.connect(admin).setTokenFee(
      await mockUSDC.getAddress(), subscriptionFee,
    );

    return {
      subscriptionGuard, spendingPolicyModule, walletInitializer, subscriptionFee,
      mockUSDC, safe, safeAddress, admin, treasury, user1, user2, user3,
    }
  }


  it("should correctly deploy a Safe wallet and setup Guard & Module", async function () {
    const {
      safe, subscriptionGuard, spendingPolicyModule, user1, user2, user3,
    } = await loadFixture(deployContractsFixture)

    // 1. validate owners and threshold
    const owners = await safe.getOwners();
    const threshold = await safe.getThreshold();

    expect(owners).to.deep.equal([user1.address, user2.address, user3.address]);
    expect(threshold).to.equal(2);

    // 2. validate guard (using storage slot)
    const GUARD_SLOT = "0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8";
    const guardStorageValue = await ethers.provider.getStorage(
      await safe.getAddress(), GUARD_SLOT,
    );
    const guardAddress = ethers.getAddress("0x" + guardStorageValue.slice(-40));
    expect(guardAddress).to.equal(await subscriptionGuard.getAddress());

    // 3. validate module is enabled
    const isModuleEnabled = await safe.isModuleEnabled(
      await spendingPolicyModule.getAddress(),
    );
    expect(isModuleEnabled).to.be.true;
  })


  it("should work as expected when subscription is active or inactive", async function () {
    const {
      safe, subscriptionGuard, user1, user2, user3, 
      mockUSDC, admin, treasury, subscriptionFee,
    } = await loadFixture(deployContractsFixture)
    const safeAddress = await safe.getAddress();

    await mockUSDC.mint(user1.address, parseUnits("100", 6));
    await mockUSDC.connect(user1).approve(
      await subscriptionGuard.getAddress(), ethers.MaxUint256,
    );
    await subscriptionGuard.connect(user1).renewSubscription(
      safeAddress, await mockUSDC.getAddress(),
    );

    // Should pass within the subscription period (15 days later)
    await time.increase(15 * 24 * 60 * 60);
    await executeSafeTx(safe, user3.address, '0', '0x', [user1, user2]);

    // Should be blocked after the subscription period (32 days later)
    await time.increase(17 * 24 * 60 * 60);
    await expect(
      executeSafeTx(safe, user3.address, '0', '0x', [user1, user2])
    ).to.be.revertedWith("SG: Subscription expired, call `renewSubscription`");

    // Should pass if renewing the subscription
    await subscriptionGuard.connect(user1).renewSubscription(
      safeAddress, await mockUSDC.getAddress(),
    );
    await executeSafeTx(safe, user3.address, '0', '0x', [user1, user2]);

    // Should bulk-renew successfully
    await subscriptionGuard.setTreasury(admin.address)
    const balanceBefore = await mockUSDC.balanceOf(user1.address);
    await subscriptionGuard.connect(user1).bulkRenewSubscription(
      safeAddress, await mockUSDC.getAddress(), 10,
    );
    const balanceAfter = await mockUSDC.balanceOf(user1.address);
    expect(balanceAfter).to.equal(balanceBefore - subscriptionFee * 10n);

    // Should pass after 10 months
    await time.increase(10 * 30 * 24 * 60 * 60);
    await executeSafeTx(safe, user3.address, '0', '0x', [user1, user2]);

    // Should be blocked after extra 2 months
    await time.increase(2 * 30 * 24 * 60 * 60);
    await expect(
      executeSafeTx(safe, user3.address, '0', '0x', [user1, user2])
    ).to.be.revertedWith("SG: Subscription expired, call `renewSubscription`");

    // Treasury should have received the fees
    expect(await mockUSDC.balanceOf(treasury.address)).to.equal(subscriptionFee * 2n);
    expect(await mockUSDC.balanceOf(admin.address)).to.equal(subscriptionFee * 10n);
  });


  it("should allow an owner to execute a transfer below the limit", async function () {
    const {
      spendingPolicyModule, subscriptionGuard, mockUSDC, 
      safe, safeAddress, user1, user3, treasury,
    } = await loadFixture(deployContractsFixture)

    const mockUSDCAddress = await mockUSDC.getAddress();
    await mockUSDC.mint(user1.address, parseUnits("100", 6));
    await mockUSDC.connect(user1).transfer(safeAddress, parseUnits("60", 6));
    await mockUSDC.connect(user1).approve(
      await subscriptionGuard.getAddress(), ethers.MaxUint256,
    );
    await subscriptionGuard.connect(user1).renewSubscription(
      safeAddress, await mockUSDC.getAddress(),
    );

    const recipientBalanceBefore = await mockUSDC.balanceOf(user3.address);
    const safeBalanceBefore = await mockUSDC.balanceOf(safeAddress);
    const spentTodayBefore = await spendingPolicyModule.getSpentToday(
      safeAddress, mockUSDCAddress,
    );
    const transferAmount = parseUnits("10", 6);

    // Transfer not allowed: token not set
    await expect(spendingPolicyModule.connect(user1).executeDailyTransfer(
      safeAddress, mockUSDCAddress, user3.address, parseUnits("50", 6),
    )).to.be.revertedWith("SPM: No daily limit for this token");

    // Transfer not allowed: amount exceeds daily limit
    await executeSafeTx(
      safe, await spendingPolicyModule.getAddress(), '0',
      spendingPolicyModule.interface.encodeFunctionData(
        "setDailyLimit",
        [mockUSDCAddress, parseUnits("40", 6)]
      ),
      [user1, user3],
    )
    await expect(
      spendingPolicyModule.connect(user1).executeDailyTransfer(
        safeAddress, mockUSDCAddress, user3.address, parseUnits("50", 6),
      )
    ).to.be.revertedWith("SPM: Exceeds daily limit");

    // Transfer not allowed: caller is not an owner
    await expect(
      spendingPolicyModule.connect(treasury).executeDailyTransfer(
        safeAddress, mockUSDCAddress, user3.address, transferAmount,
      )
    ).to.be.revertedWith("SPM: Caller not a wallet owner");

    // Transfer allowed: amount within daily limit
    await spendingPolicyModule.connect(user1).executeDailyTransfer(
      safeAddress, mockUSDCAddress, user3.address, transferAmount,
    )

    const recipientBalanceAfter = await mockUSDC.balanceOf(user3.address);
    const safeBalanceAfter = await mockUSDC.balanceOf(safeAddress);
    const spentTodayAfter = await spendingPolicyModule.getSpentToday(
      safeAddress, mockUSDCAddress,
    );

    expect(recipientBalanceAfter).to.equal(recipientBalanceBefore + transferAmount);
    expect(safeBalanceAfter).to.equal(safeBalanceBefore - transferAmount);
    expect(spentTodayAfter).to.equal(spentTodayBefore + transferAmount);

    // Transfer not allowed: amount exceeds daily limit
    await expect(
      spendingPolicyModule.connect(user1).executeDailyTransfer(
        safeAddress, mockUSDCAddress, user3.address, parseUnits("40", 6),
      )
    ).to.be.revertedWith("SPM: Exceeds daily limit");

    // Transfer allowed: spent amount resets after one day
    await time.increase(24 * 60 * 60);
    await spendingPolicyModule.connect(user1).executeDailyTransfer(
      safeAddress, mockUSDCAddress, user3.address, parseUnits("40", 6),
    )

    expect(await spendingPolicyModule.getDailyLimit(safeAddress, mockUSDCAddress))
      .to.equal(parseUnits("40", 6));
    expect(await spendingPolicyModule.getDailyLimit(ZeroAddress, mockUSDCAddress))
      .to.equal(parseUnits("0", 6));

  });


  it("should allow an owner to execute a transfer of native token", async function () {
    const {
      spendingPolicyModule, subscriptionGuard, mockUSDC, 
      safe, safeAddress, user1, user3, treasury,
    } = await loadFixture(deployContractsFixture)

    // Renew subscription
    await mockUSDC.mint(user1.address, parseUnits("100", 6));
    await mockUSDC.connect(user1).transfer(safeAddress, parseUnits("60", 6));
    await mockUSDC.connect(user1).approve(
      await subscriptionGuard.getAddress(), ethers.MaxUint256,
    );
    await subscriptionGuard.connect(user1).renewSubscription(
      safeAddress, await mockUSDC.getAddress(),
    );

    // Set daily limit
    await executeSafeTx(
      safe, await spendingPolicyModule.getAddress(), '0',
      spendingPolicyModule.interface.encodeFunctionData(
        "setDailyLimit",
        [await spendingPolicyModule.NATIVE_TOKEN(), parseEther("1")],
      ),
      [user1, user3],
    )

    // Transfer native token to Safe
    await user1.sendTransaction({ to: safeAddress, value: parseEther("1") })

    // Should execute transfer successfully
    await spendingPolicyModule.connect(user1).executeDailyTransfer(
      safeAddress, await spendingPolicyModule.NATIVE_TOKEN(), user3.address, parseEther("0.6"),
    )

    // Should revert if amount exceeds daily limit
    await expect(spendingPolicyModule.connect(user1).executeDailyTransfer(
      safeAddress, await spendingPolicyModule.NATIVE_TOKEN(), user3.address, parseEther("0.6"),
    )).to.be.revertedWith("SPM: Exceeds daily limit");

  })

});