// SPDX-License-Identifier: agpl-3.0


pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interfaces/IEmergency.sol";


contract Marketplace is 
    Initializable, 
    OwnableUpgradeable,
    IERC721ReceiverUpgradeable,
    ReentrancyGuardUpgradeable,
    IEmergency
{
    
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    uint public constant VERSION = 0x1;
    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    uint private constant PCNT_100 = 1e6;
    uint private constant MAX_FEE_PCNT = 3e5; // Max fee set at 30% //
    
    
    address public daoFeeAddress;
    uint public feePcnt;
    
    enum Currency {
        BNB,
        BUSD,
        USDT,
        USDC,
        DAI
    }
    
    mapping (Currency => address) private _supportedCurrencyMap;    
    
    struct Listing {
        address seller;
        uint price;
        Currency currency;
    }
     
    // Global listings 
    mapping(address => mapping(uint => Listing)) private _listings;  // Maps NftAddress ->  Nft-Id -> Listing
    mapping(address => EnumerableSetUpgradeable.UintSet) private _nftListedIds; // Maps NftAddress -> Id-Set
    
    // User listings
    struct UserListings {
        EnumerableSetUpgradeable.AddressSet nftAddresses;
        mapping(address => EnumerableSetUpgradeable.UintSet) nftIdMap;
        uint totalCount;
    }
    
    mapping(address => UserListings) private _userListings; // Maps UserAddress -> UserListings
     
    // Supported NFTs
    EnumerableSetUpgradeable.AddressSet private _allowedNFTs; // Only whitelisted NFTs are allowed to be sold.
   
    // Events
    event AddListing(address indexed seller, address indexed nftAddress, uint indexed id, uint price);
    event ChangeListingPrice(address indexed seller, address indexed nftAddress, uint indexed id, uint newPrice, Currency newCurrency);
    event CancelListing(address indexed seller, address indexed nftAddress, uint indexed id);
    event Buy(address indexed seller, address buyer, address indexed nftAddress, uint indexed id, uint price, uint fee);
    event DaoMultiSigEmergencyWithdraw(address to, address tokenAddress, uint amount);
    
    
    function initialize(address feeAddress) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        daoFeeAddress = feeAddress;
        feePcnt = 5e4; // default value is 5%
    }
    
    function setupCurrency(address busd, address usdt, address usdc, address dai) external onlyOwner {
        _supportedCurrencyMap[Currency.BNB] = address(0);
        _supportedCurrencyMap[Currency.BUSD] = busd;
        _supportedCurrencyMap[Currency.USDT] = usdt;
        _supportedCurrencyMap[Currency.USDC] = usdc;
        _supportedCurrencyMap[Currency.DAI] = dai;
    }

    function setFee(uint newFeePcnt) external onlyOwner {
        require(newFeePcnt <= MAX_FEE_PCNT, "Exceeded max fee percent");
        feePcnt = newFeePcnt;
    }
    
    function isNftAllowed(address nft) public view returns (bool) {
        return _allowedNFTs.contains(nft);
    }
    
    function setAllowedNft(address nft, bool allow) external onlyOwner {
        require(ERC165CheckerUpgradeable.supportsInterface(nft, INTERFACE_ID_ERC721));
        if (allow) {
            _allowedNFTs.add(nft);
        } else {
            _allowedNFTs.remove(nft);
        }
    }
    
    function getAllowedNftCount() external view returns (uint) {
        return _allowedNFTs.length();
    }
    
    function getAllowedNfts() external view returns (uint, address[] memory) {
        return getAllowedNfts(0, _allowedNFTs.length());
    }
    
    function getAllowedNfts(uint indexStart, uint count) public view returns (uint, address[] memory) {
       uint len = _allowedNFTs.length();
       
        if (len == 0 || count == 0) {
            return (0, new address[](0));
        }
        
        (uint returnCount, ) = _getEndIndex(indexStart, count, len);
        
        address[] memory nfts = new address[](returnCount);

        for (uint n = 0; n < returnCount; n++) {
            nfts[n] = _allowedNFTs.at(indexStart + n);
        }
        return (returnCount, nfts);
    }

    function getListedNFtIdsCount(address nft) external view returns (uint) {
        return _nftListedIds[nft].length();
    }
    
    function getListedNftIds(address nft) public view returns (uint, uint[] memory) {
        return getListedNftIds(nft, 0, _nftListedIds[nft].length());
    }
    
    function getListedNftIds(address nft, uint indexStart, uint count) public view returns (uint, uint[] memory) {
        
        EnumerableSetUpgradeable.UintSet storage set = _nftListedIds[nft];
        uint len =  set.length();
        
        if( len == 0 || count == 0) {
            return (0, new uint[](0));
        }
        
        (uint returnCount, ) = _getEndIndex(indexStart, count, len);
        
        uint256[] memory ids = new uint[](returnCount);

        for (uint n = 0; n < returnCount; n++) {
            ids[n] = set.at(indexStart + n);
        }
        return (returnCount, ids);
    }

    // User's Operations
    function addListing(address nft, uint id, uint price, Currency currency) external nonReentrant {
        _recordListing(nft, id, price, currency, msg.sender);
        IERC721Upgradeable(nft).safeTransferFrom(msg.sender, address(this), id);
        emit AddListing(msg.sender, nft, id, price);
    }
    
    // User or admin can cancel this listing //
    function cancelListing(address nft, uint id) external nonReentrant {
        address seller = _getSeller(nft, id);
        
        _removeListing(nft, id, msg.sender); // only seller or admin can cancel listing
        IERC721Upgradeable(nft).safeTransferFrom(address(this), seller, id);
        emit CancelListing(msg.sender, nft, id);
    }
    
    function changeListingPrice(address nft, uint id, uint newPrice, Currency newCurrency) external nonReentrant {
        require(_isSeller(nft, id, msg.sender), "Not Seller");
        _listings[nft][id].price = newPrice;
        _listings[nft][id].currency = newCurrency;
        emit ChangeListingPrice(msg.sender, nft, id, newPrice, newCurrency);
    }
    
    function buy(address nft, uint id) external payable nonReentrant {
        address seller = _getSeller(nft, id);
        require(seller != msg.sender, "Buyer same as seller");
        
        (bool valid, uint price, uint fee, Currency currency) = getPrice(nft,id);
        require(valid, "Not listed"); 
         
        _removeListing(nft, id, seller); 
         
        // Transfer price + tax from buyer to contract.
        // Then transfer price from contract to seller & fee to DaoFee address
        address token = getCurrencyAddress(currency);
        
        if (token == address(0)) {
            require (msg.value == price + fee, "Wrong price");
            bool success;
            (success, ) = seller.call{ value: price}("");
            require(success, "Transfer to seller failed");
            
            (success, ) = daoFeeAddress.call{ value: fee}("");
            require(success, "Transfer to Dao failed");
        } else {
        
            IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), price + fee);
            IERC20Upgradeable(token).safeTransfer(seller, price);
            IERC20Upgradeable(token).safeTransfer(daoFeeAddress, fee);
        }
        
        // Transfer NFT from marketplace to buyer
        IERC721Upgradeable(nft).safeTransferFrom(address(this), msg.sender, id);
        
        emit Buy(seller, msg.sender, nft, id, price, fee);
        
    }

    // Query - global
    
    function getNumberOfListingsForNFT(address nft) external view returns (uint) {
        return _nftListedIds[nft].length();
    }
    
    function getListingsForNFT(address nft, uint indexFrom, uint count) external view returns (uint , Listing[] memory) {
        
        EnumerableSetUpgradeable.UintSet storage set = _nftListedIds[nft];
        
        uint len = set.length();
        
        if (len == 0 || count ==0) {
            return (0, new Listing[](0));
        }
        
        (uint returnCount, ) = _getEndIndex(indexFrom, count, len);

        Listing[] memory items = new Listing[](returnCount); 
        uint id;
        for (uint n=0; n<returnCount; n++) {
            id = set.at(indexFrom + n);
            items[n] = _listings[nft][indexFrom+n];
        }
        return (returnCount, items);
    }
    
    function getPrice(address nft, uint id) public view returns (bool valid, uint price, uint fee, Currency currency) {
        valid = _isListed(nft, id);
        if (valid) {
            price =  _listings[nft][id].price;
            fee = _getFeeAmount(price);
            currency = _listings[nft][id].currency;
        }
    }
    
    function getFee(address nft, uint id) public view returns (uint) {
        (bool valid, , uint fee, ) = getPrice(nft, id);
        return valid ? fee : 0;
    }
    
    function getCurrencyAddress(Currency currency) public view returns (address) {
        return _supportedCurrencyMap[currency];
    } 

    
    // Query - users
    
    function getSellerOfNftId(address nft, uint id) external view returns (address) {
        return  _listings[nft][id].seller;
    }
    
    function getTotalListingBySeller(address seller) external view returns (uint) {
        return _userListings[seller].totalCount;
    }
    
    function getNumberOfListingsBySeller(address seller, address nft) external view returns (uint) {
        return _userListings[seller].nftIdMap[nft].length();
    } 
    
    function getListingIDsBySeller(address seller, address nft) external view returns (uint, uint[] memory) {
        uint len = _userListings[seller].nftIdMap[nft].length();
        return getListingIDsBySeller(seller, nft, 0, len);
    }
    
    function getListingIDsBySeller(address seller, address nft, uint indexFrom, uint count) public view returns (uint, uint[] memory) {
        
        uint len =  _userListings[seller].nftIdMap[nft].length();
         
        if( len == 0 || count == 0) {
            return (0, new uint[](0));
        }
         
        (uint returnCount, ) = _getEndIndex(indexFrom, count, len);
    
        uint[] memory items = new uint[](returnCount);
        EnumerableSetUpgradeable.UintSet storage set = _userListings[seller].nftIdMap[nft];
          
        for (uint n=0; n<returnCount; n++) {
            items[n] = set.at(indexFrom + n);
        }
        return (returnCount, items);
    }

    function onERC721Received(
        address, /* operator */
        address, /* from */
        uint256, /*id*/
        bytes calldata /* data */
    ) external override view returns (bytes4) {
        // NOTE: The contract address is always the message sender.
        address tokenAddress = msg.sender;
        require(isNftAllowed(tokenAddress), "Unsupported NFT");
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }
    
    
    // Misc 
    
    function daoMultiSigEmergencyWithdraw(address to, address tokenAddress, uint amount) external override onlyOwner {
       
        if (amount > 0 && to != address(0)) {
            if (tokenAddress == address(0)) {
                (bool success, ) = to.call{ value: amount}("");
                require(success, "Withdraw Error");
            } else {
                 IERC20Upgradeable(tokenAddress).safeTransfer(to, amount); 
            }
            emit DaoMultiSigEmergencyWithdraw(to, tokenAddress, amount);
        }
    }
    
    
    // Internal

    function _getFeeAmount(uint price) internal view returns (uint) {
        return (price * feePcnt)/PCNT_100;
    }
  
    function _requireListed(address nft, uint id, bool listed) internal view {
        require (_isListed(nft, id) == listed, listed ? "Not listed" : "Already listed");
    }
    
    function _isListed(address nft, uint id) internal view returns (bool) {
        return _listings[nft][id].seller != address(0);
    }
    
    function _isSeller(address nft, uint id, address seller) internal view returns (bool) {
        return _listings[nft][id].seller == seller;
    }
    
    function _getSeller(address nft, uint id) internal view returns (address) {
        return _listings[nft][id].seller;
    }
    

    
    function _recordListing(address nft, uint id, uint price, Currency currency, address user) internal {
    
        require(isNftAllowed(nft), "Nft not allowed");
        _requireListed(nft, id, false);
        
        // Update global listing
        _listings[nft][id] = Listing(user, price, currency);
        _nftListedIds[nft].add(id);
        
        // Update user listing
        UserListings storage item = _userListings[user];
        item.nftAddresses.add(nft);
        
        if (item.nftIdMap[nft].add(id)) {
            item.totalCount++;
        }
    }
    
    function _removeListing(address nft, uint id, address user) internal {
        
        address seller = _listings[nft][id].seller;
        require(user == seller || owner() == msg.sender, "Not seller or admin");
        
        // Update global listing
        delete _listings[nft][id];
        _nftListedIds[nft].remove(id);
        
        // Update user Listing
         UserListings storage item = _userListings[user];
        if (item.nftIdMap[nft].remove(id)) {
            item.totalCount--;
        }
        
        if (item.nftIdMap[nft].length() == 0) {
            item.nftAddresses.remove(nft);
        }
    }
    
    function _getEndIndex(uint startIndex, uint count, uint length) internal pure returns (uint returnCount, uint endIndex) {
        
        require(count > 0 && length > 0, "Invalid count or length");
        endIndex = startIndex + count - 1;
        if (endIndex >= length) {
            endIndex = length - 1;
        }
        returnCount = endIndex - startIndex + 1; 
    }
}






