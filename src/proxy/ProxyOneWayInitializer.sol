// SPDX-License-Identifier: MIT
// Last update: 2024-05-05
pragma solidity ^0.8.20;

/**
 * @title  ProxyOneWayInitializer
 * @author 0xInuarashi
 * @notice Provides an easy-to-use modifier to hook for a one-way proxy initializer function
 */
abstract contract ProxyOneWayInitializer { 

    bool internal _proxyInitialized;

    modifier proxyInitializer() virtual {
        require (!_proxyInitialized, "ProxyOneWayInitializer: Initialized");
        _proxyInitialized = true;
        _;
    }

}