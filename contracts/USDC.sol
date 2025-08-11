// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract UpgradeableUSDC is ERC20Upgradeable {
    // ============================= Constants =============================
    // ============================= Parameters ============================
    // ============================== Storage ==============================
    // =============================== Events ==============================
    // ======================= Modifier & Initializer ======================
    function initialize() initializer public {
        __ERC20_init("USDC", "USD Circle");
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }
    // =========================== View functions ==========================
    // ========================== Write functions ==========================
    // ====================== Write functions - admin ======================
}

