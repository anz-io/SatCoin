// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../SatCoinNFT.sol";

contract SatCoinNFTTest is SatCoinNFT {
    /**
     * @notice ⚠️ Will destroy all NFTs! Only for testing! ⚠️
     */
    function clearAllNFTs() public onlyOwner {
        for (uint256 i = 0; i < totalSupply; i++) {
            attributePayload[i] = bytes("");
            tokenTypeId[i] = 0;
            _burn(i);
        }
        totalSupply = 0;
    }
}
