// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "./Ownable.sol";

/**
 * @title Controllerable: Dynamic Controller System
 * @author 0xInuarashi
 * @notice Controllerable is a role validation smart contract that expands ownable style roles into configurable roles, identified by a string. 
 * Solidity automatically converts a string key in a mapping into a bytes32 type automatically.
 * Each controller type is identified by a string, so you can make an unlimited amount of controller types, such as "MINTER", "BURNER", "OPERATOR", then you can verify internally with onlyController("MINTER") or externally with isController("MINTER", <addressToLookup>)
 */

abstract contract Controllerable is Ownable {

    event ControllerSet(address indexed owner, address indexed controller, string controllerType, bool status);
    
    mapping(string => mapping(address => bool)) internal __controllers;

    function isController(string memory type_, address controller_) public view virtual returns (bool) {
        return __controllers[type_][controller_];
    }

    modifier onlyController(string memory type_) { 
        require(isController(type_, msg.sender), "Controllerable: NOT_CONTROLLER");
        _;
    }

    function setController(string memory type_, address controller_, bool bool_) public virtual onlyOwner {
        __controllers[type_][controller_] = bool_;
        emit ControllerSet(msg.sender, controller_, type_, bool_);
    }
}