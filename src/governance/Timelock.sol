// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract Timelock {

    // Need to set admin
    address public admin;

    modifier onlyAdmin {
        require(msg.sender == admin, "NOT_ADMIN");
        _;
    }

    // Mapping stores txHashes to queued state
    mapping(bytes32 => bool) public queuedTxes;

    // Que a transaction
    function queueTransaction(address target_, uint256 value_, bytes memory data_) public onlyAdmin {

    }

    // Cancel a transaction
    function cancelTransaction(bytes32 txHash_) public onlyAdmin {

    }

    // Execute a Transaction
    function executeTransaction(address target_, uint256 value_, bytes memory data_) public onlyAdmin {

    }









}