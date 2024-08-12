// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

/**
 * @title Breadchain Buttered Bread interface
 */
interface IButteredBread {
    /// @notice Occurs when user does not have sufficient Butter to mint ButteredBread
    error InsufficientFunds();
    error InvalidValue();
    error NotAllowListed();
    error NonTransferable();

    event AddButter(address _account, address _lp, uint256 _amount);
    event RemoveButter(address _account, address _lp, uint256 _amount);

    function initialize(
        address[] memory _liquidityPools,
        uint256[] memory _scalingFactors,
        string memory _name,
        string memory _symbol
    ) external;

    function allowlistedLPs(address _lp) external view returns (bool _allowed);

    function scalingFactors(address _lp) external view returns (uint256 _factor);

    function accountToLPBalances(address _account, address _lp) external view returns (uint256 _balance);

    function deposit(address _lp, uint256 _amount) external;

    function withdraw(address _lp, uint256 _amount) external;

    function modifyAllowList(address _lp, bool _allowed) external;

    function modifyScalingFactor(address _lp, uint256 _factor) external;
}
