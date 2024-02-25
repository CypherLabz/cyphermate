// SPDX-License-Identifier: MIT
// Last update: 2024-02-26
pragma solidity ^0.8.20;

/**
 * SFT418Primary is the Primary contract in a duality design for a hybrid token 
 * implementation of ERC20 + ERC721.
 * 
 * The main reason that we are introducing a duality design is to make sure that
 * both ERC20 and ERC721 cover the standard spec entirely.
 * 
 * By using transferFrom internal overloading through an if-statement, we can 
 * introduce a multitude of edge-cases that could lead to high severity exploits.
 * 
 * Because of this, a duality design has been chosen instead.
 * 
 * Additionally, toggle functions are entirely user-initiated unless overriden.
 * This is for ERC404-esque Ownable functions.
 */

/**
 * ChunkProcessable is a supplimentary contract for SFT418 which manages chunk
 * processing eligibility. 
 */
abstract contract ChunkProcessable {

    event SetChunkProcessing(address indexed operator, address indexed target, bool indexed toggle);

    mapping(address => bool) internal chunkToggle;

    // Contract: default(off), toggled(on) || EOA: default(on), toggled(off)
    function _isChunkProcessor(address target_) internal virtual view returns (bool) {
        return target_.code.length == 0 ? !chunkToggle[target_] : chunkToggle[target_];
    }

    // Internal function so that people can use it for Ownable toggles
    function _setChunkToggle(address target_, bool toggle_) internal virtual {
        chunkToggle[target_] = toggle_;
        emit SetChunkProcessing(msg.sender, target_, toggle_);
    }

    // Note: I simplified this function for codesize reasons.
    function toggleChunkProcessing() public virtual {
        _setChunkToggle(msg.sender, !chunkToggle[msg.sender]);
    }
}

/**
 * SFT418 is a ERC20-ERC721 duality hybrid token design. 
 * 
 * It uses two contracts: ERC20+Storage (main) and ERC721 (dependent) in order to 
 * comply to the infinite range of EIP-20 and EIP-721 fuzzing.
 * 
 * It uses chunk processing (to be explained)
 */

interface ISFT418Pair {
    function emitTransfers(address from_, address to_, uint256[] memory tokenIds_) external;
}

