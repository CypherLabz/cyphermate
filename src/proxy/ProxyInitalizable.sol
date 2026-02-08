// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// a helper contract that helps with proxy initalization for cleaner code
abstract contract ProxyInitializable {

    // a flag for contract initialization
    bool internal _initialized;

    // a one-use flag modifier for initializer
    modifier Initializer {
        require(!_initialized);
        _initialized = true;
        _;
    }
}