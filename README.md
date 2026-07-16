# molpha-core-contracts

Smart contracts for the Molpha decentralized oracle protocol.

This repository contains the on-chain **Validator** — a registry of oracle nodes and a Schnorr signature verifier used to validate aggregated data updates from off-chain oracle nodes.

---

## Contracts Overview

### `Validator.sol`

The core contract. It:

- Registers and removes oracle nodes (up to 256 per registry)
- Stores node public keys efficiently via SSTORE2
- Derives per-round signer groups from a deterministic selection seed
- Verifies aggregated Schnorr signatures against the coalition of selected signers
- Versions the node registry on every add/remove (immutable history)

**Key functions:**

| Function | Description |
|----------|-------------|
| `initialize()` | Sets protocol admin and creates the initial empty registry |
| `addNode(compressedPubKey, pop)` | Registers a node with a Schnorr proof-of-possession |
| `removeNode(node)` | Removes a node and bumps the registry version |
| `verify(dataUpdate, schnorrData)` | Verifies a Schnorr signature for a data update |
| `getRegistryVersion()` | Returns the current registry version |
| `getAggregateKey()` | Returns the plain-sum aggregate pubkey over all registered nodes |

### Interface

- `IValidator.sol` — public API, structs (`DataUpdate`, `SchnorrSignature`, `SchnorrProof`), and events

### Libraries

| Library | Purpose |
|---------|---------|
| `LibSecp256k1.sol` | secp256k1 curve arithmetic |
| `LibSchnorr.sol` | Schnorr signature verification |
| `LibMuSig2KeyAgg.sol` | MuSig2 key aggregation helpers |
| `NodeGroupBitmapLib.sol` | Deterministic signer-group selection from a seed |
| `BitmapLib.sol` | Bitmap popcount and bit utilities |
| `PubkeyBlobLib.sol` | Read/write node keys in SSTORE2 blobs |
| `PublishCalldataLib.sol` | Packed timestamp/round encoding helpers |

---

## Architecture

```text
              [ Off-chain Oracle Nodes ]
                        |
     Each node signs data updates; aggregator combines signatures
                        |
                    [ On-chain ]
                          |
            +----------------------------+
            | Validator                  |
            | - Node registry (SSTORE2)  |
            | - Registry versioning      |
            | - Signer-group selection   |
            | - Schnorr verification     |
            +----------------------------+
                          |
                          v
              [ Consumer / Feed contracts ]
                (integrate via verify())
```

### Verification flow

1. **Selection seed** — derived from `(jobId, registryVersion, canonicalTimestamp)`
2. **Signer group** — `NodeGroupBitmapLib` picks `signaturesRequired + redundancyBuffer` nodes from the registry
3. **Bitmap check** — `signersBitmap` must be a subset of the selected group and meet the required threshold
4. **Coalition key** — sum the public keys of all signers in the bitmap
5. **Schnorr verify** — check the aggregated signature against the coalition key and canonical message hash

The signed message is:

```text
keccak256(MESSAGE_PREFIX || jobId || registryVersion || signaturesRequired || signersBitmap || value || canonicalTimestamp)
```

---

## Project Structure

```text
molpha-core-contracts/
├── src/
│   ├── Validator.sol           # Main contract
│   ├── interfaces/             # IValidator (API, structs, events)
│   └── libs/                   # Crypto and bitmap utilities
├── test/                       # Foundry tests (Validator, libs, gas benchmarks)
├── script/
│   ├── Deploy.s.sol            # Validator deployment script
│   ├── AddNode.s.sol           # Register one or more oracle nodes
│   ├── libs/PopSignLib.sol     # PoP signing helper for admin scripts
│   └── examples/               # Sample nodes JSON for batch registration
├── add-node.sh                 # Shell wrapper for AddNode.s.sol
├── deployments/                # Per-chain address files (JSON)
└── docs/                       # Protocol specs
```

---

## Setup

Requires [Foundry](https://book.getfoundry.sh/).

```bash
forge install
forge build
forge test
```

**Toolchain:** Solidity `0.8.31`, EVM `Osaka`, optimizer enabled (`via_ir`).

### Deploy

Set `PRIVATE_KEY` and broadcast:

```bash
forge script script/Deploy.s.sol \
  --rpc-url <RPC_URL> \
  --broadcast
```

Deployment addresses are written to `deployments/<chain-name>/addresses-<timestamp>.json`.

Supported chain folders include `anvil`, `sepolia`, `avalanche-fuji`, `arbitrum-sepolia`, `bsc-testnet`, `base-sepolia`, and others (see `_deploymentChainFolder` in `script/Deploy.s.sol`).

### Register nodes

Only the protocol admin can call `addNode`. Each node must provide a Schnorr proof-of-possession over:

```text
keccak256(MOLPHA_VALIDATOR_V1 || validatorAddress || compressedPubKey)
```

The script reads the latest `Validator` address from `deployments/<chain-name>/addresses-*.json` (falls back to `NodeRegistry` in older files).

**Single node:**

```bash
export PRIVATE_KEY=<protocol_admin_key>
export NODE_PRIVATE_KEY=<node_secp256k1_private_key>

./add-node.sh avalanche-fuji https://your-rpc-url
```

**Batch (recommended for multiple nodes):** pass a JSON file as the third argument (or set `NODES_FILE`):

```bash
export PRIVATE_KEY=<protocol_admin_key>

./add-node.sh avalanche-fuji https://your-rpc-url nodes.json
```

`nodes.json` — private keys (dev/test):

```json
{
  "privateKeys": ["0x...", "0x..."]
}
```

`nodes.json` — mixed or pre-signed (production):

```json
{
  "nodes": [
    { "privateKey": "0x..." },
    {
      "compressedPubKey": "0x02...",
      "popSignature": "0x...",
      "popCommitment": "0x..."
    }
  ]
}
```

See `script/examples/nodes.private-keys.example.json`. `PRIVATE_KEY` must match `ProtocolAdmin` in the deployment address file (the shell script checks this before broadcasting).

**Pre-signed PoP (single node):** instead of `NODE_PRIVATE_KEY`:

```bash
export COMPRESSED_PUBKEY=0x02...
export POP_SIGNATURE=0x...
export POP_COMMITMENT=0x...
```

**Direct forge:**

```bash
export VALIDATOR=0x...
export PRIVATE_KEY=...
export NODES_FILE=nodes.json   # or NODE_PRIVATE_KEY for a single node

forge script script/AddNode.s.sol:AddNode \
  --rpc-url <RPC_URL> \
  --broadcast
```

---

## Security Considerations

- Only the **protocol admin** can add or remove nodes
- New nodes must submit a **Schnorr proof-of-possession** over the registration domain
- Signers must belong to the **deterministically selected group** for the round; out-of-group bits in the bitmap revert
- **Registry versioning** ensures signature verification uses the node set that was active at publish time
- Replay protection is enforced off-chain via `canonicalTimestamp` and on-chain via message binding

---

## Documentation

- [`docs/validation-v2.md`](docs/validation-v2.md) — EVM Schnorr verification specification (draft)
- [`docs/molpha-tech-specs-v3.md`](docs/molpha-tech-specs-v3.md) — Protocol technical specs

---

## License

Apache-2.0 on core contracts (`Verifier`, interfaces). See individual file headers.

---

## Authors

Maintained by the Molpha core protocol team.
