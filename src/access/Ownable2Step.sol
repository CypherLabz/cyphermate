// SPDX-License-Identifier: MIT
// Last update: 2024-01-20
pragma solidity ^0.8.20;

import { Ownable } from "./Ownable.sol";

// An extension of EIP-173 for a 2-step verification of ownership transfer.
abstract contract Ownable2Step is Ownable {

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    address public pendingOwner;

    // Override Functions
    function transferOwnership(address newOwner_) public virtual override(Ownable) onlyOwner {
        pendingOwner = newOwner_;
        emit OwnershipTransferStarted(msg.sender, newOwner_); 
    }

    function _transferOwnership(address newOwner_) internal virtual override(Ownable) {
        delete pendingOwner;
        Ownable._transferOwnership(newOwner_);
    }

    // Non-Override Functions
    function acceptOwnership() public virtual {
        require(pendingOwner == msg.sender, "Ownable2Step: NOT_PENDING_OWNER");
        Ownable2Step._transferOwnership(msg.sender);
    }

    // renounceOwnership() is made payable with a small ether requirement
    // to prevent accidental renounces
    function renounceOwnership() public payable virtual override(Ownable) onlyOwner {
        delete pendingOwner;
        Ownable.renounceOwnership();
    }
}