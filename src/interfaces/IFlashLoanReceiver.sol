// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;
// @audit-info Solidity 0.8.20 includes PUSH0 opcode which could be not compatible with some EVM networks

// @audit-issue Bad used import, it should be imported in from the file is being used
import { IThunderLoan } from "./IThunderLoan.sol";

/**
 * @dev Inspired by Aave:
 * https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/interfaces/IFlashLoanReceiver.sol
 */
interface IFlashLoanReceiver {
    
    // @audit-info Missing Natspec
    function executeOperation(
        address token,          // @audit It is the token that's being borrowed
        uint256 amount,         // @audit It is the amount that's being borrowed
        uint256 fee,            // @audit It is the fee that's being paid
        address initiator,      // @audit It is the initiator of the flash loan
        bytes calldata params   // @audit They are the parameters that are being passed to the flash loan
    )
        external
        returns (bool);
}
