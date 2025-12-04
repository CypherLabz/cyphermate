// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ERC20 {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    string public name;
    string public symbol;

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    constructor(
        string memory name_,
        string memory symbol_
    ) {
        name = name_;
        symbol = symbol_;
    }

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function _mint(address to_, uint256 amount_) internal virtual {
        require(to_ != address(0), "ERC20::_mint TO_ZERO");
        totalSupply += amount_;
        unchecked {
            balanceOf[to_] += amount_;
        }
        emit Transfer(address(0), to_, amount_);
    }

    function _burn(address from_, uint256 amount_) internal virtual {
        require(from_ != address(0), "ERC20::_burn FROM_ZERO");
        balanceOf[from_] -= amount_;
        unchecked {
            totalSupply -= amount_;
        }
        emit Transfer(from_, address(0), amount_);
    }

    function _transfer(address from_, address to_, uint256 amount_) internal virtual {
        require(from_ != address(0), "ERC20::_transfer FROM_ZERO");
        require(to_ != address(0), "ERC20::_transfer TO_ZERO");
        balanceOf[from_] -= amount_;
        unchecked {
            balanceOf[to_] += amount_;
        }
        emit Transfer(from_, to_, amount_);
    }

    function _spendAllowance(address from_, address operator_, uint256 amount_) internal virtual {
        if (allowance[from_][operator_] != type(uint256).max) {
            allowance[from_][operator_] -= amount_;
        }
    }

    function _approve(address owner_, address spender_, uint256 amount_) internal virtual {
        allowance[owner_][spender_] = amount_;
        emit Approval(owner_, spender_, amount_);
    }

    function approve(address spender_, uint256 amount_) public virtual returns (bool) {
        _approve(msg.sender, spender_, amount_);
        return true;
    }

    function transfer(address to_, uint256 amount_) public virtual returns (bool) {
        _transfer(msg.sender, to_, amount_);
        return true;
    }

    function transferFrom(address from_, address to_, uint256 amount_) public virtual returns (bool) {
        _spendAllowance(from_, msg.sender, amount_);
        _transfer(from_, to_, amount_);
        return true;
    }
}


