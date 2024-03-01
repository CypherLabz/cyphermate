// SPDX-License-Identifier: MIT
// Last update: 2024-02-20
pragma solidity ^0.8.20;

import { Ownable } from "../../../access/Ownable.sol";

// Reroll -> Random
// Royalties on a Trade to royalty receiver.
// Trade -> Pick and choose + pay royalties.

// Figure out the wrapper version
// Figure out - contracts are whitelisted by default, unless activated by contract-initiated call

// Test: whitelist to non-whitelist then action
// Test: what if some are whitelisted some are non-whitelisted and then there are an uneven amount of pooled vs held tokens because of it, does it mess something up?

// Whitelistable is a supplimentary contract for ERC404 with whitelisting enabled
abstract contract Whitelistable is Ownable {

    event Whitelisted(address indexed target, bool indexed allowed);

    mapping(address => bool) public whitelisted;

    function addToWhitelist(address target_, bool allowed_) public onlyOwner {
        whitelisted[target_] = allowed_;
        emit Whitelisted(target_, allowed_);
    }
}

abstract contract ERC404 is Whitelistable {

    /////////////////////////////////
    // Events ///////////////////////
    ///////////////////////////////// 

    // Transfer and Approval Events are emitted through YUL/ASM
    bytes32 constant internal TRANSFER_EVENT_SIG = 
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    bytes32 constant internal APPROVAL_EVENT_SIG = 
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    // event Transfer(address indexed from, address indexed to, uint256 amount); 
    function _emitERC20Transfer(address from_, address to_, uint256 amount_) internal virtual {
        assembly {
            mstore(0x0, amount_)
            log3(0x0, 0x20, TRANSFER_EVENT_SIG, from_, to_)
        }
    }

    // event Approval(address indexed owner, address indexed operator, uint256 amount); 
    function _emitERC20Approval(address owner_, address spender_, uint256 amount_) internal virtual {
        assembly { 
            mstore(0x0, amount_)
            log3(0x0, 0x20, APPROVAL_EVENT_SIG, owner_, spender_)
        }
    }

    // event Transfer(address indexed from, address indexed to, uint256 indexed tokenId); 
    function _emitERC721Transfer(address from_, address to_, uint256 id_) internal virtual {
        assembly {
            log4(0x0, 0x20, TRANSFER_EVENT_SIG, from_, to_, id_)
        }
    }

    // event Approval(address indexed owner, address indexed operator, uint256 indexed tokenId); 
    function _emitERC721Approval(address owner_, address spender_, uint256 id_) internal virtual {
        assembly {
            log4(0x0, 0x20, APPROVAL_EVENT_SIG, owner_, spender_, id_)
        }
    }

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event PoolSwapRoyaltiesReceiverSet(address indexed operator, address indexed receiver);
    event PoolSwapRoyaltiesFeeSet(address indexed operator, uint256 fee_);

    /////////////////////////////////
    // Collection Metadata //////////
    /////////////////////////////////

    string public name;
    string public symbol;

    /////////////////////////////////
    // Collection Parameters ////////
    /////////////////////////////////

    uint8 public constant decimals = 18;
    uint256 public constant totalChunks = 10000;
    uint256 public constant chunkSize = 100 ether;

    // By nature, the totalSupply is equal to (totalChunks * chunkSize)
    function totalSupply() public virtual view returns (uint256) {
        return totalChunks * chunkSize;
    }

    // The Token Pool address representing the pooled tokens' owner
    address public constant TOKEN_POOL = 0x0000000000000000000000000000000004040404;

    /////////////////////////////////
    // Collection Storage ///////////
    /////////////////////////////////

    // After that, some specific ERC404 storage
    uint256 public initializedChunkIndex;

    // ChunkInfo packs the owner and the index of the token in one 
    struct ChunkInfo {
        address owner;
        uint16 index;
    }

    // chunkToOwners is the equivalent of _owners or _ownerOf 
    ChunkInfo[totalChunks] public chunkToOwners; // can change to internal if wanted

    // Chunk stack tracking for an owner. This is used on transfer, pool/burn, and redeem/mint operations
    mapping(address => uint16[]) public ownerToChunkIndexes;

    // Active length tracking for an owner. This enables us to reuse initialized array slots instead of popping them.
    mapping(address => uint256) public ownerToActiveLength;

    // ERC20 type balanceOf and allowance
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ERC721 type getApproved and isApprovedForAll
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /////////////////////////////////
    // Constructor //////////////////
    /////////////////////////////////

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;

        // Natively, ERC404 sets the balance of the token to the deployer.
        // The ERC721 NFTs are not minted alongside it and will mint on the first transfer.
        balanceOf[msg.sender] = totalSupply();
        _emitERC721Transfer(address(0), msg.sender, totalSupply());
    }

    /////////////////////////////////
    // Functions ////////////////////
    /////////////////////////////////

    // The native version of ERC404 does not actually have a traditional "burn" and "mint" operation.
    // For this native version of ERC404, a "burn" is actually a "pool", which sends the tokens to the pool.
    // And a "mint" only applies to the ERC721 part of ERC404. Additional ERC20s cannot be minted.

    // An RNG function is created (and able to be overridden) for reroll mechanics. Natively, a nonce is not supplied.
    function _getRNG() internal virtual view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, blockhash(block.number - 1))));
    }

    // A transfer function acts as a ERC20 transfer with attached logic of ERC404-pool-redeem as follows:
    // [Transfer ERC20] --> [Evaluate chunk differences] -> [SwapSlot/Pool/Redeem the chunk differences]
    // Thus, we must create our pool, redeem, and swapSlot functions.
    // SwapSlot is an optimization of ERC404 storage on transfers, by swapping slots (xfer) instead of pool+redeem flow.
    
    // _min helps us find the smaller value of two. This is used for chunk difference comparisons.
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }

    // @0xinu: i want to abstract this into multiple smaller, reusable functions.
    // _mintOrRedeem either mints a token or retrieves it from the pool if we're fully minted
    function _mintOrRedeem(address to_) internal virtual {

        uint256 _initializedChunkIndex = initializedChunkIndex; // Load the intiialized chunk index

        // Determine if we're fully initialized and act according to the result
        if (totalChunks > _initializedChunkIndex) {
            // We're not fully initialized, so we will mint a new token.

            // Additionally, we will be using active chunk index optimization. 
            uint256 _totalLengthTo = ownerToChunkIndexes[to_].length;
            uint256 _lastActiveLengthTo = ownerToActiveLength[to_];
            
            // Thus, we need to check for available initialized slots and act according to the result
            if (_totalLengthTo > _lastActiveLengthTo) {
                // We have available initialized slots to reuse. Here, we will reuse the slot.
                // First, set the new owner and index of the token. The index will be the current active length.
                chunkToOwners[_initializedChunkIndex] = ChunkInfo(
                    to_, 
                    uint16(_lastActiveLengthTo)
                );

                // Then, we increment the active length
                unchecked {
                    ownerToActiveLength[to_]++;
                }

                // Finally, we set the minted tokenId to the reactivated array slot
                ownerToChunkIndexes[to_][_lastActiveLengthTo + 1] = uint16(_initializedChunkIndex);
            }

            else {
                // We don't have available initialized slots to reuse. Here, we will push to the array.
                // First, set the new owner and index of the token. The index will be the current total length.
                chunkToOwners[_initializedChunkIndex] = ChunkInfo(
                    to_,
                    uint16(_totalLengthTo)
                );

                // Then, we increment the active length
                unchecked {
                    ownerToActiveLength[to_]++;
                }

                // Finally, we push the minted tokenId to the newly initialized array slot
                ownerToChunkIndexes[to_].push(uint16(_initializedChunkIndex));
            }

            // Afterwards, increment the initialized chunk index
            unchecked {
                initializedChunkIndex++;
            }

            // Emit an ERC721 Transfer event
            _emitERC721Transfer(address(0), to_, _initializedChunkIndex);
        }


        else {
            // We're fully initialized, so we will redeem a token from the pool.
            // Find the active index of the pool, and use that as the next token to receive
            uint256 _redeemIndex = ownerToActiveLength[TOKEN_POOL] - 1;
            uint16 _tokenId = ownerToChunkIndexes[TOKEN_POOL][_redeemIndex]; 

            // Chunk index optimization - use slots if available
            uint256 _totalLengthTo = ownerToChunkIndexes[to_].length;
            uint256 _lastActiveLengthTo = ownerToActiveLength[to_];

            // Check if we have available intialized slots to reuse
            if (_totalLengthTo > _lastActiveLengthTo) {
                // We reuse the initialized slots
                // Ownership change of chunk
                chunkToOwners[_tokenId] = ChunkInfo(
                    to_,
                    uint16(_lastActiveLengthTo)
                );

                // Increment active length
                unchecked {
                    ownerToActiveLength[to_]++;
                }
                
                // Finally, set the tokenId at the reactivated slot
                ownerToChunkIndexes[to_][_lastActiveLengthTo] = _tokenId;
            }

            else {
                // We need to initialize a new slot
                // Ownership change of chunk
                chunkToOwners[_tokenId] = ChunkInfo(
                    to_,
                    uint16(_totalLengthTo)
                );

                // Increment active length
                unchecked { 
                    ownerToActiveLength[to_]++;
                }

                // Finally, push the new tokenId to the array
                ownerToChunkIndexes[to_].push(_tokenId);
            }

            // Afterwards, we need to remove the token from the pool. 
            // Since we are always using the last index, we can just decrease activeLength
            ownerToActiveLength[TOKEN_POOL]--;

            // A non-required sanity check of deleting getApproved (standard on transfers)
            delete getApproved[uint256(_tokenId)];

            // Emit a ERC721 transfer
            _emitERC721Transfer(TOKEN_POOL, to_, uint256(_tokenId));
        }
    }

    // function _poolChunk takes a user's chunk and puts it into a FILO queue
    function _poolChunk(address from_) internal virtual {
        // Find the FILO tokenId for the address based on the active length
        uint256 _lastIndex = ownerToActiveLength[from_] - 1;
        uint256 _tokenId = ownerToChunkIndexes[from_][_lastIndex];

        // Decrease the owner's active length 
        ownerToActiveLength[from_]--;

        // Delete approvals
        delete getApproved[_tokenId];

        // Now, we need to add the token into the pool with slot optimization
        uint256 _totalLength = ownerToChunkIndexes[TOKEN_POOL].length;
        uint256 _activeLength = ownerToActiveLength[TOKEN_POOL];

        // Available slots check
        if (_totalLength > _activeLength) {
            // We use available slot
            chunkToOwners[_tokenId] = ChunkInfo(
                TOKEN_POOL,
                uint16(_activeLength)
            );

            unchecked { 
                ownerToActiveLength[TOKEN_POOL]++;
            }

            ownerToChunkIndexes[TOKEN_POOL][_activeLength] = uint16(_tokenId);
        }

        else {
            // We initialize a new slot
            chunkToOwners[_tokenId] = ChunkInfo(
                TOKEN_POOL,
                uint16(_totalLength)
            );

            unchecked {
                ownerToActiveLength[TOKEN_POOL]++;
            }

            ownerToChunkIndexes[TOKEN_POOL].push(uint16(_tokenId));
        }

        // Emit ERC721 Transfer
        _emitERC721Transfer(from_, TOKEN_POOL, _tokenId);
    }

    // @0xinu: handle whitelist turned non-whitelist case where ownerToActiveLength is 0 or lower than actual balanceOf in chunks
    // _swapSlots is used when there is both a sender and receiver. amount_ is loops.
    function _swapSlots(address from_, address to_, uint256 amount_) internal virtual {

        for (uint256 i = 0; i < amount_;) {
            // Find the tokenId to swap from from_
            uint256 _lastIndexFrom = ownerToActiveLength[from_] - 1;
            uint256 _tokenToSwap = ownerToChunkIndexes[from_][_lastIndexFrom];

            // Now, find out available slots
            uint256 _totalLengthTo = ownerToChunkIndexes[to_].length;
            uint256 _activeLengthTo = ownerToActiveLength[to_];

            // If we have available slots
            if (_totalLengthTo > _activeLengthTo) {
                // Use the available slots
                chunkToOwners[_tokenToSwap] = ChunkInfo(
                    to_,
                    uint16(_activeLengthTo)
                );

                unchecked { 
                    ownerToActiveLength[to_]++;
                }

                ownerToChunkIndexes[to_][_activeLengthTo] = uint16(_tokenToSwap);
            }

            else {
                // Initialize a new slot
                chunkToOwners[_tokenToSwap] = ChunkInfo(
                    to_,
                    uint16(_totalLengthTo)
                );

                unchecked {
                    ownerToActiveLength[to_]++;
                }

                ownerToChunkIndexes[to_].push(uint16(_tokenToSwap));
            }

            // Decrease active length of from
            ownerToActiveLength[from_]--;

            // Remove the approvals
            delete getApproved[_tokenToSwap];

            // Emit transfer
            _emitERC721Transfer(from_, to_, _tokenToSwap);

            // Continue the loop
            unchecked { ++i; }
        }
    }

    // _transfer is the handler for an ERC20-esque transfer
    function _transfer(address from_, address to_, uint256 amount_) internal virtual {
        // No address(0) allowed because we aren't handling burns or mints to totalSupply
        require(from_ != address(0), "ERC404: _transfer from zero address");
        require(to_ != address(0), "ERC404: _transfer to zero address");

        // Store the balance of from_ and to_ before balance manipulations
        uint256 _startBalFrom = balanceOf[from_];
        uint256 _startBalTo = balanceOf[to_];

        // ERC20-esque transfer
        balanceOf[from_] -= amount_;

        unchecked { 
            balanceOf[to_] += amount_;
        }

        _emitERC20Transfer(from_, to_, amount_);

        // ERC721-esque transfer with ERC404 flow logic.
        // Here, we first check if from_ and to_ are whitelisted. 
        // If both aren't, we can just swap slots to save gas.
        if (!whitelisted[from_] && !whitelisted[to_]) {
            // We will use _swapSlot flow and then return before the subsequent flow
            uint256 _chunkDiffFrom = 
                (_startBalFrom / chunkSize) - 
                (balanceOf[from_] / chunkSize);
            
            uint256 _chunkDiffTo = 
                (balanceOf[to_] / chunkSize) - 
                (_startBalTo / chunkSize);
            
            // We grab the lowest chunk difference to do _swapSlot
            uint256 _minDiff = _min(_chunkDiffFrom, _chunkDiffTo);

            _swapSlots(from_, to_, _minDiff);

            // If we have a remainder of diff, we need to handle the difference.
            if (_chunkDiffFrom != _chunkDiffTo) {
                // If there's more chunkDiffs in from_, we have to pool it.
                if (_chunkDiffFrom > _chunkDiffTo) {
                    // Technically, I think the diff should always be 1. But, for 
                    // proper edge case handling, we will calculate the difference.
                    uint256 _toBePooled = _chunkDiffFrom - _chunkDiffTo;
                    for (uint256 i = 0; i < _toBePooled;) {
                        _poolChunk(from_);
                        unchecked { ++i; }
                    }
                }

                // If there's more chunkDiffs in to_, we have to redeem it.
                if (_chunkDiffTo > _chunkDiffFrom) {
                    // Technically, I could use an else as well. 
                    // But... I'll just declare both scenarios here.
                    uint256 _toBeRedeemed = _chunkDiffTo - _chunkDiffFrom;
                    for (uint256 i = 0; i < _toBeRedeemed;) {
                        _mintOrRedeem(to_);
                        unchecked { ++i; }
                    }
                }
            }

            // return early so that we don't execute the subsequent flow
            return;
        }

        // Handle individual from_ and to_ cases.
        // If from_ is not whitelisted, we will pool his chunks.
        if (!whitelisted[from_]) {
            uint256 _chunkDiffFrom = 
                (_startBalFrom / chunkSize) - 
                (balanceOf[from_] / chunkSize);
            
            if (_chunkDiffFrom > 0) {
                for (uint256 i = 0; i < _chunkDiffFrom;) {
                    _poolChunk(from_);
                    unchecked { ++i; }
                }
            }
        }

        // If to_ is not whitelisted, we will redeem chunks for him.
        if (!whitelisted[to_]) {
            uint256 _chunkDiffTo = 
                (balanceOf[to_] / chunkSize) - 
                (_startBalTo / chunkSize); 
            
            if (_chunkDiffTo > 0) {
                for (uint256 i = 0; i < _chunkDiffTo;) {
                    _mintOrRedeem(to_);
                    unchecked { ++i; }
                }
            }
        }

        // End of flow
    }

    // function _chunkTransfer is the handler for a ERC721-esque transfer of a chunk
    function _chunkTransfer(address from_, address to_, uint256 tokenId_) internal virtual {
        // No address(0) because we aren't handling burns and mints here
        require(from_ != address(0), "ERC404: _chunkTransfer from zero address");
        require(to_ != address(0), "ERC404: _chunkTransfer to zero address");

        // Make sure that from_ and _owner is the same
        address _owner = chunkToOwners[tokenId_].owner;
        require(_owner == from_, "ERC404: _chunkTransfer from incorrect owner");

        // We're transferring a chunk, so, an ERC20 transfer of chunkSize is made
        balanceOf[from_] -= chunkSize;

        unchecked { 
            balanceOf[to_] += chunkSize;
        }

        _emitERC20Transfer(from_, to_, chunkSize);

        // Now, since whitelisted addresses can't handle ERC721-chunks
        // We're not gonna allow transfers of chunks to them either.
        require(!whitelisted[from_], "ERC404: _chunkTransfer from whitelisted");
        require(!whitelisted[to_], "ERC404: _chunkTransfer to whitelisted");

        // Now, find the index of the tokenId_, and push it out of active state.
        uint16 _tokenIndex = chunkToOwners[tokenId_].index;
        uint256 _lastActiveIndexFrom = ownerToActiveLength[from_] - 1;

        // If the token index is not the last, replace it with the last index.
        if (_lastActiveIndexFrom != _tokenIndex) {
            ownerToChunkIndexes[from_][_tokenIndex] = 
            ownerToChunkIndexes[from_][_lastActiveIndexFrom];
        }

        // Then, decrement the active length.
        unchecked { 
            // This is OK, because otherwise _lastActiveIndexFrom will have underflowed.
            ownerToActiveLength[from_]--;
        }

        // Delete the token's approvals
        delete getApproved[tokenId_];

        // Now, it's time to set the new owner.
        uint256 _totalLengthTo = ownerToChunkIndexes[to_].length;
        uint256 _activeLengthTo = ownerToActiveLength[to_];

        // If there are available slots, use them.
        if (_totalLengthTo > _activeLengthTo) {
            chunkToOwners[tokenId_] = ChunkInfo(
                to_,
                uint16(_activeLengthTo)
            );

            unchecked {
                ownerToActiveLength[to_]++;
            }

            ownerToChunkIndexes[to_][_activeLengthTo] = uint16(tokenId_);
        }

        // There are no available slots, push a new one
        else {
            chunkToOwners[tokenId_] = ChunkInfo(
                to_,
                uint16(_totalLengthTo)
            );

            unchecked {
                ownerToActiveLength[to_]++;
            }

            ownerToChunkIndexes[to_].push(uint16(tokenId_));
        }

        // Finally, emit an ERC721 Transfer event
        _emitERC721Transfer(from_, to_, tokenId_);
    }

    // function transfer handles ERC20-esque transfers. It does not support tokenIds.
    // @0xinu: test sending a tokenId.
    function transfer(address to_, uint256 amount_) public virtual returns (bool) {
        _transfer(msg.sender, to_, amount_);
        return true;
    }

    // function transferFrom handles both ERC20-esque and ERC721-esque transfers.
    // The identifier of ERC20 or ERC721 is by checking amount with totalChunks
    function transferFrom(address from_, address to_, uint256 amtOrTokenId_) public virtual returns (bool) {
        // Determine if it's an amount or a tokenId
        if (totalChunks >= amtOrTokenId_) {
            // It's a tokenId. Check approval or ownership. (Handle as ERC721)
            require(
                msg.sender == from_ || // the sender must be the owner ||
                isApprovedForAll[from_][msg.sender] || // the sender must have approved the operator
                getApproved[amtOrTokenId_] == msg.sender, // the token must have been approved to the operator
                "ERC404: transferFrom not approved"
            );

            _chunkTransfer(from_, to_, amtOrTokenId_);
        }

        else {
            // It's an amount. Check allowance. (Handle as ERC20)
            uint256 _allowance = allowance[from_][msg.sender];

            // Deduct the allowance, if it's not max. This saves gas for max approvals.
            if (_allowance != type(uint256).max) {
                allowance[from_][msg.sender] -= amtOrTokenId_;
            }

            _transfer(from_, to_, amtOrTokenId_);
        }

        return true;
    }

    // safeTransferFroms for ERC721 operations. We return true as well, for the culture.
    function _safeTransferFrom(address from_, address to_, uint256 tokenId_, bytes memory data_) internal virtual returns (bool) {
        require(totalChunks >= tokenId_, "ERC404: _safeTransferFrom invalid tokenId");

        transferFrom(from_, to_, tokenId_);

        require(
            to_.code.length == 0 ||
                ERC721TokenReceiver(to_).onERC721Received(msg.sender, from_, tokenId_, data_) == 
                ERC721TokenReceiver.onERC721Received.selector,
            "ERC404: safeTransferFrom unsafe recipient"
        );

        return true;
    }

    function safeTransferFrom(address from_, address to_, uint256 tokenId_, bytes memory data_) public virtual returns (bool) {
        return _safeTransferFrom(from_, to_, tokenId_, data_);
    }

    function safeTransferFrom(address from_, address to_, uint256 tokenId_) public virtual returns (bool) {
        return _safeTransferFrom(from_, to_, tokenId_, "");
    }

    // function approve handles both ERC20 and ERC721 approvals, identifed by totalChunks
    function approve(address operator_, uint256 amtOrTokenId_) public virtual returns (bool) {
        // Handle ERC721 approval
        if(totalChunks >= amtOrTokenId_) {
            // Check approval or ownership
            address _owner = chunkToOwners[amtOrTokenId_].owner;
            require(
                _owner == msg.sender || // the approver must be the owner of the token ||
                isApprovedForAll[_owner][msg.sender], // the approver is an operator
                "ERC404: approve from unauthorized"
            );

            getApproved[amtOrTokenId_] = operator_;

            _emitERC721Approval(_owner, operator_, amtOrTokenId_);
        }

        // Handle ERC20 approval
        else {
            // ERC20 approvals are user-initiated only
            allowance[msg.sender][operator_] = amtOrTokenId_;
            _emitERC20Approval(msg.sender, operator_, amtOrTokenId_);
        }

        return true;
    }

    // function setApprovalForAll is an ERC721-specific method
    function setApprovalForAll(address operator_, bool approved_) public virtual {
        isApprovedForAll[msg.sender][operator_] = approved_;
        emit ApprovalForAll(msg.sender, operator_, approved_);
    }

    // function ownerOf returns the ERC721 owner. 
    function ownerOf(uint256 tokenId_) public virtual view returns (address) {
        address _owner = chunkToOwners[tokenId_].owner;
        require(_owner != address(0), "ERC404: ownerOf token does not exist");
        return _owner;
    }

    // function _reroll is an internal function that handles token rerolls from the pool.
    // _reroll does not have any ERC20 transfers as it is not needed. 
    // _reroll reuses the same storage slots, so there are no pushes ever required.
    function _reroll(uint256 tokenId_) internal virtual {
        // The token must exist
        address _owner = chunkToOwners[tokenId_].owner;
        require(_owner != address(0), "ERC404: _reroll nonexistent token");

        // Figure out the index of the token to be pooled and their data replaced.
        uint256 _tokenIndex = chunkToOwners[tokenId_].index;

        // Now, roll the RNG for the pool's tokens
        uint256 _rng = _getRNG();
        uint256 _poolLen = ownerToActiveLength[TOKEN_POOL];
        uint256 _redeemIndex = _rng % _poolLen; // a number between 0 and _poolLen - 1
        uint16 _redeemId = ownerToChunkIndexes[TOKEN_POOL][_redeemIndex];

        // Replace the _owner's token index with _redeemId, and vice versa
        ownerToChunkIndexes[_owner][_tokenIndex] = _redeemId;
        ownerToChunkIndexes[TOKEN_POOL][_redeemIndex] = uint16(tokenId_);

        // Now, update the chunk storage to the new owners and indexes
        chunkToOwners[tokenId_] = ChunkInfo(
            TOKEN_POOL,
            uint16(_redeemIndex)
        );

        chunkToOwners[_redeemId] = ChunkInfo(
            _owner,
            uint16(_tokenIndex)
        );

        // Emit the transfers between the _owner and the pool
        _emitERC721Transfer(_owner, TOKEN_POOL, tokenId_); 
        _emitERC721Transfer(TOKEN_POOL, _owner, _redeemId);
    }

    // function reroll is the public function that handles rerolls. Owner-initated only.
    // We also return a boolean true, in ERC20 fashion.
    function reroll(uint256 tokenId_) public virtual returns (bool) {
        // Optionally, we can add isApprovedForAll too, but we choose not to.
        address _owner = chunkToOwners[tokenId_].owner;
        require(_owner == msg.sender, "ERC404: reroll not from owner");
        _reroll(tokenId_);
        return true;
    }

    // function tokenURI needs to be implemented 
    function tokenURI(uint256 tokenId_) public virtual view returns (string memory);

    // function supportsInterface for ERC165 support. Currently uses ERC721 interfaces. 
    function supportsInterface(bytes4 interfaceId_) public view virtual returns (bool) {
        return
            interfaceId_ == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId_ == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId_ == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    // function viewAllStorageSlots returns the entire storage array for an address.
    // Note: this returns both the active and initialized-but-unused slots. 
    function viewAllStorageSlots(address wallet_) public virtual view returns (uint16[] memory) {
        return ownerToChunkIndexes[wallet_];
    }

    // function balanceOfChunks returns the balance of chunks for a wallet
    function balanceOfChunks(address wallet_) public virtual view returns (uint256) {
        return ownerToActiveLength[wallet_];
    }

    // function walletOfOwner returns the active slots of ownerToChunkIndexes
    function walletOfOwner(address wallet_) public virtual view returns (uint16[] memory) {
        uint256 l = ownerToActiveLength[wallet_];
        uint16[] memory _chunks = new uint16[] (l);
        for (uint256 i = 0; i < l;) {
            _chunks[i] = ownerToChunkIndexes[wallet_][i];
            unchecked { ++i; }
        }
        return _chunks;
    }
}

