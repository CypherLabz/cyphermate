// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract TimelockAdmin {

    // Events
    event AdminSet(address msgSender, address oldAdmin, address newAdmin);

    // Need to set admin
    address public admin;

    // Constructor
    constructor(address admin_) {
        _setAdmin(admin_);
    }

    // Admin Handler Functions
    function _setAdmin(address admin_) internal {
        emit AdminSet(msg.sender, admin, admin_);
        admin = admin_;
    }
    
    function setAdmin(address admin_) external onlyAdmin {
        _setAdmin(admin_);
    }

    // Modifier for admin-only functions
    modifier onlyAdmin {
        require(msg.sender == admin, "TimelockAdmin::onlyAdmin: NOT_ADMIN");
        _;
    }

}

// TODO: add timelock features
contract Timelock is TimelockAdmin {

    // Events
    event TransactionQueued(address indexed operator, bytes32 indexed txHash, address indexed target, uint256 value, bytes data, uint256 executeTimestamp);
    event TransactionCancelled(address indexed operator, bytes32 indexed txHash);
    event TransactionExecuted(address indexed operator, bytes32 indexed txHash, address indexed target, uint256 value, bytes data, uint256 executeTimestamp, bytes returnData);

    // Constructor
    constructor(address admin_) 
        TimelockAdmin(admin_)
    {}

    // Mapping stores txHashes to queued state
    mapping(bytes32 => bool) public queuedTxes;

    // Que a transaction
    function queueTransaction(address target_, uint256 value_, bytes memory data_, uint256 executeTimestamp_) public onlyAdmin {

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
    }

    // Cancel a transaction
    function cancelTransaction(bytes32 txHash_) public onlyAdmin {

        // Make sure the TX Hash is actually queued
        require(queuedTxes[txHash_] == true, 
            "Timelock::cancelTransaction: TX_NOT_QUEUED");

        // Remove it from the queue from SSTORE
        queuedTxes[txHash_] = false;

        // Emit a TransactionCancelled event
        emit TransactionCancelled(msg.sender, txHash_);
    }

    // Execute a Transaction
    function executeTransaction(address target_, uint256 value_, bytes memory data_, uint256 executeTimestamp_) public payable onlyAdmin returns (bytes memory) {

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