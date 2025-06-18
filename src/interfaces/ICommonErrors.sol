// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

/// @title Aggregators Registry Errors Interface
/// @notice Defines errors emitted by Aggregators Registry contract
interface ICommonErrors {
    error ZeroAddress();

    error ZeroValue();

    error AlreadyInitialized();
}
