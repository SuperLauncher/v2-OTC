// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";

async function main() {

  const Factory = await ethers.getContractFactory("Factory");

  const deployerAddress = "0xD507283f873837057Bc551aD9f46cbe60C8C79AA"
  const svLaunchAddress = "0xD507283f873837057Bc551aD9f46cbe60C8C79AA"
  const feeAddress = "0xD507283f873837057Bc551aD9f46cbe60C8C79AA"

  const instance = await Factory.deploy(deployerAddress, svLaunchAddress, feeAddress);
  await instance.deployed();

  console.log("Factory deployed to:", instance.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
