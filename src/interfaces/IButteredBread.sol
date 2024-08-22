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
    /// @notice Occurs when dependent variable is not set
    error Unset();

    /// @notice Specifics how much LP Token (Butter) has been added
    event AddButter(address _account, address _lp, uint256 _amount);
    /// @notice Specifics how much LP Token (Butter) has been removed
    event RemoveButter(address _account, address _lp, uint256 _amount);

    /**
     * @param liquidityPools sanctioned LPs
     * @param scalingFactors scaling factor on mint per sanctioned LP
     * Note: each scaling factor is a fixed point percent (e.g. 100 = 1X, 150 = 1.5X, 1000 = 10X)
     * @param name ERC20 token name
     * @param symbol ERC20 token symbol
     */
    struct InitData {
        address[] liquidityPools;
        uint256[] scalingFactors;
        string name;
        string symbol;
    }

    /**
     * @param balance Value of deposited Butter (LP tokens)
     * @param scalingFactor At the time of deposit or updated with `syncVotingWeight` function
     */
    struct LPData {
        uint256 balance;
        uint256 scalingFactor;
    }

    /// @notice initialize contract as TransparentUpgradeableProxy
    function initialize(InitData calldata _initData) external;

    /// @notice View total number of depositors
    function totalDepositors() external view returns (uint256 _totalDepositors);

    /// @notice View list depositors
    function listDepositors() external view returns (address[] memory _depositorList);

    /// @notice Returns whether a given liquidity pool is Breadchain sanctioned or not
    function allowlistedLPs(address _lp) external view returns (bool _allowed);

    /// @notice Returns the factor that determines how much ButteredBread should be minted for a Liquidity Pool token (Butter)
    function scalingFactors(address _lp) external view returns (uint256 _factor);

    /// @notice The amount of LP tokens (Butter) deposited for an account
    function accountToLPBalance(address _account, address _lp) external view returns (uint256 _balance);

    /// @notice Deposits Butter (LP Tokens) and mints ButteredBread according to the respective LP scaling factor
    function deposit(address _lp, uint256 _amount) external;

    /// @notice Withdraws some amount of Butter (LP token) and burns an amount of the user's ButteredBread according to the respective scaling factor
    function withdraw(address _lp, uint256 _amount) external;

    /// @notice Defines a liquidity pool's status as sanctioned or unsanctioned by Breadchain
    function modifyAllowList(address _lp, bool _allowed) external;

    /// @notice Modifies how much ButteredBread should be minted for a Liquidity Pool token (Butter)
    function modifyScalingFactor(address _lp, uint256 _factor, bool _sync) external;

    /// @notice Sync multiple voting weights with single LP scaling factor
    function syncVotingWeights(address[] calldata _account, address _lp) external;
}
