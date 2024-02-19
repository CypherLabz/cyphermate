// SPDX-License-Identifier: MIT
// Last update: 2024-02-18
pragma solidity ^0.8.20;

import { Ownable } from "../../access/Ownable.sol";

/**
 * ERC404 with a system of uninitialized and initialized array or mapping
 * transfers happen and everything happens using a array that tracks that array ish
 * the total token ids are capped at [] which is determined by total supply
 */

/**
 * About Events *~*~*~*~*
 * Events <Transfer> and <Approval> have conflicts. However, the amount of indexed 
 * parameters are different. Thus, we can emit the same signature and use log4 vs log3
 * in YUL assembly to emit accurate events with the same name and different indexed 
 * parameters.
 */

abstract contract ERC404 is Ownable { 
    // so, we do a journey. first, we define the events, which are needed

    // ERC20-like
    event ERC20Transfer(address indexed from, address indexed to, uint256 amount); // unused, see below
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    // ERC721-like
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event ERC721Approval(address indexed owner, address indexed spender, uint256 indexed id); // unused, below
    
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved); // used without asm

    // keccak256(abi.encodePacked("Transfer(address,address,uint256)"));
    bytes32 constant internal TRANSFER_EVENT_SIG =  
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    
    // keccak256(abi.encodePacked("Approval(address,address,uint256)"));
    bytes32 constant internal APPROVAL_EVENT_SIG = 
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    // Event Emitters
    function _emitERC20Transfer(address from_, address to_, uint256 amount_) internal virtual {
        assembly {
            mstore(0x0, amount_)
            log3(0x0, 0x20, TRANSFER_EVENT_SIG, from_, to_)
        }
    }

    function _emitERC721Transfer(address from_, address to_, uint256 tokenId_) internal virtual {
        assembly {
            log4(0x0, 0x20, TRANSFER_EVENT_SIG, from_, to_, tokenId_)
        }
    }

    function _emitERC20Approval(address owner_, address spender_, uint256 amount_) internal virtual {
        assembly {
            mstore(0x0, amount_)
            log3(0x0, 0x20, APPROVAL_EVENT_SIG, owner_, spender_)
        }
    }

    function _emitERC721Approval(address owner_, address spender_, uint256 tokenId_) internal virtual {
        assembly {
            log4(0x0, 0x20, APPROVAL_EVENT_SIG, owner_, spender_, tokenId_)
        }
    }

    // also, we're just gonna define some static metadata of the contract
    string public name;
    string public symbol;

    // i'm actually gonna define as well some more static-but-can-be-dynamic stuff
    uint8 public constant decimals = 18;

    // now, here are some variables that determine the starting layout of the mappings
    uint256 public constant totalChunks = 10000;
    uint256 public constant chunkSize = 1 ether;

    // in this case, the totalSupply is 1 * 10000 ether, which results in 10,000 supply
    function totalSupply() public virtual view returns (uint256) {
        return totalChunks * chunkSize;
    }

    // since we now know that the erc20 supply is 100m and the erc721 supply is 10k, we can
    // populate some data based on these logical assumptions
    uint256 public initializedChunkIndex; // starts at 0, tracks the initialized chunks

    // we assume a complete mint to an address, which then will need to be sent in a 
    // non-initialized way to a distributor (this case, it's an LP) which will then start 
    // initializing receivers of full-chunk token slabs
    struct ChunkInfo {
        address owner;
        uint96 index;
    }

    ChunkInfo[totalChunks] public chunkToOwners;
    
    // an index array for each user keeps track of which chunks the owner has
    // we make it a uint16 limiting totalChunks to 65535 and saving 16x gas on .push()
    mapping(address => uint16[]) public ownerToChunkIndexes;
    mapping(address => uint256) public ownerToActiveLength; // also acts as an erc721 balanceOf

    // now, we keep track of single-unit-of-accounts in an erc20 way
    mapping(address => uint256) public balanceOf;

    // add some allowance stuff for both erc20 and erc721
    mapping(address => mapping(address => uint256)) public allowance; // erc20
    mapping(uint256 => address) public getApproved; // erc721
    mapping(address => mapping(address => bool)) public isApprovedForAll; // erc721

    // constructor mints things to the owner
    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;

        // do a native erc20-mint to the deployer
        balanceOf[msg.sender] = totalSupply();

        // emit ERC20Transfer(address(0), msg.sender, totalSupply());
        _emitERC20Transfer(address(0), msg.sender, totalSupply());
    }

    // there's no burning for this collection. totalSupply is static. we have an address
    // that we define that will be the "pool" for the tokens
    address public constant TOKEN_POOL = 0x0000000000000000000000000000000004040404;
    
    // the token pool will be the holder for the tokens that go into the pool. 
    // tokens go into a pool when the sender loses a chunk and the receiver does not
    // create a chunk. thus, it goes into remainder land.

    // so, lets assume that the native distribution method is by the following operations:
    /**
     * 1. the deployer creates an LP that users will purchase
     * 2. the NFT counterpart is then minted by acquiring tokens from the minter
     */

    // thus, an LP-creation interaction must be done.
    // whitelist is a very easy and straightforward way in order to not mint ERC721's into 
    // addresses that don't really use it (like LPs) in order to save a lot of state operations
    event Whitelisted(address indexed target, bool allowed);

    mapping(address => bool) public whitelisted;
    
    function addToWhitelist(address target_, bool allowed_) external onlyOwner {
        whitelisted[target_] = allowed_;
        emit Whitelisted(target_, allowed_);
    }

    // after we have created a whitelisted operation, now, we can send the tokens over to an LP
    // the LP will do the minting for the users when they purchase the ERC404
    // for this, we now do transfer operations.

    // an rng creator to select the pooled token index. override or edit for your own rng logic.
    function _getRng() internal virtual view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, blockhash(block.number - 1))));
    }

    // function _mintOrRedeem either mints a token or retrieves it from the pool if we're fully minted
    function _mintOrRedeem(address to_) internal virtual {
        uint256 _initializedChunkIndex = initializedChunkIndex; // load gas savings for memory reuse

        // figure out of we're going to mint or redeem
        if (totalChunks > _initializedChunkIndex) {
            // this is a mint
            // first, find if the user has any initialized slots for us to consume
            uint256 _lastLengthTo = ownerToChunkIndexes[to_].length;
            uint256 _lastActiveLengthTo = ownerToActiveLength[to_];

            // if there are available initialized slots, use them
            if (_lastLengthTo > _lastActiveLengthTo) {
                chunkToOwners[_initializedChunkIndex] = ChunkInfo(
                    to_, 
                    uint96(_lastActiveLengthTo)
                );

                // increase the active length
                unchecked {
                    ownerToActiveLength[to_]++;
                }

                // lastly, change the tokenId at the index
                ownerToChunkIndexes[to_][_lastActiveLengthTo + 1] = uint16(_initializedChunkIndex);
            }

            // if there are no available initialized indexes, do a push operation
            else {
                chunkToOwners[_initializedChunkIndex] = ChunkInfo(
                    to_,
                    uint96(_lastLengthTo)
                );

                ownerToChunkIndexes[to_].push(uint16(_initializedChunkIndex));
            }

            // increment the initializedChunkIndex and active length
            unchecked {
                ownerToActiveLength[to_]++;
                initializedChunkIndex++;
            }

            // emit a mint
            // emit Transfer(address(0), to_, _initializedChunkIndex);
            _emitERC721Transfer(address(0), to_, _initializedChunkIndex);
        }

        else {
            // this is a redeem
            // first, we're going to find what token id we're gonna get through an rng function
            // uint256 _poolLen = ownerToChunkIndexes[TOKEN_POOL].length;
            uint256 _poolLen = ownerToActiveLength[TOKEN_POOL]; // chunk-reuse-optimization-length
            uint256 _rng = _getRng();
            uint256 _redeemIndex = _rng % _poolLen; // a number between 0 and the pool's length - 1
            uint16 _tokenId = ownerToChunkIndexes[TOKEN_POOL][_redeemIndex]; // the redeemed tokenId

            // check if to_ has any available slots. if has, use them.
            uint256 _lastLengthTo = ownerToChunkIndexes[to_].length;
            uint256 _lastActiveLengthTo = ownerToActiveLength[to_];

            // if there are available initialized slots, use them
            if (_lastLengthTo > _lastActiveLengthTo) {
                // ownership change of chunk
                chunkToOwners[_tokenId] = ChunkInfo(
                    to_,
                    uint96(_lastActiveLengthTo)
                );

                // increase active length
                unchecked {
                    ownerToActiveLength[to_]++;
                }

                // rewrite to initialized slot
                ownerToChunkIndexes[to_][_lastActiveLengthTo] = _tokenId;
            }

            // if there are no available initialized slots, do a push 
            else {
                // ownership change of chunk
                chunkToOwners[_tokenId] = ChunkInfo(
                    to_,
                    uint96(_lastLengthTo)
                );

                // push tokenId to a new slot
                ownerToChunkIndexes[to_].push(_tokenId);

                // increase active length
                unchecked {
                    ownerToActiveLength[to_]++;
                }
            }

            // now, we also need to remove the token from the pool's indexes
            if (_redeemIndex != _poolLen - 1) {
                // replace the to-be-redeemed index with the last index (phantom last)
                ownerToChunkIndexes[TOKEN_POOL][_redeemIndex] = ownerToChunkIndexes[TOKEN_POOL][_poolLen - 1];
            }

            // now, decrease the active index
            ownerToActiveLength[TOKEN_POOL]--;


            // // now, we also have to remove it from the pool's indexes
            // // if the index is not the last index
            // if (_redeemIndex != _poolLen - 1) {
            //     // replace the to-be-redeemed index with the last index
            //     ownerToChunkIndexes[TOKEN_POOL][_redeemIndex] = ownerToChunkIndexes[TOKEN_POOL][_poolLen - 1];
            // }

            // // remove the last index of the pool's chunkIndexes
            // ownerToChunkIndexes[TOKEN_POOL].pop();

            // sanity-check delete the token's existing approvals (there should be none)
            delete getApproved[_tokenId];

            // emit a transfer
            // emit Transfer(TOKEN_POOL, to_, uint256(_tokenId));
            _emitERC721Transfer(TOKEN_POOL, to_, uint256(_tokenId));
        }
    }

    // function _poolChunk takes a user's chunk and puts it into the pool in a FILO queue
    function _poolChunk(address from_) internal virtual {
        // find the FILO token id for the address
        uint256 _lastIndex = ownerToActiveLength[from_] - 1;
        uint256 _tokenId = ownerToChunkIndexes[from_][_lastIndex];

        // // now, pop the tracker for the address's tokens
        // ownerToChunkIndexes[from_].pop();

        // decrease the active length 
        ownerToActiveLength[from_]--;

        // delete the token's existing approvals
        delete getApproved[_tokenId];

        // // transfer the FILO'ed token id of from_ to the pool. optional burn for display by setting address(0) in event.
        // // the ownerOf equivalent moving
        // chunkToOwners[_tokenId] = ChunkInfo(
        //     TOKEN_POOL,
        //     uint96(ownerToChunkIndexes[TOKEN_POOL].length)
        // );

        // // we also need to store the index for gathering pool's tokens
        // ownerToChunkIndexes[TOKEN_POOL].push(uint16(_tokenId));

        // find the active index and the length of TOKEN_POOL
        uint256 _poolInitializedLength = ownerToChunkIndexes[TOKEN_POOL].length;
        uint256 _poolActiveLength = ownerToActiveLength[TOKEN_POOL];

        // there are initialized inactive slots for TOKEN_POOL to use
        if (_poolInitializedLength > _poolActiveLength) {
            // push the active length forwards by 1
            unchecked {
                ownerToActiveLength[TOKEN_POOL]++;
            }

            // we store the token id in the increased active length slot
            ownerToChunkIndexes[TOKEN_POOL][_poolActiveLength] = uint16(_tokenId);

            // now, _poolActiveLength is also the index that we will put our new token in
            chunkToOwners[_tokenId] = ChunkInfo(
                TOKEN_POOL,
                uint96(_poolActiveLength)
            );
        }

        // if there are no initialized inactive slots for TOKEN_POOL to use
        else {
            chunkToOwners[_tokenId] = ChunkInfo(
                TOKEN_POOL,
                uint96(_poolInitializedLength)
            );

            // push tokenId to new slot
            ownerToChunkIndexes[TOKEN_POOL].push(uint16(_tokenId));

            // increase active length
            unchecked { 
                ownerToActiveLength[TOKEN_POOL]++;
            }
        }

        // emit the pooling transfer
        // emit Transfer(from_, TOKEN_POOL, _tokenId);
        _emitERC721Transfer(from_, TOKEN_POOL, _tokenId);
    }

    function _swapSlots(address from_, address to_, uint256 amount_) internal virtual {

        if (amount_ == 0) return;

        // for amount
        for (uint256 i = 0; i < amount_;) {
            // amount_ here the the amount of chunks
            uint256 _lastIndexFrom = ownerToActiveLength[from_] - 1;
            uint256 _tokenToSwap = ownerToChunkIndexes[from_][_lastIndexFrom];

            // _tokenToSwap is the token that we are going to initate the swap
            // first, we need to figure out if the target needs to push, or he can reuse his index
            uint256 _lastLengthTo = ownerToChunkIndexes[to_].length;
            uint256 _lastActiveLengthTo = ownerToActiveLength[to_];

            // if there are available initialized indexes, use them
            if (_lastLengthTo > _lastActiveLengthTo) {
                // first, swap out the owner in chunkToOwners
                chunkToOwners[_tokenToSwap] = ChunkInfo(
                    to_,
                    uint96(_lastActiveLengthTo + 1)
                );

                // increase the active length
                unchecked { 
                    ownerToActiveLength[to_]++;
                }

                // and lastly, change the tokenId at the index
                ownerToChunkIndexes[to_][_lastActiveLengthTo + 1] = uint16(_tokenToSwap);
            }

            // if there are no avaialble initialized indexes, we do a push operation
            else {
                chunkToOwners[_tokenToSwap] = ChunkInfo(
                    to_,
                    uint96(_lastLengthTo)
                );

                ownerToChunkIndexes[to_].push(uint16(_tokenToSwap));

                // increase active length
                unchecked {
                    ownerToActiveLength[to_]++;
                }
            }

            // now, for the sender... 
            // i think we can actually just decrease the active length and that's it
            ownerToActiveLength[from_]--;

            _emitERC721Transfer(from_, to_, _tokenToSwap);

            unchecked { ++i; }
        }
    }
    
    // function _min returns the smaller value between a and b
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }

    // function _transfer is the handler for an ERC20-esque transfer
    function _transfer(address from_, address to_, uint256 amount_) internal virtual {
        // grab the balance of from_ and to_ before the balance manipulations
        uint256 _startBalFrom = balanceOf[from_];
        uint256 _startBalTo = balanceOf[to_];

        // first, we do a normal ERC20-esque transfer
        balanceOf[from_] -= amount_; 

        unchecked {
            // we repurpose the above checked subtraction to make sure this will not overflow
            balanceOf[to_] += amount_;
        }

        // emit ERC20Transfer(from_, to_, amount_);
        _emitERC20Transfer(from_, to_, amount_);

        // @0xinu this is broken rn, must fix 
        // storage-save-swap gas-optimized erc721-esque transfers
        if (!whitelisted[from_] && !whitelisted[to_]) {
            // do a storage-save-swap of data and then return, so that we don't trigger the bottom conditions
            uint256 _chunkDiffFrom = 
                (_startBalFrom / chunkSize) - 
                (balanceOf[from_] / chunkSize);

            uint256 _chunkDiffTo =
                (balanceOf[to_] / chunkSize) -
                (_startBalTo / chunkSize);
            
            uint256 _minDiff = _min(_chunkDiffFrom, _chunkDiffTo);

            _swapSlots(from_, to_, _minDiff);

            // there is an uneven amount of diffs
            if (_chunkDiffFrom != _chunkDiffTo) {
                if (_chunkDiffFrom > _chunkDiffTo) {
                    // more is to be pooled
                    uint256 _toBePooled = _chunkDiffFrom - _chunkDiffTo;
                    for (uint256 i = 0; i < _toBePooled;) {
                        _poolChunk(from_);
                        unchecked { ++i; }
                    }
                }

                if (_chunkDiffTo > _chunkDiffFrom) {
                    // more is to be mintedOrRedeemed
                    uint256 _toBeMintedOrRedeemed = _chunkDiffTo - _chunkDiffFrom;
                    for (uint256 i = 0; i < _toBeMintedOrRedeemed;) {
                        _mintOrRedeem(to_);
                        unchecked { ++i; }
                    }
                }
            }

            return;

            // if (_chunkDiffFrom == _chunkDiffTo && _chunkDiffFrom > 0) {
            //     // there is the same amount of chunk manipulations of from and to
            //     // in addition to that, the chunk difference is over 0
            //     // which means that manipulations must be made
            //     _swapSlots(from_, to_, _chunkDiffFrom);
            //     return;
            // }
        }

        // now, we have some ERC404-specific whitelist+erc721-esque techniques
        // whitelisted addresses dont have pseudo-phantom erc721-esque burns and mints
        if (!whitelisted[from_]) {
            uint256 _chunkDiff = 
                (_startBalFrom / chunkSize) - // the chunk size of the start
                (balanceOf[from_] / chunkSize); // chunk size of the end
            
            // if there's a chunk difference
            if (_chunkDiff > 0) {
                // we must burn (pool) their token to chunk amount
                for (uint256 i = 0; i < _chunkDiff;) {
                    _poolChunk(from_);
                    unchecked { ++i; }
                }
            }
        }

        // in the same way, we also have to check for the whitelisted of to and do the same thing, in reverse
        if (!whitelisted[to_]) {
            uint256 _chunkDiff = 
                (balanceOf[to_] / chunkSize) - // the chunk size of the end
                (_startBalTo / chunkSize); // the chunk size of the start

            // if there's a chunk difference
            if (_chunkDiff > 0) {
                // we must mint (from pool or initial) their token to chunk amount
                for (uint256 i = 0; i < _chunkDiff;) {
                    _mintOrRedeem(to_);
                    unchecked { ++i; }
                }
            }
        }
    }

    // function _chunkTransfer is the handler for a transfer of a chunk (erc721-like)
    function _chunkTransfer(address from_, address to_, uint256 tokenId_) internal virtual {
        // first, we must make sure that the chunk we are transferring is correctly from
        address _owner = chunkToOwners[tokenId_].owner;

        // require statements are the best
        require(_owner == from_, "ERC404: _chunkTransfer from incorrect owner");

        // now, do a standard erc20-esque transfer for a chunk
        balanceOf[from_] -= chunkSize;

        unchecked { 
            balanceOf[to_] += chunkSize;
        }

        // emit a erc20 transfer
        // emit ERC20Transfer(from_, to_, chunkSize);
        _emitERC20Transfer(from_, to_, chunkSize);

        // if i understand correctly, whitelisted addresses shouldn't be able to interact
        // with erc721-esque transfers. for non-pooled ever-increasing ID this may be ok but
        // for a pooled non-increasing ID system, this will break the system.
        require(!whitelisted[from_], "ERC404: _chunkTransfer whitelisted cannot use");
        require(!whitelisted[to_], "ERC404: _chunkTransfer whitelisted cannot receive");

        // erc721-esque transfer operations
        // find the token index of the token to be transferred from the sender
        uint96 _tokenIndex = chunkToOwners[tokenId_].index;
        uint256 _lastActiveIndex = ownerToActiveLength[_owner] - 1; // get the last active index

        // do enumerable-slot-swap if its not the last active index
        if (_tokenIndex != _lastActiveIndex) {
            // replace the to-be-transferred slot with the last slot of the active index
            ownerToChunkIndexes[_owner][_tokenIndex] = ownerToChunkIndexes[_owner][_lastActiveIndex];
        }

        // decrease the active length of the sender
        ownerToActiveLength[_owner]--;

        // // now, we start doing the erc721-esque transfer operation
        // // first, we must pop the current owner's index and delete their approveds
        // uint96 _tokenIndex = chunkToOwners[tokenId_].index;
        // uint256 _lastIndex = ownerToChunkIndexes[_owner].length - 1;

        // // do the enumerable-slot-swap if it's not the last index
        // if (_tokenIndex != _lastIndex) {
        //     ownerToChunkIndexes[_owner][_tokenIndex] = ownerToChunkIndexes[_owner][_lastIndex];
        // }

        // // pop the chunk index
        // ownerToChunkIndexes[_owner].pop();

        // delete the getApproved
        delete getApproved[tokenId_];

        // for a push, we need to check if the receiver has available initialized slots
        uint256 _lastLengthTo = ownerToChunkIndexes[to_].length;
        uint256 _lastActiveLengthTo = ownerToActiveLength[to_]; 

        // if there are available slots, use them
        if (_lastLengthTo > _lastActiveLengthTo) {
            chunkToOwners[tokenId_] = ChunkInfo(
                to_,
                uint96(_lastActiveLengthTo)
            );

            unchecked { 
                ownerToActiveLength[to_]++;
            }

            ownerToChunkIndexes[to_][_lastActiveLengthTo] = uint16(tokenId_);
        }

        // otherwise there are no available slots, we have to push
        else {
            chunkToOwners[tokenId_] = ChunkInfo(
                to_,
                uint96(_lastLengthTo)
            );

            ownerToChunkIndexes[to_].push(uint16(tokenId_));

            // increase active length
            unchecked { 
                ownerToActiveLength[to_]++;
            }
        }

        // emit a erc721 transfer
        // emit Transfer(from_, to_, tokenId_);
        _emitERC721Transfer(from_, to_, tokenId_);
    }

    // transfer etc operations\
    // an erc20-esque user-initiated transfer operation
    function transfer(address to_, uint256 amount_) public virtual returns (bool) {
        _transfer(msg.sender, to_, amount_);
        return true;
    }

    // @0xinu 2024-12-19 not in my optimal dev state so need to re-read this as well
    // a multi-handler for erc20-esque AND erc721-esque transferFrom operation, identified by tokenId
    function transferFrom(address from_, address to_, uint256 amtOrTokenId_) public virtual returns (bool) {

        // make sure we're not trying to mint a token (might be redundant)
        require(from_ != address(0), "ERC404: transferFrom from zero address");

        // make sure we're not trying to burn a token 
        require(to_ != address(0), "ERC404: transferFrom to zero address");

        // if the totalChunks is more than the amtOrTokenId_, this means its an erc721-esque transfer
        if (totalChunks > amtOrTokenId_) {

            // make sure that the owner of the token is from_
            require(from_ == chunkToOwners[amtOrTokenId_].owner, "ERC404: transferFrom from not owner");

            // if it is the correct from_ address, we have to check allowances
            require(
                msg.sender == from_ || // the sender must be the owner ||
                isApprovedForAll[from_][msg.sender] || // the sender must be an approved operator
                getApproved[amtOrTokenId_] == msg.sender, // the sender must have been approved for the token
                "ERC404: transferFrom not approved"
            );

            _chunkTransfer(from_, to_, amtOrTokenId_);
        }

        // otherwise, it means that it's an erc20-esque transfer
        else {
            // find out the allowance of the msg.sender
            uint256 _allowance = allowance[from_][msg.sender];

            // a gas-saving deduction of allowance if it is not .max
            if (_allowance != type(uint256).max) {
                allowance[from_][msg.sender] = _allowance - amtOrTokenId_; // gas saving minus operation
            }

            // transfer in an erc20-esque way
            _transfer(from_, to_, amtOrTokenId_);
        }

        return true;
    }

    // safeTransferFroms are a erc721-esque standard thus we can assume that amtOrTokenId will be within erc721-range only, otherwise we may be transferring erc20-esques but checking for erc721-esque receivability
    function _safeTransferFrom(address from_, address to_, uint256 amtOrTokenId_, bytes memory data_) internal virtual returns (bool) {
        require(totalChunks > amtOrTokenId_, "ERC404: _safeTransferFrom invalid ID");

        transferFrom(from_, to_, amtOrTokenId_);

        require(
            to_.code.length == 0 ||
                ERC721TokenReceiver(to_).onERC721Received(msg.sender, from_, amtOrTokenId_, data_) == 
                ERC721TokenReceiver.onERC721Received.selector,
            "ERC404: safeTransferFrom unsafe recipient"
        );

        return true;
    }

    function safeTransferFrom(address from_, address to_, uint256 amtOrTokenId_, bytes calldata data_) public virtual returns (bool) {
        return _safeTransferFrom(from_, to_, amtOrTokenId_, data_);
    }

    function safeTransferFrom(address from_, address to_, uint256 amtOrTokenId_) public virtual returns (bool) {
        return _safeTransferFrom(from_, to_, amtOrTokenId_, "");
    }

    // now that we have our transfer operations handled, we look to approval functions
    // function approve is a multi-handler for erc20-esque AND erc721-esque approve operation, identified by tokenId
    function approve(address operator_, uint256 amtOrTokenId_) public virtual returns (bool) {

        // if the totalChunks is more than amtOrTokenId_, this means it's an erc721-esque approval (amtOrTokenId_ is within chunk-range)
        if (totalChunks > amtOrTokenId_) {
            // do an erc721-esque approval
            // find the owner of the token
            address _owner = chunkToOwners[amtOrTokenId_].owner;

            // make sure the approver is authorized to approve the token
            require(
                _owner == msg.sender || // the approver must be the owner of the token
                isApprovedForAll[_owner][msg.sender], // or an approved operator
                "ERC404: approve from unallowed user"
            );
    
            getApproved[amtOrTokenId_] = operator_;

            // emit ERC721Approval(_owner, operator_, amtOrTokenId_);
            _emitERC721Approval(_owner, operator_, amtOrTokenId_);
        }

        // otherwise, it's an erc20-esque approval (amtOrTokenId_ is out of chunk-range)
        else {
            // do an erc20-esque approval
            allowance[msg.sender][operator_] = amtOrTokenId_;

            // emit Approval(msg.sender, operator_, amtOrTokenId_);
            _emitERC20Approval(msg.sender, operator_, amtOrTokenId_);
        }

        return true;
    }

    // setApprovalForAll is an erc721-specific approve 
    function setApprovalForAll(address operator_, bool approved_) public virtual {
        isApprovedForAll[msg.sender][operator_] = approved_;
        emit ApprovalForAll(msg.sender, operator_, approved_);
    }


    // standard views of owner and balance
    function ownerOf(uint256 tokenId_) public virtual view returns (address) {
        address _owner = chunkToOwners[tokenId_].owner;
        require(_owner != address(0), "ERC404: ownerOf token does not exist");
        return _owner;
    }

    // reroll operation
    // function _reroll is the internal handler for rerolling a token to the pool
    function _reroll(uint256 tokenId_) internal virtual {

        // make sure that the token actually exists
        address _owner = chunkToOwners[tokenId_].owner;
        require(_owner != address(0), "ERC404: _reroll non-existant token");

        // now, we have to create some reroll logic. there is no erc20 movement, so actually we can save some gas by not thinking about erc20 as the balances of chunks remain the same.
        
        // first, find the index of the user's token
        uint256 _indexToBePooled = chunkToOwners[tokenId_].index;

        // now, do pool RNG
        // uint256 _poolLen = ownerToChunkIndexes[TOKEN_POOL].length;
        uint256 _poolLen = ownerToActiveLength[TOKEN_POOL];
        uint256 _rng = _getRng();
        uint256 _redeemIndex = _rng % _poolLen; // a number between 0 and pool's length - 1
        uint16 _redeemId = ownerToChunkIndexes[TOKEN_POOL][_redeemIndex]; // we found the id

        // now, swap the IDs
        
        // swap the user's token to the pool's
        chunkToOwners[tokenId_] = ChunkInfo(
            TOKEN_POOL,
            uint96(_redeemIndex) // we reuse the redeem index as the new tokenId location
        );

        // we reuse the chunkIndex and store the swapped token into the pool
        ownerToChunkIndexes[TOKEN_POOL][_redeemIndex] = uint16(tokenId_); 

        // swap the redeemed ID with the index of the user
        chunkToOwners[_redeemId] = ChunkInfo(
            _owner,
            uint96(_indexToBePooled)
        );

        // we reuse the chunkIndex and store the swapped token into the user
        ownerToChunkIndexes[_owner][_indexToBePooled] = _redeemId;

        // now, emit a double transfer, indicating a reroll swap
        // emit Transfer(_owner, TOKEN_POOL, tokenId_); // owner -> pool
        // emit Transfer(TOKEN_POOL, _owner, _redeemId); // pool -> owner
        _emitERC721Transfer(_owner, TOKEN_POOL, tokenId_); // owner -> pool
        _emitERC721Transfer(TOKEN_POOL, _owner, _redeemId); // pool -> owner
    }

    // function reroll is the external handler for a user-initiated token reroll. we return a boolean in the fashion of erc20. 
    function reroll(uint256 tokenId_) public virtual returns (bool) {

        // make sure that the owner is the only one who can reroll.
        // technically, we can also allow approved users to reroll the token as well, but this is not added canonically.
        address _owner = chunkToOwners[tokenId_].owner;
        require(_owner == msg.sender, "ERC404: reroll not owner of token");

        _reroll(tokenId_);        

        return true;
    }

    // tokenuri (needs to be implemented)
    function tokenURI(uint256 tokenId_) public virtual view returns (string memory);

    // magic ERC165 selectors, this one is erc721-esque
    function supportsInterface(bytes4 interfaceId_) public view virtual returns (bool) {
        return
            interfaceId_ == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId_ == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId_ == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    function viewAllChunks(address wallet_) public view virtual returns (uint16[] memory) {
        return ownerToChunkIndexes[wallet_];
    }

    // walletOfOwner can be displayed by reading the entire array of ownerToChunkIndexes of the address
    function walletOfOwner(address wallet_) public view virtual returns (uint16[] memory) {
        uint256 l = ownerToActiveLength[wallet_];
        uint16[] memory _tokens = new uint16[] (l);
        for (uint256 i = 0; i < l;) {
            _tokens[i] = ownerToChunkIndexes[wallet_][i];
            unchecked { ++i; }
        }
        return _tokens;
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
