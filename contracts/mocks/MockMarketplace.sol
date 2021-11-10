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
import "../interfaces/IEmergency.sol";


contract MockMarketplace is 
    Initializable, 
    OwnableUpgradeable,
    IERC721ReceiverUpgradeable,
    ReentrancyGuardUpgradeable,
    IEmergency
{
    
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    uint public constant VERSION = 0x2;
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
        uint id;
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
    event AddListing(address indexed seller, address indexed nftAddress, uint indexed id, uint price, Currency currency);
    event ChangeListingPrice(address indexed seller, address indexed nftAddress, uint indexed id, uint newPrice, Currency newCurrency);
    event CancelListing(address indexed seller, address indexed nftAddress, uint indexed id);
    event Buy(address indexed seller, address buyer, address indexed nftAddress, uint indexed id, uint price, uint fee, Currency currency);
    event DaoMultiSigEmergencyWithdraw(address to, address tokenAddress, uint amount);
    event SetFee(uint oldFee, uint newFee);
    
    function initialize(address feeAddress) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        daoFeeAddress = feeAddress;
        feePcnt = 5e4; // default value is 5%
    }

    function onERC721Received(
        address, /* operator */
        address, /* from */
        uint256, /*id*/
        bytes calldata /* data */
    ) external override view returns (bytes4) {
        // NOTE: The contract address is always the message sender.
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
}






