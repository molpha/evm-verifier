# Message Format

This document defines the Molpha verifier payloads that are signed off chain and
checked by `Verifier.verify(...)` on chain.

The verifier accepts one data update and one aggregate Schnorr signature:

```solidity
struct DataUpdate {
    bytes32 value;
    bytes32 sourceId;
    uint32 registryVersion;
    uint32 signaturesRequired;
    uint64 canonicalTimestamp;
}

struct SchnorrSignature {
    bytes32 signature;
    address commitment;
    uint256 signersBitmap;
}
```

All hashes below use Solidity `abi.encodePacked` over the listed field types.
Numeric fields are encoded as their fixed-width Solidity integer types, not as
decimal strings or variable-length byte arrays.

## Data update fields

| Field | Type | Description |
| --- | --- | --- |
| `sourceId` | `bytes32` | Canonical identifier for the data source. |
| `registryVersion` | `uint32` | Immutable registry snapshot used for signer selection and public-key lookup. |
| `signaturesRequired` | `uint32` | Minimum number of selected signers required for this update. |
| `value` | `bytes32` | Application-defined value committed by the oracle nodes. |
| `canonicalTimestamp` | `uint64` | Timestamp committed by the oracle nodes and used in deterministic signer selection. |

`value` is intentionally opaque to the verifier. Consumers that need prices,
round ids, decimals, status flags, or multi-word payloads should define their own
canonical encoding and hash it into this `bytes32` value.

## Signer bitmap

`signersBitmap` identifies the nodes whose keys were included in the aggregate
signature.

- Registry node indices are zero-based.
- Bitmap positions are zero-based.
- Node index `i` maps to bit `i`.
- At most 256 active nodes can exist in a registry snapshot, so the bitmap fits
  in one `uint256`.
- Bits outside the selected signer group are invalid, even if the aggregate
  signature would otherwise verify.

Example:

```text
node index 0 -> bit 0 -> 0x...0001
node index 1 -> bit 1 -> 0x...0002
node index 7 -> bit 7 -> 0x...0080
```

For nodes `0`, `1`, and `7`, the bitmap is:

```text
0b10000011
0x83
```

Node indices are scoped to the registry version. Removing a node can swap the
tail node into the removed index in later registry versions, so consumers and
signers must not reuse an index from one registry version with another.

## Selection seed

For each update, the verifier derives a deterministic signer-selection seed:

```text
selectionSeed = keccak256(
  keccak256("MOLPHA_SELECTION_V1") ||
  sourceId ||
  registryVersion ||
  canonicalTimestamp
)
```

The selected group size is:

```text
groupSize = min(signaturesRequired + redundancyBuffer, nodeCount)
```

`redundancyBuffer` is a protocol-admin setting stored on the verifier. The
selection algorithm then samples `groupSize` node positions without replacement
from the requested registry snapshot.

Signers must compute the same selection bitmap before signing. A submitted
signature is accepted only if every set bit in `signersBitmap` is also set in the
deterministically selected bitmap.

## Signed message

The aggregate Schnorr signature signs this digest:

```text
message = keccak256(
  keccak256("MOLPHA_MESSAGE_V1") ||
  sourceId ||
  registryVersion ||
  signaturesRequired ||
  signersBitmap ||
  value ||
  canonicalTimestamp
)
```

The `signersBitmap` is part of the signed message. Changing the signer coalition
after signing changes the digest and must invalidate the signature.

The Schnorr challenge inside `LibSchnorr` is:

```text
challenge = keccak256(
  aggregatePubkey.x ||
  uint8(aggregatePubkey.yParity) ||
  message ||
  commitment
) mod secp256k1_order
```

The aggregate public key is the plain elliptic-curve sum of the public keys for
the signer indices present in `signersBitmap`, processed in ascending node-index
order.

## Registration proof of possession

Node registration uses the same Schnorr proof shape without a bitmap:

```solidity
struct SchnorrProof {
    bytes32 signature;
    address commitment;
}
```

The proof signs:

```text
popMessage = keccak256(
  keccak256("MOLPHA_VERIFIER_V1") ||
  verifierAddress ||
  compressedPubKey
)
```

`compressedPubKey` is the compressed secp256k1 public key submitted to
`addNode(...)`. Binding the proof to `verifierAddress` prevents replaying a proof
of possession from one verifier deployment into another.

## Verification outcomes

`verify(...)` returns `true` only when the aggregate Schnorr signature is valid
for the selected signer coalition and the exact signed message.

All other outcomes return `false`, including:

- Unknown `registryVersion`
- Empty registry snapshot
- `signaturesRequired == 0`
- Empty `signersBitmap`
- Fewer set bits than `signaturesRequired`
- Any signer bit outside the selected group
- Zero signature or zero commitment
- Signature scalar outside the secp256k1 scalar field
- Aggregate public key at infinity
- Incorrect Schnorr signature for the signed message

## Consumer responsibilities

The message format authenticates that enough selected Molpha nodes signed the
specified fields. It does not define application semantics for those fields.

Consumers are responsible for:

- Interpreting `sourceId` and `value`
- Enforcing timestamp freshness and monotonicity
- Rejecting stale, replayed, or out-of-order updates
- Choosing acceptable `registryVersion` and `signaturesRequired` values
- Enforcing feed authorization for the consuming application
- Handling decimals, scale, status, and invalid-value sentinels in their own
  payload format
