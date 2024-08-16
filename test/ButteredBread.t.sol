// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import "script/Constants.s.sol";
import "forge-std/StdJson.sol";
import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from
    "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ICurveStableSwap} from "src/interfaces/ICurveStableSwap.sol";
import {ButteredBread} from "src/ButteredBread.sol";
import {IButteredBread} from "src/interfaces/IButteredBread.sol";

uint256 constant XDAI_FACTOR = 7; // 700% scaling factor; X7
uint256 constant TOKEN_AMOUNT = 1000 ether;

contract ButteredBreadTest is Test {
    ButteredBread public bb;
    ICurveStableSwap public curvePoolXdai;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("gnosis"));
        curvePoolXdai = ICurveStableSwap(GNOSIS_CURVE_POOL_XDAI_BREAD);

        address[] memory _liquidityPools = new address[](1);
        _liquidityPools[0] = address(curvePoolXdai);

        uint256[] memory _scalingFactors = new uint256[](1);
        _scalingFactors[0] = XDAI_FACTOR;

        IButteredBread.InitData memory initData;
        initData.liquidityPools = _liquidityPools;
        initData.scalingFactors = _scalingFactors;
        initData.name = "ButteredBread";
        initData.symbol = "BB";

        bytes memory implementationData = abi.encodeWithSelector(ButteredBread.initialize.selector, initData);

        address bbImplementation = address(new ButteredBread());
        bb =
            ButteredBread(address(new TransparentUpgradeableProxy(bbImplementation, address(this), implementationData)));

        vm.label(address(bb), "ButteredBread");
        vm.label(GNOSIS_CURVE_POOL_XDAI_BREAD, "CurveLP_XDAI_BREAD");
    }

    function _helperAddLiquidity(address _account, uint256 _amountT0, uint256 _amountT1) internal {
        uint256 min_lp_mint = 1;

        deal(GNOSIS_BREAD, _account, _amountT0);
        deal(GNOSIS_XDAI, _account, _amountT1);

        uint256[] memory liquidityAmounts = new uint256[](2);
        liquidityAmounts[0] = _amountT0;
        liquidityAmounts[1] = _amountT1;

        vm.startPrank(_account);
        IERC20(GNOSIS_XDAI).approve(GNOSIS_CURVE_POOL_XDAI_BREAD, type(uint256).max);
        IERC20(GNOSIS_BREAD).approve(GNOSIS_CURVE_POOL_XDAI_BREAD, type(uint256).max);
        curvePoolXdai.add_liquidity(liquidityAmounts, min_lp_mint);
        curvePoolXdai.approve(address(bb), type(uint256).max);
        vm.stopPrank();
    }

    function _helperGetLpDeposit(address _account, address _lp) internal view returns (uint256 _butterBalance) {
        IButteredBread.LPData memory _lpData = bb.accountToLPData(_account, _lp);
        _butterBalance = _lpData.balance;
    }
}

contract ButteredBreadTest_MetaData is ButteredBreadTest {
    function testCurvePoolXdaiBread() public {
        assertEq(curvePoolXdai.name(), "BREAD / WXDAI");
        assertEq(curvePoolXdai.symbol(), "BUTTER");
    }

    function testButteredBread() public view {
        assertEq(bb.name(), "ButteredBread");
        assertEq(bb.symbol(), "BB");
    }
}

contract ButteredBreadTest_Unit is ButteredBreadTest {
    function setUp() public virtual override {
        super.setUp();
        _helperAddLiquidity(ALICE, TOKEN_AMOUNT, TOKEN_AMOUNT);
    }

    function testGotButter() public view {
        assertGt(curvePoolXdai.balanceOf(ALICE), TOKEN_AMOUNT * 3 / 2);
    }

    function testAccessControlForLp() public {
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, curvePoolXdai.balanceOf(ALICE));
    }

    function testAccessControlForLpRevert() public {
        deal(GNOSIS_BREAD, ALICE, TOKEN_AMOUNT);
        vm.prank(ALICE);
        vm.expectRevert();
        bb.deposit(GNOSIS_BREAD, TOKEN_AMOUNT);
    }

    function testAccessControlForOwner() public {
        bb.modifyAllowList(address(0x69), true);
        assertTrue(bb.allowlistedLPs(address(0x69)));
    }

    function testAccessControlForOwnerRevert() public {
        vm.prank(ALICE);
        vm.expectRevert();
        bb.modifyAllowList(address(0x69), true);
        assertFalse(bb.allowlistedLPs(address(0x69)));
    }

    function testDeposit() public {
        assertEq(_helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), 0);
        assertEq(curvePoolXdai.balanceOf(address(bb)), 0);

        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(_helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(_helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);

        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), depositAmount);
        assertEq(_helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), 0);
        assertEq(curvePoolXdai.balanceOf(address(bb)), 0);
    }

    function testWithdrawRevertAccessControl() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(_helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);

        vm.prank(BOBBY);
        vm.expectRevert();
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);
    }

    function testWithdrawRevertOverdraw() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(_helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);

        vm.prank(ALICE);
        vm.expectRevert();
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount + 1);
    }

    function testMintScalingFactor() public {
        assertEq(bb.scalingFactors(GNOSIS_CURVE_POOL_XDAI_BREAD), XDAI_FACTOR);

        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledMintAmount = depositAmount * XDAI_FACTOR;

        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), scaledMintAmount);
    }

    function testBurnScalingFactor() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledBurnAmount = depositAmount * XDAI_FACTOR;

        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), scaledBurnAmount);

        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), 0);
    }

    function testBurnScalingFactorWithUpdatedScalingFactor() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledBurnAmount = depositAmount * XDAI_FACTOR;

        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), scaledBurnAmount);
        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, 10);
        bb.syncVotingWeight(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD);

        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), 0);
    }

    function testBurnScalingFactorWithUpdatedScalingFactorPartialAmount() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledBurnAmount = depositAmount * XDAI_FACTOR;

        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);
        assertEq(bb.balanceOf(ALICE), scaledBurnAmount);

        uint256 updatedScalingFactor = 10;
        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, updatedScalingFactor);
        bb.syncVotingWeight(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD);

        uint256 quaterWithdraw = depositAmount / 4;
        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, quaterWithdraw);

        uint256 adjustedVotingWeight = (depositAmount * updatedScalingFactor) - (quaterWithdraw * updatedScalingFactor);
        assertEq(bb.balanceOf(ALICE), adjustedVotingWeight);
    }

    function testTransferRevertFuzzy(address _receiver) public {
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, curvePoolXdai.balanceOf(ALICE));

        uint256 bbBalance = bb.balanceOf(ALICE);
        assertGt(bbBalance, 0);

        vm.expectRevert();
        bb.transfer(_receiver, bbBalance);
    }

    function testTransferFromRevertFuzzy(address _operator, address _receiver) public {
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, curvePoolXdai.balanceOf(ALICE));

        uint256 bbBalance = bb.balanceOf(ALICE);
        assertGt(bbBalance, 0);
        bb.approve(_operator, bbBalance);
        vm.stopPrank();

        vm.prank(_operator);
        vm.expectRevert();
        bb.transferFrom(ALICE, _receiver, bbBalance);
    }
}

