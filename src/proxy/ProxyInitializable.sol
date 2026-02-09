// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// a helper contract that helps with proxy initalization for cleaner code
abstract contract ProxyInitializable {

    // error for initialized
    error AlreadyInitialized();

    // a flag for contract initialization
    bool internal _initialized;

    // a one-use flag modifier for initializer
    modifier OneWayInitializer {
        require(!_initialized, AlreadyInitialized());
        _initialized = true;
        _;
    }

    // to use on implementation constructor to trigger its initialize 
    // without calling the actual initializer
    function _oneWayInitialize() internal {
        _initialized = true;
    }
}