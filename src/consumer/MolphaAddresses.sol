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
    /// @notice The Molpha verifier (`verify(Attestation,uint64)`).
    address internal constant VERIFIER = 0xA6e49A3A1caf3E110cC04765B934C8FF118C2568;

    /// @notice `keccak256` of the verifier's CREATE2 init code (creation code ++ constructor args).
    bytes32 internal constant VERIFIER_INIT_CODE_HASH =
        0x78582ede425b4fc6bc4708b800a08a2cb94a86a75778f2a5302ca4c7a83a31a6;

    /// @notice Arachnid's deterministic deployment proxy, identical on every supported chain.
    address internal constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice CREATE2 salt: `keccak256("MOLPHA_VERIFIER_CHIVCHYN")`.
    bytes32 internal constant VERIFIER_SALT = 0x1a13ffd79d1e3978d58b0c0917160c77790755e53333227fc04e68f2963e93cc;

    /// @notice The verifier's `owner()` at deployment, and a CREATE2 constructor argument.
    address internal constant INITIAL_PROTOCOL_ADMIN = 0x6c6bCc50dDAA6884125e1060DCd6363F8866380A;

    /// @notice The verifier's redundancy buffer at deployment, and a CREATE2 constructor argument.
    uint256 internal constant INITIAL_REDUNDANCY_BUFFER = 2;
}
