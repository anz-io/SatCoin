// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/**
 * @title WalletNameRegistry
 * @notice A central, upgradeable registry to store names for Safe wallets.
 */
contract WalletNameRegistry is Ownable2StepUpgradeable {

    /// @notice Maps a Safe wallet address to its user-defined name.
    mapping(address => string) public names;

    /// @notice Emitted when a wallet's name is set or updated.
    event NameSet(address indexed safe, string oldName, string newName);

    /**
     * @notice Initializes the contract.
     */
    function initialize() public initializer {
        __Ownable_init(_msgSender());
        __Ownable2Step_init();
    }

    /**
     * @notice Sets or updates the name for the calling wallet.
     * @dev ANYONE can call this, but it only sets the name for `msg.sender`.
     *  This means only the Safe itself (via a multisig tx) can set its own name.
     * @param newName The new name for the wallet.
     */
    function setName(string memory newName) public {
        string memory oldName = names[_msgSender()];
        names[_msgSender()] = newName;
        emit NameSet(_msgSender(), oldName, newName);
    }

}