// SPDX-License-Identifier: MIT
// Last update: 2024-05-05
pragma solidity ^0.8.20;

library Strings {

    function toString(uint256 value_) internal pure returns (string memory) {
        if (value_ == 0) return "0";
        
        uint256 _iterate = value_; 
        uint256 _digits;
        
        while (_iterate != 0) {
            _digits++; 
            _iterate /= 10;
        }
        
        bytes memory _buffer = new bytes(_digits);
        
        while (value_ != 0) {
            _digits--; 
            _buffer[_digits] = bytes1(uint8(48 + uint256(value_ % 10 ))); 
            value_ /= 10; 
        }

        return string(_buffer); 
    }
}