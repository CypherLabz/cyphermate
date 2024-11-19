// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ERC-173 Compliant -> https://eips.ethereum.org/EIPS/eip-173
abstract contract Ownable {

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    address public owner; 

    modifier onlyOwner() virtual {
        require (msg.sender == owner, "Ownable::onlyOwner: NOT_OWNER");
        _;
    }

    constructor (address owner_) {
        _transferOwnership(owner_);
    }

    function _transferOwnership(address newOwner_) internal virtual {
        address _oldOwner = owner; 
        owner = newOwner_;
        emit OwnershipTransferred(_oldOwner, newOwner_);
    }

    function transferOwnership(address newOwner_) public virtual onlyOwner {
        require(newOwner_ != address(0), 
            "Ownable::transferOwnership: ZERO_ADDRESS_TRANSFER");
            
        _transferOwnership(newOwner_);
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }
}