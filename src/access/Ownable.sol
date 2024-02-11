// SPDX-License-Identifier: MIT
// Last update: 2024-01-20
pragma solidity ^0.8.20;

// ERC-173 Compliant -> https://eips.ethereum.org/EIPS/eip-173
abstract contract Ownable {

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    address public owner; 

    modifier onlyOwner() virtual {
        require (msg.sender == owner, "Ownable: NOT_OWNER");
        _;
    }

    constructor () {
        _transferOwnership(msg.sender);
    }

    function _transferOwnership(address newOwner_) internal virtual {
        address _oldOwner = owner; 
        owner = newOwner_;
        emit OwnershipTransferred(_oldOwner, newOwner_);
    }

    function transferOwnership(address newOwner_) external virtual onlyOwner {
        require(newOwner_ != address(0), "Ownable: ZERO_ADDRESS_TRANSFER");
        _transferOwnership(newOwner_);
    }

    // renounceOwnership() is made payable with a small ether requirement
    // to prevent accidental renounces
    function renounceOwnership() public payable virtual onlyOwner {
        require(msg.value == 0.000000000000000173 ether);
        _transferOwnership(address(0));
    }
}