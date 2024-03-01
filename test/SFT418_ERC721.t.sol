// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "cyphermate/tokens/SFT418/SFT418.sol";
import { SFT418PairDemo } from "cyphermate/tokens/SFT418/SFT418Pair.sol";

// Solmate testing suite
import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";
import { DSInvariantTest } from "solmate/test/utils/DSInvariantTest.sol";


abstract contract ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

contract ERC721Recipient is ERC721TokenReceiver {
    address public operator;
    address public from;
    uint256 public id;
    bytes public data;

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _id,
        bytes calldata _data
    ) public virtual override returns (bytes4) {
        operator = _operator;
        from = _from;
        id = _id;
        data = _data;

        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

contract RevertingERC721Recipient is ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        revert(string(abi.encodePacked(ERC721TokenReceiver.onERC721Received.selector)));
    }
}

contract WrongReturnDataERC721Recipient is ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        return 0xCAFEBEEF;
    }
}

contract NonERC721Recipient {}

contract SFT418TestERC721 is DSTestPlus {

    SFT418Demo      private token;
    SFT418PairDemo  private pToken;

    address private a;
    address private b;
    address private c;

    function setUp() public {
        // hevm.startPrank(a);

        pToken = new SFT418PairDemo();
        token = new SFT418Demo("Token", "TKN");

        token.initializeSFT418Pair(address(pToken));

        a = address(1);
        b = address(2);
        c = address(3);

        token.toggleChunkProcessing();
        // hevm.stopPrank();
    }

    function invariantMetadata() public {
        assertEq(pToken.name(), "Token");
        assertEq(pToken.symbol(), "TKN");
    }

    function testMint() public {
        pToken.mint(address(0xBEEF), 1337);

        assertEq(pToken.balanceOf(address(0xBEEF)), 1337);
        assertEq(pToken.ownerOf(1337), address(0xBEEF));
    }

    function testBurn() public {
        pToken.mint(address(0xBEEF), 1337);
        
        // console.log(pToken.ownerOf(1337));

        pToken.burn(1337);

        assertEq(pToken.balanceOf(address(0xBEEF)), 1336);

        hevm.expectRevert("SFT418: _NFT_ownerOf nonexistent token");
        pToken.ownerOf(1337);
    }

    function testApprove() public {

        pToken.mint(address(this), 1337);

        // console.log(msg.sender);
        // console.log(address(this));

        pToken.approve(address(0xBEEF), 1337);

        assertEq(pToken.getApproved(1337), address(0xBEEF));
    }

    function testApproveBurn() public {
        pToken.mint(address(this), 1337);

        pToken.approve(address(0xBEEF), 1337);

        pToken.burn(1337);

        assertEq(pToken.balanceOf(address(this)), 1336);
        assertEq(pToken.getApproved(1337), address(0));

        hevm.expectRevert("SFT418: _NFT_ownerOf nonexistent token");
        pToken.ownerOf(1337);
    }

    function testApproveAll() public {
        pToken.setApprovalForAll(address(0xBEEF), true);
        assertTrue(pToken.isApprovedForAll(address(this), address(0xBEEF)));
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        pToken.mint(from, 1337);

        hevm.prank(from);
        pToken.approve(address(this), 1337);

        pToken.transferFrom(from, address(0xBEEF), 1337);

        assertEq(pToken.getApproved(1337), address(0));
        assertEq(pToken.ownerOf(1337), address(0xBEEF));
        assertEq(pToken.balanceOf(address(0xBEEF)), 1);
        assertEq(pToken.balanceOf(from), 1336);
    }

    function testTransferFromSelf() public {
        pToken.mint(address(this), 1337);

        pToken.transferFrom(address(this), address(0xBEEF), 1337);

        assertEq(pToken.getApproved(1337), address(0));
        assertEq(pToken.ownerOf(1337), address(0xBEEF));
        assertEq(pToken.balanceOf(address(0xBEEF)), 1);
        assertEq(pToken.balanceOf(address(this)), 1336);
    }

    function testTransferFromApproveAll() public {
        address from = address(0xABCD);

        pToken.mint(from, 1337);

        hevm.prank(from);
        pToken.setApprovalForAll(address(this), true);

        pToken.transferFrom(from, address(0xBEEF), 1337);

        assertEq(pToken.getApproved(1337), address(0));
        assertEq(pToken.ownerOf(1337), address(0xBEEF));
        assertEq(pToken.balanceOf(address(0xBEEF)), 1);
        assertEq(pToken.balanceOf(from), 1336);
    }

    function testSafeTransferFromToEOA() public {
        address from = address(0xABCD);

        pToken.mint(from, 1337);

        hevm.prank(from);
        pToken.setApprovalForAll(address(this), true);

        pToken.safeTransferFrom(from, address(0xBEEF), 1337);

        assertEq(pToken.getApproved(1337), address(0));
        assertEq(pToken.ownerOf(1337), address(0xBEEF));
        assertEq(pToken.balanceOf(address(0xBEEF)), 1);
        assertEq(pToken.balanceOf(from), 1336);
    }

    function testSafeTransferFromToERC721Recipient() public {
        address from = address(0xABCD);
        ERC721Recipient recipient = new ERC721Recipient();

        pToken.mint(from, 1337);

        hevm.prank(from);
        pToken.setApprovalForAll(address(this), true);

        pToken.safeTransferFrom(from, address(recipient), 1337);

        assertEq(pToken.getApproved(1337), address(0));
        assertEq(pToken.ownerOf(1337), address(recipient));
        assertEq(pToken.balanceOf(address(recipient)), 1);
        assertEq(pToken.balanceOf(from), 1336);

        
        // console.log(address(this));
        // console.log(msg.sender);
        // console.log(recipient.operator());

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), from);
        assertEq(recipient.id(), 1337);
        assertBytesEq(recipient.data(), "");
    }

    function testSafeTransferFromToERC721RecipientWithData() public {
        address from = address(0xABCD);
        ERC721Recipient recipient = new ERC721Recipient();

        pToken.mint(from, 1337);

        hevm.prank(from);
        pToken.setApprovalForAll(address(this), true);

        pToken.safeTransferFrom(from, address(recipient), 1337, "testing 123");

        assertEq(pToken.getApproved(1337), address(0));
        assertEq(pToken.ownerOf(1337), address(recipient));
        assertEq(pToken.balanceOf(address(recipient)), 1);
        assertEq(pToken.balanceOf(from), 1336);

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), from);
        assertEq(recipient.id(), 1337);
        assertBytesEq(recipient.data(), "testing 123");
    }

    function testSafeMintToEOA() public {
        pToken.safeMint(address(0xBEEF), 1337);

        assertEq(pToken.ownerOf(1337), address(address(0xBEEF)));
        assertEq(pToken.balanceOf(address(address(0xBEEF))), 1337);
    }

    function testSafeMintToERC721Recipient() public {
        ERC721Recipient to = new ERC721Recipient();

        pToken.safeMint(address(to), 1337);

        // console.log(pToken.balanceOf(address(to)));

        assertEq(pToken.ownerOf(1337), address(to));
        assertEq(pToken.balanceOf(address(to)), 1337);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1337);
        assertBytesEq(to.data(), "");
    }

    function testSafeMintToERC721RecipientWithData() public {
        ERC721Recipient to = new ERC721Recipient();

        pToken.safeMint(address(to), 1337, "testing 123");

        assertEq(pToken.ownerOf(1337), address(to));
        assertEq(pToken.balanceOf(address(to)), 1337);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1337);
        assertBytesEq(to.data(), "testing 123");
    }

    function testFailMintToZero() public {
        pToken.mint(address(0), 1337);
    }

    function testFailBurnUnMinted() public {
        pToken.burn(1337);
    }

    function testFailDoubleBurn() public {
        pToken.mint(address(0xBEEF), 1337);

        pToken.burn(1337);
        pToken.burn(1337);
    }

    function testFailApproveUnMinted() public {
        pToken.approve(address(0xBEEF), 1337);
    }

    function testFailApproveUnAuthorized() public {
        pToken.mint(address(0xCAFE), 1337);

        pToken.approve(address(0xBEEF), 1337);
    }

    function testFailTransferFromUnOwned() public {
        pToken.transferFrom(address(0xFEED), address(0xBEEF), 1337);
    }

    function testFailTransferFromWrongFrom() public {
        pToken.mint(address(0xCAFE), 1337);

        pToken.transferFrom(address(0xFEED), address(0xBEEF), 1337);
    }

    function testFailTransferFromToZero() public {
        pToken.mint(address(this), 1337);

        pToken.transferFrom(address(this), address(0), 1337);
    }

    function testFailTransferFromNotOwner() public {
        pToken.mint(address(0xFEED), 1337);

        pToken.transferFrom(address(0xFEED), address(0xBEEF), 1337);
    }

    function testFailSafeTransferFromToNonERC721Recipient() public {
        pToken.mint(address(this), 1337);

        pToken.safeTransferFrom(address(this), address(new NonERC721Recipient()), 1337);
    }

    function testFailSafeTransferFromToNonERC721RecipientWithData() public {
        pToken.mint(address(this), 1337);

        pToken.safeTransferFrom(address(this), address(new NonERC721Recipient()), 1337, "testing 123");
    }

    function testFailSafeTransferFromToRevertingERC721Recipient() public {
        pToken.mint(address(this), 1337);

        pToken.safeTransferFrom(address(this), address(new RevertingERC721Recipient()), 1337);
    }

    function testFailSafeTransferFromToRevertingERC721RecipientWithData() public {
        pToken.mint(address(this), 1337);

        pToken.safeTransferFrom(address(this), address(new RevertingERC721Recipient()), 1337, "testing 123");
    }

    function testFailSafeTransferFromToERC721RecipientWithWrongReturnData() public {
        pToken.mint(address(this), 1337);

        pToken.safeTransferFrom(address(this), address(new WrongReturnDataERC721Recipient()), 1337);
    }

    function testFailSafeTransferFromToERC721RecipientWithWrongReturnDataWithData() public {
        pToken.mint(address(this), 1337);

        pToken.safeTransferFrom(address(this), address(new WrongReturnDataERC721Recipient()), 1337, "testing 123");
    }

    function testFailSafeMintToNonERC721Recipient() public {
        pToken.safeMint(address(new NonERC721Recipient()), 1337);
    }

    function testFailSafeMintToNonERC721RecipientWithData() public {
        pToken.safeMint(address(new NonERC721Recipient()), 1337, "testing 123");
    }

    function testFailSafeMintToRevertingERC721Recipient() public {
        pToken.safeMint(address(new RevertingERC721Recipient()), 1337);
    }

    function testFailSafeMintToRevertingERC721RecipientWithData() public {
        pToken.safeMint(address(new RevertingERC721Recipient()), 1337, "testing 123");
    }

    function testFailSafeMintToERC721RecipientWithWrongReturnData() public {
        pToken.safeMint(address(new WrongReturnDataERC721Recipient()), 1337);
    }

    function testFailSafeMintToERC721RecipientWithWrongReturnDataWithData() public {
        pToken.safeMint(address(new WrongReturnDataERC721Recipient()), 1337, "testing 123");
    }

    function testFailBalanceOfZeroAddress() public view {
        pToken.balanceOf(address(0));
    }

    function testFailOwnerOfUnminted() public view {
        pToken.ownerOf(1337);
    }

    function testMetadata(string memory name, string memory symbol) public {
        SFT418Demo tkn = new SFT418Demo(name, symbol);

        assertEq(tkn.name(), name);
        assertEq(tkn.symbol(), symbol);
    }

    function testMint(address to, uint256 id) public {
        if (to == address(0)) to = address(0xBEEF);
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        pToken.mint(to, id);

        assertEq(pToken.balanceOf(to), id);
        assertEq(pToken.ownerOf(id), to);
    }

    function testBurn(address to, uint256 id) public {
        if (to == address(0)) to = address(0xBEEF);
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        pToken.mint(to, id);
        
        for (uint256 i = 1; i <= id;) {
            pToken.burn(i++);
        }

        assertEq(pToken.balanceOf(to), 0);

        // idk why this doesnt work when it obviously should. it reverts but theres an error message in the test
        hevm.expectRevert("SFT418: _NFT_ownerOf nonexistent token");
        pToken.ownerOf(id);
    }

    function testApprove(address to, uint256 id) public {
        if (to == address(0)) to = address(0xBEEF);
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        pToken.mint(address(this), id);

        pToken.approve(to, id);

        assertEq(pToken.getApproved(id), to);
    }

    function testApproveBurn(address to, uint256 id) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;
        
        pToken.mint(address(this), id);

        pToken.approve(address(to), id);

        for (uint256 i = 1; i <= id;) {
            pToken.burn(i++);
        }

        assertEq(pToken.balanceOf(address(this)), 0);
        assertEq(pToken.getApproved(id), address(0));

        hevm.expectRevert("SFT418: _NFT_ownerOf nonexistent token");
        pToken.ownerOf(id);
    }

    function testApproveAll(address to, bool approved) public {
        pToken.setApprovalForAll(to, approved);

        assertBoolEq(pToken.isApprovedForAll(address(this), to), approved);
    }

    function testTransferFrom(uint256 id, address to) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;
        
        address from = address(0xABCD);

        if (to == address(0) || to == from) to = address(0xBEEF);

        pToken.mint(from, id);

        hevm.prank(from);
        pToken.approve(address(this), id);

        pToken.transferFrom(from, to, id);

        assertEq(pToken.getApproved(id), address(0));
        assertEq(pToken.ownerOf(id), to);
        assertEq(pToken.balanceOf(to), 1);
        assertEq(pToken.balanceOf(from), id - 1);
    }

    function testTransferFromSelf(uint256 id, address to) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;
        
        if (to == address(0) || to == address(this)) to = address(0xBEEF);

        pToken.mint(address(this), id);

        pToken.transferFrom(address(this), to, id);

        assertEq(pToken.getApproved(id), address(0));
        assertEq(pToken.ownerOf(id), to);
        assertEq(pToken.balanceOf(to), 1);
        assertEq(pToken.balanceOf(address(this)), id - 1);
    }

    function testTransferFromApproveAll(uint256 id, address to) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;
        
        address from = address(0xABCD);

        if (to == address(0) || to == from) to = address(0xBEEF);

        pToken.mint(from, id);

        hevm.prank(from);
        pToken.setApprovalForAll(address(this), true);

        pToken.transferFrom(from, to, id);

        assertEq(pToken.getApproved(id), address(0));
        assertEq(pToken.ownerOf(id), to);
        assertEq(pToken.balanceOf(to), 1);
        assertEq(pToken.balanceOf(from), id - 1);
    }

    function testSafeTransferFromToEOA(uint256 id, address to) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;
        
        address from = address(0xABCD);

        if (to == address(0) || to == from) to = address(0xBEEF);

        if (uint256(uint160(to)) <= 18 || to.code.length > 0) return;

        pToken.mint(from, id);

        hevm.prank(from);
        pToken.setApprovalForAll(address(this), true);

        pToken.safeTransferFrom(from, to, id);

        assertEq(pToken.getApproved(id), address(0));
        assertEq(pToken.ownerOf(id), to);
        assertEq(pToken.balanceOf(to), 1);
        assertEq(pToken.balanceOf(from), id - 1);
    }

    function testSafeTransferFromToERC721Recipient(uint256 id) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        address from = address(0xABCD);

        ERC721Recipient recipient = new ERC721Recipient();

        pToken.mint(from, id);

        hevm.prank(from);
        pToken.setApprovalForAll(address(this), true);

        pToken.safeTransferFrom(from, address(recipient), id);

        assertEq(pToken.getApproved(id), address(0));
        assertEq(pToken.ownerOf(id), address(recipient));
        assertEq(pToken.balanceOf(address(recipient)), 1);
        assertEq(pToken.balanceOf(from), id - 1);

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), from);
        assertEq(recipient.id(), id);
        assertBytesEq(recipient.data(), "");
    }

    function testSafeTransferFromToERC721RecipientWithData(uint256 id, bytes calldata data) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        address from = address(0xABCD);
        ERC721Recipient recipient = new ERC721Recipient();

        pToken.mint(from, id);

        hevm.prank(from);
        pToken.setApprovalForAll(address(this), true);

        pToken.safeTransferFrom(from, address(recipient), id, data);

        assertEq(pToken.getApproved(id), address(0));
        assertEq(pToken.ownerOf(id), address(recipient));
        assertEq(pToken.balanceOf(address(recipient)), 1);
        assertEq(pToken.balanceOf(from), id - 1);

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), from);
        assertEq(recipient.id(), id);
        assertBytesEq(recipient.data(), data);
    }

    function testSafeMintToEOA(uint256 id, address to) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        if (to == address(0)) to = address(0xBEEF);

        if (uint256(uint160(to)) <= 18 || to.code.length > 0) return;

        pToken.safeMint(to, id);

        assertEq(pToken.ownerOf(id), address(to));
        assertEq(pToken.balanceOf(address(to)), id);
    }

    function testSafeMintToERC721Recipient(uint256 id) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        ERC721Recipient to = new ERC721Recipient();

        pToken.safeMint(address(to), id);

        assertEq(pToken.ownerOf(id), address(to));
        assertEq(pToken.balanceOf(address(to)), id);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), id);
        assertBytesEq(to.data(), "");
    }

    function testSafeMintToERC721RecipientWithData(uint256 id, bytes calldata data) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        ERC721Recipient to = new ERC721Recipient();

        pToken.safeMint(address(to), id, data);

        assertEq(pToken.ownerOf(id), address(to));
        assertEq(pToken.balanceOf(address(to)), id);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), id);
        assertBytesEq(to.data(), data);
    }

    function testFailMintToZero(uint256 id) public {
        pToken.mint(address(0), id);
    }

    // irrelevant to us
    // function testFailDoubleMint(uint256 id, address to) public {
    //     if (to == address(0)) to = address(0xBEEF);

    //     pToken.mint(to, id);
    //     pToken.mint(to, id);
    // }

    function testFailBurnUnMinted(uint256 id) public {
        pToken.burn(id);
    }

    function testFailDoubleBurn(uint256 id, address to) public {
        if (to == address(0)) to = address(0xBEEF);

        pToken.mint(to, id);

        pToken.burn(id);
        pToken.burn(id);
    }

    function testFailApproveUnMinted(uint256 id, address to) public {
        pToken.approve(to, id);
    }

    function testFailApproveUnAuthorized(
        address owner,
        uint256 id,
        address to
    ) public {
        if (owner == address(0) || owner == address(this)) owner = address(0xBEEF);

        pToken.mint(owner, id);

        pToken.approve(to, id);
    }

    function testFailTransferFromUnOwned(
        address from,
        address to,
        uint256 id
    ) public {
        pToken.transferFrom(from, to, id);
    }

    function testFailTransferFromWrongFrom(
        address owner,
        address from,
        address to,
        uint256 id
    ) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        if (owner == address(0)) to = address(0xBEEF);
        if (from == owner) revert();

        pToken.mint(owner, id);

        pToken.transferFrom(from, to, id);
    }

    function testFailTransferFromToZero(uint256 id) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        pToken.mint(address(this), id);

        pToken.transferFrom(address(this), address(0), id);
    }

    function testFailTransferFromNotOwner(
        address from,
        address to,
        uint256 id
    ) public {
        if (from == address(this)) from = address(0xBEEF);
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        pToken.mint(from, id);

        pToken.transferFrom(from, to, id);
    }

    function testFailSafeTransferFromToNonERC721Recipient(uint256 id) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        pToken.mint(address(this), id);

        pToken.safeTransferFrom(address(this), address(new NonERC721Recipient()), id);
    }

    function testFailSafeTransferFromToNonERC721RecipientWithData(uint256 id, bytes calldata data) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        pToken.mint(address(this), id);

        pToken.safeTransferFrom(address(this), address(new NonERC721Recipient()), id, data);
    }

    function testFailSafeTransferFromToRevertingERC721Recipient(uint256 id) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        pToken.mint(address(this), id);

        pToken.safeTransferFrom(address(this), address(new RevertingERC721Recipient()), id);
    }

    function testFailSafeTransferFromToRevertingERC721RecipientWithData(uint256 id, bytes calldata data) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        pToken.mint(address(this), id);

        pToken.safeTransferFrom(address(this), address(new RevertingERC721Recipient()), id, data);
    }

    function testFailSafeTransferFromToERC721RecipientWithWrongReturnData(uint256 id) public {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;

        pToken.mint(address(this), id);

        pToken.safeTransferFrom(address(this), address(new WrongReturnDataERC721Recipient()), id);
    }

    function testFailSafeTransferFromToERC721RecipientWithWrongReturnDataWithData(uint256 id, bytes calldata data)
        public
    {
        if (id > token.MAX_CHUNKS()) id = token.MAX_CHUNKS();
        if (id == 0) id = 1;
        
        pToken.mint(address(this), id);

        pToken.safeTransferFrom(address(this), address(new WrongReturnDataERC721Recipient()), id, data);
    }

    function testFailSafeMintToNonERC721Recipient(uint256 id) public {
        pToken.safeMint(address(new NonERC721Recipient()), id);
    }

    function testFailSafeMintToNonERC721RecipientWithData(uint256 id, bytes calldata data) public {
        pToken.safeMint(address(new NonERC721Recipient()), id, data);
    }

    function testFailSafeMintToRevertingERC721Recipient(uint256 id) public {
        pToken.safeMint(address(new RevertingERC721Recipient()), id);
    }

    function testFailSafeMintToRevertingERC721RecipientWithData(uint256 id, bytes calldata data) public {
        pToken.safeMint(address(new RevertingERC721Recipient()), id, data);
    }

    function testFailSafeMintToERC721RecipientWithWrongReturnData(uint256 id) public {
        pToken.safeMint(address(new WrongReturnDataERC721Recipient()), id);
    }

    function testFailSafeMintToERC721RecipientWithWrongReturnDataWithData(uint256 id, bytes calldata data) public {
        pToken.safeMint(address(new WrongReturnDataERC721Recipient()), id, data);
    }

    function testFailOwnerOfUnminted(uint256 id) public view {
        pToken.ownerOf(id);
    }
}