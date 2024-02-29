// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "cyphermate/tokens/SFT418/SFT418.sol";
import { SFT418PairDemo } from "cyphermate/tokens/SFT418/SFT418Pair.sol";

contract ForgeRemaps is Test {

    function login(address user) internal {
        vm.startPrank(user);
    }

    function logout() internal {
        vm.stopPrank();
    }

    modifier lin(address user) {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    } 
}

// contract SFT418Test is ForgeRemaps {

//     SFT418Demo      private t;
//     SFT418PairDemo  private p;

//     address private a;
//     address private b;
//     address private c;

//     function setUp() public lin(a) {
//         p = new SFT418PairDemo();
//         t = new SFT418Demo("Token", "TKN");

//         t.initializeSFT418Pair(address(p));

//         a = address(1);
//         b = address(2);
//         c = address(3);

//         t.toggleChunkProcessing();
//         t.mint(a, 1000 ether); 
//     }

//     function testTokenMetadata() public {
//         assertEq(t.name(), "Token", "Incorrect token name");
//         assertEq(t.symbol(), "TKN", "Incorrect token symbol");
//         assertEq(t.decimals(), 18, "Incorrect number of decimals");
//     }

//     function testTotalSupply() public {
//         assertEq(t.totalSupply(), 1000 ether, "Total supply should match initial supply");
//     }

//     function testBalanceOfZeroTokens() public {
//         assertEq(t.balanceOf(c), 0, "Charlie's balance should initially be 0");
//         assertEq(t.balanceOf(b), 0, "Charlie's balance should initially be 0");
//     }

//     function testBalanceOfSomeTokens() public {
//         assertEq(t.balanceOf(a), 1000 ether, "Alice's balance should match the minted amount");
//     }

//     function testTransfer() public lin(a) {

//         uint256 _bal = t.balanceOf(a);

//         assertTrue(t.transfer(b, 100 ether), "1");
//         assertEq(t.balanceOf(a), _bal - 100 ether, "2");
//         assertEq(t.balanceOf(b), 100 ether, "3");

//         vm.expectRevert(stdError.arithmeticError);
//         t.transfer(b, 1000 ether); 

//         assertTrue(t.transfer(c, 0), "4");
//         assertEq(t.balanceOf(c), 0, "5");

//         vm.expectRevert();
//         t.transfer(address(0), 100 ether);
//     }    

//     function testApprove() public lin(a) {

//         assertTrue(t.approve(b, 200 ether), "1");
//         assertEq(t.allowance(a, b), 200 ether, "2");

//         assertTrue(t.approve(b, 300 ether), "3");
//         assertEq(t.allowance(a, b), 300 ether, "4");

//         login(b);

//         assertTrue(t.transferFrom(a, b, 100 ether), "5");
//         assertEq(t.allowance(a, b), 200 ether, "6");
//     }

//     function testTransferFrom() public lin(a) {

//         assertTrue(t.approve(b, 200 ether), "1");

//         login(b);

//         uint256 _bal = t.balanceOf(a);

//         assertTrue(t.transferFrom(a, c, 200 ether), "2");
//         assertEq(t.balanceOf(a), _bal - 200 ether, "3");
//         assertEq(t.balanceOf(c), 200 ether, "4");
//         assertEq(t.allowance(a, b), 0, "5");

//         vm.expectRevert(stdError.arithmeticError);
//         t.transferFrom(a, c, 1 ether);

//         logout();
//         login(a);

//         _bal = t.balanceOf(a); // refresh balance

//         vm.expectRevert(stdError.arithmeticError);
//         t.transferFrom(a, b, _bal + 1);

//         assertTrue(t.approve(a, 100 ether), "8");

//         vm.expectRevert();
//         t.transferFrom(a, address(0), 100 ether);

//         vm.expectRevert();
//         t.transferFrom(address(0), b, 100 ether);

//         assertTrue(t.transferFrom(a, a, 100 ether), "11");
//         assertEq(t.allowance(a, a), 0, "12");
//     }

//     function testMint() public lin(a) {
//         uint256 ts = t.totalSupply();

//         t.mint(b, 100 ether);

//         assertEq(t.totalSupply(), ts + 100 ether, "1");
//         assertEq(t.balanceOf(b), 100 ether, "2");

//         vm.expectRevert();
//         t.mint(address(0), 100 ether);
//     }

//     function testBurn() public lin(a) {

//         uint256 bal = t.balanceOf(a);
//         uint256 ts = t.totalSupply();

//         t.burn(a, 100 ether);
//         assertEq(t.totalSupply(), ts - 100 ether, "1");
//         assertEq(t.balanceOf(a), bal - 100 ether, "2");

//         uint256 bal2 = t.balanceOf(a);

//         vm.expectRevert(stdError.arithmeticError);
//         t.burn(a, bal2 + 1);

//         vm.expectRevert();
//         t.burn(address(0), 100 ether);
//     }

//     // ERC721
//     function testpMinting() lin(a) public {
//         p.mint(a, 1);
//         assertEq(p.ownerOf(1), a, "Owner should be address a after minting");
//     }

//     function testpTransfer() public lin(a) {
//         p.mint(a, 1);
//         p.transferFrom(a, b, 2);
//         assertEq(p.ownerOf(2), b, "Owner should be address b after transfer");
//     }

//     function testpApproval() public lin(a) {
//         p.mint(a, 1);
//         p.approve(b, 3);
//         assertEq(p.getApproved(3), b, "Address b should be approved for tokenId");
//         assertEq(p.getApproved(2), address(0), "2");
//     }

//     function testpTransferFromApproved() public lin(a) {
//         p.mint(a, 1);
//         p.approve(b, 4);

//         logout(); 
//         login(b);

//         p.transferFrom(a, c, 4);
//         assertEq(p.ownerOf(4), c, "Owner should be address c after transfer");
//     }

//     function testpBalanceUpdates() public lin(a) {
//         uint256 bala = p.balanceOf(a);

//         p.mint(a, 2);
//         assertEq(p.balanceOf(a), bala + 2, "Balance of a should be 2");

//         uint256 bala2 = p.balanceOf(a);
//         uint256 balb2 = p.balanceOf(b);
        
//         p.transferFrom(a, b, 5);
        
//         assertEq(p.balanceOf(a), bala2 - 1, "Balance of a should be 1 after transfer");
//         assertEq(p.balanceOf(b), balb2 + 1, "Balance of b should be 1 after receiving token");
//     }

//     function testpNonexistentToken() public {
//         vm.expectRevert();
//         p.ownerOf(99999);
//     }

//     function testpUnauthorizedTransfers() public lin(c) {
//         vm.expectRevert();
//         p.transferFrom(a, c, 1);
//     }
// }