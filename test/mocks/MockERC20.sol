// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @notice Mock ERC20 token for testing revenue distribution
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    /// @notice Mint tokens to any address (for testing)
    /// @param to Address to mint tokens to
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Burn tokens from any address (for testing)
    /// @param from Address to burn tokens from
    /// @param amount Amount to burn
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    /// @notice Override decimals
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
