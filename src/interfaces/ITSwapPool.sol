// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;
// @audit-info Solidity 0.8.20 includes PUSH0 opcode which could be not compatible with some EVM networks

// @audit This is probably the interface of the pool on TSwap
// @audit-answered-question Why are we using the price of a pool token in WETH?
// @audit-answer We need to get the price of a token to calculate the fee of the flash loan
interface ITSwapPool {
    function getPriceOfOnePoolTokenInWeth() external view returns (uint256);
}
