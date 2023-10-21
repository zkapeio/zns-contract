import { Wallet, Provider } from "zksync-web3";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
require("dotenv").config();

// contract interface
interface CONTRACT {
  // the name of the contract specified in the file
  name: string;
  // arguments which are passed to the constructor
  args: any[];
}

// this function will deploy both contracts at the same time.
export default async function (hre: HardhatRuntimeEnvironment) {
  var provider = new Provider(process.env.ZK_NETWORK);
  // WARNING THESE ADDRESSES ARE ON GOERLI NOT MAINNNET
  const L1_USDC_ADDRESS = "0xd35cceead182dcee0f148ebac9447da2c4d449c4";
  const L2_FEE_TOKEN = await provider.l2TokenAddress(L1_USDC_ADDRESS);

  // contracts to be deployed
  const CONTRACTS: CONTRACT[] = [
    {
      //   name: "ZNSRegistry",
      //   name: "BaseRegistrarImplementation",
      name: "ZNSRegistrarController",
      //   name: "PublicResolver",
      //   name: "ReverseRegistrar",
      //   name: "StablePriceOracle",
      //   name: "TokenURIBuilder",
      //   name: "__AdminUpgradeabilityProxy__",
      // the token address in which we accept payments
      args: [],
      //   args: [
      //     "0x4d4c47E19D9E6BB59B3141908C2D9165018199b3",
      //     "0xa416AE937AaC9Dc6f31f80f8cFEE897F837c8BE6",
      //     "0x",
      //   ],
      //   args: ["0x51112DD194456ca9AEea9cB3F521BB6D56675239"], // BaseRegistrarImplementation contratc
    },
  ];
  // get private key
  const DEPLOYER_PRIVATE_KEY = process.env.PRIVATE_KEY;
  if (!DEPLOYER_PRIVATE_KEY) throw new Error("PRIVATE_KEY not set!");
  // get fee token
  const DEPLOY_FEE_TOKEN = process.env.FEE_TOKEN || L2_FEE_TOKEN;
  if (!DEPLOY_FEE_TOKEN) throw new Error("FEE_TOKEN not set!");

  // initialize deployer
  const wallet = new Wallet(DEPLOYER_PRIVATE_KEY).connect(provider);
  const deployer = new Deployer(hre, wallet);

  for (const contract of CONTRACTS) {
    try {
      console.log(
        `Deploying ${contract.name}! if it takes too long deploy again... Was known issue`
      );
      // load artifact
      const artifact = await deployer.loadArtifact(contract.name);
      // deploy the contract
      const deployed_contract = await deployer.deploy(artifact, contract.args); // deploying with eth
      // Show the contract info.
      const contractAddress = deployed_contract.address;
      console.log(
        `${artifact.contractName} was deployed to ${contractAddress}`
      );
      console.log(deployed_contract.interface.encodeDeploy(contract.args));

      await hre.run("verify:verify", {
        address: contractAddress,
        // contract: artifact.contractName,
        constructorArguments: contract.args,
      });
    } catch (err) {
      console.log(err);
    }
  }
}
