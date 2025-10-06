// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../SatCoinNFT.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";

contract SatCoinNFTTest is SatCoinNFT, IERC4906 {
    /**
     * @notice ⚠️ Will destroy all NFTs! Only for testing! ⚠️
     */
    function clearAllNFTs() public onlyOwner {
        for (uint256 i = 0; i < totalSupply(); i++) {
            attributePayload[i] = bytes("");
            tokenTypeId[i] = 0;
            _burn(i);
        }
    }

    /**
     * @notice Update all token URIs
     */
    function updateAllTokenURIs() public onlyOwner {
        emit BatchMetadataUpdate(0, totalSupply() - 1);
    }
}
