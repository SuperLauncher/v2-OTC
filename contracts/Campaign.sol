// SPDX-License-Identifier: agpl-3.0




pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "./interfaces/ISuperDeedNFT.sol";
import "./interfaces/IEmergency.sol";

 
contract Campaign is IEmergency  {
    using SafeERC20 for ERC20;

    uint private constant FACTOR = 1e8; // factor to reduce math truncational error //
    uint private constant VALUE_10 = 10e18;
    
    address public svLaunchAddress;
    address public currencyAddress; // eg: BUSD //
    address public deedNftAddress;
    
    address public factory;
    address public campaignOwner;
    uint public softCap;            
    uint public hardCap;
    uint public totalFutureTokens;
    uint public snapshotId;
    uint public startDate;
    uint public endDate;
    uint public midDate;
    bool public setupReady;
    
    uint private _minPublicBuyLimit;            
    uint private _maxPublicBuyLimit;    
    uint private _minPrivateBuyLimit;
    uint private _lowerSvLaunch;
    uint private _upperSvLaunch;
    uint private _allocForLowerSvLaunch;
    uint private _allocForUpperSvLaunch;
    uint private _mSlope; // Y = m*X + C 
    
    
    struct Purchase {
        uint privateAmount; // amount user bought in private
        uint publicAmount;  // amount user bought in public
        bool mintedNFT;     // user has claimed ? (ie minted his NFT)
        bool refunded;      // user has refunded ?
    }
    
    enum Action {
        Buy,
        ClaimNFT,
        Refund
    }
    
    struct History {
        uint128 timeStamp;
        uint128 action;
        uint amount;
    }
    
    uint256 public totalSold; // Total sales so far.

    // States
    bool public finishUpSuccess; 
    bool public cancelled;     
    bool public readyToClaimNFT;

    // Map user address to amount invested //
    mapping(address => Purchase) public purchases; 
    
    // History 
    mapping(address => History[]) public history; 
    
    // Events
    event Purchased(address indexed user, uint timeStamp, bool privateSale, uint amount);
    event ClaimedNFT(address indexed user, uint timeStamp, uint id);
    event Refund(address indexed user, uint timeStamp, uint amount);
    event DaoMultiSigEmergencyWithdraw(address to, address tokenAddress, uint amount);
    

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory can call");
        _;
    }

    constructor() {
        factory = msg.sender;
    }
    

    function initialize(   
        address svLaunch,
        address campOwner, 
        address deed,
        address currencyToken
    ) onlyFactory external
    {
        svLaunchAddress = svLaunch;
        campaignOwner = campOwner; 
        deedNftAddress = deed;
        currencyAddress = currencyToken;
    }
    
    function setup(  
        uint256[4] calldata stats,  
        uint256[3] calldata dates, 
        uint256[5] calldata privateBuyLimits,
        uint256[2] calldata publicBuyLimits
        ) onlyFactory external 
    {
        softCap = stats[0];
        hardCap = stats[1];
        totalFutureTokens = stats[2]; // Save this value first 
        snapshotId = stats[3];
        startDate = dates[0];
        midDate =  dates[1];
        endDate =  dates[2];
        
        _minPrivateBuyLimit = privateBuyLimits[0];
        _lowerSvLaunch = privateBuyLimits[1];
        _upperSvLaunch = privateBuyLimits[2];
        _allocForLowerSvLaunch = privateBuyLimits[3];
        _allocForUpperSvLaunch = privateBuyLimits[4];
        _minPublicBuyLimit = publicBuyLimits[0];
        _maxPublicBuyLimit = publicBuyLimits[1];
        _mSlope = FACTOR * (_allocForUpperSvLaunch - _allocForLowerSvLaunch) / (_upperSvLaunch - _lowerSvLaunch);
        setupReady = true;
    }
 
    function buyFund(uint amount) external {
        
        require(setupReady, "Not setup yet");
        require(isLive(), "Campaign is not live");
        
        (uint min, uint max) = getMinMaxPurchasable(msg.sender);
        require(amount >= min, "Less than min amount");
        require(amount <= max, "Exceeded available amount");
        
        totalSold += amount;
        ERC20(currencyAddress).safeTransferFrom(msg.sender, address(this), amount);
        
        // Record user's Purchase
        Purchase storage item = purchases[msg.sender];
        if (isPrivatePeriod()) {
            item.privateAmount += amount;
        } else {
            item.publicAmount += amount;
        }

        _recordHistory(msg.sender, Action.Buy, amount);
        emit Purchased(msg.sender, block.timestamp, true, amount);
    }

    function finishUp() external {
        
        require(setupReady, "Not setup yet");
        require(!finishUpSuccess, "finishUp is already called");
        require(!isLive(), "Presale is still live");
        require(!failedOrCancelled(), "Presale failed or cancelled");
        require(softCap <= totalSold, "Did not reach soft cap");
        finishUpSuccess = true;

        // Send raised fund to Campaign Owner (MultiSig).
        ERC20(currencyAddress).safeTransfer(campaignOwner, totalSold);
        readyToClaimNFT = true;
        
        
        //totalFutureTokens
        uint entitlement = (totalFutureTokens * totalSold)/hardCap;
        ISuperDeedNFT(deedNftAddress).setTotalRaise(totalSold, entitlement);
    }

    function claimNFT() external {

        require(readyToClaimNFT, "NFT not ready to claim yet");
     
        Purchase storage item = purchases[msg.sender];
        require(!item.mintedNFT, "Already Minted NFT");
        
        uint total = item.privateAmount + item.publicAmount;
        require(total > 0 ,"Did not purchase");
        item.mintedNFT = true;
        
        // Mint NFT
        uint id = ISuperDeedNFT(deedNftAddress).mint(msg.sender, total);
        
         _recordHistory(msg.sender, Action.ClaimNFT, id);
         emit ClaimedNFT(msg.sender, block.timestamp, id);
         
    }

    function refund() external {
        require(failedOrCancelled(),"Can refund for failed or cancelled campaign only");

        Purchase storage item = purchases[msg.sender];
        require(!item.refunded, "Already Refunded");
        
        uint total = item.privateAmount + item.publicAmount;
        require(total > 0 ,"You did not participate in the campaign");
        
        item.refunded = true;   
            
        ERC20(currencyAddress).safeTransfer(msg.sender, total);
        _recordHistory(msg.sender, Action.Refund, total);
        emit Refund(msg.sender, block.timestamp,total);
    }


    function failedOrCancelled() public view returns(bool) {
        return cancelled || (block.timestamp > endDate) && (totalSold < softCap);
    }

    function isLive() public view returns(bool) {
        if (cancelled || block.timestamp < startDate || block.timestamp > endDate) return false;
        return (totalSold < hardCap); // If reached hardcap, campaign is over.
    }
    
    function isPrivatePeriod() public view returns (bool) {
        return  (block.timestamp >= startDate && block.timestamp <= midDate);
    }

    function getRemaining() public view returns (uint256){
        return hardCap - totalSold;
    }
 
    function setCancelled() onlyFactory public {
        // Can only cancel when no finishUp 
        require(!finishUpSuccess, "Too late to cancel");
        
        cancelled = true;
    }
    
    function getMinMaxPurchasable(address user) public view returns (uint min, uint max) {
        
        if (isLive()) {
            return getMinMaxPurchasableByPeriod(user, isPrivatePeriod());
        }
    }
    
    function getMinMaxPurchasableByPeriod(address user, bool privatePeriod) public view returns (uint min, uint max) {
          
        uint left = getRemaining();
        (min, max) = _getAmountPurchasable(user, privatePeriod);
        max = _min(max, left);
        min = _min(min, left);
    }
    
    function isQualifiedSubscriber(address user) external view returns (bool) {
        (uint min, uint max) =  _getAllocation(user);
        return (min > 0 && max > 0);
    }
 
    function getHistoryCount(address user) external view returns (uint) {
        return history[user].length;
    }
    
    function getHistoryItem(address user, uint index) external view returns (History memory) {
        return history[user][index];
    }
    
    function getHistoryList(address user) external view returns (History[] memory) {
        return history[user];
    }
    
    function daoMultiSigEmergencyWithdraw(address to, address tokenAddress, uint amount) external override onlyFactory {
       
        if (amount > 0 && to != address(0)) {
            // Only ERC20 token withdrawal
            ERC20(tokenAddress).safeTransfer(to, amount); 
            emit DaoMultiSigEmergencyWithdraw(to, tokenAddress, amount);
        }
    }
    
    
    // Private Functions
    
    function _getAmountPurchasable(address user, bool privateSale) private view returns (uint min, uint max) {
        
        if (privateSale) {
            (min, max) = _getAllocation(user);
            max -= purchases[user].privateAmount;
        } else {
            (min, max) = (_minPublicBuyLimit, _maxPublicBuyLimit);
            max -=  purchases[user].publicAmount;
        }
    }
    
    // User with 100 svLaunch onward is qualified to purchase in private round.
    // User with more than 10k svLaunch is treated as 10k svLaunch.
    function _getAllocation(address user) private view returns (uint, uint) {
        
        uint sv = ERC20Snapshot(svLaunchAddress).balanceOfAt(user, snapshotId);
        
        if (sv < _lowerSvLaunch) {
            return (0,0);
        } else if (sv > _upperSvLaunch) {
            sv = _allocForUpperSvLaunch;
        }
        
        uint alloc = _allocForUpperSvLaunch - ((_upperSvLaunch - sv)*_mSlope)/FACTOR;
        return (_minPrivateBuyLimit, (alloc/VALUE_10) * VALUE_10); // to 10 bUSD //
    }
        
        
    function _recordHistory(address user, Action action, uint amount) private {
        History memory item = History(uint128(block.timestamp), uint128(action), amount);
        history[user].push(item);
    }
    
    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}


    



