// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISafe {
    function setGuard(address guard) external;
    function enableModule(address module) external;
}

interface IWalletNameRegistry {
    function setName(string memory name) external;
}

/**
 * @title WalletInitializer
 * @notice A helper contract to perform initial setup on a new SatCoin Smart Wallet.
 * @dev This contract's functions are intended to be called ONLY via a delegatecall from
 *  the `setup` function of a Safe contract during its creation.
 */
contract WalletInitializer {

    /// @notice Emitted when a SatCoin Smart Wallet is initialized.
    event SatcoinWalletInitialized(address indexed safe, string name);

    /**
     * @notice Sets the initial Guard and enables the initial Module for a new Safe wallet.
     * @param guard The address of the `SubscriptionGuard` contract.
     * @param module The address of the `SpendingPolicyModule` contract.
     * @param registry The address of the `WalletNameRegistry` contract.
     * @param name The name for the wallet.
     */
    function initializeSafe(
        address guard, 
        address module,
        address registry,
        string memory name
    ) external {
        // Because this function is executed via DELEGATECALL from the new Safe wallet,
        // the `address(this)` inside the ISafe interface will be the Safe's address.
        // Therefore, the `authorized` modifier on setGuard and enableModule will pass.
        
        // 1. Set the subscription guard
        if (guard != address(0)) {
            ISafe(address(this)).setGuard(guard);
        }

        // 2. Enable the spending policy module
        if (module != address(0)) {
            ISafe(address(this)).enableModule(module);
        }

        // 3. Set the name for the wallet
        if (registry != address(0) && bytes(name).length > 0) {
            IWalletNameRegistry(registry).setName(name);
        }

        // 4. Emit the event (by the caller, not this contract)
        emit SatcoinWalletInitialized(address(this), name);
    }
    
}