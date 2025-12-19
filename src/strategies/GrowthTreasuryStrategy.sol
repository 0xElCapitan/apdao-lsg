// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";

/// @title GrowthTreasuryStrategy
/// @notice Strategy that forwards all received tokens to the Growth Treasury multisig
/// @dev Used for strategies where revenue should fund protocol growth initiatives
contract GrowthTreasuryStrategy is IStrategy, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the LSGVoter contract
    address public immutable override voter;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the Growth Treasury multisig
    address public growthTreasury;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when tokens are forwarded to the treasury
    /// @param token Address of the token forwarded
    /// @param amount Amount of tokens forwarded
    event Forwarded(address indexed token, uint256 amount);

    /// @notice Emitted when the treasury address is updated
    /// @param oldTreasury Previous treasury address
    /// @param newTreasury New treasury address
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /// @notice Emitted when tokens are rescued from the contract
    /// @param token Address of the token rescued
    /// @param to Address tokens were sent to
    /// @param amount Amount of tokens rescued
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Invalid address (zero address)
    error InvalidAddress();

    /// @notice No tokens to forward
    error NoTokensToForward();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the GrowthTreasuryStrategy
    /// @param _voter Address of the LSGVoter contract
    /// @param _growthTreasury Address of the Growth Treasury multisig
    constructor(address _voter, address _growthTreasury) {
        if (_voter == address(0)) revert InvalidAddress();
        if (_growthTreasury == address(0)) revert InvalidAddress();
        voter = _voter;
        growthTreasury = _growthTreasury;
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Update the Growth Treasury address
    /// @param _newTreasury New treasury address
    function setGrowthTreasury(address _newTreasury) external onlyOwner {
        if (_newTreasury == address(0)) revert InvalidAddress();
        address oldTreasury = growthTreasury;
        growthTreasury = _newTreasury;
        emit TreasuryUpdated(oldTreasury, _newTreasury);
    }

    /*//////////////////////////////////////////////////////////////
                          STRATEGY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute strategy: forward all tokens of given type to Growth Treasury
    /// @param token Address of the token to forward
    /// @return amount Amount of tokens forwarded
    function execute(address token) external override nonReentrant returns (uint256 amount) {
        amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) return 0;

        IERC20(token).safeTransfer(growthTreasury, amount);
        emit Forwarded(token, amount);
    }

    /// @notice Execute strategy for multiple tokens
    /// @param tokens Array of token addresses to process
    /// @return amounts Array of amounts forwarded for each token
    function executeAll(address[] calldata tokens) external override nonReentrant returns (uint256[] memory amounts) {
        amounts = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amount = IERC20(tokens[i]).balanceOf(address(this));
            if (amount > 0) {
                IERC20(tokens[i]).safeTransfer(growthTreasury, amount);
                amounts[i] = amount;
                emit Forwarded(tokens[i], amount);
            }
        }
    }

    /// @notice Emergency rescue function to recover stuck tokens
    /// @param token Address of the token to rescue
    /// @param to Address to send rescued tokens to
    /// @param amount Amount of tokens to rescue
    function rescueTokens(address token, address to, uint256 amount) external override onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        IERC20(token).safeTransfer(to, amount);
        emit TokensRescued(token, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the balance of a specific token in the strategy
    /// @param token Address of the token
    /// @return Balance of the token
    function tokenBalance(address token) external view override returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Check if this contract supports the IStrategy interface
    /// @return True always
    function supportsStrategy() external pure override returns (bool) {
        return true;
    }
}
