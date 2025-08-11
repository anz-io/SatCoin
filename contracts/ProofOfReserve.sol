// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

contract ProofOfReserve is Ownable2StepUpgradeable {
    
    struct ReserveData {
        bytes32 btcTxHash;
        uint64 timestamp;
        uint64 btcBlockHeight;
        uint64 btcBalance;
        string btcAddress;
    }

    uint64 internal totalReserve;
    ReserveData[] internal reserveEntries;
    mapping(string => uint256) internal btcAddressIndex;

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(_msgSender());
        __Ownable2Step_init();

        reserveEntries.push(ReserveData({
            btcTxHash: bytes32(0),
            timestamp: 0,
            btcBlockHeight: 0,
            btcBalance: 0,
            btcAddress: ""
        }));        // reserveEntries[0] is a dummy entry
    }

    function getEntriesCount() public view returns (uint256) {
        return reserveEntries.length - 1;
    }

    function getEntryByIndex(uint256 index) public view returns (ReserveData memory) {
        require(index < reserveEntries.length - 1, "PoR: index out of bounds");
        return reserveEntries[index + 1];
    }

    function getEntries(uint256 startIndex, uint256 endIndex) public view returns (ReserveData[] memory) {
        require(endIndex < reserveEntries.length - 1, "PoR: endIndex out of bounds");
        require(startIndex <= endIndex, "PoR: startIndex too large");
        ReserveData[] memory entries = new ReserveData[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            entries[i - startIndex] = reserveEntries[i + 1];
        }
        return entries;
    }

    function getEntryByBtcAddress(string memory btcAddress) public view returns (ReserveData memory) {
        uint256 index = btcAddressIndex[btcAddress];
        require(index != 0, "PoR: btcAddress not found");
        return reserveEntries[index];
    }

    function getTotalReserve() public view returns (uint256) {
        return totalReserve;
    }

    function addReserveEntry(
        bytes32 btcTxHash,
        uint64 timestamp,
        uint64 btcBlockHeight,
        uint64 btcBalance,
        string memory btcAddress
    ) public onlyOwner {
        require(btcAddressIndex[btcAddress] == 0, "PoR: btcAddress already exists");
        ReserveData memory entry = ReserveData({
            btcTxHash: btcTxHash,
            timestamp: timestamp,
            btcBlockHeight: btcBlockHeight,
            btcBalance: btcBalance,
            btcAddress: btcAddress
        });

        totalReserve += btcBalance;
        reserveEntries.push(entry);
        btcAddressIndex[btcAddress] = reserveEntries.length - 1;
    }
    
    function modifyReserveEntry(
        bytes32 btcTxHash,
        uint64 timestamp,
        uint64 btcBlockHeight,
        uint64 btcBalance,
        string memory btcAddress
    ) public onlyOwner {
        uint256 index = btcAddressIndex[btcAddress];
        require(index != 0, "PoR: btcAddress not found");
        ReserveData memory originEntry = reserveEntries[index];
        ReserveData memory modifiedEntry = ReserveData({
            btcTxHash: btcTxHash,
            timestamp: timestamp,
            btcBlockHeight: btcBlockHeight,
            btcBalance: btcBalance,
            btcAddress: btcAddress
        });

        totalReserve -= originEntry.btcBalance;
        totalReserve += btcBalance;
        reserveEntries[index] = modifiedEntry;
    }

}
