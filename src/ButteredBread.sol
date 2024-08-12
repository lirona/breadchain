// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC20VotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IButteredBread} from "src/interfaces/IButteredBread.sol";

/**
 * @title Breadchain Buttered Bread
 * @notice
 * @author Breadchain Collective
 * @custom:coauthor @RonTuretzky
 * @custom:coauthor @daopunk
 */
contract ButteredBread is ERC20VotesUpgradeable, OwnableUpgradeable, IButteredBread {
    mapping(address butter => bool allow) public allowlistedLPs;
    mapping(address account => mapping(address butter => uint256 balance)) public accountToLPBalances;
    mapping(address account => uint256 factor) public scalingFactors;

    modifier isAllowed(address _butter) {
        if (allowlistedLPs[_butter] != true) revert NotAllowListed();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address[] memory _liquidityPools) external initializer {
        __Ownable_init(msg.sender);
        for (uint256 i; i < _liquidityPools.length; ++i) {
            allowlistedLPs[_liquidityPools[i]] = true;
        }
    }

    /// @notice View account balance of LP Tokens
    function balanceOfButter(address _account, address _butter) external view returns (uint256 _balance) {
        _balance = accountToLPBalances[_account][_butter];
    }

    /// @notice Deposit LP tokens
    function deposit(address _butter, uint256 _amount) external virtual isAllowed(_butter) {
        _deposit(msg.sender, _butter, _amount);
    }

    /// @notice Withdraw LP tokens
    function withdraw(address _butter, uint256 _amount) external virtual {
        _withdraw(msg.sender, _butter, _amount);
    }

    /// @notice ButteredBread tokens are non-transferable
    function transfer(address, uint256) public virtual override returns (bool) {
        revert NonTransferable();
    }

    /// @notice ButteredBread tokens are non-transferable
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert NonTransferable();
    }

    function _deposit(address _account, address _butter, uint256 _amount) internal {
        uint256 beforeBalance = accountToLPBalances[_account][_butter];
        accountToLPBalances[_account][_butter] = beforeBalance + _amount;

        emit AddButter(_account, _butter, _amount);
    }

    function _withdraw(address _account, address _butter, uint256 _amount) internal {
        uint256 beforeBalance = accountToLPBalances[_account][_butter];
        if (_amount > beforeBalance) revert InsufficientFunds();

        accountToLPBalances[_account][_butter] = beforeBalance - _amount;
        IERC20(_butter).transfer(_account, _amount);

        emit RemoveButter(_account, _butter, _amount);
    }
}
