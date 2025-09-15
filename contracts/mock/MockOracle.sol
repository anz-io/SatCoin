// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockOracle is AggregatorV3Interface {

    int256 price;

    function decimals() external pure returns (uint8) {
        return 8;
	}

    function description() external pure returns (string memory) {
        return "Mock oracle for testing.";
	}

    function version() external pure returns (uint256) {
        return 1;
	}

    function getRoundData(
        uint80
    ) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert("not available");
	}

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, price, 0, 0, 0);
	}

    function setPrice(int256 _price) external {
        price = _price;
	}
}
