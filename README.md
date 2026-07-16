# molpha-evm-verifier

[![CI](https://github.com/Molpha/molpha-evm-verifier/actions/workflows/ci.yml/badge.svg)](https://github.com/Molpha/molpha-evm-verifier/actions/workflows/ci.yml)

EVM contracts for maintaining Molpha's oracle-node registry and verifying aggregated Schnorr signatures on secp256k1.

This repository contains the verification layer only. It does not aggregate signatures, store feed values, or enforce timestamp freshness for consumers.

## Overview

`Verifier` combines a versioned node registry with deterministic signer selection:

- Up to 256 active oracle nodes, addressed by a 256-bit signer bitmap
- Schnorr proof-of-possession required when a node is registered
- Immutable node-set snapshots stored with SSTORE2 after every add or remove
- Deterministic signer-group selection from the job, registry version, and canonical timestamp
- Configurable redundancy above the required signature threshold
- Aggregate Schnorr verification against the selected signers' coalition key

The protocol admin can add and remove nodes, transfer the admin role, and update the redundancy buffer. Consumers call the read-only `verify` function and remain responsible for enforcing application-level freshness, replay protection, and authorization.

## Contracts

| Path | Purpose |
| --- | --- |
| `src/Verifier.sol` | Node registry, signer selection, and aggregate signature verification |
| `src/interfaces/IVerifier.sol` | Public structs, events, and verifier API |
| `src/libs/LibSchnorr.sol` | Schnorr verification using the EVM `ecrecover` precompile |
| `src/libs/LibSecp256k1.sol` | secp256k1 point arithmetic and key utilities |
| `src/libs/NodeGroupBitmapLib.sol` | Deterministic, unbiased signer-group derivation |
| `src/libs/PubkeyBlobLib.sol` | SSTORE2-encoded public-key registry operations |

### Primary API

| Function | Description |
| --- | --- |
| `addNode(compressedPubKey, pop)` | Register a node after verifying its proof-of-possession |
| `removeNode(node)` | Remove an active node and create a new registry version |
| `verify(dataUpdate, schnorrData)` | Verify an aggregate Schnorr signature for a selected signer coalition |
| `setRedundancyBuffer(value)` | Set the extra nodes included in each selected group |
| `transferProtocolAdmin(newAdmin)` | Transfer registry administration |
| `getRegistryVersion()` | Return the latest registry version |
| `getRegistryPointer(version)` | Return the SSTORE2 pointer for a registry snapshot |
| `getTotalNodes()` | Return the number of currently active nodes |
| `getAggregateKey()` | Return the plain-sum key for the current node set |

## Verification model

For each update, the caller provides:

```solidity
struct DataUpdate {
    bytes32 jobId;
    uint32 registryVersion;
    uint32 signaturesRequired;
    bytes32 value;
    uint64 canonicalTimestamp;
}
```

The verifier:

1. Loads the requested historical registry snapshot.
2. Derives a selection seed from `jobId`, `registryVersion`, and `canonicalTimestamp`.
3. Selects `min(signaturesRequired + redundancyBuffer, nodeCount)` nodes.
4. Requires the submitted signer bitmap to be a threshold-sized subset of that group.
5. Sums the participating public keys and verifies the aggregate signature.

The signed message is:

```text
keccak256(
  keccak256("MOLPHA_MESSAGE_V1") ||
  jobId || registryVersion || signaturesRequired || signersBitmap || value || canonicalTimestamp
)
```

Node registration binds the proof-of-possession to both the verifier deployment and the compressed key:

```text
keccak256(keccak256("MOLPHA_VALIDATOR_V1") || verifierAddress || compressedPubKey)
```

All concatenations above use Solidity's `abi.encodePacked` with the types declared in `IVerifier`.

## Development

### Requirements

- [Foundry](https://getfoundry.sh/)
- Git

### Setup

```bash
git clone --recurse-submodules https://github.com/Molpha/molpha-evm-verifier.git
cd molpha-evm-verifier

forge build
forge test
```

The project uses Solidity `0.8.31`, the Cancun EVM target, IR compilation, and one million optimizer runs. Tests are self-contained and do not require an RPC URL.

Useful commands:

```bash
forge build --sizes
forge test -vvv
forge coverage --ir-minimum --report summary
FOUNDRY_PROFILE=gas forge test -vv
forge fmt
```

The default and CI profiles run correctness tests only. Gas probes live under `test/gas/` and run only through the explicit `gas` profile, keeping benchmark setup and console output out of normal test and coverage runs.

## Deployment

The deployment script creates a `Verifier` with the broadcaster as protocol admin and a default redundancy buffer of `2`:

```bash
export PRIVATE_KEY=<protocol-admin-private-key>

forge script script/Deploy.s.sol:Deploy \
  --rpc-url <rpc-url> \
  --broadcast
```

The script writes addresses to `deployments/<network>/addresses-<timestamp>.json`.

### Register nodes

Never commit private keys or RPC credentials. The examples under `script/examples/` contain the accepted JSON shapes.

```bash
export PRIVATE_KEY=<protocol-admin-private-key>
export NODE_PRIVATE_KEY=<node-private-key>

./add-node.sh <deployment-folder> <rpc-url>
```

For a batch:

```bash
export PRIVATE_KEY=<protocol-admin-private-key>
./add-node.sh <deployment-folder> <rpc-url> path/to/nodes.json
```

Production registration can provide precomputed `compressedPubKey`, `popSignature`, and `popCommitment` values instead of exposing a node private key to the script host.

## Integration notes

- `verify` is a `view` function. A successful result does not record that an update was consumed.
- `canonicalTimestamp` is signature-bound but is not compared with `block.timestamp`.
- Consumers should reject stale or duplicate updates according to their own state-transition rules.
- Registry versions are immutable snapshots; integrations should pass the version used during off-chain signing.
- Bitmap position `i - 1` represents the node at one-based registry index `i`.

## Security

Please read [SECURITY.md](SECURITY.md) before reporting a vulnerability. Do not disclose security issues in public GitHub issues.

## License

The core contracts and interfaces are licensed under the [Apache License 2.0](LICENSE). Individual files, including deployment scripts, may declare different terms in their SPDX headers.
