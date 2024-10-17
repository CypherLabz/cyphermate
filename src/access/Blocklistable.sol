// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract Blocklistable {

    event Blocklisted(address indexed operator, address indexed wallet, bool blocklisted);

    mapping(address => bool) internal _blocklisted;

    function _setBlocklist(address[] memory wallets_, bool blocklisted_) internal virtual {
        for (uint256 i; i < wallets_.length;) {
            _blocklisted[wallets_[i]] = blocklisted_;
            emit Blocklisted(msg.sender, wallets_[i], blocklisted_);
            unchecked { ++i; }
        }
    }

    function _isBlocklisted(address wallet_) internal virtual view returns (bool) {
        return _blocklisted[wallet_];
    }

    modifier notBlocklisted(address wallet_) {
        require(!_blocklisted[wallet_], "WALLET_BLOCKLISTED");
        _;
    }

}