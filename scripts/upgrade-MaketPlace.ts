// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import { upgrades } from "hardhat";

async function main() {


  const proxyAddress = '0xfDC54e85b9B18eDCeCef2aaffe02A35E8aB43C1C';


  const mk = await ethers.getContractFactory("Marketplace");
  console.log("Preparing upgrade...");
  const V2Address = await upgrades.upgradeProxy(proxyAddress, mk);
  console.log("V2 at:", V2Address);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
