// SPDX-License-Identifier: MIT
// Last update: 2024-02-26
pragma solidity ^0.8.20;

/**
 * SFT418Pair is the ERC721 pair of SFT418 which acts as the ERC721 token of 
 * a SFT418 deployment.
 * 
 * The reason that we have a dual-contract design is to comply completely with
 * both ERC20 and ERC721 standards without breaking any casess at all.
 * 
 * It uses fallbacks as communication and mainly emits events. A phantom-ish 
 * token. For more info about phantom tokens, see: 
 * https://0xinuarashi.com/articles/intro-to-phantom-minting
 */

interface ISFT418Pair {
    function linkSFT418Pair() external;
    function emitTransfers(address from_, address to_, uint256[] memory tokenIds_) external;
    function emitTransfer(address from_, address to_, uint256 tokenId_) external;
    function emitApproval(address owner_, address operator_, uint256 tokenId_) external;
    function emitSetApprovalForAll(address owner_, address operator_, bool approved_) external;
}

interface ISFT418Primary {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    
    function _deployer() external view returns (address);

    function _NFT_ownerOf(uint256 tokenId_) external view returns (address);
    function _NFT_balanceOf(address wallet_) external view returns (uint256);
    function _NFT_getApproved(uint256 tokenId_) external view returns (address);
    function _NFT_isApprovedForAll(address spender_, address operator_) external view returns (bool);

    function _NFT_approve(address spender_, uint256 tokenId_, address msgSender_) external returns (bool);
    function _NFT_setApprovalForAll(address operator_, bool approved_, address msgSender_) external returns (bool);
    function _NFT_transferFrom(address from_, address to_, uint256 tokenId_, address msgSender_) external returns (bool);

    function _NFT_mint(address to_, uint256 amount_) external returns (bool);
    function _NFT_burn(address from_, uint256 amount_) external returns (bool);

    function _NFT_reroll(address from_, uint256 tokenId_, address msgSender_) external returns (bool);
    function _NFT_repopulateChunks(address msgSender_) external returns (bool);

    // SFT418S
    function _NFT_swapUserInitiated(uint256 fromId_, uint256 toId_, uint256 fee_,
    address feeTarget_, address msgSender_) external returns (bool);

    // SFT418W
    function _NFT_wrap(uint256 tokenId_, address msgSender_) external returns (bool);
    function _NFT_unwrap(uint256 tokenId_, address msgSender_) external returns (bool);
}

