// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/// @title MultiTokenRouter
/// @notice Accumulates revenue from Vase subvalidator and forwards to LSGVoter
/// @dev Supports multiple token types with whitelisting for security
contract MultiTokenRouter is Ownable, Pausable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the LSGVoter contract that receives revenue
    address public voter;

    /// @notice Mapping of whitelisted token addresses
    mapping(address => bool) public whitelistedTokens;

    /// @notice Array of all whitelisted tokens for iteration
    address[] public tokenList;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a token's whitelist status changes
    /// @param token Address of the token
    /// @param status New whitelist status
    event TokenWhitelisted(address indexed token, bool status);

    /// @notice Emitted when revenue is received (for tracking purposes)
    /// @param token Address of the token received
    /// @param amount Amount received
    event RevenueReceived(address indexed token, uint256 amount);

    /// @notice Emitted when revenue is flushed to Voter
    /// @param token Address of the token flushed
    /// @param amount Amount flushed
    event RevenueFlushed(address indexed token, uint256 amount);

    /// @notice Emitted when the voter address is updated
    /// @param oldVoter Previous voter address
    /// @param newVoter New voter address
    event VoterUpdated(address indexed oldVoter, address indexed newVoter);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Token is not whitelisted for revenue
    error TokenNotWhitelisted(address token);

    /// @notice No revenue available to flush for this token
    error NoRevenueToFlush();

    /// @notice Invalid address provided (zero address)
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the router with a voter address
    /// @param _voter Address of the LSGVoter contract
    constructor(address _voter) {
        if (_voter == address(0)) revert InvalidAddress();
        voter = _voter;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Whitelist or remove a token from accepted revenue tokens
    /// @param _token Address of the token to whitelist/remove
    /// @param _status True to whitelist, false to remove
    function setWhitelistedToken(address _token, bool _status) external onlyOwner {
        if (_token == address(0)) revert InvalidAddress();

        // Add to list if newly whitelisted
        if (_status && !whitelistedTokens[_token]) {
            tokenList.push(_token);
        }

        whitelistedTokens[_token] = _status;
        emit TokenWhitelisted(_token, _status);
    }

    /// @notice Update the voter contract address
    /// @param _voter New voter address
    function setVoter(address _voter) external onlyOwner {
        if (_voter == address(0)) revert InvalidAddress();
        emit VoterUpdated(voter, _voter);
        voter = _voter;
    }

    /// @notice Pause the contract (emergency use)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Flush a specific token to the Voter
    /// @param _token Address of the token to flush
    /// @return amount Amount of tokens flushed
    function flush(address _token) external whenNotPaused returns (uint256 amount) {
        if (!whitelistedTokens[_token]) revert TokenNotWhitelisted(_token);

        amount = IERC20(_token).balanceOf(address(this));
        if (amount == 0) revert NoRevenueToFlush();

        IERC20(_token).safeApprove(voter, amount);
        ILSGVoter(voter).notifyRevenue(_token, amount);

        emit RevenueFlushed(_token, amount);
    }

    /// @notice Flush all whitelisted tokens to the Voter
    function flushAll() external whenNotPaused {
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            if (!whitelistedTokens[token]) continue;

            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount > 0) {
                IERC20(token).safeApprove(voter, amount);
                ILSGVoter(voter).notifyRevenue(token, amount);
                emit RevenueFlushed(token, amount);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get pending revenue for a specific token
    /// @param _token Address of the token to check
    /// @return Balance of tokens held by this contract
    function pendingRevenue(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /// @notice Get list of all whitelisted tokens
    /// @return Array of whitelisted token addresses
    function getWhitelistedTokens() external view returns (address[] memory) {
        return tokenList;
    }
}

/// @notice Interface for LSGVoter contract
interface ILSGVoter {
    /// @notice Notify voter of new revenue
    /// @param token Address of the revenue token
    /// @param amount Amount of revenue received
    function notifyRevenue(address token, uint256 amount) external;
}
