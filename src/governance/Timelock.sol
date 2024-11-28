// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Ownable } from "../access/Ownable.sol";

contract Timelock is Ownable {

    // Events
    event TransactionQueued(address indexed operator, bytes32 indexed txHash, address indexed target, uint256 value, bytes data, uint256 executeTimestamp);
    event TransactionCancelled(address indexed operator, bytes32 indexed txHash);
    event TransactionExecuted(address indexed operator, bytes32 indexed txHash, address indexed target, uint256 value, bytes data, uint256 executeTimestamp, bytes returnData);

    // Delay MIN/MAX Settings
    uint256 public constant MIN_DELAY = 2 days;
    uint256 public constant MAX_DELAY = 30 days;
    uint256 public constant EXECUTION_PERIOD = 14 days;

    // Constructor
    constructor(address admin_) 
        Ownable(admin_)
    {}

    // Mapping stores txHashes to queued state
    mapping(bytes32 => bool) public queuedTxes;

    // Que a transaction
    function queueTransaction(address target_, uint256 value_, bytes memory data_, uint256 executeTimestamp_) public onlyOwner returns (bytes32) {

        // Make sure the executeTimestamp_ is within bounds
        require(executeTimestamp_ >= (block.timestamp + MIN_DELAY) &&
                executeTimestamp_ <= (block.timestamp + MAX_DELAY),
                "Timelock::queueTransaction: TS_OOB");

        // Create the hash of the TX as a record of queued transactions
        bytes32 _txHash = keccak256(abi.encode(
            target_,
            value_,
            data_,
            executeTimestamp_
        ));

        // Make sure the TX Hash isnt currently queued
        require(queuedTxes[_txHash] == false, 
            "Timelock::queueTransaction: TX_ALREADY_QUEUED");

        // Queue the TX in SSTORE
        queuedTxes[_txHash] = true;

        // Emit a TransactionQueued event
        emit TransactionQueued(msg.sender, _txHash, target_, value_, data_, executeTimestamp_);

        // Return the txHash
        return _txHash;
    }

    // Cancel a transaction
    function cancelTransaction(bytes32 txHash_) public onlyOwner {

        // Make sure the TX Hash is actually queued
        require(queuedTxes[txHash_] == true, 
            "Timelock::cancelTransaction: TX_NOT_QUEUED");

        // Remove it from the queue from SSTORE
        queuedTxes[txHash_] = false;

        // Emit a TransactionCancelled event
        emit TransactionCancelled(msg.sender, txHash_);
    }

    // Execute a Transaction
    function executeTransaction(address target_, uint256 value_, bytes memory data_, uint256 executeTimestamp_) public payable onlyOwner returns (bytes memory) {

        // Calculate the txHash
        bytes32 _txHash = keccak256(abi.encode(
            target_,
            value_,
            data_,
            executeTimestamp_
        ));

        // Make sure the txHash has been queued
        require(queuedTxes[_txHash] = true, 
            "Timelock::executeTransaction: TX_NOT_QUEUED");

        // Make sure that the msg.value exactly matches value_ to send
        require(value_ == msg.value,
            "Timelock::executeTransaction: INCORRECT_VALUE");

        // Make sure that the TX has reached its executeTimestamp
        require(block.timestamp >= executeTimestamp_, 
            "Timelock::executeTransaction: TIMELOCK_NOT_REACHED");

        // Then, make sure its within the execution period
        require(block.timestamp <= (executeTimestamp_ + EXECUTION_PERIOD),
            "Timelock::executeTransaction: TIMELOCK_EXCEEDED_EXECUTION_PERIOD");

        // Consume the queued TX
        queuedTxes[_txHash] = false;

        // Execute the TX
        (bool success, bytes memory returnData) = target_.call{value: value_}(data_);
        require(success, "Timelock::executeTransaction: TX_REVERTED");

        // Emit a TransactionExecuted event
        emit TransactionExecuted(msg.sender, _txHash, target_, value_, data_, executeTimestamp_, returnData);

        // Return the returnData
        return returnData;
    }

    // So that accounts can send msg.value to the Timelock
    receive() external payable {}

}