import { expect } from 'chai';
import {ethers} from 'hardhat';
import { upgrades } from 'hardhat';

describe("Marketplace", function() {
  it('works', async () => {
    const Marketplace = await ethers.getContractFactory("Marketplace");
    const MarketplaceV2 = await ethers.getContractFactory("Marketplace");

    const feeAddress = "0xD507283f873837057Bc551aD9f46cbe60C8C79AA"

    const instance = await upgrades.deployProxy(Marketplace, [feeAddress]);
    await instance.deployed();
    const upgraded = await upgrades.upgradeProxy(instance.address, MarketplaceV2);

    const daoFeeAddress = await upgraded.daoFeeAddress();
    expect(daoFeeAddress).to.equal(feeAddress);
  });
});