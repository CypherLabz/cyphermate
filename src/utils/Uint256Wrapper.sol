// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Wraps things into uint256
library Uint256Wrapper {

	function wrapAddress(address a) public pure returns (uint256) {
		return uint256(uint160(a));
	}

	function toAddress(uint256 a) public pure returns (address) {
		return address(uint160(a));
	}

}