abstract contract ERC721TokenReceiver {
    function onERC721Received(
        address, // operator
        address, // from 
        uint256, // tokenId
        bytes calldata // data
    ) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

abstract contract ERC404PoolSwap is ERC404 {

    // ERC404 poolSwap contract-enforced optional royalties. Default set to 0.
    address public poolSwapRoyaltiesReceiver;
    uint256 public poolSwapRoyaltiesFee; // Denoted in 1/100 of a % per unit

    // ERC404 poolSwap ownable configurations
    function setPoolSwapRoyaltiesReceiver(address receiver_) public virtual onlyOwner {
        poolSwapRoyaltiesReceiver = receiver_;
        emit PoolSwapRoyaltiesReceiverSet(msg.sender, receiver_);
    }

    // 1/100 of a % per unit. For example, 1% fee is 100
    function setPoolSwapRoyaltiesFee(uint256 fee_) public virtual onlyOwner {
        poolSwapRoyaltiesFee = fee_;
        emit PoolSwapRoyaltiesFeeSet(msg.sender, fee_);
    }

    // function _swap is the internal handler for a swap operation
    function _swap(uint256 fromId_, uint256 toId_) internal virtual {

        // Firstly, fromId_'s owner must not be address(0)
        address _ownerFrom = chunkToOwners[fromId_].owner;
        require(_ownerFrom != address(0), "ERC404: _swap from nonexistent token");

        // Secondly, toId_'s owner must be the TOKEN_POOL
        address _ownerTo = chunkToOwners[toId_].owner;
        require(_ownerTo == TOKEN_POOL, "ERC404: _swap to not owned by pool");

        // Next, we calculate the total cost of the swap, and check balances.
        // Note: the deduction of fee must not result in a different chunkDiff
        // We can safely assume that if _ownerFrom is owned by owner, then 
        // the owner must have at least 1 chunk's worth of tokens.
        uint256 _availableRemainderFrom = balanceOf[_ownerFrom] % chunkSize;
        uint256 _swapFee = (chunkSize / 100_000) * poolSwapRoyaltiesFee;
        require(_availableRemainderFrom > _swapFee, "ERC404: _swap not enough remainder");

        // Transfer _swapFee to the royalties receiver
        // Edge case: this could result in < totalChunk amount of dust tokens to a balance
        // Edge case: this could result in a chunkDiff that does not redeem a chunk
        balanceOf[_ownerFrom] -= _swapFee;

        unchecked { 
            balanceOf[poolSwapRoyaltiesReceiver] += _swapFee;
        }

        _emitERC20Transfer(_ownerFrom, poolSwapRoyaltiesReceiver, _swapFee);

        // Now, swap the chunks! ...Find their indexes!
        uint256 _indexFrom = chunkToOwners[fromId_].index;
        uint256 _indexTo = chunkToOwners[toId_].index;

        // Swap their ownership data!
        chunkToOwners[fromId_] = ChunkInfo(
            TOKEN_POOL,
            uint16(_indexTo)
        );

        chunkToOwners[toId_] = ChunkInfo(
            _ownerFrom,
            uint16(_indexFrom)
        );

        // Swap their indexes!
        ownerToChunkIndexes[_ownerFrom][_indexFrom] = uint16(toId_);
        ownerToChunkIndexes[TOKEN_POOL][_indexTo] = uint16(fromId_);

        // Emit the swaps!
        _emitERC721Transfer(_ownerFrom, TOKEN_POOL, fromId_);
        _emitERC721Transfer(TOKEN_POOL, _ownerFrom, toId_);
    }

    // function swap is the public handler for a user-initiated swap 
    function swap(uint256 fromId_, uint256 toId_) public virtual returns (bool) {
        address _ownerFrom = chunkToOwners[fromId_].owner;
        require(_ownerFrom == msg.sender, "ERC404: swap not from owner");
        _swap(fromId_, toId_);
        return true;
    }
}