// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import "forge-std/StdJson.sol";
import {Test, console2} from "forge-std/Test.sol";
import {CURVE_STABLE_SWAP_BUTTER} from "script/Registry.s.sol";
import {ButteredBread} from "src/ButteredBread.sol";

contract ButteredBreadTest is Test {
    ButteredBread public bb;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("gnosis"));

        address[] memory _liquidityPools = new address[](1);
        _liquidityPools[0] = CURVE_STABLE_SWAP_BUTTER;

        bb = new ButteredBread();
        bb.initialize(_liquidityPools);
    }
}
