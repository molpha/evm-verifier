// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {MolphaLib} from "../../src/consumer/MolphaLib.sol";

/// @notice External surface over `MolphaLib`, whose functions take `calldata` and so cannot be
///         reached from a test's internal frame.
/// @dev Owns one `Latest`, one `Consumed`, and a per-source map, mirroring the three storage
///      shapes a real consumer uses.
contract MolphaLibHarness {
    using MolphaLib for IVerifier;

    MolphaLib.Latest internal latest;
    MolphaLib.Consumed internal consumed;
    mapping(bytes32 => MolphaLib.Latest) internal perSource;

    // ---- kind A ----

    function requireValid(IVerifier v, IVerifier.Attestation calldata att, MolphaLib.Policy calldata p) external view {
        v.requireValid(att, p);
    }

    function isValid(IVerifier v, IVerifier.Attestation calldata att, MolphaLib.Policy calldata p)
        external
        view
        returns (bool ok, uint8 code)
    {
        return v.isValid(att, p);
    }

    // ---- kind B ----

    function requireValidFields(
        IVerifier v,
        IVerifier.Attestation calldata att,
        MolphaLib.Policy calldata p,
        bytes calldata encodedFields
    ) external view {
        v.requireValid(att, p, encodedFields);
    }

    function isValidFields(
        IVerifier v,
        IVerifier.Attestation calldata att,
        MolphaLib.Policy calldata p,
        bytes calldata encodedFields
    ) external view returns (bool ok, uint8 code) {
        return v.isValid(att, p, encodedFields);
    }

    // ---- replay guards ----

    function replayKey(IVerifier.AttestationPayload calldata p) external pure returns (bytes32) {
        return MolphaLib.replayKey(p);
    }

    function acceptNewer(IVerifier.AttestationPayload calldata p) external {
        MolphaLib.acceptNewer(latest, p);
    }

    function acceptNewerFor(bytes32 sourceId, IVerifier.AttestationPayload calldata p) external {
        MolphaLib.acceptNewer(perSource[sourceId], p);
    }

    function consumeOnce(IVerifier.AttestationPayload calldata p) external {
        MolphaLib.consumeOnce(consumed, p);
    }

    function lastTimestamp() external view returns (uint64) {
        return latest.lastTimestamp;
    }

    function lastTimestampFor(bytes32 sourceId) external view returns (uint64) {
        return perSource[sourceId].lastTimestamp;
    }

    // ---- decoders ----

    function asUint256(bytes32 v) external pure returns (uint256) {
        return MolphaLib.asUint256(v);
    }

    function asInt256(bytes32 v) external pure returns (int256) {
        return MolphaLib.asInt256(v);
    }

    function asBool(bytes32 v) external pure returns (bool) {
        return MolphaLib.asBool(v);
    }

    function asAddress(bytes32 v) external pure returns (address) {
        return MolphaLib.asAddress(v);
    }
}
