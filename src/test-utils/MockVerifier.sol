// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4 <0.9.0;

import {IVerifier} from "../interfaces/IVerifier.sol";

/// @title MockVerifier
/// @notice A `verify` that returns whatever you configure, with no cryptography.
/// @dev For unit tests that exercise consumer logic rather than signature verification. Cast it:
///      `IVerifier(address(mock))`. It deliberately does NOT inherit `IVerifier`, which would
///      force stubbing a dozen unrelated registry functions; `MockVerifier.t.sol` asserts the
///      `verify` selector matches instead.
///
///      IMPORTANT: `verify` is `view` because `MolphaLib` reaches it through `STATICCALL`. It
///      therefore CANNOT record the arguments it was called with — any `SSTORE`/`TSTORE` would
///      revert the whole call. To assert on arguments, use `vm.expectCall` in your own test.
contract MockVerifier {
    bool internal _ok;
    uint8 internal _code;

    mapping(bytes32 => bool) internal _hasOverride;
    mapping(bytes32 => bool) internal _overrideOk;
    mapping(bytes32 => uint8) internal _overrideCode;

    constructor() {
        _ok = true;
        _code = 0;
    }

    /// @notice Set the result returned for every source without an override.
    function setResult(bool ok, uint8 code) external {
        _ok = ok;
        _code = code;
    }

    /// @notice Set the result returned for one `sourceId`, overriding `setResult`.
    function setResultFor(bytes32 sourceId, bool ok, uint8 code) external {
        _hasOverride[sourceId] = true;
        _overrideOk[sourceId] = ok;
        _overrideCode[sourceId] = code;
    }

    /// @notice Matches `IVerifier.verify`'s selector and shape; ignores `maxAge` entirely.
    function verify(IVerifier.Attestation calldata attestation, uint64)
        external
        view
        returns (bool success, uint8 code)
    {
        bytes32 sourceId = attestation.payload.sourceId;
        if (_hasOverride[sourceId]) return (_overrideOk[sourceId], _overrideCode[sourceId]);
        return (_ok, _code);
    }
}
