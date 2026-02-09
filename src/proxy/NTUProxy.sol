// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// NTUProxy
// We try to be as "standard compliant" as possible
// While being as minimal as possible

// store events and errors
interface INonTransparentUpgradeableProxy {
    // Events
    event ImplementationSet(address setter, address implementation);
    event AdminSet(address oldAdmin, address newAdmin);

    // Errors
    error ImplementationEmpty(); 
    error NotAdmin();
    error NewAdminEmpty();

    // Proxy administration -- we prefix with NTUP to avoid function selector conflicts 
    function NTUP_setAdmin(address newAdmin_) external;
    function NTUP_setImplementation(address newImplementation_) external;
    function NTUP_upgradeToAndCall(address newImplementation_, bytes memory data_) external;
}

// main contract for NTUProxy
contract NonTransparentUpgradeableProxy is INonTransparentUpgradeableProxy {

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

    // ===== modifier =====
    modifier onlyAdmin {
        require(msg.sender == _admin(), NotAdmin());
        _;
    }

    // ===== proxy administration =====
    function NTUP_setAdmin(address newAdmin_) external onlyAdmin {
        require(newAdmin_ != address(0), NewAdminEmpty());
        _setAdmin(newAdmin_);
    }

    function NTUP_setImplementation(address newImplementation_) external onlyAdmin {
        _setImplementation(newImplementation_);
    }

    function NTUP_upgradeToAndCall(address newImplementation_, bytes memory data_) external onlyAdmin {
        _setImplementationAndDelegateCall(newImplementation_, data_);
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
    fallback() external payable {
        _delegate(_implementation());
    }

    // we add receive() because linter is screaming at me 
    receive() external payable {
        _delegate(_implementation());
    }
}
