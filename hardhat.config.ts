import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-verify";
import "hardhat-tracer";
import "dotenv/config";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      evmVersion: "cancun",
    },
  },
  networks: {
    sepolia: {
      url: process.env.RPC_SEPOLIA,
      accounts: [
        process.env.PRIVATE_KEY_ADMIN!,
      ]
    },
    bnb: {
      url: process.env.RPC_BNB,
      accounts: [
        process.env.PRIVATE_KEY_ADMIN!,
      ]
    },
    polygon: {
      url: process.env.RPC_POL,
      accounts: [
        process.env.PRIVATE_KEY_ADMIN!,
      ]
    },
  },
  etherscan: {
    apiKey: process.env.API_ETHERSCAN!,
  },
};

export default config;

