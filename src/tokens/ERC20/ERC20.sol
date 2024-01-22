// SPDX-License-Identifier: MIT
// Last update: 2024-01-22

// EIP-20 Compliant -> https://eips.ethereum.org/EIPS/eip-20
// Unaudited: Needs audit!
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
        balanceOf[to_] += amount_;
        emit Transfer(address(0), to_, amount_);
    }

    function _burn(address from_, uint256 amount_) internal virtual {
        totalSupply -= amount_;
        balanceOf[from_] -= amount_;
        emit Transfer(from_, address(0), amount_);
    }
    
    function approve(address spender_, uint256 amount_) public virtual returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    function transfer(address to_, uint256 amount_) public virtual returns (bool) {
        require(to_ != address(0), "ERC20: TRANSFER_NOT_BURN");
        balanceOf[msg.sender] -= amount_; // uses built-in solidity underflow protection
        balanceOf[to_] += amount_;
        emit Transfer(msg.sender, to_, amount_);
        return true;
    }

    function transferFrom(address from_, address to_, uint256 amount_) public virtual returns (bool) {
        require(from_ != address(0), "ERC20: TRANSFERFROM_NOT_MINT");
        require(to_ != address(0), "ERC20: TRANSFERFROM_NOT_BURN");
        allowance[from_][to_] -= amount_; // uses built-in solidity underflow protection
        balanceOf[from_] -= amount_; // uses built-in solidity underflow protection
        balanceOf[to_] += amount_;
        emit Transfer(from_, to_, amount_);
        return true;
    }
}