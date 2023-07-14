require("dotenv").config();
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-truffle5";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "@nomiclabs/hardhat-solhint";
import "hardhat-contract-sizer";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-docgen";
import "@openzeppelin/hardhat-upgrades";
import { solidityConfig } from "./hardhat.solidity-config";

const MAINNET_JSON_RPC_PROVIDER_URL = process.env.MAINNET_JSON_RPC_PROVIDER_URL;
const GOERLI_JSON_RPC_PROVIDER_URL = process.env.GOERLI_JSON_RPC_PROVIDER_URL;
const MAINNET_PRIVATE_KEY = process.env.MAINNET_PRIVATE_KEY;
const TESTNET_PRIVATE_KEY = process.env.TESTNET_PRIVATE_KEY;

const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
const ARBISCAN_API_KEY = process.env.ARBISCAN_API_KEY;

// L2 Configuration
const ARBITRUM_MAINNET_JSON_RPC_PROVIDER_URL =
  process.env.ARBITRUM_MAINNET_JSON_RPC_PROVIDER_URL;
const ARBITRUM_GOERLI_JSON_RPC_PROVIDER_URL =
  process.env.ARBITRUM_GOERLI_JSON_RPC_PROVIDER_URL;

// Sidechain Configuration
const PALM_MAINNET_JSON_RPC_PROVIDER_URL =
  process.env.PALM_MAINNET_JSON_RPC_PROVIDER_URL;
const PALM_TESTNET_JSON_RPC_PROVIDER_URL =
  process.env.PALM_TESTNET_JSON_RPC_PROVIDER_URL;

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

module.exports = {
  solidity: solidityConfig,
  networks: {
    hardhat: {
      gasPrice: 100000000000, // 100 gwei
      initialBaseFeePerGas: 0,
    },
    mainnet: {
      url: MAINNET_JSON_RPC_PROVIDER_URL,
      accounts: [`0x${MAINNET_PRIVATE_KEY}`],
      gasPrice: "auto",
      gasMultiplier: 1.75,
    },
    goerli: {
      url: GOERLI_JSON_RPC_PROVIDER_URL,
      accounts: [`0x${TESTNET_PRIVATE_KEY}`],
      gasPrice: "auto",
      gasMultiplier: 4.0,
    },
    palm_mainnet: {
      url: PALM_MAINNET_JSON_RPC_PROVIDER_URL,
      accounts: [`0x${MAINNET_PRIVATE_KEY}`],
      gasPrice: "auto",
      gasMultiplier: 1.5,
    },
    palm_testnet: {
      url: PALM_TESTNET_JSON_RPC_PROVIDER_URL,
      accounts: [`0x${TESTNET_PRIVATE_KEY}`],
      gasPrice: "auto",
      gasMultiplier: 1.5,
    },
    arbitrum: {
      url: ARBITRUM_MAINNET_JSON_RPC_PROVIDER_URL,
      accounts: [`0x${MAINNET_PRIVATE_KEY}`],
      gasPrice: "auto",
      gasMultiplier: 1.5,
    },
    "arbitrum-goerli": {
      url: ARBITRUM_GOERLI_JSON_RPC_PROVIDER_URL,
      accounts: [`0x${TESTNET_PRIVATE_KEY}`],
      gasPrice: "auto",
      gasMultiplier: 1.5,
    },
    coverage: {
      url: "http://localhost:8545",
    },
  },
  etherscan: {
    apiKey: {
      mainnet: ETHERSCAN_API_KEY,
      goerli: ETHERSCAN_API_KEY,
      arbitrum: ARBISCAN_API_KEY, // This is unused but here in case hardhat changes
      arbitrumOne: ARBISCAN_API_KEY,
      arbitrumGoerli: ARBISCAN_API_KEY,
    },
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: false,
    disambiguatePaths: false,
  },
  docgen: {
    path: "./docs",
    clear: true,
    runOnCompile: false,
    except: [
      `^contracts/interfaces/v0.5.x/`,
      `^contracts/interfaces/v0.8.x/IManifold.sol`,
      `^contracts/interfaces/v0.8.x/IBonusContract.sol`,
      `^contracts/libs/v0.5.x/`,
      `^contracts/minter-suite/Minters/.*V0.sol`,
      `^contracts/mock`,
      `^contracts/PBAB\\+Collabs/.*/.*.sol`,
      `^contracts/BasicRandomizer.sol`,
      `^contracts/BasicRandomizerV2.sol`,
    ],
  },
  gasReporter: {
    currency: "USD",
    gasPrice: 100,
    enabled: true,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  },
  mocha: {
    timeout: 100000,
  },
};
