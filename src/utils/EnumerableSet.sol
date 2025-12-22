// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// minimalist enumerableSet for adding enumerable to things
// all values are casted into uint256, so you can transform them 
// to anything you want to store
// example for address = uint256(uint160(address)) 
library EnumerableSet {

	// data structure 
	struct Set {
		uint256[] values;
		mapping(uint256 => uint256) indexPlusOne;
	}

	// data manipulations
	function add(Set storage s, uint256 v) internal returns (bool) {
		if (s.indexPlusOne[v] != 0) return false;
		s.values.push(v);
		s.indexPlusOne[v] = s.values.length;
		return true;
	}

	function remove(Set storage s, uint256 v) internal returns (bool) {
		uint256 idxP1 = s.indexPlusOne[v];
		if (idxP1 == 0) return false;

		uint256 lastIdxP1 = s.values.length;
		
		if(idxP1 != lastIdxP1) {
			// replace to-remove value with last value in array
			uint256 lv = s.values[lastIdxP1-1];
			s.values[idxP1-1] = lv;
			s.indexPlusOne[lv] = idxP1;
		}

		// pop the array and remove the stored index
		s.values.pop();
		delete s.indexPlusOne[v];
		return true;
	}

	function contains(Set storage s, uint256 v) internal view returns (bool) {
		return s.indexPlusOne[v] != 0;
	}

	function length(Set storage s) internal view returns (uint256) {
		return s.values.length;
	}

	function at(Set storage s, uint256 idx) internal view returns (uint256) {
		return s.values[idx];
	}
}
