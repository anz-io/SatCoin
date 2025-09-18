# SatCoin Contracts

This project provides a set of Solidity smart contracts to create an `ERC20` token, `SatCoin`, which is pegged to Bitcoin's smallest unit, the satoshi. It includes a decentralized exchange (DEX) contract, the `Teller`, for swapping SatCoin with stablecoins, and a `DCA` contract for setting up recurring purchases (Dollar-Cost Averaging).

## Core Contracts

* **`SatCoin.sol`**: A standard upgradeable ERC20 token for SatCoin. It includes an `owner`-only minting function to control the token supply.

* **`Teller.sol`**: The core exchange contract. It functions as an automated market maker that allows users to buy and sell `SatCoin` for whitelisted stablecoins. It uses a dynamic slippage model based on trade size and integrates with Chainlink price feeds to determine the BTC exchange rate.

* **`DCA.sol`**: An automated investment contract. Users can create, manage, and cancel DCA plans to automatically purchase `SatCoin` on a weekly or monthly basis. An authorized `operator` account is responsible for executing these batch transactions.

* **`ProofOfReserve.sol`**: A contract for on-chain transparency. It allows the project owner to record and manage Bitcoin reserve data, such as transaction hashes and balances, providing a public proof of the assets backing SatCoin.

### Libraries

* **`MathLib.sol`**: A simple library for fixed-point arithmetic, used for precise calculations within the `Teller` contract.
