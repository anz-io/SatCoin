import { ethers } from "hardhat";
import { formatUnits, getBytes, parseUnits, Signature, ZeroAddress } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

import "dotenv/config";
import { 
  SpendingPolicyModule, SubscriptionGuard, 
  WalletInitializer, Safe as SafeContract, MockUSDC,
 } from "../typechain-types";


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


async function main() {

  // Load signers and contract addresses
  const [admin, user1] = await ethers.getSigners();
  console.log(`👤 Deployer address: ${admin.address}\n`);

  const walletInitializer = await ethers.getContractAt(
    "WalletInitializer", process.env.BNB_WI!
  ) as WalletInitializer
  const subscriptionGuard = await ethers.getContractAt(
    "SubscriptionGuard", process.env.BNB_SG!
  ) as SubscriptionGuard
  const spendingPolicyModule = await ethers.getContractAt(
    "SpendingPolicyModule", process.env.BNB_SPM!
  ) as SpendingPolicyModule
  console.log(`🔮 Wallet Initializer address: ${await walletInitializer.getAddress()}`);
  console.log(`🔮 Subscription Guard address: ${await subscriptionGuard.getAddress()}`);
  console.log(`🔮 Spending Policy Module address: ${await spendingPolicyModule.getAddress()}\n`);

  const safe0 = await ethers.getContractAt(
    "Safe", process.env.BNB_SAFE_0!
  ) as SafeContract
  const mockUSDC = await ethers.getContractAt(
    "MockUSDC", process.env.BNB_MUSDC!
  ) as MockUSDC
  console.log(`🔑 Safe0 address: ${await safe0.getAddress()}`);
  console.log(`💵 MockUSDC address: ${await mockUSDC.getAddress()}\n`);

  // Set daily limit
  await executeSafeTx(
    safe0,
    await spendingPolicyModule.getAddress(),
    '0',
    spendingPolicyModule.interface.encodeFunctionData(
      "setDailyLimit",
      [await mockUSDC.getAddress(), parseUnits("1000", 6)],  // Allow 1000 USDC withdrawals
    ),
    [admin, user1],
  )
  
  // Check if the daily limit is set
  const dailyLimit = await spendingPolicyModule.getDailyLimit(safe0, await mockUSDC.getAddress());
  console.log(`✅ New daily limit set: ${formatUnits(dailyLimit, 6)}`);

  // Withdraw USDC
  const tx = await spendingPolicyModule.connect(user1).executeDailyTransfer(
    await safe0.getAddress(),
    await mockUSDC.getAddress(),
    user1.address,
    parseUnits("100", 6),
  )
  console.log(`💵 Withdrawal of 100 USDC transaction hash: ${tx.hash}`);

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });