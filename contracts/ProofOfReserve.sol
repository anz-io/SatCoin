// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/**
 * @title ProofOfReserve
 * @dev A contract for managing Bitcoin reserve proof entries with upgradeable functionality.
 * This contract allows the owner to add, modify, and query Bitcoin reserve data.
 */
contract ProofOfReserve is Ownable2StepUpgradeable {
    
    /**
     * @dev Structure to store Bitcoin reserve data
     * @param btcTxHash The Bitcoin transaction hash
     * @param timestamp The timestamp of the transaction
     * @param btcBlockHeight The Bitcoin block height
     * @param btcBalance The Bitcoin balance after this transaction
     * @param btcAddress The Bitcoin address
     */
    struct ReserveData {
        bytes32 btcTxHash;
        uint64 timestamp;
        uint64 btcBlockHeight;
        uint64 btcBalance;
        string btcAddress;
    }

    /// @dev The total reserve amount across all entries
    uint64 internal totalReserve;

    /// @dev The array of reserve entries
    ReserveData[] internal reserveEntries;

    /// @dev The mapping of Bitcoin address to the index of the entry
    mapping(string => uint256) internal btcAddressIndex;

    event ReserveEntryAdded(ReserveData entry);
    event ReserveEntryModified(ReserveData oldEntry, ReserveData newEntry);

    /**
     * @notice Initializes the contract with the deployer as the owner
     * @dev This function can only be called once during contract deployment
     */
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

    /**
     * @notice Gets the total number of reserve entries
     * @dev Excludes the dummy entry at index 0
     * @return The count of valid reserve entries
     */
    function getEntriesCount() public view returns (uint256) {
        return reserveEntries.length - 1;
    }

    /**
     * @notice Retrieves a specific reserve entry by its index
     * @param index The index of the entry to retrieve (0-based)
     * @dev The index is adjusted internally to account for the dummy entry
     * @return The ReserveData struct at the specified index
     */
    function getEntryByIndex(uint256 index) public view returns (ReserveData memory) {
        require(index < reserveEntries.length - 1, "PoR: index out of bounds");
        return reserveEntries[index + 1];
    }

    /**
     * @notice Retrieves a range of reserve entries
     * @param startIndex The starting index of the range (0-based)
     * @param endIndex The ending index of the range (exclusive)
     * @dev Returns entries from startIndex to endIndex-1, adjusted for dummy entry
     * @return An array of ReserveData structs in the specified range
     */
    function getEntries(uint256 startIndex, uint256 endIndex) public view returns (ReserveData[] memory) {
        require(endIndex < reserveEntries.length, "PoR: endIndex out of bounds");
        require(startIndex < endIndex, "PoR: startIndex too large");
        ReserveData[] memory entries = new ReserveData[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            entries[i - startIndex] = reserveEntries[i + 1];
        }
        return entries;
    }

    /**
     * @notice Retrieves a reserve entry by Bitcoin address
     * @param btcAddress The Bitcoin address to search for
     * @dev Reverts if the address is not found
     * @return The ReserveData struct for the specified Bitcoin address
     */
    function getEntryByBtcAddress(string memory btcAddress) public view returns (ReserveData memory) {
        uint256 index = btcAddressIndex[btcAddress];
        require(index != 0, "PoR: btcAddress not found");
        return reserveEntries[index];
    }

    /**
     * @notice Gets the total reserve amount across all entries
     * @return The total Bitcoin reserve amount
     */
    function getTotalReserve() public view returns (uint256) {
        return totalReserve;
    }

    /**
     * @notice Adds a new reserve entry
     * @param btcTxHash The Bitcoin transaction hash
     * @param timestamp The timestamp when the entry was created
     * @param btcBlockHeight The Bitcoin block height
     * @param btcBalance The Bitcoin balance amount
     * @param btcAddress The Bitcoin address
     * @dev Only the contract owner can call this function
     * @dev Reverts if the Bitcoin address already exists
     */
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

        emit ReserveEntryAdded(entry);
    }
    
    /**
     * @notice Modifies an existing reserve entry
     * @param btcTxHash The new Bitcoin transaction hash
     * @param timestamp The new timestamp
     * @param btcBlockHeight The new Bitcoin block height
     * @param btcBalance The new Bitcoin balance amount
     * @param btcAddress The Bitcoin address to modify
     * @dev Only the contract owner can call this function
     * @dev Reverts if the Bitcoin address is not found
     * @dev Updates the total reserve by subtracting the old balance and adding the new balance
     */
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

        emit ReserveEntryModified(originEntry, modifiedEntry);
    }

}
