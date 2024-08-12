// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC20VotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IButteredBread} from "src/interfaces/IButteredBread.sol";

/**
 * @title Breadchain Buttered Bread
 * @notice Deposit LP tokens (butter) to earn yield
 * @author Breadchain Collective
 * @custom:coauthor @RonTuretzky
 * @custom:coauthor @daopunk
 */
contract ButteredBread is ERC20VotesUpgradeable, OwnableUpgradeable, IButteredBread {
    mapping(address lp => bool allow) public allowlistedLPs;
    mapping(address lp => uint256 factor) public scalingFactors;
    mapping(address account => mapping(address lp => uint256 balance)) public accountToLPBalances;

    modifier isAllowed(address _lp) {
        if (allowlistedLPs[_lp] != true) revert NotAllowListed();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address[] memory _liquidityPools,
        uint256[] memory _scalingFactors,
        string memory _name,
        string memory _symbol
    ) external initializer {
        if (_liquidityPools.length != _scalingFactors.length) revert InvalidValue();
        __Ownable_init(msg.sender);
        __ERC20_init(_name, _symbol);
        for (uint256 i; i < _liquidityPools.length; ++i) {
            allowlistedLPs[_liquidityPools[i]] = true;
            scalingFactors[_liquidityPools[i]] = _scalingFactors[i];
        }
    }

    /// @notice Deposit LP tokens
    function deposit(address _lp, uint256 _amount) external virtual isAllowed(_lp) {
        _deposit(msg.sender, _lp, _amount);
    }

    /// @notice Withdraw LP tokens
    function withdraw(address _lp, uint256 _amount) external virtual {
        _withdraw(msg.sender, _lp, _amount);
    }

    /// @notice allow or deny LP token
    function modifyAllowList(address _lp, bool _allowed) external virtual onlyOwner {
        allowlistedLPs[_lp] = _allowed;
    }

    /// @notice set LP token scaling factor
    function modifyScalingFactor(address _lp, uint256 _factor) external virtual onlyOwner isAllowed(_lp) {
        if (_factor == 0) revert InvalidValue();
        scalingFactors[_lp] = _factor;
    }

    /// @notice ButteredBread tokens are non-transferable
    function transfer(address, uint256) public virtual override returns (bool) {
        revert NonTransferable();
    }

    /// @notice ButteredBread tokens are non-transferable
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert NonTransferable();
    }

    /// @notice Deposit LP tokens and mint ButteredBread with corresponding LP scaling factor
    function _deposit(address _account, address _lp, uint256 _amount) internal {
        uint256 beforeBalance = accountToLPBalances[_account][_lp];
        accountToLPBalances[_account][_lp] = beforeBalance + _amount;

        _mint(_account, _amount * scalingFactors[_lp]);
        if (this.delegates(_account) == address(0)) _delegate(_account, _account);

        emit AddButter(_account, _lp, _amount);
    }

    /// @notice Withdraw LP tokens and burn ButteredBread with corresponding LP scaling factor
    function _withdraw(address _account, address _lp, uint256 _amount) internal {
        uint256 beforeBalance = accountToLPBalances[_account][_lp];
        if (_amount > beforeBalance) revert InsufficientFunds();
        accountToLPBalances[_account][_lp] = beforeBalance - _amount;

        _burn(_account, _amount * scalingFactors[_lp]);
        IERC20(_lp).transfer(_account, _amount);

        emit RemoveButter(_account, _lp, _amount);
    }
}
