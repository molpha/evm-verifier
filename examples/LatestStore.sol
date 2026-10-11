// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4 <0.9.0;

import {IVerifier} from "@molpha/evm-verifier/interfaces/IVerifier.sol";
import {MolphaLib} from "@molpha/evm-verifier/consumer/MolphaLib.sol";

/// @notice Kind A + per-source `Latest`: a permissionless store anyone may push updates into.
/// @dev `MolphaLib.Latest` carries no `sourceId` of its own, so tracking more than one source
///      REQUIRES a mapping keyed by source. Sharing one `Latest` across sources makes them fight,
///      each rejecting the other's updates as not-newer.
contract LatestStore {
    using MolphaLib for IVerifier;
    using MolphaLib for MolphaLib.Latest;

    IVerifier public immutable VERIFIER;
    uint32 public immutable MIN_SIGNATURES;
    uint64 public immutable MAX_AGE;

    mapping(bytes32 => bool) public allowedSource;
    mapping(bytes32 => MolphaLib.Latest) internal latest;
    mapping(bytes32 => bytes32) public value;

    error SourceNotAllowed(bytes32 sourceId);

    constructor(IVerifier verifier, bytes32[] memory sources, uint32 minSignatures, uint64 maxAge) {
        VERIFIER = verifier;
        MIN_SIGNATURES = minSignatures;
        MAX_AGE = maxAge;
        for (uint256 i; i < sources.length; ++i) {
            allowedSource[sources[i]] = true;
        }
    }

    /// @dev The allow-list is checked against an INDEPENDENT record, then the policy is built from
    ///      it. Building the policy out of `att.payload.sourceId` would make `MolphaLib`'s source
    ///      binding a tautology — the check would compare the value against itself.
    function submit(IVerifier.Attestation calldata att) external {
        bytes32 sourceId = att.payload.sourceId;
        if (!allowedSource[sourceId]) revert SourceNotAllowed(sourceId);

        VERIFIER.requireValid(
            att, MolphaLib.Policy({sourceId: sourceId, minSignatures: MIN_SIGNATURES, maxAge: MAX_AGE})
        );
        latest[sourceId].acceptNewer(att.payload);
        value[sourceId] = att.payload.value;
    }

    function lastTimestamp(bytes32 sourceId) external view returns (uint64) {
        return latest[sourceId].lastTimestamp;
    }
}
