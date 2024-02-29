// SPDX-License-Identifier: MIT
// Last update: 2024-02-15
pragma solidity ^0.8.20;

// There is no real EIP for ERC404. It's a bootstrapped standard!

/**
 * ERC404 is basically a ERC20 with chunking based on checkpoints of balances for users that act like ERC721s that can be traded.
 */
abstract contract ERC404 {

    // ERC20 Events
    event ERC20Transfer(address indexed from, address indexed to, uint256 amount);
    event Approve(address indexed owner, address indexed spender, uint256 amount);

    // ERC721 Events
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event ERC721Approval(address indexed owner, address indexed spender, 
        uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // So, let's describe some abilities: 
    // ERC721 is a chunk of ERC20
    // ERC721 is tracked per-address on a user-array basis
    // ERC20 is a non-chunk native fungible token
    // ERC721s are "minted" and "burned" based on checkpoints of chunks

    // Define some constraints and constants -----
    // The token identification
    string public name;
    string public symbol;

    // ERC20-specific constants
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    // ERC721-specific constants
    function maxIndex() public view virtual returns (uint256) {
        return 9999;
    }
    
    // ERC404-specific constants
    function chunkSize() public view virtual returns (uint256) {
        // chunkSize is how many ERC20s per ERC721 
        return 10000 ether;
    }
    // -----

    // Define some mappings -----
    // ERC20 mappings
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ERC721 mappings
    mapping(uint256 => address) public _ownerOf; // public-for-tracking
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    // ERC404 mappings
    mapping(address => uint256[]) public _ownerTokens; // tokens of owner
    // -----

    // Define some state storages -----
    uint256 public totalSupply; // erc20-totalsupply
    uint256 public mintedTokenIndex; // erc721-starts-at-0
    uint256[] public pooledTokens; // stores the pooled tokens

    function __erc20mint(address to_, uint256 amount_) internal virtual {
        // Increment totalSupply
        totalSupply += amount_; 

        // Increment their balance
        unchecked { 
            balanceOf[to_] += amount_;
        }

        emit ERC20Transfer(address(0), to_, amount_);
    }

    function __erc20burn(address from_, uint256 amount_) internal virtual {
        // Decrement balance
        balanceOf[from_] -= amount_;

        // Decrement totalSupply
        unchecked {
            totalSupply -= amount_;
        }

        emit ERC20Transfer(from_, address(0), amount_);
    }

    // function __erc20transfer() {}

    function __erc721mint(address to_) internal virtual {
        uint256 _tokenId = mintedTokenIndex++;

        require(maxIndex() >= _tokenId, "ERC404: max index reached!");

        // // If we're fully minted
        // if (mintedTokenIndex >= maxIndex()) {
        //     uint256 _poolLen = pooledTokens.length;
        //     uint256 _rand = uint256(keccak256(abi.encodePacked(msg.sender, block.prevrandao))); // pseudo-random 

        //     _tokenId = _rand % _poolLen; // makes a number of _poolLen-1 max
        // }

        // // If we're not fully minted
        // else {
        //     _tokenId = mintedTokenIndex++;
        // }
        
        _ownerOf[_tokenId] = to_;
        
        _ownerTokens[to_].push(_tokenId);
        
        emit Transfer(address(0), to_, _tokenId);
    }

    function __erc721burn(address from_) internal virtual {
        uint256 _ownedLen = _ownerTokens[from_].length;
        require(_ownedLen > 0, "ERC404: no token to burn!");

        uint256 _tokenId = _ownerTokens[from_][_ownedLen - 1];

        address _owner = _ownerOf[_tokenId];
        delete _ownerOf[_tokenId];
        delete getApproved[_tokenId];
        emit Transfer(_owner, address(0), _tokenId);
    }

    // function __erc721transfer() {}

    function _erc404mint(address to_, uint256 amount_) internal virtual {
        // first, get the user's current balance
        uint256 _bal = balanceOf[to_];
        // then, calculate the amount of chunk-increment there is
        uint256 _chunkAdd = ((_bal + amount_) % chunkSize()) - (_bal % chunkSize());
        // mint the erc20s
        __erc20mint(to_, amount_);
        // mint the erc721s
        for (uint256 i = 0; i < _chunkAdd;) {
            __erc721mint(to_);
            unchecked { ++i; }
        }
    }




    




}