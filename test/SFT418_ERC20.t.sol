// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "cyphermate/tokens/SFT418/SFT418.sol";
import { SFT418PairDemo } from "cyphermate/tokens/SFT418/SFT418Pair.sol";

// Solmate testing suite
import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";
import { DSInvariantTest } from "solmate/test/utils/DSInvariantTest.sol";

contract SFT418Test is DSTestPlus {

    SFT418Demo      private token;
    SFT418PairDemo  private p;

    address private a;
    address private b;
    address private c;

    function setUp() public {
        hevm.startPrank(a);

        p = new SFT418PairDemo();
        token = new SFT418Demo("Token", "TKN");

        token.initializeSFT418Pair(address(p));

        a = address(1);
        b = address(2);
        c = address(3);

        token.toggleChunkProcessing();
        hevm.stopPrank();
    }

    function invariantMetadata() public {
        assertEq(token.name(), "Token");
        assertEq(token.symbol(), "TKN");
        assertEq(token.decimals(), 18);
    }

    function testMint() public {
        token.mint(address(0xBEEF), 1e18);

        assertEq(token.totalSupply(), 1e18);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testBurn() public {
        token.mint(address(0xBEEF), 1e18);
        token.burn(address(0xBEEF), 0.9e18);

        assertEq(token.totalSupply(), 1e18 - 0.9e18);
        assertEq(token.balanceOf(address(0xBEEF)), 0.1e18);
    }

    function testApprove() public {
        assertTrue(token.approve(address(0xBEEF), 1e18));
        assertEq(token.allowance(address(this), address(0xBEEF)), 1e18);
    }

    function testTransfer() public {
        token.mint(address(this), 1e18);

        assertTrue(token.transfer(address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        token.mint(from, 1e18);

        hevm.prank(from);
        token.approve(address(this), 1e18);

        assertTrue(token.transferFrom(from, address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.allowance(from, address(this)), 0);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testInfiniteApproveTransferFrom() public {
        address from = address(0xABCD);

        token.mint(from, 1e18);

        hevm.prank(from);
        token.approve(address(this), type(uint256).max);

        assertTrue(token.transferFrom(from, address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.allowance(from, address(this)), type(uint256).max);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testFailTransferInsufficientBalance() public {
        token.mint(address(this), 0.9e18);
        token.transfer(address(0xBEEF), 1e18);
    }

    function testFailTransferFromInsufficientAllowance() public {
        address from = address(0xABCD);

        token.mint(from, 1e18);

        hevm.prank(from);
        token.approve(address(this), 0.9e18);

        token.transferFrom(from, address(0xBEEF), 1e18);
    }

    function testFailTransferFromInsufficientBalance() public {
        address from = address(0xABCD);

        token.mint(from, 0.9e18);

        hevm.prank(from);
        token.approve(address(this), 1e18);

        token.transferFrom(from, address(0xBEEF), 1e18);
    }

    function testMetadata(
        string calldata name,
        string calldata symbol
    ) public {
        SFT418Demo tkn = new SFT418Demo(name, symbol);
        assertEq(tkn.name(), name);
        assertEq(tkn.symbol(), symbol);
        assertEq(tkn.decimals(), 18);
    }

    function testMint(address from, uint256 amount) public {

        token.toggleChunkProcessing();

        // // no address(0) mint and burn
        // if (from == address(0)) {
        //     hevm.expectRevert("SFT418: _mint to zero address");
        // }

        // // mintAmount above MAX_SUPPLY()
        // else if (amount > token.MAX_SUPPLY()) {
        //     hevm.expectRevert("SFT418: _mint exceeds max supply");
        // }

        token.mint(from, amount);

        assertEq(token.totalSupply(), amount);
        assertEq(token.balanceOf(from), amount);
    }

    function testBurn(
        address from,
        uint256 mintAmount,
        uint256 burnAmount
    ) public {
        
        token.toggleChunkProcessing();

        burnAmount = bound(burnAmount, 0, mintAmount);

        // no address(0) mint and burn
        // if (from == address(0)) {
        //     hevm.expectRevert("SFT418: _mint to zero address");
        // }

        // // mintAmount above MAX_SUPPLY()
        // else if (mintAmount > token.MAX_SUPPLY()) {
        //     hevm.expectRevert("SFT418: _mint exceeds max supply");
        // }

        token.mint(from, mintAmount);

        // // rawrz
        // if (from == address(0)) {
        //     hevm.expectRevert("SFT418: _burn from zero address");
        // }

        // else if (burnAmount > mintAmount) {
        //     hevm.expectRevert(stdError.arithmeticError);
        // }
        
        token.burn(from, burnAmount);

        assertEq(token.totalSupply(), mintAmount - burnAmount);
        assertEq(token.balanceOf(from), mintAmount - burnAmount);
    }

    function testApprove(address to, uint256 amount) public {
        assertTrue(token.approve(to, amount));

        assertEq(token.allowance(address(this), to), amount);
    }

    function testTransfer(address from, uint256 amount) public {
        
        token.toggleChunkProcessing();

        // // mintAmount above MAX_SUPPLY()
        // if (amount > token.MAX_SUPPLY()) {
        //     hevm.expectRevert("SFT418: _mint exceeds max supply");
        // }

        token.mint(address(this), amount);

        // // to is not address zero
        // if (from == address(0)) {
        //     hevm.expectRevert("SFT418: _transfer to zero address");
        // }

        assertTrue(token.transfer(from, amount));
        assertEq(token.totalSupply(), amount);

        if (address(this) == from) {
            assertEq(token.balanceOf(address(this)), amount);
        } else {
            assertEq(token.balanceOf(address(this)), 0);
            assertEq(token.balanceOf(from), amount);
        }
    }

    function testTransferFrom(
        address to,
        uint256 approval,
        uint256 amount
    ) public {
        
        token.toggleChunkProcessing();

        amount = bound(amount, 0, approval);

        address from = address(0xABCD);

        // // mintAmount above MAX_SUPPLY()
        // if (amount > token.MAX_SUPPLY()) {
        //     hevm.expectRevert("SFT418: _mint exceeds max supply");
        // }

        token.mint(from, amount);

        hevm.prank(from);
        token.approve(address(this), approval);

        // // to is not address zero
        // if (to == address(0)) {
        //     hevm.expectRevert("SFT418: _transfer to zero address");
        // }

        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.totalSupply(), amount);

        uint256 app = from == address(this) || approval == type(uint256).max ? approval : approval - amount;
        assertEq(token.allowance(from, address(this)), app);

        if (from == to) {
            assertEq(token.balanceOf(from), amount);
        } else {
            assertEq(token.balanceOf(from), 0);
            assertEq(token.balanceOf(to), amount);
        }
    }

    function testFailBurnInsufficientBalance(
        address to,
        uint256 mintAmount,
        uint256 burnAmount
    ) public {
        burnAmount = bound(burnAmount, mintAmount + 1, type(uint256).max);

        token.mint(to, mintAmount);
        token.burn(to, burnAmount);
    }

    function testFailTransferInsufficientBalance(
        address to,
        uint256 mintAmount,
        uint256 sendAmount
    ) public {
        sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);

        token.mint(address(this), mintAmount);
        token.transfer(to, sendAmount);
    }

    function testFailTransferFromInsufficientAllowance(
        address to,
        uint256 approval,
        uint256 amount
    ) public {
        amount = bound(amount, approval + 1, type(uint256).max);

        address from = address(0xABCD);

        token.mint(from, amount);

        hevm.prank(from);
        token.approve(address(this), approval);

        token.transferFrom(from, to, amount);
    }

    function testFailTransferFromInsufficientBalance(
        address to,
        uint256 mintAmount,
        uint256 sendAmount
    ) public {
        sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);

        address from = address(0xABCD);

        token.mint(from, mintAmount);

        hevm.prank(from);
        token.approve(address(this), sendAmount);

        token.transferFrom(from, to, sendAmount);
    }
}

contract ERC20Invariants is DSTestPlus, DSInvariantTest {
    BalanceSum balanceSum;
    SFT418Demo token;

    function setUp() public {
        token = new SFT418Demo("Token", "TKN");
        balanceSum = new BalanceSum(token);

        addTargetContract(address(balanceSum));
    }

    function invariantBalanceSum() public {
        assertEq(token.totalSupply(), balanceSum.sum());
    }
}

contract BalanceSum {
    SFT418Demo token;
    uint256 public sum;

    constructor(SFT418Demo _token) {
        token = _token;
    }

    function mint(address from, uint256 amount) public {
        token.mint(from, amount);
        sum += amount;
    }

    function burn(address from, uint256 amount) public {
        token.burn(from, amount);
        sum -= amount;
    }

    function approve(address to, uint256 amount) public {
        token.approve(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public {
        token.transferFrom(from, to, amount);
    }

    function transfer(address to, uint256 amount) public {
        token.transfer(to, amount);
    }
}