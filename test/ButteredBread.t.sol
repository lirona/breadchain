// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import "forge-std/StdJson.sol";
import {Test, console2} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from
    "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {CURVE_POOL_XDAI_BREAD} from "script/Registry.s.sol";
import {ICurveStableSwap} from "src/interfaces/ICurveStableSwap.sol";
import {ButteredBread} from "src/ButteredBread.sol";

uint256 constant XDAI_FACTOR = 10;

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
    }

    function testConfirmPoolXdai() public {
        assertEq(curvePoolXdai.name(), "BREAD / WXDAI");
        assertEq(curvePoolXdai.symbol(), "BUTTER");
    }
}
