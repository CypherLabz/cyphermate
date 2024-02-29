// SPDX-License-Identifier: MIT
// Last update: 2024-02-23
pragma solidity ^0.8.20;

import { Ownable } from "../../../access/Ownable.sol";

// Reroll -> Random
// Royalties on a Trade to royalty receiver.
// Trade -> Pick and choose + pay royalties.

// Test: whitelist to non-whitelist then action
// Test: what if some are whitelisted some are non-whitelisted and then there are an uneven amount of pooled vs held tokens because of it, does it mess something up?

// ALL ITEMS ABOVE DONE BABY

// Figure out - contracts are whitelisted by default, unless activated by contract-initiated call

// Now, do:
// Contracts = WL by default unless triggered
// Repopulate (chunk initiation of uninitiated chunks)
// Reorder (reorder internal chunkToActiveIndex)

// here's the harder part... lets go!!!
// And do:
// Convert initialized-balance-on-mint to _mintERC20 and _mintERC721
// Implement a burn system (required for wrapper version anyway)

// Then do:
// Figure out the wrapper version

// WOOP WOOP IM HERE NOW

// Need to do:
// Lower size of the smart contract 

// After that do:
// TokenId can be customizable over starting at 0 (ARrraRarrARRarrGGGhhgHrhah)

// Whitelistable is a supplimentary contract for ERC404 with whitelisting enabled
abstract contract Whitelistable is Ownable {

    // We're renovating the owner-initiated whitelist manipulation to allow user-initiated as well
    // For EOA, chunk stacking is ON by default
    // For Contracts, chunk stacking is OFF by default
    // We've written the logic to account for activeLength dips and overs from WL->NWL NWL->WL situations
    event SetChunkSwitch(address indexed operator, address indexed target, bool indexed toggle);

    // chunkToggle as a switch.  
    // If you are an EOA, FALSE means that you are processing chunks. So you will mint NFTs
    // If you are a smart contract, FALSE means you are NOT processing chunks.
    // This means if you are a smart contract and you want to handle chunks, 
    // Call toggleChunkProcessing from your contract to this contract.
    mapping(address => bool) public chunkToggle;

    // _isChunkProcessor returns whether or not we should process chunks for the address
    // If the target is an EOA, it will return the flip of chunkToggle (default true)
    // If the target is a contract, it will return the chunkToggle (default false)
    function _isChunkProcessor(address target_) internal virtual view returns (bool) {
        return target_.code.length == 0 ? !chunkToggle[target_] : chunkToggle[target_];
    }

    function toggleChunkProcessing(bool processChunks_) public virtual {
        // If they are an EOA, flip the condition around. 
        // This is just for human-understandable input. 
        // This means that the same boolean argument will result in the same condition
        // for both EOAs and smart contracts.
        // Note: we can use codeSize to allow contract constructor calling without
        // implementing a interface method in the logic through .call
        bool boolToSet_ = msg.sender == tx.origin ? !processChunks_ : processChunks_;
        
        // Set the toggle and emit the event
        chunkToggle[msg.sender] = boolToSet_;
        emit SetChunkSwitch(msg.sender, msg.sender, boolToSet_);
    }

    function setChunkProcessingFor(address target_, bool processChunks_) public virtual onlyOwner {
        bool boolToSet_ = target_.code.length == 0 ? !processChunks_ : processChunks_;
        chunkToggle[target_] = boolToSet_;
        emit SetChunkSwitch(msg.sender, target_, processChunks_);
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
    event ChunkReordered(address indexed owner, uint256 indexed tokenId, uint256 posFrom, uint256 posTo);
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
    function TOTAL_CHUNKS() public virtual pure returns (uint256) { 
        // Override to change total chunks
        return 10000; 
    }
    function CHUNK_SIZE() public virtual pure returns (uint256) { 
        // Override to change chunk size
        return 1 ether; 
    }
    function MAX_SUPPLY() public virtual pure returns (uint256) {
        // By nature, MAX_SUPPLY is total chunks * chunk size
        return TOTAL_CHUNKS() * CHUNK_SIZE();
    }

    // The Token Pool address representing the pooled tokens' owner
    address public constant TOKEN_POOL = 0x0000000000000000000000000000000004040404;
    address public constant BURN_POOL = 0x000000000000000000000000000000000404deAD; // BURN_POOL is only used for ERC404Wrapper. For a burn in NATIVE, we send to TOKEN_POOL

    /////////////////////////////////
    // Collection Storage ///////////
    /////////////////////////////////

    // ERC20 totalSupply tracker
    uint256 public totalSupply;

    // After that, some specific ERC404 storage
    uint256 public initializedChunkIndex;

    // ChunkInfo packs the owner and the index of the token in one 
    struct ChunkInfo {
        address owner;
        uint32 index;
    }

    // chunkToOwners is the equivalent of _owners or _ownerOf 
    mapping(uint256 => ChunkInfo) public chunkToOwners;

    // Chunk stack tracking for an owner. This is used on transfer, pool/burn, and redeem/mint operations
    mapping(address => uint32[]) public ownerToChunkIndexes;

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

        // A boilerplate "mint max supply to deployer without minting the ERC721 tokens"
        toggleChunkProcessing(false);
        _mint(msg.sender, MAX_SUPPLY());
    }

    // These are NATIVE-ERC404 type _mint and _burn. For BRIDE-ERC404 refer to ERC404Wrapper functionality instead.
    // To mint an NFT, the ID is determinstic on a stack. You cannot define it here. 
    // Use mint(to_, CHUNK_SIZE()) for exactly 1.00 NFT
    function _mint(address to_, uint256 amount_) internal virtual {
        // Disallow using tokenIds, we enforce it here for clearer implementation guidelines
        require(amount_ > TOTAL_CHUNKS(), "ERC404: _mint amount falls within tokenIds");
        
        // Store balance before balance manipulations
        uint256 _startBalTo = balanceOf[to_];

        // Firstly, increase the totalSupply and ERC20 of receiver
        require(MAX_SUPPLY() >= (totalSupply + amount_), "ERC404: _mint exceeds max supply");
        
        unchecked { 
            totalSupply += amount_; // overflow check already in require statement
            balanceOf[to_] += amount_; // can reuse the same overflow check
        }

        _emitERC20Transfer(address(0), to_, amount_);
        
        // Now, create the ERC721-esque flow, if the receiver is a chunk processor
        if (_isChunkProcessor(to_)) {
            // Calculate chunk differences
            uint256 _chunkDiff = 
                (balanceOf[to_] / CHUNK_SIZE()) - 
                (_startBalTo / CHUNK_SIZE());
            
            // If there are any chunk differences, then process the chunks using _mintOrRedeem
            for (uint256 i = 0; i < _chunkDiff;) {
                _mintOrRedeem(to_);
                unchecked { ++i; }
            }
        }
    }

    // _burn function using either an amount or NFT input
    function _burn(address from_, uint256 amtOrTokenId_) internal virtual {
        // Determine if it's a tokenId or an amount
        if (TOTAL_CHUNKS() >= amtOrTokenId_) {
            // It's a tokenId
            address _owner = chunkToOwners[amtOrTokenId_].owner;
            require(_owner != address(0), "ERC404: _burn nonexistent token");
            require(_owner == from_, "ERC404: _burn incorrect owner");

            // Now, process both a chunk amount of tokens, and then pool the token in BURN_POOL
            balanceOf[from_] -= CHUNK_SIZE();

            unchecked {
                totalSupply -= CHUNK_SIZE();
            }

            _emitERC20Transfer(from_, address(0), CHUNK_SIZE());

            // Pool the token to BURN_POOL. This requires chunk-stack manipulation
            // Find the active index of from
            uint256 _fromActiveIndex = ownerToActiveLength[from_] - 1;

            // Reorder the token in from's chunk stack to the top
            _reorder(from_, amtOrTokenId_, _fromActiveIndex);

            // After reordering, we can pool the target chunk using _poolChunk
            _poolChunk(from_, TOKEN_POOL);
        }

        else {
            // It's an amount, so we store the balance before manipulation
            uint256 _startBalFrom = balanceOf[from_];

            // Then, we do an ERC20 burn
            balanceOf[from_] -= amtOrTokenId_;

            unchecked {
                totalSupply -= amtOrTokenId_;
            }

            _emitERC20Transfer(from_, address(0), amtOrTokenId_);

            // After, we calculate the chunk difference and loop _poolChunk
            uint256 _chunkDiff = 
                (_startBalFrom / CHUNK_SIZE()) - 
                (balanceOf[from_] / CHUNK_SIZE());
            
            for (uint256 i = 0; i < _chunkDiff;) {
                _poolChunk(from_, TOKEN_POOL);
                unchecked { ++i; }
            }
        }
    }

    // _reorder function reorders the tokenId in the FILO chunk stack
    function _reorder(address from_, uint256 tokenId_, uint256 posTo_) internal virtual {
        // We only allow reorders of tokenIds
        require(TOTAL_CHUNKS() >= tokenId_, "ERC404: _reorder not tokenId");

        uint256 _currTokenIndex = chunkToOwners[tokenId_].index;
        
        // If it's the same index, just return
        if (_currTokenIndex == posTo_) return;
        
        address _owner = chunkToOwners[tokenId_].owner;
        uint256 _activeIndex = ownerToActiveLength[from_] - 1;

        require(_owner == from_, "ERC404: _reorder incorrect owner");
        require(_activeIndex >= posTo_, "ERC404: _reorder out of bounds");

        // swap the positions of tokenId_ and posTo_ internally
        uint32 _tokenIdAtPosToBefore = ownerToChunkIndexes[from_][posTo_];
        ownerToChunkIndexes[from_][_currTokenIndex] = _tokenIdAtPosToBefore;
        ownerToChunkIndexes[from_][posTo_] = uint32(tokenId_);

        // now, rewrite the location lookup at chunk data
        chunkToOwners[_tokenIdAtPosToBefore].index = uint32(_currTokenIndex);
        chunkToOwners[tokenId_].index = uint32(posTo_);

        emit ChunkReordered(from_, tokenId_, _currTokenIndex, posTo_);
    }

    // NOTE: REMOVE THIS AFTER TESTING
    function testMint(address to_, uint256 amount_) public virtual {
        _mint(to_, amount_);
    }

    function burn(uint256 amtOrTokenId_) public virtual {
        // If it's an NFT, it must be owned by the sender.
        if (TOTAL_CHUNKS() >= amtOrTokenId_) {
            address _owner = chunkToOwners[amtOrTokenId_].owner;
            require(_owner == msg.sender, "ERC404: burn not from owner");
        }

        _burn(msg.sender, amtOrTokenId_);   
    }

    function reorder(uint256 tokenId_, uint256 posTo_) public virtual {
        // We assume that the input is a tokenId. It gets valiated in _reorder.
        // Here, we validate the owner.
        address _owner = chunkToOwners[tokenId_].owner;
        require(_owner == msg.sender, "ERC404: reorder not from owner");

        _reorder(msg.sender, tokenId_, posTo_);
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
        if (TOTAL_CHUNKS() > _initializedChunkIndex) {
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
                    uint32(_lastActiveLengthTo)
                );

                // Then, we increment the active length
                unchecked {
                    ownerToActiveLength[to_]++;
                }

                // Finally, we set the minted tokenId to the reactivated array slot
                ownerToChunkIndexes[to_][_lastActiveLengthTo] = uint32(_initializedChunkIndex);
            }

            else {
                // We don't have available initialized slots to reuse. Here, we will push to the array.
                // First, set the new owner and index of the token. The index will be the current total length.
                chunkToOwners[_initializedChunkIndex] = ChunkInfo(
                    to_,
                    uint32(_totalLengthTo)
                );

                // Then, we increment the active length
                unchecked {
                    ownerToActiveLength[to_]++;
                }

                // Finally, we push the minted tokenId to the newly initialized array slot
                ownerToChunkIndexes[to_].push(uint32(_initializedChunkIndex));
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
            uint32 _tokenId = ownerToChunkIndexes[TOKEN_POOL][_redeemIndex]; 

            // Chunk index optimization - use slots if available
            uint256 _totalLengthTo = ownerToChunkIndexes[to_].length;
            uint256 _lastActiveLengthTo = ownerToActiveLength[to_];

            // Check if we have available intialized slots to reuse
            if (_totalLengthTo > _lastActiveLengthTo) {
                // We reuse the initialized slots
                // Ownership change of chunk
                chunkToOwners[_tokenId] = ChunkInfo(
                    to_,
                    uint32(_lastActiveLengthTo)
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
                    uint32(_totalLengthTo)
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
    function _poolChunk(address from_, address pool_) internal virtual {
        // Find the FILO tokenId for the address based on the active length
        uint256 _activeLengthFrom = ownerToActiveLength[from_];

        if (_activeLengthFrom == 0) return; 

        uint256 _lastIndex = _activeLengthFrom - 1;
        uint256 _tokenId = ownerToChunkIndexes[from_][_lastIndex];

        // Decrease the owner's active length 
        ownerToActiveLength[from_]--;

        // Delete approvals
        delete getApproved[_tokenId];

        // Now, we need to add the token into the pool with slot optimization
        uint256 _totalLength = ownerToChunkIndexes[pool_].length;
        uint256 _activeLength = ownerToActiveLength[pool_];

        // Available slots check
        if (_totalLength > _activeLength) {
            // We use available slot
            chunkToOwners[_tokenId] = ChunkInfo(
                pool_,
                uint32(_activeLength)
            );

            unchecked { 
                ownerToActiveLength[pool_]++;
            }

            ownerToChunkIndexes[pool_][_activeLength] = uint32(_tokenId);
        }

        else {
            // We initialize a new slot
            chunkToOwners[_tokenId] = ChunkInfo(
                pool_,
                uint32(_totalLength)
            );

            unchecked {
                ownerToActiveLength[pool_]++;
            }

            ownerToChunkIndexes[pool_].push(uint32(_tokenId));
        }

        // Emit ERC721 Transfer
        _emitERC721Transfer(from_, pool_, _tokenId);
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
                    uint32(_activeLengthTo)
                );

                unchecked { 
                    ownerToActiveLength[to_]++;
                }

                ownerToChunkIndexes[to_][_activeLengthTo] = uint32(_tokenToSwap);
            }

            else {
                // Initialize a new slot
                chunkToOwners[_tokenToSwap] = ChunkInfo(
                    to_,
                    uint32(_totalLengthTo)
                );

                unchecked {
                    ownerToActiveLength[to_]++;
                }

                ownerToChunkIndexes[to_].push(uint32(_tokenToSwap));
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
        // if (!whitelisted[from_] && s_isChunkProcessor(to_)) {
        if (ownerToActiveLength[from_] > 0 && _isChunkProcessor(to_)) {
            // We will use _swapSlot flow and then return before the subsequent flow
            uint256 _chunkDiffFrom = 
                (_startBalFrom / CHUNK_SIZE()) - 
                (balanceOf[from_] / CHUNK_SIZE());
            
            uint256 _chunkDiffTo = 
                (balanceOf[to_] / CHUNK_SIZE()) - 
                (_startBalTo / CHUNK_SIZE());

            // @0xinu: im passing out. handle wl->nwl nwl->wl cases
            _chunkDiffFrom = _min(_chunkDiffFrom, ownerToActiveLength[from_]);
            
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
                        _poolChunk(from_, TOKEN_POOL);
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
        // if (!whitelisted[from_] && ownerToActiveLength[from_] > 0) {
        if (ownerToActiveLength[from_] > 0) {
            uint256 _chunkDiffFrom = 
                (_startBalFrom / CHUNK_SIZE()) - 
                (balanceOf[from_] / CHUNK_SIZE());
            
            if (_chunkDiffFrom > 0) {
                for (uint256 i = 0; i < _chunkDiffFrom;) {
                    _poolChunk(from_, TOKEN_POOL);
                    unchecked { ++i; }
                }
            }
        }

        // If to_ is not whitelisted, we will redeem chunks for him.
        if (_isChunkProcessor(to_)) {
            uint256 _chunkDiffTo = 
                (balanceOf[to_] / CHUNK_SIZE()) - 
                (_startBalTo / CHUNK_SIZE()); 
            
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

        // We're transferring a chunk, so, an ERC20 transfer of CHUNK_SIZE() is made
        balanceOf[from_] -= CHUNK_SIZE();

        unchecked { 
            balanceOf[to_] += CHUNK_SIZE();
        }

        _emitERC20Transfer(from_, to_, CHUNK_SIZE());

        // @0xinu: 20240221: I'm removing this because we can handle uneven activeLength cases etc. now. But we need to test it.
        // // Now, since whitelisted addresses can't handle ERC721-chunks
        // // We're not gonna allow transfers of chunks to them either.
        // require(!whitelisted[from_], "ERC404: _chunkTransfer from whitelisted");
        // require(_isChunkProcessor(to_), "ERC404: _chunkTransfer to whitelisted");

        // Now, find the index of the tokenId_, and push it out of active state.
        uint32 _tokenIndex = chunkToOwners[tokenId_].index;
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
                uint32(_activeLengthTo)
            );

            unchecked {
                ownerToActiveLength[to_]++;
            }

            ownerToChunkIndexes[to_][_activeLengthTo] = uint32(tokenId_);
        }

        // There are no available slots, push a new one
        else {
            chunkToOwners[tokenId_] = ChunkInfo(
                to_,
                uint32(_totalLengthTo)
            );

            unchecked {
                ownerToActiveLength[to_]++;
            }

            ownerToChunkIndexes[to_].push(uint32(tokenId_));
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
    // The identifier of ERC20 or ERC721 is by checking amount with TOTAL_CHUNKS()
    function transferFrom(address from_, address to_, uint256 amtOrTokenId_) public virtual returns (bool) {
        // Determine if it's an amount or a tokenId
        if (TOTAL_CHUNKS() >= amtOrTokenId_) {
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
        require(TOTAL_CHUNKS() >= tokenId_, "ERC404: _safeTransferFrom invalid tokenId");

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

    // function approve handles both ERC20 and ERC721 approvals, identifed by TOTAL_CHUNKS()
    function approve(address operator_, uint256 amtOrTokenId_) public virtual returns (bool) {
        // Handle ERC721 approval
        if(TOTAL_CHUNKS() >= amtOrTokenId_) {
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
        uint32 _redeemId = ownerToChunkIndexes[TOKEN_POOL][_redeemIndex];

        // Replace the _owner's token index with _redeemId, and vice versa
        ownerToChunkIndexes[_owner][_tokenIndex] = _redeemId;
        ownerToChunkIndexes[TOKEN_POOL][_redeemIndex] = uint32(tokenId_);

        // Now, update the chunk storage to the new owners and indexes
        chunkToOwners[tokenId_] = ChunkInfo(
            TOKEN_POOL,
            uint32(_redeemIndex)
        );

        chunkToOwners[_redeemId] = ChunkInfo(
            _owner,
            uint32(_tokenIndex)
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

    // function _repopulateChunks is the internal handler for repopulating chunks of a user
    function _repopulateChunk(address target_) internal virtual {
        // find the balance of the user
        uint256 _balanceOfTarget = balanceOf[target_];

        // find the chunkDiff of the target from their balance
        uint256 _chunksEligible = _balanceOfTarget / CHUNK_SIZE();
        uint256 _activeChunks = ownerToActiveLength[target_];
        uint256 _chunkDiff = _chunksEligible - _activeChunks;

        // now, repopulate the chunks using a loop of _mintOrRedeem
        for (uint256 i = 0; i < _chunkDiff;) {
            _mintOrRedeem(target_);
            unchecked { ++i; }
        }
    }

    // function repopulateChunks is the external handler for a user-initiated repopulation request
    function repopulateChunk() external virtual {
        _repopulateChunk(msg.sender);
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
    function viewAllStorageSlots(address wallet_) public virtual view returns (uint32[] memory) {
        return ownerToChunkIndexes[wallet_];
    }

    // function balanceOfChunks returns the balance of chunks for a wallet
    function balanceOfChunks(address wallet_) public virtual view returns (uint256) {
        return ownerToActiveLength[wallet_];
    }

    // function walletOfOwner returns the active slots of ownerToChunkIndexes
    function walletOfOwner(address wallet_) public virtual view returns (uint32[] memory) {
        uint256 l = ownerToActiveLength[wallet_];
        uint32[] memory _chunks = new uint32[] (l);
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
        uint256 _availableRemainderFrom = balanceOf[_ownerFrom] % CHUNK_SIZE();
        uint256 _swapFee = (CHUNK_SIZE() / 100_000) * poolSwapRoyaltiesFee;
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
            uint32(_indexTo)
        );

        chunkToOwners[toId_] = ChunkInfo(
            _ownerFrom,
            uint32(_indexFrom)
        );

        // Swap their indexes!
        ownerToChunkIndexes[_ownerFrom][_indexFrom] = uint32(toId_);
        ownerToChunkIndexes[TOKEN_POOL][_indexTo] = uint32(fromId_);

        // Delete their approveds!
        delete getApproved[fromId_];
        delete getApproved[toId_];

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

/**
 * ERC404Wrapper is the BRIDGE version of ERC404. 
 * It is meant to be used for wrapping an ERC721 token and turning it into ERC404
 * and allowing ERC404 functionality for the ERC721 token.
 * 
 * Compared to ERC404 NATIVE, ERC404Wrapper has a few different things going on:
 * 1/ MINT and BURN functions are changed and are ERC721-only.
 * 2/ The bridge is to be created with constructor details that tell what the token is
*/

interface IERC721 {
    function transferFrom(address from_, address to_, uint256 tokenId_) external;
}

abstract contract ERC404Wrapper is ERC404PoolSwap {

    // Immutable values to be determined on constructor deployment
    address public immutable ERC721_INTERFACE;

    // Define the interface for the wrapper. A one-time operation that cannot be unchanged.
    constructor(address interface_) {
        ERC721_INTERFACE = interface_;
    }

    // Override _mint and _burn so that it doesn't do anything.
    function _mint(address, uint256) internal pure override(ERC404) { revert("disabled"); }
    function _burn(address, uint256) internal pure override(ERC404) { revert("disabled"); }

    // wrap is the ERC404Wrapper version of a mint. Please don't use _mint when using ERC404Wrapper
    function wrap(uint256 tokenId_) public virtual {
        // Transfer the NFT to this smart contract
        IERC721(ERC721_INTERFACE).transferFrom(msg.sender, address(this), tokenId_);

        // This should never happen
        address _ownerBefore = chunkToOwners[tokenId_].owner;
        require(_ownerBefore == address(0), "ERC404Wrapper: wrap owner exception");

        // Increment total supply
        totalSupply += CHUNK_SIZE();

        // Mint a CHUNK_SIZE of ERC20 to the wrapper
        unchecked {
            balanceOf[msg.sender] += CHUNK_SIZE(); // if the above addition succeded, this must succeed without overflowing
        }

        // Emit an ERC20 transfer
        _emitERC20Transfer(address(0), msg.sender, CHUNK_SIZE());

        // Now, mint the NFT equivalent
        uint256 _activeLength = ownerToActiveLength[msg.sender];
        uint256 _totalLength = ownerToChunkIndexes[msg.sender].length;

        // Mint by reusing initialized index
        if (_totalLength > _activeLength) {
            chunkToOwners[tokenId_] = ChunkInfo(
                msg.sender,
                uint32(_activeLength)
            );

            unchecked {
                ownerToActiveLength[msg.sender]++;
            }

            ownerToChunkIndexes[msg.sender][_activeLength] = uint32(tokenId_);
        }

        // Mint by pushing a new index
        else {
            chunkToOwners[tokenId_] = ChunkInfo(
                msg.sender,
                uint32(_totalLength)
            );

            unchecked {
                ownerToActiveLength[msg.sender]++;
            }

            ownerToChunkIndexes[msg.sender].push(uint32(tokenId_));
        }

        _emitERC721Transfer(address(0), msg.sender, tokenId_);
    }

    function wrapMany(uint256[] calldata tokenIds_) public virtual {
        uint256 l = tokenIds_.length;
        for (uint256 i = 0; i < l;) {
            wrap(tokenIds_[i]);
            unchecked { ++i; }
        }
    }

    // 
    function unwrap(uint256 tokenId_) public virtual {
        // First, make sure that the msg.sender is the owner
        address _owner = chunkToOwners[tokenId_].owner;
        require(_owner == msg.sender, "ERC404: unwrap incorrect owner");
        require(_owner != address(0), "ERC404: unwrap nonexistent token");

        // BURN a CHUNK_SIZE of ERC20 from the wrapper
        balanceOf[msg.sender] -= CHUNK_SIZE();

        unchecked { 
            totalSupply -= CHUNK_SIZE(); 
        }

        _emitERC20Transfer(msg.sender, address(0), CHUNK_SIZE());

        // Now, reorder the token to the top of the chunk stack
        uint256 _ownerActiveIndex = ownerToActiveLength[_owner] - 1;
        _reorder(_owner, tokenId_, _ownerActiveIndex);

        // Then, burn the chunk
        delete getApproved[tokenId_];
        delete chunkToOwners[tokenId_];

        unchecked { 
            ownerToActiveLength[msg.sender]--; // We assume this is > 0 because the owner has a chunk
        }

        _emitERC721Transfer(msg.sender, address(0), tokenId_);

        // Transfer the NFT back to the unwrapper
        IERC721(ERC721_INTERFACE).transferFrom(address(this), msg.sender, tokenId_);
    }

    function unwrapMany(uint256[] calldata tokenIds_) public virtual {
        uint256 l = tokenIds_.length;
        for (uint256 i = 0; i < l;) {
            unwrap(tokenIds_[i]);
            unchecked { ++i; }
        }
    }
}