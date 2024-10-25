// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC721 } from "../ERC721.sol";
import { Strings } from "../../../libraries/Strings.sol";

// ERC721 with a standard tokenURI function and state variables ease of implementation
abstract contract ERC721TokenURI is ERC721 {

    string public baseTokenURI;

    function _setBaseTokenURI(string memory uri_) internal virtual {
        baseTokenURI = uri_;
    }

    function tokenURI(uint256 id_) public virtual override(ERC721) view 
    returns (string memory) {
        return string(abi.encodePacked(
            baseTokenURI,
            Strings.toString(id_)
        ));
    }
}