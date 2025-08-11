// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

contract SatCoin is ERC20Upgradeable, Ownable2StepUpgradeable {

    function initialize() public initializer {
        __ERC20_init("SatCoin", "SAT");
        __Ownable_init(_msgSender());
        __Ownable2Step_init();
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
