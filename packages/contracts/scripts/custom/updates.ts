import hre from "hardhat";
import { ethers } from "hardhat";
import { BYTECODE_STORAGE_READER_LIBRARY_ADDRESSES } from "../util/constants";
// Import your deployment details
import { deployDetailsArray } from "../../deployments/engine/V3/partners/tableland/deployment-config.arbitrum-staging";

const intendedNetwork = "arbitrum-goerli";
const deployDetails = deployDetailsArray[0];
//////////////////////////////////////////////////////////////////////////////
// CONFIG ENDS HERE
//////////////////////////////////////////////////////////////////////////////
async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  const networkName = network.name == "homestead" ? "mainnet" : network.name;
  if (networkName != intendedNetwork) {
    throw new Error(
      `[ERROR] This script is intended to be run on ${intendedNetwork} only`
    );
  }
  const bytecodeStorageLibraryAddress =
    BYTECODE_STORAGE_READER_LIBRARY_ADDRESSES[networkName];
  if (!bytecodeStorageLibraryAddress) {
    throw new Error(
      `[ERROR] No bytecode storage reader library address configured for network ${networkName}`
    );
  }
  //////////////////////////////////////////////////////////////////////////////
  // UPDATES BEGINS HERE
  //////////////////////////////////////////////////////////////////////////////

  // Setup up a connection to the deployed contract
  const genArt721CoreFactory = await ethers.getContractFactory(
    deployDetails.genArt721CoreContractName,
    {
      libraries: {
        BytecodeStorageReader: bytecodeStorageLibraryAddress,
      },
    }
  );
  const contract = genArt721CoreFactory.attach(
    "0x6112F84D998143b2990Ab76824738852B6aF3F82" // Update with your Engine Flex contract address
  );
  // TODO write data
  const base = await contract.defaultBaseURI();
  console.log(base);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
