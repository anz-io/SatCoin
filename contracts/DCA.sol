// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./Teller.sol";

using SafeERC20 for IERC20;


/**
 * @title DCA Contract (Upgradeable)
 * @notice Allows users to manage Dollar-Cost Averaging plans for buying SatCoin.
 * @dev This contract follows the Transparent Upgradeable Proxy pattern.
 */
contract DCA is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {

    Teller public teller;

    address public operator;

    uint256 public constant MAX_PLANS_PER_USER = 20;

    uint256 private _nextPlanId;

    enum DCAType { EXACT_IN, EXACT_OUT }
    enum DCAFrequency { WEEKLY, MONTHLY }

    struct DCAPlan {
        address user;
        address tokenIn;
        DCAType dcaType;
        DCAFrequency dcaFrequency;
        uint256 amount;         // amount of stablecoin, for `EXACT_IN` mode
        uint256 maxAmountIn;    // max amount of stablecoin, for `EXACT_OUT` mode
        uint256 lastExecuted;
        bool isActive;
    }

}