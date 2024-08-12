// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

/**
 * @title Breadchain Buttered Bread interface
 */
interface IButteredBread {
    /// @notice Occurs when user does not have sufficient Butter to mint ButteredBread
    error InsufficientFunds();
    /// @notice Occurs when an invalid value is attempted to be used in setter functions
    error InvalidValue();
    /// @notice Occurs when attempting a deposit with a non sanctioned LP
    error NotAllowListed();
    /// @notice Occurs when attempting to transfer ButteredBread , a utility token for voting not meant for trading
    error NonTransferable();

    /// @notice Specifics how much LP Token (Butter) has been added  
    event AddButter(address _account, address _lp, uint256 _amount);
    /// @notice Specifics how much LP Token (Butter) has been removed
    event RemoveButter(address _account, address _lp, uint256 _amount);

    function initialize(
        address[] memory _liquidityPools,
        uint256[] memory _scalingFactors,
        string memory _name,
        string memory _symbol
    ) external;

    /// @notice Returns whether a given liquidity pool is Breadchain sanctioned or not 
    function allowlistedLPs(address _lp) external view returns (bool _allowed);

    /// @notice Returns the factor that determines how much ButteredBread should be minted for a Liquidity Pool token (Butter)
    function scalingFactors(address _lp) external view returns (uint256 _factor);

    /// @notice The amount of LP tokens (Butter) deposited for a an account
    function accountToLPBalances(address _account, address _lp) external view returns (uint256 _balance);

    /// @notice Deposits Butter (LP Tokens) and mints ButteredBread according to the respective LP scaling factor
    function deposit(address _lp, uint256 _amount) external;

    /// @notice Withdraws some amount of Butter (LP token) and burns an amount of the user's ButteredBread according to the respective scaling factor
    function withdraw(address _lp, uint256 _amount) external;

    /// @notice Defines a liquidity pool's status as sanctioned or unsanctioned by Breadchain
    function modifyAllowList(address _lp, bool _allowed) external;

    /// @notice Modifies how much ButteredBread should be minted for a Liquidity Pool token (Butter)
    function modifyScalingFactor(address _lp, uint256 _factor) external;
}
