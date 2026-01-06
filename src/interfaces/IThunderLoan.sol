// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
// @audit-info Solidity 0.8.20 includes PUSH0 opcode which could be not compatible with some EVM networks

// @audit-issue Theinterface is not implemented in ThunderLoan
interface IThunderLoan {
    // @audit-issue The token parameter should be an IERC20
    function repay(address token, uint256 amount) external;
}
