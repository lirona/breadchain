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

uint256 constant XDAI_FACTOR = 700; // 700% scaling factor; 7X
uint256 constant TOKEN_AMOUNT = 1000 ether;
address constant TEST_ADDR = address(0x69);

contract ButteredBreadTest is Test {
    ButteredBread public bb;
    ICurveStableSwap public curvePoolXdai;

    uint256 public fixedPointPercent;
    address[] public aliceList;

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

        fixedPointPercent = bb.FIXED_POINT_PERCENT();

        vm.label(address(bb), "ButteredBread");
        vm.label(GNOSIS_CURVE_POOL_XDAI_BREAD, "CurveLP_XDAI_BREAD");

        aliceList.push(ALICE);
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
        bb.modifyScalingFactor(TEST_ADDR, XDAI_FACTOR, false);
        bb.modifyAllowList(TEST_ADDR, true);
        assertTrue(bb.allowlistedLPs(TEST_ADDR));
    }

    function testAccessControlForOwnerRevert() public {
        bb.modifyScalingFactor(TEST_ADDR, XDAI_FACTOR, false);

        vm.prank(ALICE);
        vm.expectRevert();
        bb.modifyAllowList(TEST_ADDR, true);
        assertFalse(bb.allowlistedLPs(TEST_ADDR));
    }

    function testAccessControlForOwnerRevertUnset() public {
        vm.expectRevert();
        bb.modifyAllowList(TEST_ADDR, true);
        assertFalse(bb.allowlistedLPs(TEST_ADDR));
    }

    function testDeposit() public {
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), 0);
        assertEq(curvePoolXdai.balanceOf(address(bb)), 0);

        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);

        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), depositAmount);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), 0);
        assertEq(curvePoolXdai.balanceOf(address(bb)), 0);
    }

    function testWithdrawRevertAccessControl() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), depositAmount);
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
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);

        vm.prank(ALICE);
        vm.expectRevert();
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount + 1);
    }

    function testMintScalingFactor() public {
        assertEq(bb.scalingFactors(GNOSIS_CURVE_POOL_XDAI_BREAD), XDAI_FACTOR);

        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledMintAmount = depositAmount * XDAI_FACTOR / fixedPointPercent;

        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), scaledMintAmount);
    }

    function testBurnScalingFactor() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledBurnAmount = depositAmount * XDAI_FACTOR / fixedPointPercent;

        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), scaledBurnAmount);

        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), 0);
    }

    function testBurnScalingFactorWithUpdatedScalingFactor() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledBurnAmount = depositAmount * XDAI_FACTOR / fixedPointPercent;

        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), scaledBurnAmount);
        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, 1000, false);
        bb.syncVotingWeights(aliceList, GNOSIS_CURVE_POOL_XDAI_BREAD);

        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), 0);
    }

    function testBurnScalingFactorWithUpdatedScalingFactorPartialAmount() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledBurnAmount = depositAmount * XDAI_FACTOR / fixedPointPercent;

        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);
        assertEq(bb.balanceOf(ALICE), scaledBurnAmount);

        uint256 updatedScalingFactor = 1000;
        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, updatedScalingFactor, false);
        bb.syncVotingWeights(aliceList, GNOSIS_CURVE_POOL_XDAI_BREAD);

        uint256 quaterWithdraw = depositAmount / 4;
        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, quaterWithdraw);

        uint256 adjustedVotingWeight =
            ((depositAmount * updatedScalingFactor) - (quaterWithdraw * updatedScalingFactor)) / fixedPointPercent;
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
        // scaling factor range of 1X - 100X
        _s.initialFactor = bound(_s.initialFactor, 100, 100_000);
        _s.updatedFactor = bound(_s.updatedFactor, 100, 100_000);

        _s.deposit = bound(_s.deposit, 1 ether, 10_000 ether);
        vm.assume(_s.withdrawal <= _s.deposit);
        vm.assume(_s.withdrawal > 1 ether / 2);

        deal(GNOSIS_CURVE_POOL_XDAI_BREAD, ALICE, _s.deposit);
        vm.prank(ALICE);
        curvePoolXdai.approve(address(bb), _s.deposit);

        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.initialFactor, false);

        assertEq(bb.scalingFactors(GNOSIS_CURVE_POOL_XDAI_BREAD), _s.initialFactor);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), 0);
        assertEq(curvePoolXdai.balanceOf(ALICE), _s.deposit);
        _;
    }

    function testDepositAndMint(Scenario memory _s) public happyPath(_s) {
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit);

        assertEq(bb.balanceOf(ALICE), _s.deposit * _s.initialFactor / fixedPointPercent);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit);
        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
    }

    function testWithdrawAndBurn(Scenario memory _s) public happyPath(_s) {
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit);

        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit);
        assertEq(curvePoolXdai.balanceOf(ALICE), 0);

        uint256 preWithdrawBalance = bb.balanceOf(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.withdrawal);

        assertEq(bb.balanceOf(ALICE), preWithdrawBalance - (_s.withdrawal * _s.initialFactor / fixedPointPercent));
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit - _s.withdrawal);
        assertEq(curvePoolXdai.balanceOf(ALICE), _s.withdrawal);
    }

    function testWithdrawAndBurnWithUpdatedScalingFactor(Scenario memory _s) public happyPath(_s) {
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit);

        uint256 initDeposit = bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD);
        assertEq(initDeposit, _s.deposit);
        assertEq(bb.balanceOf(ALICE), _s.deposit * _s.initialFactor / fixedPointPercent);
        assertEq(curvePoolXdai.balanceOf(ALICE), 0);

        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.updatedFactor, false);

        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.withdrawal);

        uint256 maxDelta = 1;
        /// @dev accuracy within 1 wei
        assertApproxEqAbs(
            bb.balanceOf(ALICE),
            (_s.deposit * _s.updatedFactor / fixedPointPercent) - (_s.withdrawal * _s.updatedFactor / fixedPointPercent),
            maxDelta
        );

        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit - _s.withdrawal);
        assertEq(curvePoolXdai.balanceOf(ALICE), _s.withdrawal);
    }

    function testModifyScalingFactorAndSync(Scenario memory _s) public happyPath(_s) {
        vm.assume(_s.deposit % 2 == 0);

        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit / 2);
        /// @dev deposit twice to check non-duplication of depositors array
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit / 2);
        vm.stopPrank();

        uint256 doubleDeposit = _s.deposit * 2;
        deal(GNOSIS_CURVE_POOL_XDAI_BREAD, BOBBY, doubleDeposit);

        vm.startPrank(BOBBY);
        curvePoolXdai.approve(address(bb), doubleDeposit);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, doubleDeposit);
        vm.stopPrank();

        address[] memory depositors;
        depositors = bb.listDepositors();
        assertEq(depositors.length, 2);
        assertEq(depositors[0], ALICE);
        assertEq(depositors[1], BOBBY);

        /// @dev accuracy within 1 or 2 wei (due to fixed point division in test setup)
        uint256 maxDelta = 1;
        uint256 maxDeltaDouble = 2;
        assertApproxEqAbs(bb.balanceOf(ALICE), _s.deposit * _s.initialFactor / fixedPointPercent, maxDeltaDouble);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit);
        assertEq(bb.balanceOf(BOBBY), doubleDeposit * _s.initialFactor / fixedPointPercent);
        assertEq(bb.accountToLPBalance(BOBBY, GNOSIS_CURVE_POOL_XDAI_BREAD), doubleDeposit);

        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.updatedFactor, true);

        /// @dev accuracy within 1 wei
        assertApproxEqAbs(bb.balanceOf(ALICE), _s.deposit * _s.updatedFactor / fixedPointPercent, maxDeltaDouble);
        assertApproxEqAbs(bb.balanceOf(BOBBY), doubleDeposit * _s.updatedFactor / fixedPointPercent, maxDelta);
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
        bb.modifyScalingFactor(_contract, 69, false);
    }
}
