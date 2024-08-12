// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

interface ICurveStableSwap {
    function name() external returns (string memory);
    function symbol() external returns (string memory);
}
