// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// A pragmatic implementation of ERC721 
// Author: 0xInuarashi
contract ERC721 {

    // Events
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Approval(address indexed owner, address indexed spender, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // Token Metadata
    string public name;
    string public symbol;
    string public baseURI;

    // Storage
    mapping(uint256 => address) internal _ownerOf;
    mapping(address => uint256) internal _balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    // Constructor
    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    // Read Functions
    function ownerOf(uint256 id_) public virtual view returns (address) {
        address _owner = _ownerOf[id_];
        require(_owner != address(0), "ERC721::ownerOf nonexistent");
        return _owner;
    }

    function balanceOf(address wallet_) public virtual view returns (uint256) {
        require(wallet_ != address(0), "ERC721::balanceOf addr0");
        return _balanceOf[wallet_];
    }

    // Internal Write Functions
    function _transfer(address from_, address to_, uint256 id_) internal virtual {
        require(from_ == _ownerOf[id_], "ERC721::_transfer from not owner");
        require(to_ != address(0), "ERC721::_transfer to addr0");

        unchecked {
            _balanceOf[from_]--;
            _balanceOf[to_]++;
        }

        _ownerOf[id_] = to_;
        delete getApproved[id_];
        emit Transfer(from_, to_, id_);
    }
    
    function _mint(address to_, uint256 id_) internal virtual {
        require(to_ != address(0), "ERC721::_mint to addr0");
        require(_ownerOf[id_] == address(0), "ERC721::_mint exists");

        unchecked {
            _balanceOf[to_]++;
        }

        _ownerOf[id_] = to_;
        emit Transfer(address(0), to_, id_);
    }

    function _burn(uint256 id_) internal virtual {
        address _owner = _ownerOf[id_];

        require(_owner != address(0), "ERC721::_burn nonexistent");

        unchecked { 
            _balanceOf[_owner]--;
        }

        delete _ownerOf[id_];
        delete getApproved[id_];

        emit Transfer(_owner, address(0), id_);
    }

    // User Operations
    function approve(address spender_, uint256 id_) public virtual {
        address _owner = _ownerOf[id_];

        require(_owner == msg.sender ||
            isApprovedForAll[_owner][msg.sender], 
            "ERC721::approve no auth"
        );

        getApproved[id_] = spender_;
        emit Approval(_owner, spender_, id_);
    }

    function setApprovalForAll(address operator_, bool approved_) public virtual {
        isApprovedForAll[msg.sender][operator_] = approved_;
        emit ApprovalForAll(msg.sender, operator_, approved_);
    }

    function transferFrom(address from_, address to_, uint256 id_) public virtual {
        require(from_ == msg.sender ||
            isApprovedForAll[from_][msg.sender] ||
            getApproved[id_] == msg.sender,
            "ERC721::transferFrom no auth"
        );

        _transfer(from_, to_, id_);
    }

    function _safeTransferFrom(address from_, address to_, uint256 id_, bytes memory data_) internal virtual {
        transferFrom(from_, to_, id_);

        require(
            to_.code.length == 0 ||
                ERC721TokenReceiver(to_).onERC721Received(
                    msg.sender, 
                    from_, 
                    id_, 
                    data_
                ) == ERC721TokenReceiver.onERC721Received.selector,
            "ERC721::_safeTransferFrom unhandled receiver");
    }

    function safeTransferFrom(address from_, address to_, uint256 id_) public virtual {
        _safeTransferFrom(from_, to_, id_, "");
    }

    function safeTransferFrom(address from_, address to_, uint256 id_, bytes memory data_) public virtual {
        _safeTransferFrom(from_, to_, id_, data_);
    }

    // Token URI 
    function _setBaseURI(string memory uri_) internal virtual {
        baseURI = uri_;
    }
    function tokenURI(uint256) public virtual view returns (string memory) {
        return "";
    }

    // Helpers
    function supportsInterface(bytes4 interfaceId_) public virtual view returns (bool) {
        return 
            interfaceId_ == bytes4(keccak256("supportsInterface(bytes4)")) ||
            interfaceId_ == 0x80ac58cd || // ERC165 - ERC721
            interfaceId_ == 0x5b5e139f; // ERC165 - ERC721Metadata
        // interfaceIds are literally just magic numbers
    }

    function toString(uint256 v) internal pure returns (string memory r) {
        // Cred to Vectorized (crammed version)
        assembly { 
            r := add(mload(0x40),0x80) mstore(0x40,add(r,0x20)) mstore(r,0)
            let e := r let w := not(0)
            for {let t := v} 1 {} { r := add(r,w) mstore8(r,add(48,mod(t,10))) t := div(t,10) if iszero(t) {break} }
            let n := sub(e,r) r := sub(r,0x20) mstore(r,n)
        }
    }
}

abstract contract ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}