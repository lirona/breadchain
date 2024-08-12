// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import "script/Registry.s.sol";
import "forge-std/StdJson.sol";
import "forge-std/StdUtils.sol";
import {Test, console2} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from
    "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ICurveStableSwap} from "src/interfaces/ICurveStableSwap.sol";
import {ButteredBread} from "src/ButteredBread.sol";

uint256 constant XDAI_FACTOR = 7;
uint256 constant TOKEN_AMOUNT = 1000 ether;

contract ButteredBreadTest is Test {
    ButteredBread public bb;
    ICurveStableSwap public curvePoolXdai;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("gnosis"));
        curvePoolXdai = ICurveStableSwap(CURVE_POOL_XDAI_BREAD);

        address[] memory _liquidityPools = new address[](1);
        _liquidityPools[0] = address(curvePoolXdai);

        uint256[] memory _scalingFactors = new uint256[](1);
        _scalingFactors[0] = XDAI_FACTOR;

        bytes memory initData = abi.encodeWithSelector(
            ButteredBread.initialize.selector, _liquidityPools, _scalingFactors, "ButteredBread", "BB"
        );

        address bbImplementation = address(new ButteredBread());
        bb = ButteredBread(address(new TransparentUpgradeableProxy(bbImplementation, address(this), initData)));

        vm.label(address(bb), "ButteredBread");
        vm.label(CURVE_POOL_XDAI_BREAD, "CurveLP_XDAI_BREAD");
    }

    function _helperAddLiquidity(address _account, uint256 _amountT0, uint256 _amountT1) internal {
        uint256 min_lp_mint = 1;

        deal(BREAD, _account, _amountT0);
        deal(XDAI, _account, _amountT1);

        uint256[] memory liquidityAmounts = new uint256[](2);
        liquidityAmounts[0] = _amountT0;
        liquidityAmounts[1] = _amountT1;

        vm.startPrank(_account);
        IERC20(XDAI).approve(CURVE_POOL_XDAI_BREAD, type(uint256).max);
        IERC20(BREAD).approve(CURVE_POOL_XDAI_BREAD, type(uint256).max);
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
        bb.deposit(CURVE_POOL_XDAI_BREAD, curvePoolXdai.balanceOf(ALICE));
    }

    function testAccessControlForLpRevert() public {
        deal(BREAD, ALICE, TOKEN_AMOUNT);
        vm.prank(ALICE);
        vm.expectRevert();
        bb.deposit(BREAD, TOKEN_AMOUNT);
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
        assertEq(bb.accountToLPBalances(ALICE, CURVE_POOL_XDAI_BREAD), 0);
        assertEq(curvePoolXdai.balanceOf(address(bb)), 0);

        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(bb.accountToLPBalances(ALICE, CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(bb.accountToLPBalances(ALICE, CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);

        vm.prank(ALICE);
        bb.withdraw(CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), depositAmount);
        assertEq(bb.accountToLPBalances(ALICE, CURVE_POOL_XDAI_BREAD), 0);
        assertEq(curvePoolXdai.balanceOf(address(bb)), 0);
    }

    function testWithdrawRevertAccessControl() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(bb.accountToLPBalances(ALICE, CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);

        vm.prank(BOBBY);
        vm.expectRevert();
        bb.withdraw(CURVE_POOL_XDAI_BREAD, depositAmount);
    }

    function testWithdrawRevertOverdraw() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(bb.accountToLPBalances(ALICE, CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);

        vm.prank(ALICE);
        vm.expectRevert();
        bb.withdraw(CURVE_POOL_XDAI_BREAD, depositAmount + 1);
    }

    function testMintScalingFactor() public {
        assertEq(bb.scalingFactors(CURVE_POOL_XDAI_BREAD), XDAI_FACTOR);

        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledMintAmount = depositAmount * XDAI_FACTOR;

        vm.prank(ALICE);
        bb.deposit(CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), scaledMintAmount);
    }

    function testBurnScalingFactor() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledMintAmount = depositAmount * XDAI_FACTOR;

        vm.prank(ALICE);
        bb.deposit(CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), scaledMintAmount);

        vm.prank(ALICE);
        bb.withdraw(CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), 0);
    }

    function testTransferRevert() public {
        vm.startPrank(ALICE);
        bb.deposit(CURVE_POOL_XDAI_BREAD, curvePoolXdai.balanceOf(ALICE));

        uint256 bbBalance = bb.balanceOf(ALICE);
        assertGt(bbBalance, 0);

        vm.expectRevert();
        bb.transfer(BOBBY, bbBalance);
    }

    function testTransferFromRevert() public {
        vm.startPrank(ALICE);
        bb.deposit(CURVE_POOL_XDAI_BREAD, curvePoolXdai.balanceOf(ALICE));

        uint256 bbBalance = bb.balanceOf(ALICE);
        assertGt(bbBalance, 0);
        bb.approve(BOBBY, bbBalance);
        vm.stopPrank();

        vm.prank(BOBBY);
        vm.expectRevert();
        bb.transferFrom(ALICE, BOBBY, bbBalance);
    }
}

// contract ButteredBreadTest_Fuzz is ButteredBreadTest {}
