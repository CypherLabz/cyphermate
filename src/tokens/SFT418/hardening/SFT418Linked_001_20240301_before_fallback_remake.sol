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
    function _NFT_transferFrom(address from_, address to_, uint256 tokenId_) external returns (bool);

    function _NFT_mint(address to_, uint256 amount_) external returns (bool);
    function _NFT_burn(address from_, uint256 amount_) external returns (bool);

    function _NFT_reroll(address from_, uint256 tokenId_, address msgSender_) external returns (bool);
    function _NFT_repopulateChunks(address msgSender_) external returns (bool);

    // SFT418S
    function _NFT_swapUserInitiated(uint256 fromId_, uint256 toId_, uint256 fee_,
    address feeTarget_, address msgSender_) external returns (bool);
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
        require(SFT418._NFT_transferFrom(from_, to_, tokenId_));
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
                ERC721TokenReceiver(to_).onERC721Received(from_, to_, tokenId_, data_) ==
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

    function _calldataload(uint256 offset_) private pure returns (uint256 _val) {
        assembly {
            _val := calldataload(offset_)
        }
    }

    modifier SFT418Fallback() virtual {
        // Grab the first bytes32 of calldata and right shift bytes28 resulting in bytes4 selector
        bytes4 l_fnSelector = bytes4(bytes32(_calldataload(0x00) >> 224)); 

        // Load the address of the SFT418 pair
        address l_pairAddress = address(SFT418);

        // FALLBACK LINK FUNCTION
        // "linkSFT418Pair()" >> "0x4f2d134e"
        if (l_fnSelector == 0x4f2d134e) {
            // read the _deployer of the sender
            address _senderDeployer = ISFT418Primary(msg.sender)._deployer();

            // make sure our caller is deployed by the same deployer
            require(_senderDeployer == _deployer, "SFT418Pair: fallback() linkSFT418Pair invalid deployer");

            // make sure we've never linked before (one-time thing only)
            require(l_pairAddress == address(0), "SFT418Pair: fallback() linkSFT418Pair already paired");

            // link the contract
            SFT418 = ISFT418Primary(msg.sender);

            // emit event
            emit ContractLinked(msg.sender);
        }

        // FALLBACK PAIR FUNCTIONS
        // "emitTransfers(address,address,uint256[])" >> "0xc9063eae"
        if (l_fnSelector == 0xc9063eae) {
            _requirePair(l_pairAddress, msg.sender);
            assembly {
                let from_ := calldataload(0x04) // load from_ address from first 32 bytes of calldata arguments
                let to_ := calldataload(0x24)  // load to_ address from second 32 bytes of calldata args
                let o := add(0x24, calldataload(0x44)) // get the offset of tokenIds_ array
                let end := add(o, shl(5, calldataload(sub(o, 0x20)))) // get the end of tokenIds_ array
                for {} iszero(eq(o, end)) { o:= add(0x20, o) } { // yul loop
                    // emit NFT transfer
                    log4(codesize(), 0x00, _TRANSFER_EVENT_SIGNATURE, from_, to_, calldataload(o))
                }
                mstore(0x00, 0x01)
                return(0x00, 0x20)
            }
        }

        // "emitTransfer(address,address,uint256)" >> "0x23de6651"
        if (l_fnSelector == 0x23de6651) {
            require(msg.sender == l_pairAddress, "SFT418Pair: fallback() emitTransfer not from pair");
            assembly {
                let from_ := calldataload(0x04)
                let to_ := calldataload(0x24)
                let tokenId_ := calldataload(0x44)
                log4(codesize(), 0x00, _TRANSFER_EVENT_SIGNATURE, from_, to_, tokenId_)
                mstore(0x00, 0x01)
                return(0x00, 0x20)
            }
        }

        // "emitApproval(address,address,uint256)" >> "0x5687f2b8"
        if (l_fnSelector == 0x5687f2b8) {
            require(msg.sender == l_pairAddress, "SFT418Pair: fallback() emitApproval not from pair");
            assembly {
                let owner_ := calldataload(0x04)
                let spender_ := calldataload(0x24)
                let tokenId_ := calldataload(0x44)
                log4(codesize(), 0x00, _APPROVAL_EVENT_SIGNATURE, owner_, spender_, tokenId_)
                mstore(0x00, 0x01)
                return(0x00, 0x20)
            }
        }

        // "emitSetApprovalForAll(address,address,bool)" >> "0xfb5a1525"
        if (l_fnSelector == 0xfb5a1525) {
            require(msg.sender == l_pairAddress, "SFT418Pair: fallback() emitSetApprovalForAll not from pair");
            assembly {
                let owner_ := calldataload(0x04)
                let operator_ := calldataload(0x24)
                let approved_ := calldataload(0x44)
                
                // load approved_ and emit it as non-indexed event data
                mstore(0x00, approved_) 
                log3(0x00, 0x20, _APPROVAL_FOR_ALL_EVENT_SIGNATURE, owner_, operator_)
                
                // replace approved_ with 1 to return true afterwards
                mstore(0x00, 0x01)
                return(0x00, 0x20)
            }
        }

        _;
    }

    // Hook the SFT418Fallback into fallback()
    fallback() external virtual SFT418Fallback {
        revert ("Unrecognized calldata");
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
    
    // "TokenWrapped(address,uint256)"
    bytes32 internal constant _TOKEN_WRAPPED_EVENT_SIGNATURE =
        0x2273a99739c31a37346636a3013c2cedebee7cd5b4c560faded39d298c1dd45c;
    
    // "TokenUnwrapped(address,uint256)"
    bytes32 internal constant _TOKEN_UNWRAPPED_EVENT_SIGNATURE = 
        0x7f8146ca1ae17ad17561461ef221d97c8160bfddcae0edb68f53ce8dc5ce4af3;

    
}