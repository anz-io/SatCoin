// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockBUSD is ERC20 {
    constructor() ERC20("MockBUSD", "BUSD") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
