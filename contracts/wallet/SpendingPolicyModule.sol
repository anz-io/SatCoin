// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Enum as SafeOperationEnum } from "@safe-global/safe-contracts/contracts/common/Enum.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ISafe
 * @dev Interface for the Safe contract to allow our module to interact with it.
 */
interface ISafe {
    /// @dev Executes a transaction from a Safe module.
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        SafeOperationEnum.Operation operation
    ) external returns (bool success);

    /// @dev Checks if an address is an owner of the Safe.
    function isOwner(address owner) external view returns (bool);
}


/**
 * @title SpendingPolicyModule
 * @notice A Safe module that enables a shared daily transfer limit for wallet owners,
 *  allowing them to execute transfers below the limit without requiring multisig.
 */
contract SpendingPolicyModule {

    // ============================= Constants =============================

    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;


    // ============================== Storage ==============================

    /// @notice Maps each Safe to its token-specific daily limits.
    /// @dev mapping(safeAddress => mapping(tokenAddress => dailyLimit))
    mapping(address => mapping(address => uint256)) public tokenDailyLimits;

    /// @notice Tracks the amount of a specific token spent by a Safe on a given day.
    /// @dev mapping(safe => mapping(token => mapping(dayTimestamp => spentAmount)))
    mapping(address => mapping(address => mapping(uint256 => uint256))) public dailySpent;


    // =============================== Events ==============================

    /// @notice Emitted when a daily limit is set or updated for a token.
    event DailyLimitSet(
        address indexed safe,
        address indexed token,
        uint256 dailyLimit
    );

    /// @notice Emitted when a transfer is successfully executed via this module.
    event DailyTransferExecuted(
        address indexed safe,
        address indexed owner,
        address indexed token,
        address to,
        uint256 amount
    );


    // ===================== Write functions - multisig ====================

    /**
     * @notice Sets the shared daily transfer limit for a specific token.
     * @dev This function must be called via a multisig transaction from the Safe itself.
     *  To set a policy for native ETH, use `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`.
     * @param token The address of the ERC20 token or native token.
     * @param dailyLimit The new shared daily transfer limit for this token.
     */
    function setDailyLimit(address token, uint256 dailyLimit) public {
        require(
            msg.sender.code.length > 0, 
            "SPM: EOA not allowed"
        );
        tokenDailyLimits[msg.sender][token] = dailyLimit;
        emit DailyLimitSet(msg.sender, token, dailyLimit);
    }


    // ======================= Write functions - user ======================
    
    /**
     * @notice Allows any owner to execute a token transfer within the daily limit.
     * @param safe The target Safe wallet address.
     * @param token The address of the token to transfer.
     * @param to The recipient address.
     * @param amount The amount of the token to transfer.
     */
    function executeDailyTransfer(
        address safe, 
        address token, 
        address to, 
        uint256 amount
    ) public {
        // Check conditions
        require(ISafe(safe).isOwner(msg.sender), "SPM: Caller not a wallet owner");

        uint256 dailyLimit = tokenDailyLimits[safe][token];
        require(dailyLimit > 0, "SPM: No daily limit for this token");

        uint256 today = (block.timestamp + 8 hours) / 1 days;
        uint256 spent = dailySpent[safe][token][today];
        require(spent + amount <= dailyLimit, "SPM: Exceeds daily limit");

        // State updates
        dailySpent[safe][token][today] = spent + amount;

        // Transfer
        bool success;
        if (token == NATIVE_TOKEN) {
            // Native token transfer
            success = ISafe(safe).execTransactionFromModule(
                to, amount, "", SafeOperationEnum.Operation.Call
            );
        } else {
            // ERC20 token transfer
            bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
            success = ISafe(safe).execTransactionFromModule(
                token, 0, data, SafeOperationEnum.Operation.Call
            );
        }

        require(success, "SPM: Transfer failed");
        emit DailyTransferExecuted(safe, msg.sender, token, to, amount);
    }


    // =========================== View functions ==========================

    /**
     * @notice Gets the daily spending limit for a specified token.
     * @param safe The address of the Safe.
     * @param token The address of the token.
     * @return The configured daily limit.
     */
    function getDailyLimit(address safe, address token) public view returns (uint256) {
        return tokenDailyLimits[safe][token];
    }

    /**
     * @notice Gets the total amount spent for a specified token on the current day.
     * @param safe The address of the Safe.
     * @param token The address of the token.
     * @return The amount spent today.
     */
    function getSpentToday(address safe, address token) public view returns (uint256) {
        uint256 today = (block.timestamp + 8 hours) / 1 days;
        return dailySpent[safe][token][today];
    }
}