abstract contract SFT418Pair {

    /////////////////////////////////
    // Events ///////////////////////
    ///////////////////////////////// 

    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Approval(address indexed owner, address indexed spender, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event ContractLinked(address contract_);

    // keccak256(bytes("Transfer(address,address,uint256)"))
    bytes32 internal constant _TRANSFER_EVENT_SIGNATURE = 
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    
    // keccak256(bytes("Approval(address,address,uint256)"))
    bytes32 internal constant _APPROVAL_EVENT_SIGNATURE =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;
    
    // keccak256(bytes("ApprovalForAll(address,address,bool)"))
    bytes32 internal constant _APPROVAL_FOR_ALL_EVENT_SIGNATURE = 
        0x17307eab39ab6107e8899845ad3d59bd9653f200f220920489ca2b5937696c31;

    /////////////////////////////////
    // SFT418Primary Connector //////
    /////////////////////////////////

    // The interface for SFT418Primary 
    ISFT418Primary public SFT418; 

    // Deployer for initialization of pairing
    address internal _deployer;

    // Constructor to load _deployer
    constructor() {
        _deployer = msg.sender;
    }

    /////////////////////////////////
    // ERC721 Interface Reads ///////
    /////////////////////////////////

    function name() public virtual view returns (string memory) {
        return SFT418.name();
    }

    function symbol() public virtual view returns (string memory) {
        return SFT418.symbol();
    }

    function ownerOf(uint256 tokenId_) public virtual view returns (address) {
        return SFT418._NFT_ownerOf(tokenId_);
    }

    function balanceOf(address wallet_) public virtual view returns (uint256) {
        return SFT418._NFT_balanceOf(wallet_);
    }

    function getApproved(uint256 tokenId_) public virtual view returns (address) {
        return SFT418._NFT_getApproved(tokenId_);
    }

    function isApprovedForAll(address spender_, address operator_) public virtual view returns (bool) {
        return SFT418._NFT_isApprovedForAll(spender_, operator_);
    }

    /////////////////////////////////
    // ERC721 Interface Writes //////
    /////////////////////////////////

    function approve(address spender_, uint256 tokenId_) public virtual {
        require(SFT418._NFT_approve(spender_, tokenId_, msg.sender));
    }

    function setApprovalForAll(address operator_, bool approved_) public virtual {
        require(SFT418._NFT_setApprovalForAll(operator_, approved_, msg.sender));
    }

    function transferFrom(address from_, address to_, uint256 tokenId_) public virtual {
        require(SFT418._NFT_transferFrom(from_, to_, tokenId_, msg.sender));
    }

    ////////////////////////////////////////////
    // ERC721 Interface Writes (Internal) //////
    ////////////////////////////////////////////

    function _mint(address to_, uint256 amount_) internal virtual {
        require(SFT418._NFT_mint(to_, amount_));
    }

    function _burn(address from_, uint256 amount_) internal virtual {
        require(SFT418._NFT_burn(from_, amount_));
    }

    /////////////////////////////////
    // SFT418 Interface Writes //////
    /////////////////////////////////

    function reroll(uint256 tokenId_) public virtual {
        require(SFT418._NFT_reroll(msg.sender, tokenId_, msg.sender));
    }

    function repopulate() public virtual {
        require(SFT418._NFT_repopulateChunks(msg.sender));
    }

    /////////////////////////////////
    // ERC721-Native Functions //////
    /////////////////////////////////

    function _checkOnERC721Received(address from_, address to_, uint256 tokenId_, bytes memory data_) internal virtual {
        require(
            to_.code.length == 0 ||
                ERC721TokenReceiver(to_).onERC721Received(msg.sender, from_, tokenId_, data_) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "SFT418: _checkOnERC721Received not ERC721 receiver"
        );
    }

    function safeTransferFrom(address from_, address to_, uint256 tokenId_, bytes calldata data_) public virtual {
        transferFrom(from_, to_, tokenId_);
        _checkOnERC721Received(from_, to_, tokenId_, data_);
    }

    function safeTransferFrom(address from_, address to_, uint256 tokenId_) public virtual {
        transferFrom(from_, to_, tokenId_);
        _checkOnERC721Received(from_, to_, tokenId_, "");
    }

    function tokenURI(uint256 tokenId_) public virtual view returns (string memory);

    /////////////////////////////////
    // ERC165 Interface /////////////
    /////////////////////////////////

    function supportsInterface(bytes4 interface_) public view virtual returns (bool) {
        return
            interface_ == 0x01ffc9a7 || // ERC165 Interface ID for ERC165 `supportsInterface(bytes4)`
            interface_ == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interface_ == 0x5b5e139f;   // ERC165 Interface ID for ERC721Metadata
    }

    /////////////////////////////////
    // Fallback SFT418 Interface ////
    /////////////////////////////////
    // Fallback method of communication inspired by DN404 / Solady

    function _requirePair(address pair_, address sender_) internal pure {
        require(pair_ == sender_, "SFT418: fallback() sender is not pair");
    }

    function _calldataload(uint256 offset_) internal pure returns (uint256 _val) {
        assembly {
            _val := calldataload(offset_)
        }
    }

    function _addrload(uint256 offset_) internal pure returns (address) {
        return address(uint160(_calldataload(offset_)));
    }

    function _fbreturn(uint256 word_) internal pure {
        assembly{
            mstore(0x00, word_)
            return(0x00, 0x20)
        }
    }

    function _SFT418FallbackHook(uint256 fnSelector_, address pairAddress_) 
    internal virtual returns (uint256) {

        // "emitTransfers(address,address,uint256[])" >> "0xc9063eae"
        if (fnSelector_ == 0xc9063eae) {
            _requirePair(pairAddress_, msg.sender);
            assembly {
                let from_ := calldataload(0x04) // load from_ address from first 32 bytes of calldata arguments
                let to_ := calldataload(0x24)  // load to_ address from second 32 bytes of calldata args
                let o := add(0x24, calldataload(0x44)) // get the offset of tokenIds_ array
                let end := add(o, shl(5, calldataload(sub(o, 0x20)))) // get the end of tokenIds_ array
                for {} iszero(eq(o, end)) { o:= add(0x20, o) } { // yul loop and emit NFT transfer
                    log4(codesize(), 0x00, _TRANSFER_EVENT_SIGNATURE, from_, to_, calldataload(o))
                }
            }
            return 1;
        }

        // "emitTransfer(address,address,uint256)" >> "0x23de6651"
        if (fnSelector_ == 0x23de6651) {
            _requirePair(pairAddress_, msg.sender);
            emit Transfer(_addrload(0x04), _addrload(0x24), _calldataload(0x44));
            return 1;
        }

        // "emitApproval(address,address,uint256)" >> "0x5687f2b8"
        if (fnSelector_ == 0x5687f2b8) {
            _requirePair(pairAddress_, msg.sender);
            emit Approval(_addrload(0x04), _addrload(0x24), _calldataload(0x44));
            return 1;
        }

        // "emitSetApprovalForAll(address,address,bool)" >> "0xfb5a1525"
        if (fnSelector_ == 0xfb5a1525) {
            _requirePair(pairAddress_, msg.sender);
            emit ApprovalForAll(_addrload(0x04), _addrload(0x24), (_calldataload(0x44) > 0));
            return 1;
        }

        // "linkSFT418Pair()" >> "0x4f2d134e"
        if (fnSelector_ == 0x4f2d134e) {
            // read the _deployer of the sender
            address _senderDeployer = ISFT418Primary(msg.sender)._deployer();

            // make sure our caller is deployed by the same deployer
            require(_senderDeployer == _deployer, "SFT418Pair: fallback() linkSFT418Pair invalid deployer");

            // make sure we've never linked before (one-time thing only)
            require(pairAddress_ == address(0), "SFT418Pair: fallback() linkSFT418Pair already paired");

            // link the contract
            SFT418 = ISFT418Primary(msg.sender);

            // emit event
            emit ContractLinked(msg.sender);
        }

        return 0;
    }

    function _SFT418FallbackHookExtra(uint256 fnSelector_, address pairAddress_) 
    internal virtual returns (uint256) {}

    fallback() external virtual {

        // Load the function selector and pair address
        uint256 l_fnSelector = _calldataload(0x00) >> 224;
        address l_pairAddress = address(SFT418);

        // Return the value of fallback function to r. If r is 0, continue.
        uint256 r = _SFT418FallbackHook(l_fnSelector, l_pairAddress);
        if (r == 0) r = _SFT418FallbackHookExtra(l_fnSelector, l_pairAddress);

        // Return the final value of r
        _fbreturn(r);
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

contract SFT418PairDemo is SFT418Pair {
    
    function tokenURI(uint256) public virtual pure override(SFT418Pair) 
    returns (string memory) {
        return "";
    }

    /////////////////////////////////
    // Test Functions ///////////////
    /////////////////////////////////

    function mint(address to_, uint256 amount_) public virtual {
        _mint(to_, amount_);
    }

    function burn(address from_, uint256 amount_) public virtual {
        _burn(from_, amount_);
    }

    function burn(uint256 tokenId_) public virtual {
        address _owner = ownerOf(tokenId_);
        _burn(_owner, tokenId_);
    }

    function _safeMint(address to, uint256 id) internal virtual {
        _mint(to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, "") ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function _safeMint(
        address to,
        uint256 id,
        bytes memory data
    ) internal virtual {
        _mint(to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, data) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function safeMint(address to, uint256 id) public virtual {
        _safeMint(to, id);
    }

    function safeMint(address to, uint256 id, bytes memory data) public virtual {
        _safeMint(to, id, data);
    }
}

import { Ownable } from "../../access/Ownable.sol";

abstract contract SFT418SPair is SFT418Pair, Ownable {

    event SwapFeesReceiverSet(address indexed operator, address indexed receiver);
    event SwapFeeSet(address indexed operator, uint256 fee);

    address public SWAP_FEE_RECEIVER;
    uint256 public SWAP_FEE; // In basis points

    function setSwapFeeReceiver(address receiver_) public virtual onlyOwner {
        SWAP_FEE_RECEIVER = receiver_;
        emit SwapFeesReceiverSet(msg.sender, receiver_);
    }

    function setSwapFee(uint256 fee_) public virtual onlyOwner {
        SWAP_FEE = fee_;
        emit SwapFeeSet(msg.sender, fee_);
    }

    // A user-initiated swap of an owned token to a pooled token
    function swap(uint256 fromId_, uint256 toId_) public virtual {
        require(SFT418._NFT_swapUserInitiated(
            fromId_,
            toId_,
            SWAP_FEE,
            SWAP_FEE_RECEIVER,
            msg.sender
        ));
    }
}

abstract contract SFT418WPair is SFT418SPair {

    event TokenWrapped(address indexed sender, uint256 indexed tokenId);
    event TokenUnwrapped(address indexed sender, uint256 indexed tokenId);
    
    function wrap(uint256 tokenId_) public virtual {
        require(SFT418._NFT_wrap(tokenId_, msg.sender));
    }

    function unwrap(uint256 tokenId_) public virtual {
        require(SFT418._NFT_unwrap(tokenId_, msg.sender));
    }

    function _SFT418FallbackHookExtra(uint256 fnSelector_, address pairAddress_) 
    internal virtual override(SFT418Pair) returns (uint256) {
        
        // "emitTokenWrapped(address,uint256)" >> "0x576fef23"
        if (fnSelector_ == 0x576fef23) {
            _requirePair(pairAddress_, msg.sender);
            emit TokenWrapped(_addrload(0x04), _calldataload(0x24));
            return 1;
        }

        // "emitTokenUnwrapped(address,uint256)" >> "0x76352c11"
        if (fnSelector_ == 0x76352c11) {
            _requirePair(pairAddress_, msg.sender);
            emit TokenUnwrapped(_addrload(0x04), _calldataload(0x24));
            return 1;
        }

        return 0;
    }
}