// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@safe-global/safe-contracts/contracts/base/GuardManager.sol";
import { Enum as SafeOperationEnum } from "@safe-global/safe-contracts/contracts/common/Enum.sol";

/**
 * @title SubscriptionGuard
 * @notice A Safe Guard contract that enforces a monthly subscription fee for wallet operations.
 *  If a wallet's subscription expires, all transactions will be blocked until the fee is paid.
 */
contract SubscriptionGuard is BaseGuard, Ownable2StepUpgradeable {

    // ============================= Constants =============================

    using SafeERC20 for IERC20;
    
    /// @notice The duration of one subscription period.
    uint256 public constant SUBSCRIPTION_PERIOD = 31 days;


    // ============================== Storage ==============================
    
    /// @notice The address of the treasury that receives subscription fees.
    address public treasury;

    /// @notice Maps each Safe wallet to its subscription expiration timestamp.
    mapping(address => uint256) public subscriptions;

    /// @notice Maps supported token addresses to their required fee amount.
    mapping(address => uint256) public tokenFees;


    // =============================== Events ==============================

    /// @notice Emitted when a subscription is successfully renewed for a Safe.
    event Subscribed(address indexed safe, uint256 oldExpiration, uint256 newExpiration);

    /// @notice Emitted when a new fee is set for a token.
    event FeeSet(address indexed token, uint256 feeAmount);

    /// @notice Emitted when the treasury address is changed.
    event TreasurySet(address indexed oldTreasury, address indexed newTreasury);


    // ============================ Constructor ============================

    /**
     * @notice Initializes the contract.
     * @dev This function can only be called once during contract deployment.
     * @param initialTreasury The address of the treasury that receives subscription fees.
     */
    function initialize(address initialTreasury) public initializer {
        __Ownable_init(_msgSender());
        __Ownable2Step_init();

        require(initialTreasury != address(0), "SubscriptionGuard: Invalid treasury address");
        treasury = initialTreasury;
    }


    // ====================== Write functions - admin ======================

    /**
     * @notice Sets or updates the fee for a supported token.
     * @dev Setting the fee to 0 effectively removes support for that token.
     * @param token The address of the token (e.g., USDC, USDT).
     * @param feeAmount The fee in the token's smallest unit (e.g., 2990000 for $2.99 USDC).
     */
    function setTokenFee(address token, uint256 feeAmount) public onlyOwner {
        tokenFees[token] = feeAmount;
        emit FeeSet(token, feeAmount);
    }

    /**
     * @notice Updates the treasury address that receives subscription fees.
     */
    function setTreasury(address newTreasury) public onlyOwner {
        require(newTreasury != address(0), "SubscriptionGuard: Invalid treasury address");
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasurySet(oldTreasury, newTreasury);
    }


    // ========================== Write functions ==========================
    
    /**
     * @notice Renews the subscription for a Safe wallet.
     * @dev Anyone can call this function to pay for any Safe's subscription.
     *  The caller must first approve to spend the token.
     * @param safe The address of the Safe wallet to renew the subscription for.
     * @param token The address of the token to be used for payment.
     */
    function renewSubscription(address safe, address token) public {
        // Check conditions
        uint256 feeAmount = tokenFees[token];
        require(feeAmount > 0, "SubscriptionGuard: This token is not supported");

        // Transfer the fee
        IERC20(token).safeTransferFrom(_msgSender(), treasury, feeAmount);

        // Update states
        uint256 currentExpiration = subscriptions[safe];
        uint256 newExpiration = (
            block.timestamp > currentExpiration ? block.timestamp : currentExpiration
        ) + SUBSCRIPTION_PERIOD;
        subscriptions[safe] = newExpiration;

        // Event
        emit Subscribed(safe, currentExpiration, newExpiration);
    }

    /**
     * @notice Renews the subscription for a Safe wallet for a specified number of months.
     * @dev Same as `renewSubscription`, but for multiple months.
     * @param safe The address of the Safe wallet to renew the subscription for.
     * @param token The address of the token to be used for payment.
     * @param months The number of months to renew the subscription for.
     */
    function bulkRenewSubscription(address safe, address token, uint8 months) public {
        // Check conditions
        uint256 feeAmount = tokenFees[token];
        require(feeAmount > 0, "SubscriptionGuard: This token is not supported");
        require(months > 0, "SubscriptionGuard: Invalid months");

        // Transfer the fee
        IERC20(token).safeTransferFrom(_msgSender(), treasury, feeAmount * months);

        // Update states
        uint256 currentExpiration = subscriptions[safe];
        uint256 newExpiration = (
            block.timestamp > currentExpiration ? block.timestamp : currentExpiration
        ) + SUBSCRIPTION_PERIOD * months;
        subscriptions[safe] = newExpiration;

        // Event
        emit Subscribed(safe, currentExpiration, newExpiration);
    }



    // ===================== View functions - override =====================

    /**
     * @notice This is the core function called by the Safe before every transaction.
     * @dev It checks if the wallet's subscription is active. If not, it reverts the transaction,
     *  unless the transaction is a call to this contract's `renewSubscription` function.
     */
    function checkTransaction(
        address to,
        uint256,    // value
        bytes memory data,
        SafeOperationEnum.Operation, //operation
        uint256, //safeTxGas
        uint256, //baseGas
        uint256, //gasPrice
        address, //gasToken
        address payable, //refundReceiver
        bytes memory, //signatures
        address // msgSender, but not the msgSender for this call
    ) public view override {
        uint256 expiration = subscriptions[_msgSender()];
        if (block.timestamp > expiration) {
            // Wallet locked
            // EXCEPTION: Allow calls to this contract's `renewSubscription` function to pass through.
            require(
                (to == address(this)) && (bytes4(data) == this.renewSubscription.selector), 
                "SubscriptionGuard: Subscription has expired"
            );
        }
    }

    /**
     * @notice Called by the Safe after every transaction. Not used.
     */
    function checkAfterExecution(bytes32 txHash, bool success) public override {}
    
}