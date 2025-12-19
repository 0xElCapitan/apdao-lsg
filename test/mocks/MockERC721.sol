// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title MockERC721
/// @notice Mock ERC721 token for testing NFT-based voting power
/// @dev Simulates apDAO seat NFT for testing
contract MockERC721 is ERC721 {
    uint256 private _tokenIdCounter;

    constructor() ERC721("Mock Seat NFT", "MSEAT") {}

    /// @notice Mint a new NFT to an address
    /// @param to Address to mint to
    /// @return tokenId The ID of the minted token
    function mint(address to) external returns (uint256 tokenId) {
        tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        _mint(to, tokenId);
    }

    /// @notice Mint multiple NFTs to an address
    /// @param to Address to mint to
    /// @param count Number of NFTs to mint
    function mintBatch(address to, uint256 count) external {
        for (uint256 i = 0; i < count; i++) {
            _mint(to, _tokenIdCounter);
            _tokenIdCounter++;
        }
    }

    /// @notice Burn an NFT
    /// @param tokenId Token ID to burn
    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }
}
