# ArtBlocks Engine Flex

_The following describes how to create an ArtBlocks Engine Flex contract, deployed on the Arbitrum Goerli testnet and using custom development infrastructure. There are some initial steps required before you can dive into deploying the project._

---

# Setup

first, clone the repo with `git clone https://github.com/ArtBlocks/artblocks-contracts`, navigate to `packages/contracts`, and duplicate the `.env.example` file as `.env` in the root of this directory.

you’ll need to configure some environment variables, including the setup of your EVM account’s private key and accounts for API keys at AWS, Alchemy (or another node provider), CoinMarketCap, Arbiscan, and Hasura.

## Private key

export your the private key for your dev wallet and save it to the both the `MAINNET_PRIVATE_KEY` and `TESTNET_PRIVATE_KEY` variables. it’s a best practice to use different keys here, but for the scripts to work properly, they need both of these values populated, even though we’re only deploying to the testnet.

## Create an AWS account

artblocks uses the [AWS JS SDK](https://docs.aws.amazon.com/sdk-for-javascript/v3/developer-guide/welcome.html); first, navigate [here](https://portal.aws.amazon.com/billing/signup) to create an AWS account.

1. go to the [console dashboard](http://console.aws.amazon.com), click your username in the top-right corner, and then click ****\*****Security credentials****\*****
2. scroll down to ****\*\*\*****Access keys****\*\*\***** and click **\*\***Create access key,**\*\*** and proceed with the setup to create the key (note: we’ll use the root user account for simplicity sake, which isn’t recommended)
3. once created, note the ****\*\*****Access key****\*\***** and ********\*\*\*\*********Secret access secret********\*\*\*\*********

save these credentials as `ARBITRUM_AWS_ACCESS_KEY_ID` and `ARBITRUM_AWS_SECRET_ACCESS_KEY`, respectively, in the `.env` file.

## Create an Alchemy account

navigate [here](https://dashboard.alchemy.com/) and create an account. then, create an application, and choose Arbitrum Goerli as the chain. once created, you can click **\*\*\*\***View app**\*\*\*\*** and then see the HTTPS URL (which exposes the API key)—this should be saved to the `ARBITRUM_GOERLI_JSON_RPC_PROVIDER_URL` variable.

## Create a CoinMarketCap account

create an account ([here](https://pro.coinmarketcap.com/signup/)), navigate to the [dashboard](https://pro.coinmarketcap.com/account/), copy the API key, and then save it as the `COINMARKETCAP_API_KEY` variable

## Create an Arbiscan account

create an Arbiscan account ([here](https://arbiscan.io/login)), navigate to API keys (left-hand side), click the **_Add_** button next to _My API keys_, and the save that value to `ARBISCAN_API_KEY`.

## Create a Hasura account

go to the [Hasura signup page](https://cloud.hasura.io/signup) and create an account. once signed up, a project will be created for you—you’ll want to choose “GraphQL backend.” then, in your project’s console (should look like `https://cloud.hasura.io/project/<project_id>/console/`), copy the `x-hasura-admin-secret` and save it to `HASURA_ADMIN_SECRET_ARBITRUM_DEV` (as well as `GRAPHQL_API_ENDPOINT_DEV`, to ensure scripts can run). also, copy the GraphQL endpoint and the top and save this to `GRAPHQL_API_ENDPOINT_ARBITRUM_STAGING` (as well as `HASURA_ADMIN_SECRET_STAGING`).

> Note: These also need to exist in the ******\*\*\*******project’s root******\*\*\******* `.env` file as `HASURA_GRAPHQL_API_ENDPOINT` and `HASURA_ADMIN_SECRET` due to a GraphQL script that’s ran during the contract deployment process.

### Database & tables

you’ll have to create a database and tables to insert into. in the Hasura console, start by navigating to the \***\*Data\*\*** tab and create a Postgres database instance (you’ll be prompted to authorize an integrated service). then, you’ll need to create two tables:

- table name: `contracts_metadata`; schema:
  ```
  address TEXT,
  name TEXT,
  bucket_name TEXT,
  default_vertical_name TEXT
  ```
- table name: `projects_metadata`; schema:
  ```
  id TEXT,
  contract_address TEXT,
  artist_address TEXT,
  project_id TEXT,
  vertical_name TEXT
  ```

lastly, you’ll want to create a relationship by clicking on the ******\*\*\*\*******projects_metadata******\*\*\*\******* table (left-hand side) and navigate to the ******\*******Relationships******\******* tab, relating the `projects_metadata`'s `contract_address` column to the `contracts_metadata`'s `address` column. give this relationship a name (e.g., ******\*\*\*\*******contract_to_metadata******\*\*\*\*******) and click ****\*\*\*\*****Create relationship****\*\*\*\*****.

## Final output

Thus, you should have all of the following variables set up in `.env`:

```
MAINNET_PRIVATE_KEY=<your_key>
TESTNET_PRIVATE_KEY=<your_key>
COINMARKETCAP_API_KEY=<your_key>
ARBITRUM_AWS_ACCESS_KEY_ID=<your_id>
ARBITRUM_AWS_SECRET_ACCESS_KEY=<your_key>
ARBISCAN_API_KEY=<your_key>
ARBITRUM_GOERLI_JSON_RPC_PROVIDER_URL=<your_url>
GRAPHQL_API_ENDPOINT_DEV=<your_url>
GRAPHQL_API_ENDPOINT_ARBITRUM_STAGING=<your_url>
HASURA_ADMIN_SECRET_DEV=<your_key>
HASURA_ADMIN_SECRET_ARBITRUM_STAGING=<your_key>
```

Also, note the root directory also need the following set in its `.env` file:

```
HASURA_GRAPHQL_API_ENDPOINT=<your_url>
HASURA_ADMIN_SECRET=<your_key>
```

### Testnet funds

Since we’re deploying to Arbitrum Goerli, you’ll need to get testnet Ethereum Goerli currency from a faucet and bridge that over to Arbitrum Goerli:

1. Request testnet Ether from a faucet (e.g., [here](https://goerlifaucet.com/) or [here](https://faucet.paradigm.xyz/)).
2. Move the ETH from Ethereum to Arbitrum at https://bridge.arbitrum.io/—i.e., make sure your wallet is connected to Arbitrum Goerli, select `ETH`, and then bridge it over.

Great, we’re all set up and ready to actually get into the code!

# Contract deployment

## Installation & setup

we’ll be using the generic engine deployer script, located at `scripts/engine/V3/generic-engine-deployer.ts`. before doing so, you’ll have to install dependencies by running the command in the _root_ of the project (i.e., not in `artblocks-contracts/packaes/cotracts`), which will subsequently install subdirectory packages, too. this is needed due to the root’s `graphql.config.ts` and related scripts that will ran when deploying Engine Flex contacts.

```bash
yarn
```

then, navigate to the `packages/contracts` directory. build the contracts and generate typechain types:

```bash
cd packages/contracts
yarn compile
yarn generate:typechain
```

once those are complete, you’ll need to create a deployment config file and copy it to a directory created in `deployments/engine/V3/partners/tableland`—we’ll use the example `deployment-config.arbitrum-dev.ts` file:

```bash
mkdir deployments/engine/V3/partners/tableland
cp deployments/engine/V3/internal-testing/staging-example-arbitrum-flex/deployment-config.arbitrum-staging.ts deployments/engine/V3/partners/tableland
```

## File updates & fixes

### GraphQL

in the `deployment-config.arbitrum-staging.ts` file, change the `tokenName` and `tokenTicker` values to describe your own values (e.g., `ArtRigs` and `ARIGS`, respectively). lastly, you’ll need to fix a typo in the `graphql` folder—edit `insert-projects-meta.graphql` and change `projects_meta_pkey` to `projects_metadata_pkey`:

```graphql
# ...

mutation InsertProjectsMetadata(
  $projectsMetadata: [projects_metadata_insert_input!]!
) {
  insert_projects_metadata(
    objects: $projectsMetadata
    on_conflict: {
      constraint: projects_metadata_pkey # Update this
# ...
```

### Hardhat config

the `hardhat.config.ts` file uses an incorrect key for verification. change `"arbitrum-goerli"` to `arbitrumGoerli`:

```jsx
// ...
etherscan: {
  apiKey: {
    mainnet: ETHERSCAN_API_KEY,
    goerli: ETHERSCAN_API_KEY,
    arbitrum: ARBISCAN_API_KEY,
    arbitrumOne: ARBISCAN_API_KEY,
    arbitrumGoerli: ARBISCAN_API_KEY, // Update this
  },
 },
// ...
```

## Deploy the registry contract

now, you’ll need to deploy the registry contract, otherwise, you’ll be trying to use the ArtBlocks-managed registry, which requires knowing the core team’s deployer private key. run the following:

```jsx
yarn hardhat run --network arbitrum-goerli scripts/engine/V3/engine-registry-deployer.ts
```

this will log the deployed registry address; update the `engineRegistryAddress` in the deployments file at `deployments/engine/V3/partners/tableland/deployment-config.arbitrum-staging.ts`:

```jsx
// ...
engineRegistryAddress: "0x138E3aFeb7dC8944d464326cb2ff2b429cdA808b",
// ...
```

you’ll also have to update this value in the `scripts/util/util/constants.ts` file by changing the `KNOWN_ENGINE_REGISTRIES`’s `"arbitrum-goerli"` dev values. the key is the deployed address above, and the value is ******\*\*******your wallet’s******\*\******* address in which you extracted the private key for (i.e., the deployer address). do so in the third value since this one not indexed in any subgraphs and meant for testing only, which is applicable here since it’s a custom deployment and has no subgraph relationship.

```jsx
export const KNOWN_ENGINE_REGISTRIES = {
  // ...
  "arbitrum-goerli": {
		// ...
    // [INDEXED] arbitrum goerli staging | deployer: arbitrum staging deployer wallet
    "0x138E3aFeb7dC8944d464326cb2ff2b429cdA808b":
      "0x4D5286d81317E284Cd377cB98b478552Bbe641ae",
  // ...
```

## Deploy the Engine Flex contract

now, run the deploy script:

```bash
yarn deploy:staging-arbitrum:v3-engine
```

you’ll be prompted for the deployment config file where you’ll provide the path to `deployment-config.arbitrum-staging.ts`. for example:

```bash
deployments/engine/V3/partners/tableland/deployment-config.arbitrum-staging.ts
```

now, we’ll wait for a number of things to happen:

- contract deployments:
  - admin ACL: `AdminACLV1`
  - randomizer: `BasicRandomizerV2`
  - core Engine Flex: `GenArt721CoreV3_Engine_Flex`
  - minter contracts: `MinterFilterV1`, `MinterSetPriceV4`, and `MinterDAExpSettlementV1`
- contract configurations (e.g., setting contract addresses and admins for various contracts)
- contract verification process
- creation of AWS S3 buckets
- writing data to the `contracts_metadata` and `projects_metadata` tables with information from the deployment, including the Flex Engine contract address, artist address, and project info

### Results

this information will be written to the project-specific markdown file, e.g., at `/contracts/deployments/engine/V3/partners/tableland/DEPLOYMENTS.md`. note that the block explorer values are incorrectly defined with `arbitrum-goerli.etherscan.io` instead of `goerli.arbiscan.io`.

you can view your deployed Engine Flex contract on arbiscan, for example, [here](https://goerli.arbiscan.io/address/0x6112F84D998143b2990Ab76824738852B6aF3F82#code). and you can also check out OpenSea’s testnet domain to view the collection. the collection name will automatically be set during the deployment process, but you can simply search the deployed Engine Flex contract there, for example, [here](https://testnets.opensea.io/collection/artrigs-3). the Hasura database should have information populated (under the \***\*Data\*\*** tab, which stores a reference to your [S3 bucket](https://s3.console.aws.amazon.com/s3/home)).