contract ButteredBreadTest_Fuzz is ButteredBreadTest {
    struct Scenario {
        uint256 deposit;
        uint256 withdrawal;
        uint256 initialFactor;
        uint256 updatedFactor;
    }

    modifier happyPath(Scenario memory _s) {
        _s.initialFactor = bound(_s.initialFactor, 1, 100);
        _s.updatedFactor = bound(_s.updatedFactor, 1, 100);
        _s.deposit = bound(_s.deposit, 1 ether, 10_000 ether);
        vm.assume(_s.withdrawal <= _s.deposit);
        vm.assume(_s.withdrawal > 1 ether / 2);

        deal(GNOSIS_CURVE_POOL_XDAI_BREAD, ALICE, _s.deposit);
        vm.prank(ALICE);
        curvePoolXdai.approve(address(bb), _s.deposit);

        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.initialFactor);

        assertEq(bb.scalingFactors(GNOSIS_CURVE_POOL_XDAI_BREAD), _s.initialFactor);
        assertEq(_helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), 0);
        assertEq(curvePoolXdai.balanceOf(ALICE), _s.deposit);
        _;
    }

    function testDepositAndMint(Scenario memory _s) public happyPath(_s) {
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit);

        assertEq(bb.balanceOf(ALICE), _s.deposit * _s.initialFactor);
        assertEq(_helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit);
        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
    }

    function testWithdrawAndBurn(Scenario memory _s) public happyPath(_s) {
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit);

        assertEq(_helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit);
        assertEq(curvePoolXdai.balanceOf(ALICE), 0);

        uint256 preWithdrawBalance = bb.balanceOf(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.withdrawal);

        assertEq(bb.balanceOf(ALICE), preWithdrawBalance - (_s.withdrawal * _s.initialFactor));
        assertEq(_helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit - _s.withdrawal);
        assertEq(curvePoolXdai.balanceOf(ALICE), _s.withdrawal);
    }

    function testWithdrawAndBurnWithUpdatedScalingFactor(Scenario memory _s) public happyPath(_s) {
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit);

        uint256 initDeposit = _helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD);
        assertEq(initDeposit, _s.deposit);
        assertEq(bb.balanceOf(ALICE), _s.deposit * _s.initialFactor);
        assertEq(curvePoolXdai.balanceOf(ALICE), 0);

        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.updatedFactor);
        uint256 preWithdrawal = _helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD);

        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.withdrawal);

        uint256 postWithdrawal = _helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD);

        assertEq(bb.balanceOf(ALICE), ((_s.deposit * _s.updatedFactor) - (_s.withdrawal * _s.updatedFactor)));
        assertEq(bb.balanceOf(ALICE), postWithdrawal * _s.updatedFactor);

        if (_s.updatedFactor > _s.initialFactor) {
            assertEq(
                bb.balanceOf(ALICE),
                (preWithdrawal * _s.initialFactor) + (_s.deposit * _s.updatedFactor) - (_s.deposit * _s.initialFactor)
                    - (_s.withdrawal * _s.updatedFactor)
            );
        }
        if (_s.updatedFactor < _s.initialFactor) {
            assertEq(
                bb.balanceOf(ALICE),
                (preWithdrawal * _s.initialFactor) - (_s.deposit * _s.initialFactor) + (_s.deposit * _s.updatedFactor)
                    - (_s.withdrawal * _s.updatedFactor)
            );
        }

        assertEq(_helperGetLpDeposit(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit - _s.withdrawal);
        assertEq(curvePoolXdai.balanceOf(ALICE), _s.withdrawal);
    }

    function testAccessControlForOwner(address _attacker, address _contract, bool _allow) public {
        vm.assume(_attacker != address(this));
        vm.prank(_attacker);
        vm.expectRevert();
        bb.modifyAllowList(_contract, _allow);
    }

    function testAccessControlOnNonExistent(address _contract) public {
        vm.assume(_contract != GNOSIS_CURVE_POOL_XDAI_BREAD);
        vm.expectRevert();
        bb.modifyScalingFactor(_contract, 69);
    }
}
