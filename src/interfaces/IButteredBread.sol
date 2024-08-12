// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

/**
 * @title Breadchain Buttered Bread interface
 */
interface IButteredBread {
    error NotAllowListed();
    error NonTransferable();
    error InsufficientFunds();
    error InvalidValue();

    event AddButter(address _account, address _butter, uint256 _amount);
    event RemoveButter(address _account, address _butter, uint256 _amount);

    function initialize(
        address[] memory _liquidityPools,
        uint256[] memory _scalingFactors,
        string memory _name,
        string memory _symbol
    ) external;

    function balanceOfButter(address _account, address _butter) external returns (uint256 _balance);

    function deposit(address _butter, uint256 _amount) external;

    function withdraw(address _butter, uint256 _amount) external;
}
