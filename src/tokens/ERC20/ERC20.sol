// SPDX-License-Identifier: MIT
// Last update: 2024-01-22

// EIP-20 Compliant -> https://eips.ethereum.org/EIPS/eip-20
abstract contract ERC20 {

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    string public name;
    string public symbol;
    uint8 public immutable decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function _mint(address to_, uint256 amount_) internal virtual {
        totalSupply += amount_;
        
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked { 
            balanceOf[to_] += amount_; 
        }
        
        emit Transfer(address(0), to_, amount_);
    }

    function _burn(address from_, uint256 amount_) internal virtual {
        balanceOf[from_] -= amount_;
        
        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount_;
        }
        
        emit Transfer(from_, address(0), amount_);
    }
    
    function approve(address spender_, uint256 amount_) public virtual returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    function transfer(address to_, uint256 amount_) public virtual returns (bool) {
        require(to_ != address(0), "ERC20: TRANSFER_NOT_BURN");

        balanceOf[msg.sender] -= amount_; // underflow-as-require
        
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to_] += amount_;
        }

        emit Transfer(msg.sender, to_, amount_);
        return true;
    }

    function transferFrom(address from_, address to_, uint256 amount_) public virtual returns (bool) {
        require(from_ != address(0), "ERC20: TRANSFERFROM_NOT_MINT");
        require(to_ != address(0), "ERC20: TRANSFERFROM_NOT_BURN");
        
        allowance[from_][msg.sender] -= amount_; // underflow-as-require
        balanceOf[from_] -= amount_; // underflow-as-require
        
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to_] += amount_;
        }

        emit Transfer(from_, to_, amount_);
        return true;
    }
}