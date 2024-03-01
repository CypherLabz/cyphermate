// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract ERC721 {

    // Events
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Approval(address indexed owner, address indexed spender, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // Token Metadata
    string public name;
    string public symbol;
    function tokenURI(uint256 id_) public virtual view returns (string memory);

    // Token Storage
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
    function ownerOf(uint256 id_) public virtual view returns (address _owner) {
        require((_owner = _ownerOf[id_]) != address(0), "ERC721: ownerOf nonexistent token");
    }

    function balanceOf(address wallet_) public virtual view returns (uint256) {
        require(wallet_ != address(0), "ERC721: balanceOf zero address");
        return _balanceOf[wallet_];
    }

    // Write Functions
    function approve(address spender_, uint256 id_) public virtual {
        address _owner = _ownerOf[id_];
        
        require(_owner == msg.sender ||
                isApprovedForAll[_owner][msg.sender],
                "ERC721: approve not authorized");
        
        getApproved[id_] = spender_;
        emit Approval(_owner, spender_, id_);
    }

    function setApprovalForAll(address operator_, bool approved_) public virtual {
        isApprovedForAll[msg.sender][operator_] = approved_;
        emit ApprovalForAll(msg.sender, operator_, approved_);
    }

    function transferFrom(address from_, address to_, uint256 id_) public virtual {
        require(from_ == _ownerOf[id_], "ERC721: transferFrom from not owner");
        require(to_ != address(0), "ERC721 transferFrom to zero address");
        
        require(from_ == msg.sender ||
                isApprovedForAll[from_][msg.sender] ||
                getApproved[id_] == msg.sender,
                "ERC721: transferFrom not authorized");

        unchecked {
            _balanceOf[from_]--;
            _balanceOf[to_]++;
        }

        _ownerOf[id_] = to_;
        delete getApproved[id_];
        emit Transfer(from_, to_, id_);
    }

    function _safeTransferFrom(address from_, address to_, uint256 id_, bytes memory data_) internal virtual {
        transferFrom(from_, to_, id_);

        require(
            to_.code.length == 0 ||
                ERC721TokenReceiver(to_).onERC721Received(msg.sender, from_, id_, data_) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "ERC721: _safeTransferFrom to unhandled receiver");
    }
    
    function safeTransferFrom(address from_, address to_, uint256 id_) public virtual {
        _safeTransferFrom(from_, to_, id_, "");
    }

    function safeTransferFrom(address from_, address to_, uint256 id_, bytes calldata data_) public virtual {
        _safeTransferFrom(from_, to_, id_, data_);
    }

    // Internal Mint and Burn
    function _mint(address to_, uint256 id_) internal virtual {
        require(to_ != address(0), "ERC721: _mint to zero address");
        require(_ownerOf[id_] == address(0), "ERC721: _mint existent token");

        unchecked {
            _balanceOf[to_]++;
        }

        _ownerOf[id_] = to_;

        emit Transfer(address(0), to_, id_);
    }

    function _burn(uint256 id_) internal virtual {
        address _owner = _ownerOf[id_];

        require(_owner != address(0), "ERC721: _burn nonexistent token");

        unchecked {
            _balanceOf[_owner]--;
        }

        delete _ownerOf[id_];
        delete getApproved[id_];

        emit Transfer(_owner, address(0), id_);
    }

    // ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
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

contract ERC721Demo is ERC721 {

    constructor(string memory name_, string memory symbol_) 
        ERC721(name_, symbol_)
    {}

    function tokenURI(uint256) public pure override(ERC721) returns (string memory) {
        return "";
    }

    function mint(address to_, uint256 id_) public virtual {
        _mint(to_, id_);
    }

    function burn(uint256 id_) public virtual {
        _burn(id_);
    }

    function safeMint(address to, uint256 id) public virtual {
        _mint(to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, "") ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function safeMint(
        address to,
        uint256 id,
        bytes memory data
    ) public virtual {
        _mint(to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, data) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }
}