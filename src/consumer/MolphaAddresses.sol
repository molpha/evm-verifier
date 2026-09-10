// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4 <0.9.0;

/// @title MolphaAddresses
/// @notice Canonical Molpha deployment addresses for consumers to pin.
/// @dev `Verifier` is deployed through Arachnid's deterministic-deployment proxy with a fixed salt
///      and a pinned constructor argument, so it lands on the same address on every chain where
///      that proxy exists and standard CREATE2 semantics apply. That is a claim about the chains
///      actually listed in `deployments.json` — NOT about every chain. Chains without the proxy, or
///      with non-standard CREATE2 (e.g. zkSync Era), must read `deployments.json` instead.
///
///      The address is a pure function of (factory, salt, creation code, constructor args). The
///      build therefore sets `bytecode_hash = "none"` so it does not also depend on comments,
///      natspec, or file paths. `test/deploy/MolphaAddresses.t.sol` re-derives everything here and
///      fails if any ingredient drifts.
library MolphaAddresses {
    /// @notice The Molpha verifier.
    /// @dev PROVISIONAL: `address(0)` until the audited build is frozen and deployed. Nothing is
    ///      deployed for the current `verify(Attestation,uint64)` interface yet, so a real-looking
    ///      constant here would be worse than one that fails loudly. Consumers must not ship
    ///      against this value while it is zero — read `deployments.json`, or wait for the tag
    ///      that sets it (v1.0.0; pre-release tags may still carry the placeholder).
    address internal constant VERIFIER = address(0);

    /// @notice `keccak256` of the verifier's CREATE2 init code (creation code ++ constructor args).
    /// @dev PROVISIONAL alongside `VERIFIER`; both are set by the same release.
    bytes32 internal constant VERIFIER_INIT_CODE_HASH = bytes32(0);

    /// @notice Arachnid's deterministic deployment proxy, identical on every supported chain.
    address internal constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice CREATE2 salt: `keccak256("MOLPHA_VERIFIER_BREBENESKUL")`.
    bytes32 internal constant VERIFIER_SALT = 0x65f8c5b96cad31c95bf82d305265f370b90a3fb13b903b2bb53f923cd800d835;

    /// @notice The verifier's `owner()` at deployment, and a CREATE2 constructor argument.
    address internal constant INITIAL_PROTOCOL_ADMIN = 0x6c6bCc50dDAA6884125e1060DCd6363F8866380A;

    /// @notice The verifier's redundancy buffer at deployment, and a CREATE2 constructor argument.
    uint256 internal constant INITIAL_REDUNDANCY_BUFFER = 2;
}
