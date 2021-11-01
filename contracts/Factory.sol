// SPDX-License-Identifier: agpl-3.0


pragma solidity ^0.8.0;


import "@openzeppelin/contracts/access/Ownable.sol";
import "./Campaign.sol";
import "./SuperDeedNFT.sol";

contract Factory is Ownable {
  
    address public svLaunchAddress;
    address public daoFeeAddress;
    address public deployerAddress;
    
    struct CampaignInfo {
        address contractAddress;
        address owner;
        address distributor;
        address deedNFT;
    }
    
    // List of campaign and their project owner address. 
    mapping(uint256 => CampaignInfo) public allCampaigns;
    uint256 private count;
    
    modifier onlyDeployer() {
        require(msg.sender == deployerAddress, "Only deployer can call");
        _;
    }
    
    constructor(address deployer, address svLaunch, address feeAddress) Ownable() {
        require(deployer != address(0) && svLaunch != address(0) && feeAddress != address(0), "Invalid address");
        
        deployerAddress = deployer;
        svLaunchAddress = svLaunch;
        daoFeeAddress = feeAddress;
    }
    
    function setDeployer(address newDeployer) external onlyOwner {
        require(newDeployer != address(0), "Invalid address");
        deployerAddress = newDeployer;
    }
    
    function setDaoFeeAddress(address newDaoFeeAddress) external onlyOwner {
        require(newDaoFeeAddress != address(0), "Invalid address");
        daoFeeAddress = newDaoFeeAddress;
    }

    function createCampaign(
        address campaignOwner,
        address distributor,
        address currency, // eg BUSD //
        string calldata symbol
    ) external onlyDeployer returns (address campaignAddress)
    {
        require(campaignOwner != address(0) && distributor != address(0) && currency != address(0), "Invalid address");
       
        // Deploy Campaign contract
        bytes32 salt = keccak256(abi.encodePacked(symbol, campaignOwner, msg.sender));
        campaignAddress = address(new Campaign{salt: salt}());
        
        // Deploy NFT Deed certificate
        string memory deedName = string(abi.encodePacked(symbol, "-Deed")); // Append symbol from XYZ -> XYZ-Deed
        address deedNFT = address(new SuperDeedNFT(campaignAddress, distributor, daoFeeAddress, symbol, deedName)); 
         
        Campaign(campaignAddress).initialize 
        (   svLaunchAddress,
            campaignOwner,
            deedNFT,
            currency
        );
        
        allCampaigns[count] = CampaignInfo(campaignAddress, campaignOwner, distributor, deedNFT);
        count++;
    }
    
    // stats : softcap, hardcap, totalTokensForHardCap, snapshotID
    // dates : start, mid, end
    // privateBuyLimits : minAmount, lower-bound svLaunch (100e18), upper-bound svLaunch(25000e18), lowerAmount(100e18), upperAmount(25000e18)
    // publicBuyLimits : minAmount, maxAmount
    function setupCampaign(
        uint256 campaignID, 
        address campaignAddressCheck,
        uint[4] calldata stats,  
        uint[3] calldata dates, 
        uint[5] calldata privateBuyLimits,
        uint[2] calldata publicBuyLimits
        
    ) external onlyDeployer 
    {
        _validate(campaignID, campaignAddressCheck);
        
        require(stats[0] < stats[1],"Soft cap can't be higher than hard cap");
        require(stats[2] > 0 && stats[3] > 0, "Invalid values");
        require(dates[0] < dates[1] && dates[1] <= dates[2],"Invalid dates");
        require(block.timestamp < dates[0] ,"Start date must be higher than current date ");
        require(privateBuyLimits[0] > 0 && privateBuyLimits[1] > 0 && privateBuyLimits[2] > 0, "Invalid limits");
        require(privateBuyLimits[2] > privateBuyLimits[1], "Invalid upper-lower limit");
        require(privateBuyLimits[4] > privateBuyLimits[3], "Invalid upper-lower amount");
        require(publicBuyLimits[0] > 0 && publicBuyLimits[1] > 0 && publicBuyLimits[0] <= publicBuyLimits[1] ,"Invalid public buy limit" );
        
        Campaign(campaignAddressCheck).setup(stats, dates, privateBuyLimits, publicBuyLimits);
    }
    
  
    function cancelCampaign(uint256 campaignID, address campaignAddressCheck) external onlyDeployer {
        
        _validate(campaignID, campaignAddressCheck);
        Campaign camp = Campaign(campaignAddressCheck);
        camp.setCancelled();
    }
    
    // Allow MultiSig Dao Admin key to withdraw 
    function daoMultiSigEmergencyWithdraw(address contractAddress, address tokenAddress, uint amount) external onlyOwner {
        IEmergency(contractAddress).daoMultiSigEmergencyWithdraw(msg.sender, tokenAddress, amount);
    }
    
    function _validate(uint256 campaignID, address campaignAddressCheck) view internal {
        require(campaignID < count, "Invalid ID");
        CampaignInfo memory info = allCampaigns[campaignID];
        require(info.contractAddress != address(0), "Invalid Campaign contract");
        require(info.contractAddress == campaignAddressCheck, "Campaign address check fails");
    }
}



