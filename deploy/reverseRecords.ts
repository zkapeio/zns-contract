import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as ethers from "ethers";
import * as zk from "zksync-web3";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
require("dotenv").config();

// An example of a deploy script which will deploy and call a factory-like contract (meaning that the main contract
// may deploy other contracts).
//
// In terms of presentation it's mostly copied from `001_deploy.ts`, so this example acts more like an integration test
// for plugins/server capabilities.
export default async function (hre: HardhatRuntimeEnvironment) {
  console.log(`Running deploy script`);

  // Initialize an Ethereum wallet.
  const DEPLOYER_PRIVATE_KEY = process.env.PRIVATE_KEY;
  if (!DEPLOYER_PRIVATE_KEY) throw new Error("PRIVATE_KEY not set!");
  const zkWallet = new zk.Wallet(DEPLOYER_PRIVATE_KEY);

  // Create deployer object and load desired artifact.
  const deployer = new Deployer(hre, zkWallet);

  // Load the artifact we want to deploy.
  const reverseRecords = await deployer.loadArtifact("ReverseRecords");

  // Deploy this contract. The returned object will be of a `Contract` type, similarly to ones in `ethers`.
  // This contract has no constructor arguments.
  //   const args = ["0x7fA4257f6d7F143bb0602F84c2AD333C5e78009C"]; // mainnet
  const args = ["0x9cfBa9b6308c135E47E0073AC0733B3C8c7D5414"]; //testnet

  const reverseRecordsContract = await deployer.deploy(reverseRecords, args);

  const contractAddress = reverseRecordsContract.address;

  console.log(`apeAccountContract : ${contractAddress}`);
  await hre.run("verify:verify", {
    address: contractAddress,
    // contract: artifact.contractName,
    constructorArguments: args,
  });
}
