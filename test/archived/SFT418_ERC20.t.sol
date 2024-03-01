// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import "cyphermate/tokens/SFT418/SFT418.sol";
// import { SFT418PairDemo } from "cyphermate/tokens/SFT418/SFT418Pair.sol";

// contract ForgeRemaps is Test {

//     function login(address user) internal {
//         vm.startPrank(user);
//     }

//     function logout() internal {
//         vm.stopPrank();
//     }

//     modifier lin(address user) {
//         vm.startPrank(user);
//         _;
//         vm.stopPrank();
//     } 
// }

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
//     }

//     // Solmate ERC20 Test Script (Without Permit20)

//     function invariantMetadata() public {
//         assertEq(t.name(), "Token");
//         assertEq(t.symbol(), "TKN");
//         assertEq(t.decimals(), 18);
//     }

//     function testMint() public {
//         t.mint(address(0xBEEF), 1e18);

//         assertEq(t.totalSupply(), 1e18);
//         assertEq(t.balanceOf(address(0xBEEF)), 1e18);
//     }

//     function testBurn() public {
//         t.mint(address(0xBEEF), 1e18);
//         t.burn(address(0xBEEF), 0.9e18);

//         assertEq(t.totalSupply(), 1e18 - 0.9e18);
//         assertEq(t.balanceOf(address(0xBEEF)), 0.1e18);
//     }

//     function testApprove() public {
//         assertTrue(t.approve(address(0xBEEF), 1e18));

//         assertEq(t.allowance(address(this), address(0xBEEF)), 1e18);
//     }

//     function testTransfer() public {
//         t.mint(address(this), 1e18);

//         assertTrue(t.transfer(address(0xBEEF), 1e18));
//         assertEq(t.totalSupply(), 1e18);

//         assertEq(t.balanceOf(address(this)), 0);
//         assertEq(t.balanceOf(address(0xBEEF)), 1e18);
//     }

//     function testTransferFrom() public {
//         address from = address(0xABCD);

//         t.mint(from, 1e18);

//         login(from);
        
//         t.approve(address(this), 1e18);

//         assertTrue(t.transferFrom(from, address(0xBEEF), 1e18));
//         assertEq(t.totalSupply(), 1e18);

//         assertEq(t.allowance(from, address(this)), 0);

//         assertEq(t.balanceOf(from), 0);
//         assertEq(t.balanceOf(address(0xBEEF)), 1e18);
//     }

//     function testInfiniteApproveTransferFrom() public {
//         address from = address(0xABCD);

//         t.mint(from, 1e18);

//         login(from);

//         t.approve(address(this), type(uint256).max);

//         console.log(t.balanceOf(from));
        
//         assertTrue(t.transferFrom(from, address(0xBEEF), 1e18));
//         // assertEq(t.totalSupply(), 1e18);

//         // assertEq(t.allowance(from, address(this)), type(uint256).max);

//         // assertEq(t.balanceOf(from), 0);
//         // assertEq(t.balanceOf(address(0xBEEF)), 1e18);
//     }

//     function testFailTransferInsufficientBalance() public {
//         t.mint(address(this), 0.9e18);
//         t.transfer(address(0xBEEF), 1e18);
//     }

//     function testFailTransferFromInsufficientAllowance() public {
//         address from = address(0xABCD);

//         t.mint(from, 1e18);

//         login(from);
//         t.approve(address(this), 0.9e18);

//         t.transferFrom(from, address(0xBEEF), 1e18);
//     }

//     function testFailTransferFromInsufficientBalance() public {
//         address from = address(0xABCD);

//         t.mint(from, 0.9e18);

//         login(from);
//         t.approve(address(this), 1e18);

//         t.transferFrom(from, address(0xBEEF), 1e18);
//     }

//     function testMetadata(
//         string calldata name,
//         string calldata symbol,
//         uint8 decimals
//     ) public {
//         SFT418Demo tkn = new SFT418Demo(name, symbol);
//         assertEq(tkn.name(), name);
//         assertEq(tkn.symbol(), symbol);
//         assertEq(tkn.decimals(), decimals);
//     }

//     function testMint(address from, uint256 amount) public {
//         t.mint(from, amount);

//         assertEq(t.totalSupply(), amount);
//         assertEq(t.balanceOf(from), amount);
//     }

//     // function testBurn(
//     //     address from,
//     //     uint256 mintAmount,
//     //     uint256 burnAmount
//     // ) public {
//     //     burnAmount = bound(burnAmount, 0, mintAmount);

//     //     t.mint(from, mintAmount);
//     //     t.burn(from, burnAmount);

//     //     assertEq(t.totalSupply(), mintAmount - burnAmount);
//     //     assertEq(t.balanceOf(from), mintAmount - burnAmount);
//     // }

//     function testApprove(address to, uint256 amount) public {
//         assertTrue(t.approve(to, amount));

//         assertEq(t.allowance(address(this), to), amount);
//     }

//     function testTransfer(address from, uint256 amount) public {
//         t.mint(address(this), amount);

//         assertTrue(t.transfer(from, amount));
//         assertEq(t.totalSupply(), amount);

//         if (address(this) == from) {
//             assertEq(t.balanceOf(address(this)), amount);
//         } else {
//             assertEq(t.balanceOf(address(this)), 0);
//             assertEq(t.balanceOf(from), amount);
//         }
//     }

//     function testTransferFrom(
//         address to,
//         uint256 approval,
//         uint256 amount
//     ) public {
//         amount = bound(amount, 0, approval);

//         address from = address(0xABCD);

//         t.mint(from, amount);

//         login(from);
//         t.approve(address(this), approval);

//         assertTrue(t.transferFrom(from, to, amount));
//         assertEq(t.totalSupply(), amount);

//         uint256 app = from == address(this) || approval == type(uint256).max ? approval : approval - amount;
//         assertEq(t.allowance(from, address(this)), app);

//         if (from == to) {
//             assertEq(t.balanceOf(from), amount);
//         } else {
//             assertEq(t.balanceOf(from), 0);
//             assertEq(t.balanceOf(to), amount);
//         }
//     }

//     function testFailBurnInsufficientBalance(
//         address to,
//         uint256 mintAmount,
//         uint256 burnAmount
//     ) public {
//         burnAmount = bound(burnAmount, mintAmount + 1, type(uint256).max);

//         t.mint(to, mintAmount);
//         t.burn(to, burnAmount);
//     }

//     function testFailTransferInsufficientBalance(
//         address to,
//         uint256 mintAmount,
//         uint256 sendAmount
//     ) public {
//         sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);

//         t.mint(address(this), mintAmount);
//         t.transfer(to, sendAmount);
//     }

//     function testFailTransferFromInsufficientAllowance(
//         address to,
//         uint256 approval,
//         uint256 amount
//     ) public {
//         amount = bound(amount, approval + 1, type(uint256).max);

//         address from = address(0xABCD);

//         t.mint(from, amount);

//         login(from);
//         t.approve(address(this), approval);

//         t.transferFrom(from, to, amount);
//     }

//     function testFailTransferFromInsufficientBalance(
//         address to,
//         uint256 mintAmount,
//         uint256 sendAmount
//     ) public {
//         sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);

//         address from = address(0xABCD);

//         t.mint(from, mintAmount);

//         login(from);
//         t.approve(address(this), sendAmount);

//         t.transferFrom(from, to, sendAmount);
//     }
// }