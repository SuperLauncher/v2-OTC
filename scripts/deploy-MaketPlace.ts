// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import { upgrades } from 'hardhat';

async function main() {

  const Marketplace = await ethers.getContractFactory("Marketplace");

  const feeAddress = "0xD507283f873837057Bc551aD9f46cbe60C8C79AA"

  const instance = await upgrades.deployProxy(Marketplace, [feeAddress]);
  await instance.deployed();

  console.log("Marketplace deployed to:", instance.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