abstract contract SFT418 is ChunkProcessable {

    /////////////////////////////////
    // Events ///////////////////////
    ///////////////////////////////// 

    // ERC20 Events
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed operator, uint256 amount);

    // SFT418-Specific Events
    event ChunkReordered(address indexed owner, uint256 indexed tokenId, 
    uint256 posFrom, uint256 posTo);

    /////////////////////////////////
    // Collection Metadata //////////
    /////////////////////////////////

    string public name;
    string public symbol;

    /////////////////////////////////
    // Collection Parameters ////////
    /////////////////////////////////

    // Override these functions to change their parameters
    function decimals() public virtual returns (uint8) { 
        return 18; 
    }
    function TOTAL_CHUNKS() public virtual returns (uint256) {
        return 10000;
    }
    function CHUNK_SIZE() public virtual returns (uint256) {
        return 1 ether;
    }
    function MAX_SUPPLY() public virtual returns (uint256) {
        return TOTAL_CHUNKS() * CHUNK_SIZE();
    }

    // TOKEN_POOL is the phantom address of the token pool. 418POOL in leetspeak.
    address public constant TOKEN_POOL = 0x0000000000000000000000000000000004189001;

    /////////////////////////////////
    // Collection Storage ///////////
    /////////////////////////////////
    
    // ERC20 Total Supply
    uint256 public totalSupply;

    // ERC20 Balances and Allowances
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ERC721 getApproved and isApprovedForAll
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    // [SFT418Pair] a REQUIRED pairing between SFT418 (ERC20) and SFT418Pair (ERC721)
    ISFT418Pair public NFT;

    // [SFT418Pair] Mint IDs. Override to change starting ID.
    uint256 public mintedTokens;
    function _startTokenId() internal virtual returns (uint256) {
        return 1; 
    }
    function _nextTokenId() internal virtual returns (uint256) {
        return mintedTokens + _startTokenId();
    }

    // [SFT418Pair] ChunkInfo packs owner and index together for optimization
    // (yes, I know, I can use packed uint256 + bitshift schema as well >.<)
    struct ChunkInfo {
        address owner;
        uint32 index;
    }

    // [SFT418Pair] Akin to ERC721 ownerOf mapping.
    mapping(uint256 => ChunkInfo) public chunkToOwners;

    // [SFT418Pair] Chunk Stack tracking for an owner.
    mapping(address => uint32[]) public ownerToChunkIndexes;

    // [SFT418Pair] Active Chunk Indxes for chunk stack optimization
    mapping(address => uint256) public ownerToActiveLength;

    /////////////////////////////////
    // Constructor //////////////////
    /////////////////////////////////

    // Basic Token Metadata Constructor
    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    // A REQUIRED initializer for implementation constructor to pair.
    // Incorrect pairing will cause subsequent functions to break entirely.
    function _initializeSFT418Pair(address pair_) internal virtual {
        NFT = ISFT418Pair(pair_);
    }

    /////////////////////////////////
    // Internal Helper Functions ////
    /////////////////////////////////

    // _calChunkDiff: (a,b) for sender = (before, after) || receiver = (after, before)
    function _calChunkDiff(uint256 a, uint256 b) internal virtual returns (uint256) {
        require(a > b, "SFT418: _chunkDiff input value exception"); // Optional require
        return (a / CHUNK_SIZE()) - (b / CHUNK_SIZE());
    }

    // _min returns the smaller value between 2 values
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }

    /////////////////////////////////
    // Internal Logic Functions /////
    /////////////////////////////////

    // _pushChunk and _popChunk are the bread and butter of chunk manipulation
    function _pushChunk(address to_, uint256 id_) internal virtual {
        // Get totalLength and activeLength of to_
        uint256 _totalLengthTo = ownerToChunkIndexes[to_].length;
        uint256 _activeLengthTo = ownerToActiveLength[to_];
        uint256 _pushIndex = _min(_totalLengthTo, _activeLengthTo);

        chunkToOwners[id_] = ChunkInfo(
            to_,
            uint32(_pushIndex)
        );

        unchecked {
            ownerToActiveLength[to_]++;
        }

        if (_totalLengthTo > _activeLengthTo) {
            ownerToChunkIndexes[to_][_pushIndex] = uint32(id_);
        }

        else {
            ownerToChunkIndexes[to_].push(uint32(id_));
        }
    }

    function _popChunk(address from_) internal virtual {
        ownerToActiveLength[from_]--;
    }

    // Internal NFT Minting and storage manipulations. Returns value to interface with  SFT418Pair
    function _NFTMintOrRedeem(address to_, uint256 amount_) internal virtual 
    returns (uint256) {

        uint256[] memory _tokenIds = new uint256[] (amount_);

        for (uint256 i = 0; i < amount_;) {

            // Load the minted NFT index
            uint256 _mintedTokens = mintedTokens;

            // Determine if we are minting or redeeming
            if (TOTAL_CHUNKS() > _mintedTokens) {
                // Mint a new token ~~~
                uint256 _nextId = _nextTokenId();            
                
                _pushChunk(to_, _nextId);
                
                unchecked {
                    mintedTokens++;
                }

                _tokenIds[i] = _nextId;
            }

            else {
                // Redeem an existing token from the pool ~~
                uint256 _redeemIndex = ownerToActiveLength[TOKEN_POOL] - 1;
                uint32 _redeemId = ownerToChunkIndexes[TOKEN_POOL][_redeemIndex];

                _pushChunk(to_, _redeemId);
                _popChunk(TOKEN_POOL);

                // A non-required sanity check of deleting getApproved (standard on transfer)
                delete getApproved[uint256(_redeemId)];

                _tokenIds[i] = _redeemId;
            }

            unchecked { ++i; }
        }
    }

    // function _NFTPoolChunk pools the active index chunk of the target
    function _NFTPoolChunk(address from_) internal virtual returns (uint256) {
        // Get active length 
        uint256 _activeLengthFrom = ownerToActiveLength[from_];

        // If there are no tokens to be pooled from the target, simply return
        if (_activeLengthFrom == 0) return 0; // NFT.emitTranfers will ignore tokenId 0

        // Get the token ID to be popped
        uint256 _tokenId = ownerToChunkIndexes[from_][_activeLengthFrom - 1];

        // Pop and delete approvals
        _popChunk(from_);
        delete getApproved[_tokenId];

        // Push chunk to pool
        _pushChunk(TOKEN_POOL, _tokenId);

        return _tokenId;
    }

    // function _NFTSwapSlots swaps the slot of from_ and to_, or does mint/pool 
    // as required. It is askin to a transfer, internally, with a controlled NFT flow
    // _NFTSwapSlots MUST work on the assumption that there activeIndexes > 0
    // and returns _tokenIds for NFT.emitEvents 
    function _NFTSwapSlots(address from_, address to_, uint256 amount_) internal virtual returns (uint256[] memory) {

        uint256[] memory _tokenIds = new uint256[] (amount_);
        
        for (uint256 i = 0; i < amount_;) {
            // Find the tokenId to swap
            uint256 _activeLengthFrom = ownerToActiveLength[from_];
            uint256 _tokenToSwap = ownerToChunkIndexes[from_][_activeLengthFrom - 1];

            // Push chunk to receiver
            _pushChunk(to_, _tokenToSwap);

            // Pop chunk from sender
            _popChunk(from_);
            delete getApproved[_tokenToSwap];

            _tokenIds[i] = _tokenToSwap;
            unchecked { ++i; }
        }

        return _tokenIds;
    }

    /////////////////////////////////
    // Functions ////////////////////
    /////////////////////////////////

    function _transfer(address from_, address to_, uint256 amount_) internal virtual {
        // Disallow targets to be address(0) as that's no longer a transfer
        require(from_ != address(0), "SFT418: _transfer from zero address");
        require(to_ != address(0), "SFT418: _transfer to zero address");

        // Store the before balances of from_ and to_ for chunkDiff comparisons
        uint256 _startBalFrom = balanceOf[from_];
        uint256 _startBalTo = balanceOf[to_];

        // ERC20 balance transfer
        balanceOf[from_] -= amount_;

        unchecked {
            balanceOf[to_] += amount_;
        }

        emit Transfer(from_, to_, amount_);

        if (ownerToActiveLength[from_] > 0 && // From must have chunks
            _isChunkProcessor(to_)) // To must receive chunks
        {
            // If so, we can simply swap the slots
            uint256 _chunkDiffFrom = _calChunkDiff(_startBalFrom, balanceOf[from_]);
            uint256 _chunkDiffTo = _calChunkDiff(balanceOf[to_], _startBalTo);

            // Recalculate chunkDiffFrom to account for disparity of chunks and balances
            // This is because we must swap only to the max of the index. 
            // Otherwise, we are swapping non-existent chunk-indexes.
            _chunkDiffFrom = _min(_chunkDiffFrom, ownerToActiveLength[from_]);

            // Then, we must also swap the smallest chunkDiff, to guarantee swap slots
            // are available, and we are not swapping non-existent chunk-indexes.
            uint256 _minDiff = _min(_chunkDiffFrom, _chunkDiffTo);

            // Swap the slots! (Chain the transfer events)
            NFT.emitTransfers(from_, to_, _NFTSwapSlots(from_, to_, _minDiff));


        }
    }

    // Native SFT418 minting uses incremental IDs. This only supports amount_, not ID.
    function _mint(address to_, uint256 amount_) internal virtual {

        // Load the starting balance of the receiver for chunk-size comparisons       
        uint256 _startBalTo = balanceOf[to_];

        // Make sure we don't exceed MAX_SUPPLY
        require(MAX_SUPPLY() >= (totalSupply + amount_), 
            "SFT418: _mint exceeds max supply");

        // Increment totalSupply and balanceOf 
        // Overflow check is not needed as it was checked in the require statement above
        unchecked {
            totalSupply += amount_;
            balanceOf[to_] += amount_;
        }

        // ERC20 Native Transfer Event
        emit Transfer(address(0), to_, amount_);

        // SFT418: ChunkProcessor Check and then Mint Chunks
        if (_isChunkProcessor(to_)) {

            // Calculate chunk differences and run ERC721 minting loop
            uint256 _chunkDiff = _calChunkDiff(balanceOf[to_], _startBalTo);

            // If there are chunks, operate on them
            if (_chunkDiff > 0) {

                // // Grab tokenIds to memory for batch event sending. 
                // uint256[] memory _tokenIds = new uint256[] (_chunkDiff);

                // // Manipulate the storage and return the tokenID manipulated to _tokenIds
                // for (uint256 i = 0; i < _chunkDiff;) {
                //     _tokenIds[i] = _NFTMintOrRedeem(to_);
                //     unchecked { ++i; }
                // }

                // Send event to SFT418Pair as a batch
                NFT.emitTransfers(address(0), to_, _NFTMintOrRedeem(to_, _chunkDiff));
            }
        }
    }

    // _burn function using amount_ as an input
    function _burn(address from_, uint256 amount_) internal virtual {
        // Get the starting balance for chunkDiff comparisons
        uint256 _startBalFrom = balanceOf[from_];

        // Do an ERC20 burn
        balanceOf[from_] -= amount_;

        unchecked { 
            totalSupply -= amount_;
        }

        emit Transfer(from_, address(0), amount_);

        // Calculate chunk diff
        uint256 _chunkDiff = _calChunkDiff(_startBalFrom, balanceOf[from_]);

        // If there are chunks, operate on them
        if (_chunkDiff > 0) {

            // Grab tokenIds to memory for batch event sending.
            uint256[] memory _tokenIds = new uint256[] (_chunkDiff);

            // Manipulate storage and write tokenId to _tokenIds
            for (uint256 i = 0; i < _chunkDiff;) {
                _tokenIds[i] = _NFTPoolChunk(from_);
                unchecked { ++i; }
            }

            // Send event to SFT418Pair as a batch
            NFT.emitTransfers(from_, address(0), _tokenIds);
        }
    }
}

contract SFT418Demo is SFT418 {
    
    constructor(string memory name_, string memory symbol_) 
        SFT418(name_, symbol_)
    {}


}