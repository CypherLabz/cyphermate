// SPDX-License-Identifier: MIT
// Last update: 2024-02-12
pragma solidity ^0.8.20;

// EIP-20 Compliant -> https://eips.ethereum.org/EIPS/eip-20
abstract contract ERC20 {

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    string public name;
    string public symbol;

    // Override decimals using a function override here
    function decimals() public view virtual returns (uint8) {
        return 18; 
    }

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function _mint(address to_, uint256 amount_) internal virtual {
        require(to_ != address(0), "ERC20: _mint to zero");

        totalSupply += amount_;
        
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked { 
            balanceOf[to_] += amount_; 
        }
        
        emit Transfer(address(0), to_, amount_);
    }

    function _burn(address from_, uint256 amount_) internal virtual {
        require(from_ != address(0), "ERC20: _burn from zero");

        balanceOf[from_] -= amount_;
        
        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount_;
        }
        
        emit Transfer(from_, address(0), amount_);
    }

    function _transfer(address from_, address to_, uint256 amount_) internal virtual {
        require(from_ != address(0), "ERC20: _transfer from_ zero");
        require(to_ != address(0), "ERC20: _transfer to_ zero");

        balanceOf[from_] -= amount_; // underflow-as-require

        // Cannot overflow because the sum of all user 
        // balances can't exceed max uint256 value.
        unchecked { 
            balanceOf[to_] += amount_;
        }

        emit Transfer(from_, to_, amount_);
    }

    function _spendAllowance(address from_, address operator_, uint256 amount_) 
    internal virtual {
        if (allowance[from_][operator_] != type(uint256).max) {
            allowance[from_][operator_] -= amount_; // underflow-as-require
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