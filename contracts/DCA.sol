// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./Teller.sol";

using SafeERC20 for IERC20;


/**
 * @title DCA Contract (Upgradeable)
 * @notice Allows users to manage Dollar-Cost Averaging plans for buying SatCoin.
 * @dev This contract follows the Transparent Upgradeable Proxy pattern.
 */
contract DCA is Initializable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {

    // ============================= Constants =============================

    /// @notice The max number of active DCA plans a single user can have.
    uint256 public constant MAX_PLANS_PER_USER = 20;

    /// @notice The max number of DCA plans that can be executed in a single batch txs.
    uint256 public constant MAX_EXECUTIONS_PER_BATCH = 100;

    /// @notice The Teller contract used for executing token swaps.
    ITeller public teller;


    // ============================== Storage ==============================

    /// @notice The address authorized to execute batch DCA plans.
    address public operator;

    /// @notice A counter for generating unique DCA plan IDs. Starts at 1.
    uint256 public nextPlanId;

    /// @notice The type of DCA plan.
    enum DCAType { 
        EXACT_IN,   // Spend a fixed amount of stablecoin for a variable amount of SatCoin.
        EXACT_OUT   // Spend a variable amount of stablecoin for a fixed amount of SatCoin.
    }
    
    /// @notice The execution frequency of the DCA plan.
    enum DCAFrequency { 
        WEEKLY, 
        MONTHLY 
    }

    /// @notice Represents a user's DCA plan.
    struct DCAPlan {
        address user;           // The owner of the plan.
        address tokenIn;        // The stablecoin used for purchase.
        DCAType dcaType;        // The type of the DCA plan (EXACT_IN or EXACT_OUT).
        DCAFrequency dcaFrequency; // The execution frequency.
        uint256 amount;         // stablecoin amount for `EXACT_IN`, SatCoin amount for `EXACT_OUT`.
        uint256 maxAmountIn;    // max amount of stablecoin to spend, only for `EXACT_OUT` mode.
        uint256 lastExecuted;   // Timestamp of the last successful execution.
        bool isActive;          // Flag indicating if the plan is active.
    }

    /// @notice Mapping from a plan ID to its corresponding DCAPlan struct.
    mapping(uint256 => DCAPlan) public dcaPlans;

    /// @notice Mapping from a user's address to an array of their active plan IDs.
    mapping(address => uint256[]) public userPlanIds;

    /// @notice Mapping from a plan ID to its index in the user's `userPlanIds` array for O(1) removal.
    mapping(uint256 => uint256) public planIdToIndex;


    // =============================== Events ==============================

    event OperatorSet(address indexed newOperator);
    event DCACreated(address indexed user, uint256 indexed planId, DCAPlan plan);
    event DCAUpdated(address indexed user, uint256 indexed planId, DCAPlan plan);
    event DCACanceled(address indexed user, uint256 indexed planId, DCAPlan plan);
    event DCAExecuted(
        uint256 indexed planId,
        bool success,
        uint256 amountIn,
        uint256 amountOut,
        bytes reason
    );


    // ======================= Modifier & Constructor ======================

    /**
     * @notice Initializes the contract.
     * @dev Can only be called once.
     * @param _tellerAddress The address of the Teller contract.
     * @param _initialOperator The initial operator address.
     * @param _initialOwner The initial owner of the contract.
     */
    function initialize(
        address _tellerAddress,
        address _initialOperator,
        address _initialOwner
    ) public initializer {
        __Ownable_init(_initialOwner);
        __Ownable2Step_init();
        __ReentrancyGuard_init();

        require(_tellerAddress != address(0), "DCA: Invalid Teller address");
        require(_initialOperator != address(0), "DCA: Invalid operator address");

        teller = ITeller(_tellerAddress);
        operator = _initialOperator;

        nextPlanId = 1;
    }

    /// @dev Throws if the caller is not the operator.
    modifier onlyOperator() {
        require(_msgSender() == operator, "DCA: Not operator");
        _;
    }

    /// @dev Throws if the caller is not the operator or the contract itself.
    modifier onlyOperatorOrSelf() {
        require(
            _msgSender() == operator || _msgSender() == address(this),
            "DCA: Not operator or self"
        );
        _;
    }


    // ====================== Write functions - admin ======================

    /**
     * @notice Sets the operator address.
     * @dev Can only be called by the contract owner.
     * @param _newOperator The address of the new operator.
     */
    function setOperator(address _newOperator) public onlyOwner {
        require(_newOperator != address(0), "DCA: Invalid operator address");
        operator = _newOperator;
        emit OperatorSet(_newOperator);
    }


    // =========================== View functions ==========================

    /**
     * @notice Returns the total number of DCA plans ever created.
     * @return The total plan count.
     */
    function plansLength() public view returns (uint256) {
        return nextPlanId - 1;
    }

    /**
     * @notice Retrieves all active plan IDs for a given user.
     * @param user The address of the user.
     * @return An array of plan IDs.
     */
    function getPlansByUser(address user) public view returns (uint256[] memory) {
        return userPlanIds[user];
    }


    // ========================== Write functions ==========================

    /**
     * @notice Creates a new DCA plan for the caller.
     * @param tokenIn The stablecoin to use for purchase.
     * @param dcaType The type of DCA (0 for EXACT_IN, 1 for EXACT_OUT).
     * @param dcaFrequency The frequency (0 for WEEKLY, 1 for MONTHLY).
     * @param amount The amount for the plan (stablecoin for EXACT_IN, SatCoin for EXACT_OUT).
     * @param maxAmountIn The max stablecoin to spend (required for EXACT_OUT).
     */
    function createDCA(
        address tokenIn,
        DCAType dcaType,
        DCAFrequency dcaFrequency,
        uint256 amount,
        uint256 maxAmountIn
    ) public nonReentrant {
        // Check conditions
        require(userPlanIds[_msgSender()].length < MAX_PLANS_PER_USER, "DCA: Max plans reached");
        require(amount > 0, "DCA: Amount must be positive");
        require(teller.stablecoinDecimals(tokenIn) > 0, "DCA: Token not supported");
        require(
            dcaType == DCAType.EXACT_IN || maxAmountIn > 0, 
            "DCA: Max input must be positive for EXACT_OUT"
        );

        // Create plan
        uint256 planId = nextPlanId++;  // Start from 1, not 0
        dcaPlans[planId] = DCAPlan({
            user: _msgSender(),
            tokenIn: tokenIn,
            dcaType: dcaType,
            dcaFrequency: dcaFrequency,
            amount: amount,
            maxAmountIn: maxAmountIn,
            lastExecuted: 0,
            isActive: true
        });
        uint256 userPlanIndex = userPlanIds[_msgSender()].length;
        userPlanIds[_msgSender()].push(planId);
        planIdToIndex[planId] = userPlanIndex;

        // Event
        emit DCACreated(_msgSender(), planId, dcaPlans[planId]);
    }

    /**
     * @notice Updates the amount and maxAmountIn for an existing DCA plan.
     * @dev The caller must be the plan owner.
     * @param planId The ID of the plan to update.
     * @param amount The new amount for the plan.
     * @param maxAmountIn The new max stablecoin to spend (for EXACT_OUT).
     */
    function updateDCA(uint256 planId, uint256 amount, uint256 maxAmountIn) public nonReentrant {
        // Check conditions
        DCAPlan storage plan = dcaPlans[planId];
        require(plan.user == _msgSender(), "DCA: Not plan owner");
        require(plan.isActive, "DCA: Plan is not active");
        require(amount > 0, "DCA: Amount must be positive");

        // Update plan
        plan.amount = amount;
        if (plan.dcaType == DCAType.EXACT_OUT) {
            require(maxAmountIn > 0, "DCA: Max input must be positive for EXACT_OUT");
            plan.maxAmountIn = maxAmountIn;
        }

        // Event
        emit DCAUpdated(_msgSender(), planId, plan);
    }

    /**
     * @notice Cancels an active DCA plan.
     * @dev This deactivates the plan and removes it from the user's active plan list.
     * @param planId The ID of the plan to cancel.
     */
    function cancelDCA(uint256 planId) public nonReentrant {
        // Check conditions
        DCAPlan storage plan = dcaPlans[planId];
        require(plan.user == _msgSender(), "DCA: Not plan owner");
        require(plan.isActive, "DCA: Plan is not active");

        // Cancel plan
        plan.isActive = false;
        uint256[] storage planIds = userPlanIds[_msgSender()];
        uint256 indexToRemove = planIdToIndex[planId];
        uint256 lastPlanId = planIds[planIds.length - 1];
        if (planIds.length > 1 && indexToRemove != planIds.length - 1) {
            planIds[indexToRemove] = lastPlanId;
            planIdToIndex[lastPlanId] = indexToRemove;
        }
        planIds.pop();
        delete planIdToIndex[planId];

        // Event
        emit DCACanceled(_msgSender(), planId, plan);
    }

    /**
     * @notice Executes a batch of DCA plans.
     * @dev Can only be called by the operator. Skips inactive plans and catches individual failures.
     * @param planIds An array of plan IDs to execute.
     */
    function executeBatchDCA(uint256[] calldata planIds) public onlyOperator {
        // Avoid gas limit exceeded
        require(planIds.length <= MAX_EXECUTIONS_PER_BATCH, "DCA: Exceeds max executions per batch");

        for (uint256 i = 0; i < planIds.length; i++) {
            // Fetch plan information
            uint256 planId = planIds[i];
            DCAPlan storage plan = dcaPlans[planId];

            // If illegal plan, skip but do not revert the entire batch
            if (!plan.isActive || plan.user == address(0)) {
                emit DCAExecuted(planId, false, 0, 0, bytes("Inactive or invalid plan"));
                continue;
            }
            plan.lastExecuted = block.timestamp;

            // Execute plan and catch revert reason
            try this.executeSingleDCA(planId) { } catch (bytes memory reason) {
                emit DCAExecuted(planId, false, 0, 0, reason);
            }
        }
    }


    // ========================= Internal functions ========================

    /**
     * @notice Executes a single DCA plan's logic.
     * @dev This is called externally by `executeBatchDCA` to isolate failures.
     * Requires caller to be the operator or the contract itself.
     * @param planId The ID of the plan to execute.
     */
    function executeSingleDCA(uint256 planId) public nonReentrant onlyOperatorOrSelf {
        DCAPlan storage plan = dcaPlans[planId];
        require(plan.isActive && plan.user != address(0), "DCA: Plan not executable");

        if (plan.dcaType == DCAType.EXACT_IN) {
            _executeBuyExactIn(planId, plan);
        } else {
            _executeBuyExactOut(planId, plan);
        }
    }

    /**
     * @notice Internal logic for executing an EXACT_IN plan.
     * @dev Pulls a fixed amount of stablecoin from the user and buys SatCoin.
     * @param planId The ID of the plan.
     * @param plan The plan's storage pointer.
     */
    function _executeBuyExactIn(uint256 planId, DCAPlan storage plan) internal {
        // Fetch plan information
        uint256 amountIn = plan.amount;
        IERC20 tokenIn = IERC20(plan.tokenIn);

        // Transfer
        tokenIn.safeTransferFrom(plan.user, address(this), amountIn);

        // Approve & Buy
        tokenIn.forceApprove(address(teller), amountIn);
        (uint256 satCoinAmountOut, ) = teller.buyExactIn(amountIn, plan.tokenIn, 0, plan.user);

        // Event
        emit DCAExecuted(planId, true, amountIn, satCoinAmountOut, "");
    }

    /**
     * @notice Internal logic for executing an EXACT_OUT plan.
     * @dev Buys a fixed amount of SatCoin, pulling the required amount of stablecoin from the user.
     * @param planId The ID of the plan.
     * @param plan The plan's storage pointer.
     */
    function _executeBuyExactOut(uint256 planId, DCAPlan storage plan) internal {
        // Fetch plan information
        uint256 amountOut = plan.amount;
        uint256 maxAmountIn = plan.maxAmountIn;
        IERC20 tokenIn = IERC20(plan.tokenIn);

        // Preview & Transfer
        (uint256 requiredAmountIn, ) = teller.previewBuyExactOut(amountOut, plan.tokenIn);
        require(requiredAmountIn <= maxAmountIn, "DCA: Excessive input amount");
        tokenIn.safeTransferFrom(plan.user, address(this), requiredAmountIn);

        // Approve & Buy
        tokenIn.forceApprove(address(teller), requiredAmountIn);
        teller.buyExactOut(amountOut, plan.tokenIn, requiredAmountIn, plan.user);

        // Event
        emit DCAExecuted(planId, true, requiredAmountIn, amountOut, "");
    }

}