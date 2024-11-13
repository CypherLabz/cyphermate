// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract Timelock {

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

    // Modifier for admin-only functions
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






    // So that accounts can send msg.value to the Timelock
    receive() external payable {}

}