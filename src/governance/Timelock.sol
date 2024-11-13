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

contract Timelock is TimelockAdmin {

    // Events
    event TransactionQueued(address indexed operator, bytes32 indexed txHash, address indexed target, uint256 value, bytes data, uint256 executeTimestamp);
    event TransactionCancelled(address indexed operator, bytes32 indexed txHash);

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
    function executeTransaction(address target_, uint256 value_, bytes memory data_, uint256 executeTimestamp_) public onlyAdmin {
        

    }






    // So that accounts can send msg.value to the Timelock
    receive() external payable {}

}