// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4 <0.9.0;

import {IVerifier} from "../interfaces/IVerifier.sol";

/// @title MolphaLib
/// @notice The consumer-side obligations `Verifier.verify` deliberately refuses to own, as code.
/// @dev `Verifier.verify` is a total function: it authenticates a signature and nothing else. It
///      does not decide whether the source is one you asked for, whether the threshold is adequate
///      for your application, whether you have already acted on this attestation, or how to read
///      the 32-byte `value`. Each of those is a bug an integrator would otherwise write by hand.
///      This library is that checklist, layered strictly outside the verifier: it holds no storage,
///      touches no verifier state, and adds three calldata comparisons plus (for kind B) one
///      `keccak256` ahead of the EC math.
///
///      Two obligations here are security-relevant and easy to miss:
///
///      1. **Threshold floor.** `sourceId` commits the source configuration, NOT the threshold.
///         `signaturesRequired` is chosen by whoever requested the attestation. A consumer that
///         pins `sourceId` without its own floor accepts whatever threshold the protocol permits.
///         `Policy.minSignatures` is that floor and every integration must set it deliberately.
///      2. **Replay.** `verify` is `view`, so the same attestation verifies an unlimited number of
///         times, forever. Any state-mutating consumer needs `Latest` or `Consumed`.
///
///      Result codes: this library's codes occupy `0xF0-0xFF`; the verifier's `VerifyCodes.R_*`
///      table stays below `0xF0`, so `isValid` can return either space unambiguously. The library
///      deliberately does not import `VerifyCodes` — verifier codes are passed through opaquely.
library MolphaLib {
    /// @notice Disables the verifier's freshness check.
    /// @dev Not a neutral default. `maxAge` is the only absolute-freshness defence there is;
    ///      `acceptNewer` enforces monotonicity, not recency, so with `NO_MAX_AGE` a consumer's
    ///      FIRST accepted attestation may be arbitrarily old. Set this only when the application
    ///      genuinely has no recency requirement, or enforces one by other means.
    uint64 internal constant NO_MAX_AGE = 0;

    /// @notice What a consumer commits to, independent of what the attestation claims.
    /// @param sourceId The one source this consumer accepts. Required, non-zero.
    /// @param minSignatures Consumer threshold floor. Required, >= 1. Independent of the protocol
    ///        floor and may exceed it. Not committed under `sourceId` — see the note above.
    /// @param maxAge Freshness window in seconds, forwarded verbatim to the verifier.
    ///        `NO_MAX_AGE` disables the check.
    struct Policy {
        bytes32 sourceId;
        uint32 minSignatures;
        uint64 maxAge;
    }

    /// @notice Monotonic replay guard. One SSTORE, no unbounded growth. The default choice.
    /// @dev Holds no `sourceId`. A single `Latest` shared across two sources makes them fight:
    ///      each source's updates reject the other's as not-newer. Track per source with
    ///      `mapping(bytes32 => Latest)`. This is the most likely misuse of this library.
    struct Latest {
        uint64 lastTimestamp;
    }

    /// @notice Exact-once replay guard. One SSTORE per attestation, unbounded growth.
    /// @dev Use only when out-of-order acceptance is genuinely required; otherwise `Latest`.
    struct Consumed {
        mapping(bytes32 => bool) seen;
    }

    uint8 internal constant L_WRONG_SOURCE = 0xF0;
    uint8 internal constant L_THRESHOLD_POLICY = 0xF1;
    uint8 internal constant L_PAYLOAD_MISMATCH = 0xF2;
    uint8 internal constant L_INVALID_POLICY = 0xF3;

    error InvalidPolicy();
    error WrongSource(bytes32 expected, bytes32 actual);
    error ThresholdBelowPolicy(uint32 minimum, uint32 actual);
    error PayloadMismatch(bytes32 expected, bytes32 actual);
    error VerifyFailed(uint8 code);
    error NotNewer(uint64 last, uint64 actual);
    error AlreadyConsumed(bytes32 key);
    error MalformedWord(bytes32 value);

    // ---------------------------------------------------------------------
    // Kind A — `value` is the result itself, one ABI-encoded word
    // ---------------------------------------------------------------------

    /// @notice Validate an attestation against a policy, reverting on the first failure.
    /// @dev Check order is load-bearing: the three calldata comparisons run before the external
    ///      staticcall, so a garbage attestation never pays for EC math.
    function requireValid(IVerifier v, IVerifier.Attestation calldata att, Policy memory p) internal view {
        _requirePolicy(att, p);
        _requireVerified(v, att, p);
    }

    /// @notice Non-reverting form of `requireValid`, for batch and keeper contracts that must skip
    ///         a bad attestation without losing the whole transaction.
    /// @return ok True when the attestation satisfies both the policy and the verifier.
    /// @return code `0` on success. `0xF0`+ for a policy failure, otherwise the verifier's own code.
    function isValid(IVerifier v, IVerifier.Attestation calldata att, Policy memory p)
        internal
        view
        returns (bool ok, uint8 code)
    {
        code = _checkPolicy(att, p);
        if (code != 0) return (false, code);
        return v.verify(att, p.maxAge);
    }

    // ---------------------------------------------------------------------
    // Kind B — `value` is keccak256 over an unsigned payload carried alongside
    // ---------------------------------------------------------------------

    /// @notice Validate a kind B attestation, binding `encodedFields` to the signed digest.
    /// @param encodedFields `abi.encode(field_1, ..., field_n)` per the source's schema. Unsigned
    ///        calldata: its only guarantee is that it hashes to the signed `value`. Decode it with
    ///        `abi.decode` against the schema tuple; this library does not interpret it.
    function requireValid(
        IVerifier v,
        IVerifier.Attestation calldata att,
        Policy memory p,
        bytes calldata encodedFields
    ) internal view {
        _requirePolicy(att, p);
        bytes32 digest = keccak256(encodedFields);
        if (digest != att.payload.value) revert PayloadMismatch(att.payload.value, digest);
        _requireVerified(v, att, p);
    }

    /// @notice Non-reverting form of the kind B `requireValid`.
    function isValid(IVerifier v, IVerifier.Attestation calldata att, Policy memory p, bytes calldata encodedFields)
        internal
        view
        returns (bool ok, uint8 code)
    {
        code = _checkPolicy(att, p);
        if (code != 0) return (false, code);
        if (keccak256(encodedFields) != att.payload.value) return (false, L_PAYLOAD_MISMATCH);
        return v.verify(att, p.maxAge);
    }

    // ---------------------------------------------------------------------
    // Replay guards. Operate on consumer storage; this library holds none.
    // ---------------------------------------------------------------------

    /// @notice Accept only strictly newer attestations for one logical feed.
    /// @dev Call before any external interaction (checks-effects-interactions). As a side effect
    ///      this narrows the timestamp-grinding window: a grinded `canonicalTimestamp` must still
    ///      exceed the last one accepted.
    function acceptNewer(Latest storage l, IVerifier.AttestationPayload calldata p) internal {
        uint64 last = l.lastTimestamp;
        if (p.canonicalTimestamp <= last) revert NotNewer(last, p.canonicalTimestamp);
        l.lastTimestamp = p.canonicalTimestamp;
    }

    /// @notice Accept each attestation at most once, in any order.
    /// @dev Call before any external interaction (checks-effects-interactions).
    function consumeOnce(Consumed storage c, IVerifier.AttestationPayload calldata p) internal {
        bytes32 key = replayKey(p);
        if (c.seen[key]) revert AlreadyConsumed(key);
        c.seen[key] = true;
    }

    /// @notice Identity of one logical update: `keccak256(sourceId || canonicalTimestamp)`.
    /// @dev `registryVersion` is DELIBERATELY EXCLUDED. During the registry grace window the same
    ///      `(sourceId, canonicalTimestamp)` can be attested under two consecutive registry
    ///      versions with different selection groups. Both describe the same observation, and a
    ///      consumer must treat them as one update — including it would let the second version
    ///      replay the first. Both operands are fixed-size, so the packed encoding is unambiguous.
    function replayKey(IVerifier.AttestationPayload calldata p) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(p.sourceId, p.canonicalTimestamp));
    }

    // ---------------------------------------------------------------------
    // Kind A decoders (strict)
    // ---------------------------------------------------------------------

    /// @notice Read the word as `uint256`.
    /// @dev Also correct for any `uintN` schema — the ABI zero-extends to a full word. A consumer
    ///      downcasting to `uintN` must range-check that itself.
    function asUint256(bytes32 v) internal pure returns (uint256) {
        return uint256(v);
    }

    /// @notice Read the word as `int256`.
    /// @dev Also correct for any `intN` schema — the ABI sign-extends to a full word, so this
    ///      same-width reinterpretation preserves the value.
    function asInt256(bytes32 v) internal pure returns (int256) {
        return int256(uint256(v));
    }

    /// @notice Read the word as `bool`, rejecting any non-canonical encoding.
    function asBool(bytes32 v) internal pure returns (bool) {
        if (uint256(v) > 1) revert MalformedWord(v);
        return v != bytes32(0);
    }

    /// @notice Read the word as `address`, rejecting a dirty upper 96 bits.
    function asAddress(bytes32 v) internal pure returns (address) {
        if (uint256(v) >> 160 != 0) revert MalformedWord(v);
        return address(uint160(uint256(v)));
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    /// @dev The reverting half of the check order. Kept textually adjacent to `_checkPolicy`,
    ///      which must stay in lockstep with it; `MolphaLib.Policy.t.sol` asserts that parity.
    function _requirePolicy(IVerifier.Attestation calldata att, Policy memory p) private pure {
        if (p.sourceId == bytes32(0) || p.minSignatures == 0) revert InvalidPolicy();
        if (att.payload.sourceId != p.sourceId) revert WrongSource(p.sourceId, att.payload.sourceId);
        if (att.payload.signaturesRequired < p.minSignatures) {
            revert ThresholdBelowPolicy(p.minSignatures, att.payload.signaturesRequired);
        }
    }

    /// @dev The code-returning half of the check order. Returns `0` when every check passes.
    function _checkPolicy(IVerifier.Attestation calldata att, Policy memory p) private pure returns (uint8) {
        if (p.sourceId == bytes32(0) || p.minSignatures == 0) return L_INVALID_POLICY;
        if (att.payload.sourceId != p.sourceId) return L_WRONG_SOURCE;
        if (att.payload.signaturesRequired < p.minSignatures) return L_THRESHOLD_POLICY;
        return 0;
    }

    function _requireVerified(IVerifier v, IVerifier.Attestation calldata att, Policy memory p) private view {
        (bool ok, uint8 code) = v.verify(att, p.maxAge);
        if (!ok) revert VerifyFailed(code);
    }
}
