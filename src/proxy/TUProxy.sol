// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// TUProxy
// Minimal style.
// The difference between NTUP and TUP is that the admin can interact with 
// the smart contract itself. To achieve "transparency", handle admin differently
// in the fallback.

interface ITransparentUpgradeableProxy {

    // Events
    event ImplementationSet(address setter, address implementation);
    event AdminSet(address oldAdmin, address newAdmin);

    // Errors
    error ImplementationEmpty(); 
    error NotAdmin();
}

interface ITransparentUpgradeableProxyAdmin {
    // Proxy administration
    function setAdmin(address newAdmin_) external;
    function setImplementation(address newImplementation_) external;
    function upgradeToAndCall(address newImplementation_, bytes memory data_) external;
}

// main contract TUProxy
contract TransparentUpgradeableProxy is ITransparentUpgradeableProxy {

    // ===== constructor =====
    constructor(address admin_, address implementation_, bytes memory data_) {
        // set the proxy admin
        _setAdmin(admin_);
        // set implementation and call
        _setImplementationAndDelegateCall(implementation_, data_);
    }

    // ===== storage layout locations EIP1967 =====
    bytes32 internal constant ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
    bytes32 internal constant IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    // ===== proxy administration is handled in fallback() and forwarded to _adminCall() =====
    function _adminCall() internal {
        // setAdmin
        if (msg.sig == ITransparentUpgradeableProxyAdmin.setAdmin.selector) {
            (address newAdmin_) = abi.decode(msg.data[4:], (address));
            _setAdmin(newAdmin_);
        }

        // setImplementation
        if (msg.sig == ITransparentUpgradeableProxyAdmin.setImplementation.selector) {
            (address implementation_) = abi.decode(msg.data[4:], (address));
            _setImplementation(implementation_);
        }

        // upgradeToAndCall
        if (msg.sig == ITransparentUpgradeableProxyAdmin.upgradeToAndCall.selector) {
            (address newImplementation_, bytes memory data_) = abi.decode(msg.data[4:], (address, bytes));
            _setImplementationAndDelegateCall(newImplementation_, data_);
        }
    }

    // ===== asm write methods =====
    function _setAddress(bytes32 slot_, address value_) internal {
        assembly {
            sstore(slot_, value_)
        }
    }

    function _getAddress(bytes32 slot_) internal view returns (address value_) {
        assembly {
            value_ := sload(slot_)
        }
    }

    // ===== asm read methods =====
    function _admin() internal view returns (address) {
        return _getAddress(ADMIN_SLOT);
    }

    function _implementation() internal view returns (address) {
        return _getAddress(IMPLEMENTATION_SLOT);
    }

    // ===== main delegation code =====
    function _delegate(address implementation_) internal {
        require(implementation_.code.length != 0, ImplementationEmpty());

        assembly {
            calldatacopy(0, 0, calldatasize())

            let result := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)

            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    // ===== internal functions =====
    function _setAdmin(address newAdmin_) internal {
        _setAddress(ADMIN_SLOT, newAdmin_);
        emit AdminSet(msg.sender, newAdmin_);
    }
    
    function _setImplementation(address newImplementation_) internal {
        _setAddress(IMPLEMENTATION_SLOT, newImplementation_);
        emit ImplementationSet(msg.sender, newImplementation_);
    }

    function _delegateCallToImplementation(bytes memory data_) internal {
        if (data_.length > 0) {
            require(_implementation().code.length != 0, ImplementationEmpty());
            (bool success, bytes memory returndata) = _implementation().delegatecall(data_);
            require(success, string(returndata));
        }
    }

    function _setImplementationAndDelegateCall(address newImplementation_, bytes memory data_) internal {
        _setImplementation(newImplementation_);
        _delegateCallToImplementation(data_);
    }

    // ===== delegation entry point handler =====
    fallback() external {
        // by handling admin differently here, we achieve "transparency"
        if (_admin() == msg.sender) {
            _adminCall();
        } else {
            _delegate(_implementation());
        } 
    }
}