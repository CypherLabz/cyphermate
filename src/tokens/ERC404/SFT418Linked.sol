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

interface ISF418Primary {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);

    function _ownerOf(uint256 tokenId_) external view returns (address);
    function _balanceOf(address wallet_) external view returns (uint256);

}

abstract contract SFT418Pair {

    /////////////////////////////////
    // Events ///////////////////////
    ///////////////////////////////// 

    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Approval(address indexed owner, address indexed spender, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /////////////////////////////////
    // SFT418Primary Connector //////
    /////////////////////////////////

    // The interface for SFT418Primary 
    ISF418Primary public SFT418; 

    // Deployer for initialization of pairing
    address internal _deployer;

    /////////////////////////////////
    // SFT418 Interface Functions ///
    /////////////////////////////////

    function ownerOf(uint256 tokenId_) public virtual view returns (address) {
        return SFT418._ownerOf(tokenId_);
    }

    function balanceOf(address wallet_) public virtual view returns (uint256) {
        return SFT418._balanceOf(wallet_);
    }

    /////////////////////////////////
    // ERC721 Native Functions //////
    /////////////////////////////////

    function tokenURI(uint256 tokenId_) public virtual view returns (string memory);
}