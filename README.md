# molpha-evm-verifier

[![CI](https://github.com/Molpha/molpha-evm-verifier/actions/workflows/ci.yml/badge.svg)](https://github.com/Molpha/molpha-evm-verifier/actions/workflows/ci.yml)

EVM contracts for Molpha's oracle-node registry and aggregate Schnorr signature verification on secp256k1.

This repository contains the on-chain verification layer only. It does not aggregate signatures, publish feed values, store consumed updates, enforce timestamp freshness, or decide whether a feed is authorized for a consuming application. Integrators call `Verifier.verify(...)` and apply their own application-level checks around the returned result.

## Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Contracts](#contracts)
- [Verification model](#verification-model)
- [Public API](#public-api)
- [Development](#development)
- [Deployment](#deployment)
- [Node registration](#node-registration)
- [Integration checklist](#integration-checklist)
- [Security](#security)
- [License](#license)

## Overview

`Verifier` combines a versioned oracle-node registry with deterministic signer selection:

- Up to 256 active oracle nodes, represented by a single 256-bit signer bitmap.
- Node registration requires a Schnorr proof-of-possession over the node's compressed secp256k1 public key.
- Every registry mutation creates an immutable SSTORE2-backed public-key snapshot.
- Historical registry versions remain verifiable after later node additions or removals.
- Signer groups are selected deterministically from `feedId`, `registryVersion`, and `canonicalTimestamp`.
- The protocol admin can configure a redundancy buffer so each selected group can contain more nodes than the required threshold.
- Aggregate Schnorr signatures are verified against the plain-sum public key of the submitted signer coalition.

The contract is intentionally narrow. It answers one question: "Did enough selected Molpha nodes sign this exact data update under the stated registry version?" Everything after that is up to the caller.

## Architecture

### Registry snapshots

The registry stores public keys as ABI-encoded `LibSecp256k1.Point[]` blobs written with Solady's `SSTORE2`.

- Registry version `0` is created in the constructor and contains no active nodes.
- Array index `0` is reserved for the aggregate public key of the active set.
- Active node keys use one-based indices: node index `1` maps to signer bitmap bit `0`, node index `2` maps to bit `1`, and so on.
- `addNode` appends a key, updates the aggregate key, writes a new blob, and increments the registry version.
- `removeNode` removes a key, updates the aggregate key, writes a new blob, and increments the registry version.
- If a removed node is not the tail node, the current tail node is swapped into the removed index. Consumers should not assume node indices are stable across registry versions.

### Signer selection

For each update, the contract derives a selection seed:

```text
keccak256(
  keccak256("MOLPHA_SELECTION_V1") ||
  feedId ||
  registryVersion ||
  canonicalTimestamp
)
```

`NodeGroupBitmapLib` expands that seed with `keccak256(seed || keccak256("MOLPHA_SELECTION_DERIVE") || counter)`, reads eight big-endian `uint32` limbs from each digest, and samples indices without replacement. It rejects out-of-range limbs to avoid modulo bias. When the requested group is larger than half of the node set, it samples exclusions and returns the complement.

The selected group size is:

```text
min(signaturesRequired + redundancyBuffer, nodeCount)
```

The submitted signer bitmap must be a subset of that selected group and must contain at least `signaturesRequired` bits.

### Signature verification

Molpha uses Schnorr signatures over secp256k1. `LibSchnorr` verifies signatures through the EVM `ecrecover` precompile using the same verification identity used by Scribe-style Schnorr implementations.

For aggregate verification, the verifier:

1. Loads the registry snapshot requested by `dataUpdate.registryVersion`.
2. Derives the deterministic selected signer group.
3. Checks that the submitted bitmap contains enough selected signers.
4. Sums the selected signers' public keys in ascending index order.
5. Verifies the aggregate Schnorr signature against the signed message digest.

Invalid signatures return `false`. Malformed inputs, invalid registry versions, insufficient signers, unselected signers, zero signature fields, and invalid signature scalars revert with custom errors from `IVerifier`.

## Contracts

| Path | Purpose |
| --- | --- |
| `src/Verifier.sol` | Node registry, registry snapshots, signer selection, and aggregate signature verification |
| `src/interfaces/IVerifier.sol` | Public structs, events, errors, and verifier API |
| `src/libs/LibSchnorr.sol` | secp256k1 Schnorr verification using `ecrecover` |
| `src/libs/LibSecp256k1.sol` | secp256k1 point arithmetic, compression, decompression, and key utilities |
| `src/libs/NodeGroupBitmapLib.sol` | Deterministic unbiased signer-group bitmap derivation |
| `src/libs/PubkeyBlobLib.sol` | Helpers for SSTORE2-encoded public-key registry blobs |
| `script/Deploy.s.sol` | Deterministic CREATE2 deployment script |
| `script/AddNode.s.sol` | Single-node and batch node-registration script |
| `script/libs/DeployConstants.sol` | Shared deployment salt and initial redundancy buffer |
| `script/libs/PopSignLib.sol` | Admin-script helper for registration proof-of-possession signatures |

## Verification model

Consumers pass the data update and the aggregate Schnorr signature:

```solidity
struct DataUpdate {
    bytes32 feedId;
    uint32 registryVersion;
    uint32 signaturesRequired;
    bytes32 value;
    uint64 canonicalTimestamp;
}

struct SchnorrSignature {
    bytes32 signature;
    address commitment;
    uint256 signersBitmap;
}
```

The signed message is:

```text
keccak256(
  keccak256("MOLPHA_MESSAGE_V1") ||
  feedId ||
  registryVersion ||
  signaturesRequired ||
  signersBitmap ||
  value ||
  canonicalTimestamp
)
```

Node proof-of-possession uses:

```solidity
struct SchnorrProof {
    bytes32 signature;
    address commitment;
}
```

The proof signs:

```text
keccak256(
  keccak256("MOLPHA_VERIFIER_V1") ||
  verifierAddress ||
  compressedPubKey
)
```

All concatenations above use Solidity `abi.encodePacked` with the field types shown in `IVerifier`.

## Public API

### Admin functions

| Function | Description |
| --- | --- |
| `addNode(bytes compressedPubKey, SchnorrProof pop)` | Registers a node after validating its compressed public key and proof-of-possession |
| `removeNode(address node)` | Removes an active node and writes a new registry snapshot |
| `setRedundancyBuffer(uint256 newRedundancyBuffer)` | Sets the extra nodes included in each selected signer group |
| `transferProtocolAdmin(address newProtocolAdmin)` | Transfers the protocol admin role |

Admin functions revert unless `msg.sender == protocolAdmin`.

### Verification function

| Function | Description |
| --- | --- |
| `verify(DataUpdate dataUpdate, SchnorrSignature schnorrData)` | Returns `true` when the aggregate Schnorr signature is valid for the selected signer coalition |

`verify` is `view`. A successful call does not persist state and does not prevent replay by itself.

### Read functions

| Function | Description |
| --- | --- |
| `getRegistryVersion()` | Latest registry version |
| `getRegistryPointer()` | SSTORE2 pointer for the latest registry snapshot |
| `getRegistryPointer(uint256 registryVersion)` | SSTORE2 pointer for a historical registry snapshot |
| `isNode(address node)` | Whether a node is currently active |
| `getTotalNodes()` | Number of active nodes in the latest registry |
| `getNodesSetHash()` | Hash of the latest encoded registry blob |
| `getAggregateKey()` | Plain-sum aggregate public key for the latest active set |
| `getNodeIndex(address node)` | Current one-based node index, or `0` if inactive |

Solidity also exposes public getters for `protocolAdmin`, `redundancyBuffer`, `registryPointers`, `nodeIndexes`, `nodeKeyX`, and `nodeKeyY`.

## Development

### Requirements

- [Foundry](https://getfoundry.sh/)
- Git with submodule support

### Setup

```bash
git clone --recurse-submodules https://github.com/Molpha/molpha-evm-verifier.git
cd molpha-evm-verifier

forge build
forge test
```

If the repository was cloned without submodules:

```bash
git submodule update --init --recursive
```

The project uses Solidity `0.8.31`, the Cancun EVM target, IR compilation, and one million optimizer runs.

### Common commands

```bash
forge fmt
forge fmt --check
forge build --sizes
forge test -vvv
forge test --fuzz-runs 10000
forge coverage --ir-minimum --report summary
forge lint
```

Gas probes live under `test/gas/` and are excluded from the default profile:

```bash
FOUNDRY_PROFILE=gas forge test -vv
```

### Test layout

| Path | Purpose |
| --- | --- |
| `test/unit/` | Registry, admin, verification, bitmap, pubkey-blob, and Schnorr unit tests |
| `test/integration/` | External fixture compatibility tests |
| `test/gas/` | Gas probes for verifier and selection logic |
| `test/shared/VerifierTestBase.sol` | Shared signing and registry helpers |
| `test/libs/LibSchnorrTestSign.sol` | Test-only Schnorr signing helper |
| `test/fixtures/fixture.json` | Fixture data used by integration tests |

CI runs formatting, build, normal tests, fuzz tests, and Forge lint.

## Deployment

`script/Deploy.s.sol` deploys `Verifier` with CREATE2. Foundry routes `new Verifier{salt: ...}` through Arachnid's deterministic deployment proxy at:

```text
0x4e59b44847b379578588920cA78FbF26c0B4956C
```

The predicted address depends on:

- CREATE2 factory: `0x4e59b44847b379578588920cA78FbF26c0B4956C`
- Salt: `keccak256("MOLPHA_VERIFIER_BREBENESKUL")`
- Constructor args: `initialProtocolAdmin = deployer`, `initialRedundancyBuffer = 2`
- Compiler, optimizer, EVM version, and init code

Override the salt with `DEPLOY_SALT` when you intentionally want a different address.

### Dry run

```bash
export PRIVATE_KEY=<protocol-admin-private-key>

forge script script/Deploy.s.sol:Deploy \
  --rpc-url <rpc-url>
```

### Broadcast

```bash
export PRIVATE_KEY=<protocol-admin-private-key>

forge script script/Deploy.s.sol:Deploy \
  --rpc-url <rpc-url> \
  --broadcast
```

The deployment script is idempotent. If bytecode already exists at the predicted address, it skips deployment and writes the existing address to the output file.

Deployment outputs are written to:

```text
deployments/<network>/addresses.json
```

Those local deployment outputs are intentionally ignored by git.

The script maps common chain IDs to readable folder names, including `ethereum`, `sepolia`, `anvil`, `avalanche-fuji`, `avalanche`, `arbitrum-sepolia`, `arbitrum-one`, `bsc-testnet`, `bsc`, `xdc-apothem`, `base-sepolia`, `base`, `polygon`, and `polygon-amoy`. Unknown chains use `chain-<id>`.

## Node registration

Only the current `protocolAdmin` can add or remove nodes.

### Single node from a private key

`script/AddNode.s.sol` can derive the compressed public key and proof-of-possession from a node private key:

```bash
export PRIVATE_KEY=<protocol-admin-private-key>
export VERIFIER=<verifier-address>
export NODE_PRIVATE_KEY=<node-private-key>

forge script script/AddNode.s.sol:AddNode \
  --rpc-url <rpc-url> \
  --broadcast
```

Example:

```bash
forge script script/AddNode.s.sol:AddNode \
  --rpc-url https://avax-fuji.g.alchemy.com/v2/YOUR_API_KEY \
  --broadcast
```

### Single node from precomputed proof data

For production operations, prefer generating the node proof off-host and passing only public registration data to the admin script:

```bash
export PRIVATE_KEY=<protocol-admin-private-key>
export VERIFIER=<verifier-address>
export COMPRESSED_PUBKEY=0x02...
export POP_SIGNATURE=0x...
export POP_COMMITMENT=0x...

forge script script/AddNode.s.sol:AddNode \
  --rpc-url <rpc-url> \
  --broadcast
```

### Batch registration

Batch files support either a top-level `privateKeys` array:

```json
{
  "privateKeys": [
    "0x...",
    "0x..."
  ]
}
```

or a `nodes` array that can mix private-key entries with precomputed proof entries:

```json
{
  "nodes": [
    {
      "privateKey": "0x..."
    },
    {
      "compressedPubKey": "0x02...",
      "popSignature": "0x...",
      "popCommitment": "0x..."
    }
  ]
}
```

Run:

```bash
export PRIVATE_KEY=<protocol-admin-private-key>
export VERIFIER=<verifier-address>
export NODES_FILE=path/to/nodes.json

forge script script/AddNode.s.sol:AddNode \
  --rpc-url <rpc-url> \
  --broadcast
```

Example JSON files live under `script/examples/`.

Never commit `.env`, local node lists, private keys, or RPC credentials.

## Integration checklist

When integrating `Verifier` into a consumer contract or off-chain client:

- Pass the registry version that was used during off-chain signing.
- Treat node indices as version-specific. They can change after removals because the registry swaps the tail node into the removed slot.
- Build signer bitmaps with zero-based bit positions: bit `i - 1` represents one-based registry index `i`.
- Reject stale updates by comparing `canonicalTimestamp` against your own freshness policy.
- Reject duplicate or replayed updates according to your consumer state machine.
- Validate that the `feedId` is authorized for your application before trusting `value`.
- Decide how many signatures your feed requires and pass that value in `DataUpdate.signaturesRequired`.
- Handle both outcomes from `verify`: malformed inputs or unselected signers may revert; well-formed but invalid signatures return `false`.
- Remember that `value` is an opaque `bytes32`. Consumers define the encoding, scale, and semantic meaning.
- Pin deployments, registry versions, and expected chain IDs in production configuration.

## Security

Please read [SECURITY.md](SECURITY.md) before reporting a vulnerability. Do not disclose security issues in public GitHub issues.

This repository is a smart-contract verification component. Public release does not imply that every deployment, feed, signer, or consumer integration is safe. Integrators should review the contracts, deployment configuration, node operations, and consumer-side replay/freshness logic before using the verifier in production.

## License

The core contracts and interfaces are licensed under the [Apache License 2.0](LICENSE). Individual files, including deployment scripts and libraries, may declare different terms in their SPDX headers.
