// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/tokens/ERC404/ERC404.sol";
import "../src/tokens/ERC404/SFT418Primary.sol";

contract ERC404Test is Test {
    MockERC404 private token;
    address private constant ZERO_ADDRESS = address(0);
    address private alice;
    address private bob;
    address private charlie;
    uint private constant INITIAL_SUPPLY = 1000 * 10 ** 18;

    function setUp() public {
        token = new MockERC404("Token", "TKN");
        alice = address(1);
        bob = address(2);
        charlie = address(3);
        token.mint(alice, 1000 * 10 ** 18); // Give Alice some tokens for testing
    }

    function testTokenMetadata() public {
        assertEq(token.name(), "Token", "Incorrect token name");
        assertEq(token.symbol(), "TKN", "Incorrect token symbol");
        assertEq(token.decimals(), 18, "Incorrect number of decimals");
    }

    function testTotalSupply() public {
        assertEq(token.totalSupply(), INITIAL_SUPPLY, "Total supply should match initial supply");
    }

    function testBalanceOfZeroTokens() public {
        assertEq(token.balanceOf(charlie), 0, "Charlie's balance should initially be 0");
    }

    function testBalanceOfSomeTokens() public {
        assertEq(token.balanceOf(alice), 1000 * 10 ** 18, "Alice's balance should match the minted amount");
    }

    function testTransfer() public {
        vm.startPrank(alice);

        uint256 _bal = token.balanceOf(alice);

        assertTrue(token.transfer(bob, 100 * 10 ** 18), "Transfer of 100 tokens should succeed");
        assertEq(token.balanceOf(alice), _bal - 100 * 10 ** 18, "Alice should have 400 tokens after transfer");
        assertEq(token.balanceOf(bob), 100 * 10 ** 18, "Bob should have 100 tokens after transfer");

        vm.expectRevert(stdError.arithmeticError);
        token.transfer(bob, 1000 * 10 ** 18); 

        assertTrue(token.transfer(charlie, 0), "Transfer of 0 tokens should succeed");
        assertEq(token.balanceOf(charlie), 0, "Charlie's balance should remain 0 after transferring 0 tokens");

        vm.expectRevert("ERC404: _transfer to zero address");
        token.transfer(ZERO_ADDRESS, 100 * 10 ** 18);

        vm.stopPrank();
    }

    function testApprove() public {
        vm.startPrank(alice);

        assertTrue(token.approve(bob, 200 * 10 ** 18), "Approval of 200 tokens should succeed");
        assertEq(token.allowance(alice, bob), 200 * 10 ** 18, "Bob's allowance from Alice should be 200");

        assertTrue(token.approve(bob, 300 * 10 ** 18), "Approval of 300 tokens should succeed");
        assertEq(token.allowance(alice, bob), 300 * 10 ** 18, "Bob's allowance from Alice should be updated to 300");

        // vm.expectRevert("Should revert due to approving zero address");
        // token.approve(ZERO_ADDRESS, 100);

        assertTrue(token.approve(bob, 1000 * 10 ** 18), "Approval of 1000 tokens should succeed even if it exceeds balance");
        assertEq(token.allowance(alice, bob), 1000 * 10 ** 18, "Bob's allowance from Alice should be 1000");

        vm.stopPrank();
    }

    function testTransferFrom() public {
        vm.startPrank(alice);

        token.approve(bob, 200 * 10 ** 18);

        vm.stopPrank();

        vm.startPrank(bob);

        uint256 _bal = token.balanceOf(alice);

        assertTrue(token.transferFrom(alice, charlie, 200 * 10 ** 18), "TransferFrom of 200 tokens should succeed");
        assertEq(token.balanceOf(alice), _bal - 200 * 10 ** 18, "Alice's balance should be reduced by 200");
        assertEq(token.balanceOf(charlie), 200 * 10 ** 18, "Charlie's balance should increase by 200");
        assertEq(token.allowance(alice, bob), 0, "Bob's allowance from Alice should be reduced to zero");

        vm.expectRevert(stdError.arithmeticError);
        token.transferFrom(alice, charlie, 1 * 10 ** 18);

        vm.stopPrank();

        vm.startPrank(alice);

        vm.expectRevert(stdError.arithmeticError);
        token.transferFrom(alice, bob, 501 * 10 ** 18);

        token.approve(alice, 100 ether);

        vm.expectRevert("ERC404: _transfer to zero address");
        token.transferFrom(alice, ZERO_ADDRESS, 100 * 10 ** 18);

        vm.expectRevert(stdError.arithmeticError);
        token.transferFrom(ZERO_ADDRESS, bob, 100 * 10 ** 18);

        vm.stopPrank();
    }

    function testMint() public {
        uint256 _totalSupply = token.totalSupply();

        token.mint(bob, 100 * 10 ** 18);
        assertEq(token.totalSupply(), _totalSupply + 100 * 10 ** 18, "Total supply should be increased by 100");
        assertEq(token.balanceOf(bob), 100 * 10 ** 18, "Bob's balance should be increased by 100 after mint");

        // vm.expectRevert("Should revert due to minting to zero address");
        // token.mint(ZERO_ADDRESS, 100);
    }

    function testBurn() public {
        uint256 _bal = token.balanceOf(alice);
        uint256 _totalSupply = token.totalSupply();

        token.burn(alice, 100 * 10 ** 18);        
        assertEq(token.totalSupply(), _totalSupply - 100 * 10 ** 18, "Total supply should be reduced by 100");
        assertEq(token.balanceOf(alice), _bal - 100 * 10 ** 18, "Alice's balance should be reduced by 100 after burn");

        uint256 _bal2 = token.balanceOf(alice);
        uint256 _totalSupply2 = token.totalSupply();

        token.burn(alice, 900 * 10 ** 18);
        assertEq(token.totalSupply(), _totalSupply2 - 900 * 10 ** 18, "Total supply should be reduced by 500");
        assertEq(token.balanceOf(alice), _bal2 - 900 * 10 ** 18, "Alice's balance should be zero after burning all tokens");

        // vm.expectRevert("Should revert due to burning from zero address");
        // token.burn(ZERO_ADDRESS, 100);

        // console.log(token.balanceOf(alice));

        vm.expectRevert(stdError.arithmeticError);
        token.burn(alice, 1 * 10 ** 18); // Alice has no tokens left
    }
}
