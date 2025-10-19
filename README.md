# SatCoin Contracts

This project provides a set of Solidity smart contracts to create an `ERC20` token, `SatCoin`, which is pegged to Bitcoin's smallest unit, the satoshi. It includes a decentralized exchange (DEX) contract, the `Teller`, for swapping SatCoin with stablecoins, and a `DCA` contract for setting up recurring purchases (Dollar-Cost Averaging).

## Core Contracts

* **`SatCoin.sol`**: A standard upgradeable ERC20 token for SatCoin. It includes an `owner`-only minting function to control the token supply.

* **`Teller.sol`**: The core exchange contract. It functions as an automated market maker that allows users to buy and sell `SatCoin` for whitelisted stablecoins. It uses a dynamic slippage model based on trade size and integrates with Chainlink price feeds to determine the BTC exchange rate.

* **`DCA.sol`**: An automated investment contract. Users can create, manage, and cancel DCA plans to automatically purchase `SatCoin` on a weekly or monthly basis. An authorized `operator` account is responsible for executing these batch transactions.

* **`ProofOfReserve.sol`**: A contract for on-chain transparency. It allows the project owner to record and manage Bitcoin reserve data, such as transaction hashes and balances, providing a public proof of the assets backing SatCoin.

* **`SatCoinNFT.sol`**: A contract for a dynamic, on-chain generated NFT collection. It features a secure, signature-based minting process where a backend signer authorizes each mint, preventing unauthorized creation. The contract supports different NFT types with unique images and traits, which are dynamically assembled and returned as a Base64 encoded JSON in the tokenURI.

* **`SubscriptionGuard.sol`**: An upgradeable Safe `Guard` contract that enforces a subscription fee for wallet usage. It blocks transactions if the subscription expires, allowing only renewal calls, and prevents the Guard itself from being removed via `setGuard`.

* **`SpendingPolicyModule.sol`**: An upgradeable Safe `Module` enabling wallet owners to execute daily transfers (native token or ERC20) below a shared, configurable limit without requiring full multisig approval.

* **`WalletInitializer.sol`**: A utility contract designed for `delegatecall` during Safe wallet creation (`setup` function) to atomically configure the initial `Guard` and enable the primary `Module` in a single transaction.

### Libraries

* **`MathLib.sol`**: A simple library for fixed-point arithmetic, used for precise calculations within the `Teller` contract.
