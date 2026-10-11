// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

/// @title DeployConstants
/// @notice Shared CREATE2 deployment parameters for cross-chain deterministic addresses.
/// @dev The predicted address depends on: CREATE2 factory, salt, init code (bytecode + constructor args),
///      and compiler settings. Use the same Foundry profile on every chain.
library DeployConstants {
    /// @dev Fixed salt for `Verifier` CREATE2 deployment.
    bytes32 internal constant VERIFIER_SALT = keccak256("MOLPHA_VERIFIER_BREBENESKUL");

    /// @dev Initial protocol admin (the `Verifier`'s `owner()`), pinned so the CREATE2 address is
    ///      a function of repo contents alone rather than of whoever runs the deploy script.
    ///      `AddNode.s.sol` requires `PRIVATE_KEY` to be this address.
    address internal constant PROTOCOL_ADMIN = 0x6c6bCc50dDAA6884125e1060DCd6363F8866380A;

    /// @dev Initial redundancy buffer passed to the `Verifier` constructor.
    uint256 internal constant REDUNDANCY_BUFFER = 2;
}
