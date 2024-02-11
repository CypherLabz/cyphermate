// SPDX-License-Identifier: MIT
// Last update: 2024-02-12
pragma solidity ^0.8.20;

import { ERC20 } from "../ERC20.sol";

// An extension of ERC20 which allows user-initiated self-burn and an allowanced burnFrom
abstract contract ERC20Burnable is ERC20 {

    function burn(uint256 amount_) public virtual {
        ERC20._burn(msg.sender, amount_);
    }

    function burnFrom(address from_, uint256 amount_) public virtual {
        ERC20._spendAllowance(from_, msg.sender, amount_);
        ERC20._burn(msg.sender, amount_);
    }
}