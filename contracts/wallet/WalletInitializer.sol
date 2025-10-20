// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISafe {
    function setGuard(address guard) external;
    function enableModule(address module) external;
}

/**
 * @title WalletInitializer
 * @notice A helper contract to perform initial setup on a new SatCoin Smart Wallet.
 * @dev This contract's functions are intended to be called ONLY via a delegatecall from
 *  the `setup` function of a Safe contract during its creation.
 */
contract WalletInitializer {

    /**
     * @notice Sets the initial Guard and enables the initial Module for a new Safe wallet.
     * @param guard The address of the `SubscriptionGuard` contract.
     * @param module The address of the `SpendingPolicyModule` contract.
     */
    function initializeSafe(address guard, address module) external {
        // Because this function is executed via DELEGATECALL from the new Safe wallet,
        // the `address(this)` inside the ISafe interface will be the Safe's address.
        // Therefore, the `authorized` modifier on setGuard and enableModule will pass.
        
        // Set the subscription guard
        if (guard != address(0)) {
            ISafe(address(this)).setGuard(guard);
        }

        // Enable the spending policy module
        if (module != address(0)) {
            ISafe(address(this)).enableModule(module);
        }
    }
    
}