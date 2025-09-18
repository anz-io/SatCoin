import { expect } from "chai"
import { ethers, upgrades } from "hardhat"
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers"
import { deployContract, deployUpgradeableContract } from "../scripts/utils"
import { DCA, MockOracle, MockUSDC, SatCoin, Teller } from "../typechain-types"
import { hexlify, parseUnits, toUtf8Bytes, ZeroAddress } from "ethers"

describe("DCA", function () {

  async function deployContracts() {
    const [admin, operator, user1, user2] = await ethers.getSigners()

    const mockusdc = await deployContract("MockUSDC", []) as MockUSDC
    const satcoin = await deployUpgradeableContract("SatCoin", []) as SatCoin

    const oracle = await deployContract("MockOracle", []) as MockOracle
    const teller = await deployUpgradeableContract("Teller", [
      admin.address, await satcoin.getAddress(), await oracle.getAddress(),
    ]) as Teller

    const dca = await deployUpgradeableContract("DCA", [
      await teller.getAddress(), operator.address, admin.address,
    ]) as DCA

    return {
      satcoin, mockusdc, admin, operator,
      user1, user2, oracle, teller, dca,
    }
  }


  it("should create, update, cancel, and execute DCA plans correctly", async function () {
    const {
      satcoin, mockusdc, admin, operator,
      user1, user2, oracle, teller, dca,
    } = await loadFixture(deployContracts)

    // =================================================================
    // 1. SETUP PHASE
    // =================================================================

    const tellerAddress = await teller.getAddress();
    const dcaAddress = await dca.getAddress();
    const mockusdcAddress = await mockusdc.getAddress();
    await dca.connect(admin).setOperator(operator.address)

    // Configure Teller: Price, supported token, and liquidity
    await oracle.setPrice(parseUnits("75000", 8)); // 1 BTC = $75,000
    await teller.connect(admin).addSupportedToken(mockusdcAddress);

    // Mint SatCoin for Teller liquidity
    await satcoin.connect(admin).mint(tellerAddress, parseUnits("1", 8 + 18)); // 1 BTC worth of SatCoin

    // Mint USDC for users
    await mockusdc.mint(user1.address, parseUnits("10000", 6));
    await mockusdc.mint(user2.address, parseUnits("10000", 6));

    // Users must approve the DCA contract to spend their USDC
    await mockusdc.connect(user1).approve(dcaAddress, ethers.MaxUint256);
    await mockusdc.connect(user2).approve(dcaAddress, ethers.MaxUint256);


    // =================================================================
    // 2. CREATE DCA PLANS PHASE
    // =================================================================

    // Enums for readability
    const EXACT_IN = 0n;
    const EXACT_OUT = 1n;
    const WEEKLY = 0n;
    const MONTHLY = 1n;

    // User1 and User2 create 10 plans in total
    await dca.connect(user1).createDCA(
      mockusdcAddress, EXACT_IN, WEEKLY, parseUnits("100", 6), 0
    ); // Plan 1
    await dca.connect(user2).createDCA(
      mockusdcAddress, EXACT_OUT, MONTHLY, parseUnits("10000", 18), parseUnits("10", 6)
    ); // Plan 2: Get 10k sats for max 10 USDC
    await dca.connect(user1).createDCA(
      mockusdcAddress, EXACT_OUT, WEEKLY, parseUnits("50000", 18), parseUnits("50", 6)
    ); // Plan 3
    await dca.connect(user2).createDCA(
      mockusdcAddress, EXACT_IN, WEEKLY, parseUnits("200", 6), 0
    ); // Plan 4
    await dca.connect(user1).createDCA(
      mockusdcAddress, EXACT_IN, MONTHLY, parseUnits("50", 6), 0
    ); // Plan 5
    await dca.connect(user2).createDCA(
      mockusdcAddress, EXACT_OUT, WEEKLY, parseUnits("25000", 18), parseUnits("25", 6)
    ); // Plan 6
    await dca.connect(user1).createDCA(
      mockusdcAddress, EXACT_IN, WEEKLY, parseUnits("150", 6), 0
    ); // Plan 7
    await dca.connect(user2).createDCA(
      mockusdcAddress, EXACT_IN, MONTHLY, parseUnits("300", 6), 0
    ); // Plan 8
    await dca.connect(user1).createDCA(
      mockusdcAddress, EXACT_OUT, MONTHLY, parseUnits("75000", 18), parseUnits("75", 6)
    ); // Plan 9
    await dca.connect(user2).createDCA(
      mockusdcAddress, EXACT_IN, WEEKLY, parseUnits("125", 6), 0
    ); // Plan 10

    // Verify plan creation
    expect(await dca.getPlansByUser(user1.address)).to.have.lengthOf(5);
    expect(await dca.getPlansByUser(user2.address)).to.have.lengthOf(5);
    expect(await dca.nextPlanId()).to.equal(11);
    expect(await dca.plansLength()).to.equal(10);


    // =================================================================
    // 3. UPDATE AND CANCEL PHASE
    // =================================================================

    // User1 updates Plan 1
    const newAmount = parseUnits("120", 6);
    await expect(dca.connect(user1).updateDCA(1, newAmount, 0))
      .to.emit(dca, "DCAUpdated")
      .withArgs(user1.address, 1, [
        user1.address, mockusdcAddress, EXACT_IN, WEEKLY, newAmount, 0, 0, true,
      ]);

    const plan1 = await dca.dcaPlans(1);
    expect(plan1.amount).to.equal(newAmount);

    // User2 updates Plan 6
    await expect(dca.connect(user2).updateDCA(6, parseUnits("25000", 18), parseUnits("25", 6)))
      .to.emit(dca, "DCAUpdated")
      .withArgs(user2.address, 6, [
        user2.address, mockusdcAddress, EXACT_OUT, WEEKLY,
        parseUnits("25000", 18), parseUnits("25", 6), 0, true,
      ]);

    // User2 cancels Plan 4
    const plan4BeforeCancel = await dca.dcaPlans(4);
    await expect(dca.connect(user2).cancelDCA(4))
      .to.emit(dca, "DCACanceled")
      .withArgs(user2.address, 4, [
        user2.address, mockusdcAddress, EXACT_IN, WEEKLY, plan4BeforeCancel.amount, 0, 0, false
      ]);
    const plan4 = await dca.dcaPlans(4);
    expect(plan4.isActive).to.be.false;
    expect(await dca.getPlansByUser(user2.address)).to.have.lengthOf(4); // List of active plans reduced

    // User2 cancels Plan 8
    const plan8BeforeCancel = await dca.dcaPlans(8);
    await expect(dca.connect(user2).cancelDCA(8))
      .to.emit(dca, "DCACanceled")
      .withArgs(user2.address, 8, [
        user2.address, mockusdcAddress, EXACT_IN, MONTHLY, plan8BeforeCancel.amount, 0, 0, false
      ]);
    const plan8 = await dca.dcaPlans(8);
    expect(plan8.isActive).to.be.false;
    expect(await dca.getPlansByUser(user2.address)).to.have.lengthOf(3); // List of active plans reduced

    expect(await dca.getPlansByUser(user1.address)).to.be.deep.equal([1, 3, 5, 7, 9]);
    expect(await dca.getPlansByUser(user2.address)).to.be.deep.equal([2, 10, 6]);


    // =================================================================
    // 4. EXECUTE BATCH PHASE
    // =================================================================

    const planIdsToExecute = [1, 2, 3, 5, 6, 7, 9, 10]; // All plans except canceled plan 4 and 8

    // Calculate expected SatCoin amounts for each user before execution
    let expectedSatCoinForUser1 = 0n;
    let expectedSatCoinForUser2 = 0n;

    for (const planId of planIdsToExecute) {
      const plan = await dca.dcaPlans(planId);
      if (plan.dcaType === EXACT_IN) {
        const [satCoinAmountOut,] = await teller.previewBuyExactIn(plan.amount, mockusdcAddress);
        if (plan.user === user1.address) {
          expectedSatCoinForUser1 += satCoinAmountOut;
        } else {
          expectedSatCoinForUser2 += satCoinAmountOut;
        }
      } else { // EXACT_OUT
        if (plan.user === user1.address) {
          expectedSatCoinForUser1 += plan.amount;
        } else {
          expectedSatCoinForUser2 += plan.amount;
        }
      }
    }

    // Get balances before execution
    const user1SatCoinBefore = await satcoin.balanceOf(user1.address);
    const user2SatCoinBefore = await satcoin.balanceOf(user2.address);

    // Operator executes the batch
    await dca.connect(operator).executeBatchDCA(planIdsToExecute);

    // Get balances after execution
    const user1SatCoinAfter = await satcoin.balanceOf(user1.address);
    const user2SatCoinAfter = await satcoin.balanceOf(user2.address);

    // Verify balance changes
    expect(user1SatCoinAfter).to.equal(user1SatCoinBefore + expectedSatCoinForUser1);
    expect(user2SatCoinAfter).to.equal(user2SatCoinBefore + expectedSatCoinForUser2);

    // Verify that lastExecuted timestamp was updated for an executed plan
    const executedPlan1 = await dca.dcaPlans(1);
    const latestTimestamp = await time.latest();
    expect(executedPlan1.lastExecuted).to.equal(latestTimestamp);

    // Verify that canceled plan was not executed and timestamp is 0
    const canceledPlan4 = await dca.dcaPlans(4);
    expect(canceledPlan4.lastExecuted).to.equal(0);
  });


  it("should handle failed executions correctly in a batch", async function () {
    const {
      mockusdc, admin, operator, user1, oracle, teller, dca, satcoin,
    } = await loadFixture(deployContracts)

    // =================================================================
    // 1. SETUP
    // =================================================================
    const dcaAddress = await dca.getAddress();
    const mockusdcAddress = await mockusdc.getAddress();
    await dca.connect(admin).setOperator(operator.address);
    await teller.connect(admin).addSupportedToken(mockusdcAddress);
    await oracle.setPrice(parseUnits("75000", 8));
    await satcoin.connect(admin).mint(await teller.getAddress(), parseUnits("1", 8 + 18));

    // Mint just enough USDC for one plan, so the second one fails
    await mockusdc.mint(user1.address, parseUnits("150", 6));
    await mockusdc.connect(user1).approve(dcaAddress, ethers.MaxUint256);

    // =================================================================
    // 2. CREATE PLANS
    // =================================================================
    const EXACT_IN = 0n;
    const WEEKLY = 0n;

    // Plan 1: Valid and will succeed
    await dca.connect(user1).createDCA(mockusdcAddress, EXACT_IN, WEEKLY, parseUnits("100", 6), 0);

    // Plan 2: User1 doesn't have enough USDC for this one, so it will fail
    await dca.connect(user1).createDCA(mockusdcAddress, EXACT_IN, WEEKLY, parseUnits("200", 6), 0);

    // Plan 3: This plan will be canceled before execution
    await dca.connect(user1).createDCA(mockusdcAddress, EXACT_IN, WEEKLY, parseUnits("50", 6), 0);
    await dca.connect(user1).cancelDCA(3);

    // =================================================================
    // 3. EXECUTE AND VERIFY EVENTS
    // =================================================================
    const planIdsToExecute = [1, 2, 3]; // One success, one failure, one inactive
    const tx = await dca.connect(operator).executeBatchDCA(planIdsToExecute);

    // Verify Plan 3 (inactive plan) triggered "Inactive or invalid plan"
    await expect(tx)
      .to.emit(dca, "DCAExecuted")
      .withArgs(3, false, 0, 0, hexlify(toUtf8Bytes("Inactive or invalid plan")));

    // Verify Plan 2 (insufficient funds) in try/catch failed
    await expect(tx)
      .to.emit(dca, "DCAExecuted")
      .withArgs(2, false, 0, 0, (reason: any) => {
        // The exact revert reason from ERC20 might be complex, 
        // so we just check that a reason exists.
        return reason.length > 2; 
      });

    // Verify Plan 1 executed successfully
    await expect(tx)
      .to.emit(dca, "DCAExecuted")
      .withArgs(1, true, parseUnits("100", 6), (amountOut: any) => amountOut > 0, "0x");

    // Check Plan 3 status, ensure it was not executed
    const plan3 = await dca.dcaPlans(3);
    expect(plan3.lastExecuted).to.equal(0);
  });


})