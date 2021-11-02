// SPDX-License-Identifier: agpl-3.0


pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./interfaces/ISuperDeedNFT.sol";


contract SuperDeedNFT is ISuperDeedNFT, ERC721Enumerable {

    using SafeERC20 for ERC20;
    
    string private constant SUPER_DEED = "SuperDeed";
    string private constant BASE_URI = "https://superlauncher.io/metadata/";
    uint private constant PCNT_100 = 1e6;
    uint private constant MAX_FEE_PCNT = 5e5; // 50%
        
    address private _minter; // minter can mint and set totalRaise value
    address private _distributor; // distributor can set asset address and distribute tokens
    address public daoFeeAddress;
    uint public daoFeePcnt;
    
    
    struct Asset {
        string symbol;
        string deedName;
        address tokenAddress;
        uint totalEntitlement;
    }
    
    uint private _tokenIds;
    Asset public asset;
    uint public totalRaise;
    
    struct NftInfo {
        uint weight;
        uint nextClaimIndex;
        uint claimedPtr;
        bool valid;
    }
    
    // NFT data map
    mapping(uint => NftInfo) private _nftInfoMap;
    
    // token releases
    struct TokenRelease {
        uint timeStamp;
        uint amount;
    }
    
    // Accounting System
    TokenRelease[] private _tokenReleases;
    uint public totalTokensReleased;
    
    
    // Events
    event Mint(address indexed user, uint timeStamp, uint id, uint amount);
    event Claim(address indexed user, uint timeStamp, uint id, uint amount);
    event Split(uint timeStamp, uint id1, uint id2, uint amount);
    event Combine(uint timeStamp, uint id1, uint id2);
    event DistributeTokens(uint timeStamp, uint total, uint fee);
    
    modifier onlyMinter() {
        require(msg.sender == _minter, "Only minter can call");
        _;
    }
    
    modifier onlyDistributor() {
        require(msg.sender == _distributor, "Only distributor can call");
        _;
    }

    constructor(
        address minter, 
        address distributor, 
        address feeAddress, 
        string memory tokenSymbol, 
        string memory deedName
    ) ERC721(deedName, SUPER_DEED) 
    {
        _minter = minter;    
        _distributor = distributor;
        daoFeeAddress = feeAddress;
        asset.symbol = tokenSymbol;
        asset.deedName = deedName;
    }
    
    function tokenURI(uint256 /*tokenId*/) public view virtual override returns (string memory) {
        return  string(abi.encodePacked(BASE_URI, asset.deedName));
    }

    // only Camapign contract can mint this
    function mint(address to, uint weight) external onlyMinter override returns (uint){
        return _mintInternal(to, weight, 0 , 0);
    }
    
    // Note: this is called by the Campaign upon finishUp(). Called once only.
    function setTotalRaise(uint raised, uint entitledTokens) external override onlyMinter {
        require(totalRaise == 0, "Can only be called once");
        require(raised > 0 && entitledTokens > 0, "Invalid value");
        totalRaise = raised;
        asset.totalEntitlement = entitledTokens;
    }
    
    function setAssetInfo( string memory symbol) external  onlyDistributor {
        asset.symbol = symbol;
    }
    
    function setDaoFee(uint feePcnt) external onlyDistributor {
        require(feePcnt <= MAX_FEE_PCNT, "Exceeded fee percent");
        daoFeePcnt = feePcnt;
    }
    
    // Note: In a normal workflow, the asset address is set only once, upon confirmation from project owner.
    // However, just in case that project owner need to change the address (eg: in case of re-issue before TGE),
    // then distributor will be able to change BEFORE making first distribution. But once first distributon is made,
    // token address cannot be changed anymore.
    function setAssetAddress(address tokenAddress) external  onlyDistributor {
        require(tokenAddress != address(0), "Invalid asset address");
        require(_tokenReleases.length == 0, "Cannot set token address after distribution");
        
        asset.tokenAddress = tokenAddress;
    }
    
    function distributeTokens(uint amount) external onlyDistributor {
        require(asset.tokenAddress != address(0), "Invalid asset address");
        require(amount > 0, "Invalid amount");
        
        // Transfer in tokens
        ERC20(asset.tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        
        // Account for daoFee
        uint remain = amount;
        uint fee;
        if (daoFeePcnt > 0) {
            fee = (daoFeePcnt * amount)/PCNT_100;
            ERC20(asset.tokenAddress).safeTransfer(daoFeeAddress, fee);
            remain -= fee; 
        }

        _tokenReleases.push(TokenRelease(block.timestamp, remain));
        totalTokensReleased += remain;
        
        emit DistributeTokens(block.timestamp, amount, fee);
    }
    
    function getClaimable(uint id) public view returns (bool valid, uint amount, uint indexFrom, uint indexTo, uint claimedSofar, uint totalEntitlement) {
        
        uint len = _tokenReleases.length;
        
        NftInfo memory item = _nftInfoMap[id];
        valid = item.valid;
        
        // If there's token distribution(s) to be claimed, then indexFrom and indexTo will have valid values.
        // If not, they will default to 0 index.
        if (valid) {
            
            if (len > item.nextClaimIndex) {
                amount = ((totalTokensReleased - item.claimedPtr) * item.weight)/totalRaise;
                indexFrom = item.nextClaimIndex;
                indexTo = len - 1;
            }
            totalEntitlement = (item.weight * asset.totalEntitlement) / totalRaise;
            claimedSofar = (item.weight * item.claimedPtr) / totalRaise;
        }
    }
    
    
    function claim(uint id) external {
        
        require(ownerOf(id) == msg.sender, "Not owner");
        
        (bool valid, uint amt, , uint indexTo, , ) = getClaimable(id);
        
        require(valid, "Invalid Id");
        require(amt > 0, "Zero amount to claim");
        
        ERC20(asset.tokenAddress).safeTransfer(msg.sender, amt);
        
        NftInfo storage item = _nftInfoMap[id];
        item.nextClaimIndex = indexTo + 1;
        item.claimedPtr = totalTokensReleased;
         
        // Emit event
        emit Claim(msg.sender, block.timestamp, id, amt);
    }
    
    function getItemInfo(uint id) external view returns (NftInfo memory) {
        return _nftInfoMap[id];
    }

    function weightOf(uint id) external view returns (uint) {
        return _exists(id) ? _nftInfoMap[id].weight : 0;
    }
    
    function getTokenReleasesCount() external view returns (uint) {
        return _tokenReleases.length;
    }
    
    function getTokenReleaseItem(uint index) external view returns (TokenRelease memory) {
        return _tokenReleases[index];
    }
    
    function getTokenReleaseList() external view returns (TokenRelease[] memory) {
        return _tokenReleases;
    }
    
    function splitByPercent(uint id, uint pcnt) external returns (uint) {
        require(pcnt > 0 && pcnt < PCNT_100, "Invalid percentage");
        
        uint amount = (_nftInfoMap[id].weight * pcnt)/PCNT_100;
        return _splitByAmount(id, amount);
    }
    
    function splitByAmount(uint id, uint amount) external returns (uint) {
       return _splitByAmount(id, amount);
    }
    
    // When we combine 2 NFT, we need to make sure that the 2 NFT claim status is same.
    // Otherwise, the user should claim the tokens (distribution) before combining. 
    function combine(uint id1, uint id2) external {
         require(ownerOf(id1) == msg.sender && ownerOf(id2) == msg.sender, "Not owner");
         require(_nftInfoMap[id1].nextClaimIndex == _nftInfoMap[id2].nextClaimIndex, "Please claim before combining");
         
         _nftInfoMap[id1].weight += _nftInfoMap[id2].weight;
         
         // Burn NFT 2 
         _burn(id2);
    }
    
    function _splitByAmount(uint id, uint amount) internal returns (uint newId) {
        
        require(ownerOf(id) == msg.sender, "Not owner");
       
        // reduce own amount
        NftInfo storage item = _nftInfoMap[id];
        require(item.weight > amount, "Exceeded amount");
        item.weight -= amount;
        
        // mint new amount
        newId = _mintInternal(msg.sender, amount, item.nextClaimIndex , item.claimedPtr);
        emit Split(block.timestamp, id, newId, amount);
    }
        
    function _mintInternal(address to, uint weight, uint nextClaimIndex, uint claimedPtr) internal returns (uint) {
        uint id = _tokenIds++;
        _mint(to, id);
        _nftInfoMap[id] = NftInfo(weight, nextClaimIndex, claimedPtr, true);
        return id;
    }
}

