// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

/// @title DeployConstants
/// @notice Shared CREATE2 deployment parameters for cross-chain deterministic addresses.
/// @dev The predicted address depends on: CREATE2 factory, salt, init code (bytecode + constructor args),
///      and compiler settings. Use the same Foundry profile on every chain.
library DeployConstants {
    /// @dev Fixed salt for `Verifier` CREATE2 deployment.
    bytes32 internal constant VERIFIER_SALT = keccak256("MOLPHA_VERIFIER_BREBENESKUL");

    /// @dev Initial redundancy buffer passed to the `Verifier` constructor.
    uint256 internal constant REDUNDANCY_BUFFER = 2;
}
