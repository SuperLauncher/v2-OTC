import { expect } from 'chai';
import {ethers} from 'hardhat';
import { upgrades } from 'hardhat';

describe("Marketplace", function() {
  it('works', async () => {
    const Marketplace = await ethers.getContractFactory("Marketplace");
    const MarketplaceV2 = await ethers.getContractFactory("MockMarketplace");

    const feeAddress = "0xD507283f873837057Bc551aD9f46cbe60C8C79AA"

    const instance = await upgrades.deployProxy(Marketplace, [feeAddress]);
    await instance.deployed();
    
    const daoFeeAddress = await instance.daoFeeAddress();
    expect(daoFeeAddress).to.equal(feeAddress);

    const fee = await instance.feePcnt();
    expect(fee).to.be.equals("50000");
    
    const version = await instance.VERSION();
    expect(version).to.be.equals("1");
  });

  it('upgrade', async () => {
    const Marketplace = await ethers.getContractFactory("Marketplace");
    const MarketplaceV2 = await ethers.getContractFactory("MockMarketplace");

    const feeAddress = "0xD507283f873837057Bc551aD9f46cbe60C8C79AA"

    const instance = await upgrades.deployProxy(Marketplace, [feeAddress]);
    await instance.deployed();
    const upgraded = await upgrades.upgradeProxy(instance.address, MarketplaceV2);

    const daoFeeAddress = await instance.daoFeeAddress();
    expect(daoFeeAddress).to.equal(feeAddress);

    const fee = await upgraded.feePcnt();
    expect(fee).to.be.equals("50000");
    
    const version = await upgraded.VERSION();
    expect(version).to.be.equals("2");
  });
});