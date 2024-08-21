// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC20VotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IButteredBread} from "src/interfaces/IButteredBread.sol";

/**
 * @title Breadchain Buttered Bread
 * @notice Deposit Butter (LP tokens) to earn scaling rewards
 * @author Breadchain Collective
 * @custom:coauthor @RonTuretzky
 * @custom:coauthor @daopunk
 */
contract ButteredBread is ERC20VotesUpgradeable, OwnableUpgradeable, IButteredBread {
    uint256 public constant FIXED_POINT_PERCENT = 100;
    address public constant ZERO_ADDRESS = address(0);

    /// @notice Access control for Breadchain sanctioned liquidity pools
    mapping(address lp => bool allowed) public allowlistedLPs;
    /// @notice How much ButteredBread should be minted for a Liquidity Pool token (Butter)
    mapping(address lp => uint256 factor) public scalingFactors;
    /// @notice Butter balance by account and Liquidity Pool token deposited
    mapping(address account => mapping(address lp => LPData)) internal _accountToLPData;

    /// @notice List of accounts that have deposited 1 or more LP token types
    address[] public accountsList;

    modifier onlyAllowed(address _lp) {
        if (allowlistedLPs[_lp] != true) revert NotAllowListed();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @param _initData See IButteredBread
    function initialize(InitData calldata _initData) external initializer {
        if (_initData.liquidityPools.length != _initData.scalingFactors.length) revert InvalidValue();

        __Ownable_init(msg.sender);
        __ERC20_init(_initData.name, _initData.symbol);

        for (uint256 i; i < _initData.liquidityPools.length; ++i) {
            allowlistedLPs[_initData.liquidityPools[i]] = true;
            scalingFactors[_initData.liquidityPools[i]] = _initData.scalingFactors[i];
        }
    }

    /**
     * @notice The amount of LP tokens (Butter) deposited for a an account
     * @param _account Voting account
     * @param _lp Liquidity Pool token
     */
    function accountToLPData(address _account, address _lp) external view returns (LPData memory _lpData) {
        _lpData = _accountToLPData[_account][_lp];
    }

    /**
     * @notice The amount of LP tokens (Butter) deposited for a an account
     * @param _account Voting account
     * @param _lp Liquidity Pool token
     */
    function accountToLPBalance(address _account, address _lp) external view returns (uint256 _lpBalance) {
        _lpBalance = _accountToLPData[_account][_lp].balance;
    }

    /**
     * @notice Deposit LP tokens
     * @param _lp Liquidity Pool token
     * @param _amount Value of LP token
     */
    function deposit(address _lp, uint256 _amount) external onlyAllowed(_lp) {
        _deposit(msg.sender, _lp, _amount);
    }

    /**
     * @notice Withdraw LP tokens
     * @param _lp Liquidity Pool token
     * @param _amount Value of LP token
     */
    function withdraw(address _lp, uint256 _amount) external onlyAllowed(_lp) {
        _withdraw(msg.sender, _lp, _amount);
    }

    /**
     * @notice Allow or deny LP token
     * @param _lp Liquidity Pool token
     * @param _allowed Sanction status of LP token
     */
    function modifyAllowList(address _lp, bool _allowed) external onlyOwner {
        allowlistedLPs[_lp] = _allowed;
    }

    /**
     * @notice Set LP token scaling factor
     * @param _lp Liquidity Pool token
     * @param _factor Scaling percentage incentive of LP token (e.g. 100 = 1X, 150 = 1.5X, 1000 = 10X)
     * @param _sync Automatically sync all accounts voting weights with new factor
     * Note: avoid DDOS attack setting _sync to false and manually syncing with syncVotingWeights
     */
    function modifyScalingFactor(address _lp, uint256 _factor, bool _sync) external onlyOwner onlyAllowed(_lp) {
        _modifyScalingFactor(_lp, _factor);
        if (_sync) {
            for (uint256 i = 0; i < accountsList.length; i++) {
                _syncVotingWeight(accountsList[i], _lp);
            }
        }
    }

    /**
     * @notice Manually sync list of accounts with single LP scaling factor
     * @param _accounts List of voting accounts
     * @param _lp Liquidity Pool token
     */
    function syncVotingWeights(address[] calldata _accounts, address _lp) external onlyAllowed(_lp) {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _syncVotingWeight(_accounts[i], _lp);
        }
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
        if (_amount < 1 ether) revert InsufficientDeposit();

        if (_accountToLPData[_account][ZERO_ADDRESS].balance != 1) {
            /// @dev truthy value to check if account has ever made a deposit
            _accountToLPData[_account][ZERO_ADDRESS].balance = 1;
            accountsList.push(_account);
        }

        IERC20(_lp).transferFrom(_account, address(this), _amount);
        _accountToLPData[_account][_lp].balance += _amount;

        uint256 currentScalingFactor = scalingFactors[_lp];
        _accountToLPData[_account][_lp].scalingFactor = currentScalingFactor;

        _mint(_account, _amount * currentScalingFactor / FIXED_POINT_PERCENT);
        if (this.delegates(_account) == address(0)) _delegate(_account, _account);

        emit AddButter(_account, _lp, _amount);
    }

    /// @notice Withdraw LP tokens and burn ButteredBread with corresponding LP scaling factor
    function _withdraw(address _account, address _lp, uint256 _amount) internal {
        uint256 beforeBalance = _accountToLPData[_account][_lp].balance;
        if (_amount > beforeBalance) revert InsufficientFunds();

        _syncVotingWeight(_account, _lp);
        _accountToLPData[_account][_lp].balance -= _amount;

        _burn(_account, _amount * scalingFactors[_lp] / FIXED_POINT_PERCENT);
        IERC20(_lp).transfer(_account, _amount);

        emit RemoveButter(_account, _lp, _amount);
    }

    function _modifyScalingFactor(address _lp, uint256 _factor) internal {
        if (_factor < 100) revert InvalidValue();
        scalingFactors[_lp] = _factor;
    }

    /// @notice Sync voting weight with scaling factor
    function _syncVotingWeight(address _account, address _lp) internal {
        uint256 currentScalingFactor = scalingFactors[_lp];
        uint256 initialScalingFactor = _accountToLPData[_account][_lp].scalingFactor;

        if (currentScalingFactor != initialScalingFactor) {
            uint256 lpBalance = _accountToLPData[_account][_lp].balance;
            _accountToLPData[_account][_lp].scalingFactor = currentScalingFactor;

            if (lpBalance > 0) {
                if (currentScalingFactor > initialScalingFactor) {
                    _mint(
                        _account,
                        (lpBalance * currentScalingFactor - lpBalance * initialScalingFactor) / FIXED_POINT_PERCENT
                    );
                } else {
                    _burn(
                        _account,
                        (lpBalance * initialScalingFactor - lpBalance * currentScalingFactor) / FIXED_POINT_PERCENT
                    );
                }
            }
        }
    }
}
