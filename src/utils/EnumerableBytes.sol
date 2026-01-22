// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// minimalist enumerableSet in bytes for adding enumerable to things
// all values are dynamically stored as bytes for multi-word storage, 
// so you can transform them to anything you want to store
// using translation functions. 
// you need to write the translation functions yourself.

// there is a limitation: bytes values cannot be identical, 
// as enumerableBytes works using id-lookup like enumerableSet.

library EnumerableBytes {

	// data structure 
	struct BSet {
		bytes[] values; // values packed as a big array
		mapping(bytes => uint256) indexPlusOne; // location of data in values
	}

	// data manipulations
	function add(BSet storage s, bytes calldata v) internal returns (bool) {
		if (s.indexPlusOne[v] != 0) return false;
		s.values.push(v);
		s.indexPlusOne[v] = s.values.length;
		return true;
	}

	function remove(BSet storage s, bytes calldata v) internal returns (bool) {
		uint256 idxP1 = s.indexPlusOne[v];
		if (idxP1 == 0) return false;

		uint256 lastIdxP1 = s.values.length;
		
		if(idxP1 != lastIdxP1) {
			// replace to-remove value with last value in array
			bytes memory lv = s.values[lastIdxP1-1];
			s.values[idxP1-1] = lv;
			s.indexPlusOne[lv] = idxP1;
		}

		// pop the array and remove the stored index
		s.values.pop();
		delete s.indexPlusOne[v];
		return true;
	}

	function contains(BSet storage s, bytes calldata v) internal view returns (bool) {
		return s.indexPlusOne[v] != 0;
	}

	function length(BSet storage s) internal view returns (uint256) {
		return s.values.length;
	}

	function at(BSet storage s, uint256 idx) internal view returns (bytes memory) {
		return s.values[idx];
	}
}
