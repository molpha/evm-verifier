# molpha-evm-verifier

[![CI](https://github.com/Molpha/molpha-evm-verifier/actions/workflows/ci.yml/badge.svg)](https://github.com/Molpha/molpha-evm-verifier/actions/workflows/ci.yml)

EVM contracts for Molpha's oracle-node registry and aggregate Schnorr signature verification on secp256k1.

This repository contains the on-chain verification layer only. It does not aggregate signatures, publish feed values, store consumed updates, or decide whether a feed is authorized for a consuming application. Integrators call `Verifier.verify(...)` with an optional `maxAge` for on-chain freshness, and apply their own application-level checks around the returned result.

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
- Signer groups are selected deterministically from `sourceId`, `registryVersion`, and `canonicalTimestamp`.
- The owner can configure a redundancy buffer so each selected group can contain more nodes than the required threshold.
- Aggregate Schnorr signatures are verified against the plain-sum public key of the submitted signer coalition.

The contract is intentionally narrow. It answers one question: "Did enough selected Molpha nodes sign this exact data update under the stated registry version?" Everything after that is up to the caller.

## Architecture

### Registry snapshots

The registry stores public keys as ABI-encoded `LibSecp256k1.Point[]` blobs written with Solady's `SSTORE2`.

- Registry version `0` is created in the constructor and contains no active nodes.
- Active node keys use zero-based blob indices: node index `i` maps to signer bitmap bit `i`.
- Each published version carries an `activatesAt` timestamp and a chained `registryRoot`.
- Retired versions remain verifiable for `PREVIOUS_GRACE` (60 seconds) after the successor version activates.
- `addNode` appends a key, writes a new blob, publishes a new registry version, and chains a new `registryRoot`.
- `removeNode` removes a key, writes a new blob, publishes a new registry version, and chains a new `registryRoot`.
- If a removed node is not the tail node, the current tail node is swapped into the removed index. Consumers should not assume node indices are stable across registry versions.

### Signer selection

For each update, the contract derives a selection seed:

```text
keccak256(
  keccak256("MOLPHA_SELECTION_V1") ||
  sourceId ||
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

1. Loads the registry snapshot requested by `attestation.payload.registryVersion`.
2. Derives the deterministic selected signer group.
3. Checks that the submitted bitmap is a subset of the selected group and contains at least `signaturesRequired` signers.
4. Sums the public keys of every set bit in the submitted signer bitmap.
5. Verifies the aggregate Schnorr signature against the signed message digest.

`verify` is non-reverting: predicate failures and invalid signatures return `(false, code)` using the shared result codes in `VerifyCodes`. See `docs/registry-v2.md` for the full registry-v2 semantics.

### `verify` gas metrics

Measured with `FOUNDRY_PROFILE=gas forge test -vv --match-contract VerifierGasTest` using the repository Foundry
settings: Solidity `0.8.31`, Cancun EVM, IR compilation, optimizer enabled with one million runs.

The table below isolates the number of submitted aggregate signers, with redundancy buffer `2`. `Total` includes the
measured execution gas, calldata gas, and the `21,000` base transaction gas.

| Active nodes | Signers | Execution | Calldata | Total |
| ---: | ---: | ---: | ---: | ---: |
| 8 | 5 | 13,979 | 2,308 | 37,287 |
| 256 | 1 | 9,251 | 2,320 | 32,571 |
| 256 | 5 | 15,428 | 2,344 | 38,772 |
| 256 | 9 | 19,921 | 2,392 | 43,313 |
| 256 | 18 | 29,782 | 2,488 | 53,270 |
| 256 | 32 | 44,834 | 2,524 | 68,358 |
| 256 | 64 | 80,724 | 2,644 | 104,368 |

These are warm-state figures: the benchmark calls `verify` twice and reports the second call. A first-in-block
transaction additionally pays a cold-access surcharge of roughly `2,000`–`5,300` gas — one cold `SLOAD` for the
registry entry and one cold account access for the key blob.

## Contracts

| Path | Purpose |
| --- | --- |
| `src/Verifier.sol` | Node registry, registry snapshots, signer selection, and aggregate signature verification |
| `src/interfaces/IVerifier.sol` | Public structs, events, errors, and verifier API |
| `src/libs/LibSchnorr.sol` | secp256k1 Schnorr verification using `ecrecover` |
| `src/libs/LibSecp256k1.sol` | secp256k1 point arithmetic, compression, decompression, and key utilities |
| `src/libs/NodeGroupBitmapLib.sol` | Deterministic unbiased signer-group bitmap derivation |
| `src/libs/PubkeyBlobLib.sol` | Helpers for SSTORE2-encoded public-key registry blobs |
| `src/libs/VerifierLib.sol` | Packed registry entries, signer selection, and aggregate key math |
| `src/libs/VerifyCodes.sol` | Shared `verify` result codes |
| `src/libs/KeysCommitmentLib.sol` | Canonical ordered-coordinate commitment used in registry roots |
| `script/Deploy.s.sol` | Deterministic CREATE2 deployment script |
| `script/AddNode.s.sol` | Single-node and batch node-registration script |
| `script/libs/DeployConstants.sol` | Shared deployment salt and initial redundancy buffer |
| `script/libs/PopSignLib.sol` | Admin-script helper for registration proof-of-possession signatures |

## Verification model

Consumers pass the data update and the aggregate Schnorr signature:

```solidity
struct AttestationPayload {
    bytes32 value;
    bytes32 sourceId;
    uint32 registryVersion;
    uint8 signaturesRequired;
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
  value ||
  sourceId ||
  registryVersion ||
  signaturesRequired ||
  canonicalTimestamp ||
  signersBitmap
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
| `removeNode(address node, uint256 index)` | Removes the node at `index` after checking the `(node, index)` witness, and writes a new registry snapshot |
| `setRedundancyBuffer(uint256 newRedundancyBuffer)` | Publishes a new registry version with the updated redundancy buffer |

Admin functions revert unless `msg.sender == owner()`.

### Verification function

| Function | Description |
| --- | --- |
| `verify(Attestation attestation, uint64 maxAge)` | Returns `(true, VerifyCodes.R_OK)` when the aggregate Schnorr signature is valid. Pass `maxAge > 0` to also require `canonicalTimestamp` within that age of `block.timestamp`; `maxAge = 0` skips freshness. Other outcomes return `(false, code)` without reverting. |

`verify` is `view`. A successful call does not persist state and does not prevent replay by itself.

### Read functions

| Function | Description |
| --- | --- |
| `getRegistryVersion()` | Latest registry version |
| `getRegistryPointer()` | SSTORE2 pointer for the latest registry snapshot |
| `getRegistryPointer(uint256 registryVersion)` | SSTORE2 pointer for a historical registry snapshot |
| `getRegistryRoot()` / `getRegistryRoot(uint256)` | Chained registry root for the current or historical version |
| `activatesAt(uint256 registryVersion)` | Unix timestamp when a version became live |
| `retiredAt(uint256 registryVersion)` | Unix timestamp when a version was superseded |
| `isLatestVersion(uint256 registryVersion)` | Whether a version is the current registry head |
| `isNode(address node)` | Whether a node is currently active (not retired) |
| `getTotalNodes()` | Number of active nodes in the latest registry |
| `nodeStatus(address)` | Eligibility status: `0` never, `1` active, `2` retired |

Solidity also exposes public getters for `owner`, `redundancyBuffer`, and `nodeStatus`. Registry snapshots are stored in
a private mapping and read through `getRegistryPointer`.

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
FOUNDRY_PROFILE=coverage forge coverage --ir-minimum --report summary
forge lint
```

Gas probes live under `test/gas/` and are excluded from the default profile:

```bash
FOUNDRY_PROFILE=gas forge test -vv
```

The coverage profile excludes two 256-node boundary tests that remain covered by
the normal test suite but exceed Foundry's instrumentation gas ceiling under
`forge coverage`.

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

Only the current `owner()` can add or remove nodes.

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

**Use the SDK.** `src/consumer/MolphaLib.sol` is this checklist as code. Import it, set a `Policy`,
choose a replay guard:

```solidity
using MolphaLib for IVerifier;
using MolphaLib for MolphaLib.Latest;

IVerifier immutable VERIFIER = IVerifier(MolphaAddresses.VERIFIER);
MolphaLib.Policy internal policy;   // sourceId, minSignatures, maxAge — set in the constructor
MolphaLib.Latest internal latest;

function settle(IVerifier.Attestation calldata att) external {
    VERIFIER.requireValid(att, policy);   // source, threshold floor, freshness, signature
    latest.acceptNewer(att.payload);      // replay
    _apply(MolphaLib.asInt256(att.payload.value));
}
```

See [`examples/`](examples) for three complete consumers and [`docs/consumer-sdk.md`](docs/consumer-sdk.md)
for the full guide. What the library does and does not decide for you:

- **`Policy.minSignatures` is mandatory and is your own floor.** `sourceId` commits the source
  configuration, *not* the threshold — `signaturesRequired` is chosen by whoever requested the
  attestation. Today there is no protocol minimum in the verifier beyond rejecting zero, so your
  floor is the only floor.
- **`verify` is `view`, so attestations replay forever.** Any state-mutating consumer needs
  `MolphaLib.Latest` (monotonic, one SSTORE — the default) or `MolphaLib.Consumed` (exact-once,
  unbounded growth, for out-of-order acceptance).
- **`maxAge = 0` is not a neutral default.** It disables the only absolute-freshness check;
  `acceptNewer` enforces monotonicity, not recency, so your first accepted update may be
  arbitrarily old.
- **`value` is an opaque `bytes32`.** Kind A is one ABI word — decode with `asUint256`/`asInt256`/
  `asBool`/`asAddress`, which reject non-canonical encodings. Kind B is `keccak256(encodedFields)`
  and you pass the unsigned preimage alongside; `MolphaLib` binds the hash, you own the tuple.

Integrating against the raw `IVerifier` instead? Then all of the above is yours to write, plus:

- Pass the registry version used during off-chain signing, and respect version lifetimes:
  `canonicalTimestamp` must be at or after `activatesAt`, and non-latest versions expire
  `PREVIOUS_GRACE` seconds after the successor activates.
- Treat node indices as version-specific — the registry swaps the tail node into a removed slot.
- Build signer bitmaps with zero-based bit positions: bit `i` is registry index `i`.
- Handle `false` returns and inspect `code` (`VerifyCodes`) rather than treating all failures alike.
- Pin deployments, registry versions, and expected chain IDs in production configuration.

## Installing

| Channel | Install | Import root |
| --- | --- | --- |
| Foundry | `forge install molpha/evm-verifier` plus the remapping `@molpha/evm-verifier/=lib/evm-verifier/src/` | `@molpha/evm-verifier/…` |
| npm | `npm i @molpha/evm-verifier` (published with `src/` contents at the package root) | `@molpha/evm-verifier/…` |

Both channels resolve the same string:

```solidity
import {IVerifier} from "@molpha/evm-verifier/interfaces/IVerifier.sol";
import {MolphaLib} from "@molpha/evm-verifier/consumer/MolphaLib.sol";
```

Everything on the consumer surface — `interfaces/IVerifier.sol`, `consumer/MolphaLib.sol`,
`consumer/MolphaAddresses.sol`, `libs/VerifyCodes.sol`, `test-utils/MockVerifier.sol` — compiles on
`>=0.8.4 <0.9.0` with zero external dependencies, and CI proves it by building that closure with
solc 0.8.4. `test-utils/MolphaTestSigner.sol` is the exception: it deploys the real `Verifier`, so it
is pinned to `^0.8.31` and depends on solady. It is intended for Foundry.

> `MolphaAddresses.VERIFIER` is `address(0)` until the audited build is deployed. Read
> `deployments.json` for the current state; the package is published as `1.0.0-rc.N` while the
> placeholder stands.

## Security

Please read [SECURITY.md](SECURITY.md) before reporting a vulnerability. Do not disclose security issues in public GitHub issues.

This repository is a smart-contract verification component. Public release does not imply that every deployment, feed, signer, or consumer integration is safe. Integrators should review the contracts, deployment configuration, node operations, and consumer-side replay/freshness logic before using the verifier in production.

## License

The core contracts and interfaces are licensed under the [Apache License 2.0](LICENSE). Individual files, including deployment scripts and libraries, may declare different terms in their SPDX headers.
