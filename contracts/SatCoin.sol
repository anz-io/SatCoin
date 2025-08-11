// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/**
 * @title SatCoin
 * @dev An upgradeable ERC20 token contract for SatCoin with minting functionality.
 * This contract allows the owner to mint new tokens to specified addresses.
 */
contract SatCoin is ERC20Upgradeable, Ownable2StepUpgradeable {

    /**
     * @notice Initializes the contract with token name and symbol
     * @dev This function can only be called once during contract deployment
     * @dev Sets up the ERC20 token with name "SatCoin" and symbol "SAT"
     */
    function initialize() public initializer {
        __ERC20_init("SatCoin", "SAT");
        __Ownable_init(_msgSender());
        __Ownable2Step_init();
    }

    /**
     * @notice Mints new tokens to a specified address
     * @param to The address to receive the minted tokens
     * @param amount The amount of tokens to mint
     * @dev Only the contract owner can call this function
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
