// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {IVerifier} from "../interfaces/IVerifier.sol";
import {LibSecp256k1} from "./LibSecp256k1.sol";

/// @title VerifierLib
/// @notice Registry-entry packing and the pure/view math behind `Verifier.verify`.
library VerifierLib {
    /// @dev SSTORE2 blob index of the first encoded point: 1 STOP byte + 64-byte array head.
    uint256 private constant KEYS_CODE_OFFSET = 65;

    bytes32 private constant MESSAGE_PREFIX = keccak256("MOLPHA_MESSAGE_V1");

    /// @notice Milliseconds per second. `timestamp` is unix milliseconds; `maxAge` and registry
    ///         activation are in seconds.
    uint64 internal constant MILLIS_PER_SECOND = 1000;

    /// @dev Packed registry entry (registry-v2):
    ///      bits   0..159   SSTORE2 pointer
    ///      bits 160..168   nodeCount (9): key slots in the blob, holes included
    ///      bits 169..195   reserved (27)
    ///      bits 196..235   activatesAt unix seconds (40)
    ///      bit  236         isLatest (1)
    ///      bits 237..255   reserved (19)
    uint256 private constant NODE_COUNT_SHIFT = 160;
    uint256 private constant ACTIVATES_AT_SHIFT = 196;
    uint256 private constant IS_LATEST_SHIFT = 236;
    uint256 private constant COUNT_MASK = 0x1ff;
    uint256 private constant TIMESTAMP_MASK = 0xffffffffff;
    uint256 private constant IS_LATEST_MASK = uint256(1) << IS_LATEST_SHIFT;

    /// @dev `timestamp` (unix milliseconds) as unix seconds, the unit of `block.timestamp`
    ///      and of `activatesAt`. Floors, so a timestamp up to 999 ms ahead of the chain clock still
    ///      reads as the current second.
    function timestampSeconds(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / MILLIS_PER_SECOND;
    }

    function constructMessage(IVerifier.AttestationPayload calldata payload, uint256 signersBitmap)
        internal
        pure
        returns (bytes32 message)
    {
        message = keccak256(
            abi.encodePacked(
                MESSAGE_PREFIX,
                payload.value,
                payload.sourceId,
                payload.registryVersion,
                payload.signaturesRequired,
                payload.timestamp,
                signersBitmap
            )
        );
    }

    /// @dev Reads a single key straight out of the SSTORE2 blob, without materialising the
    ///      whole array in memory. `entry` is the packed slot; `extcodecopy` truncates its
    ///      address operand to 160 bits, so the upper fields are discarded for free.
    ///      Out-of-range indices and holes (removed nodes) read as the zero point.
    function nodeAt(uint256 entry, uint256 blobIndex) internal view returns (LibSecp256k1.Point memory node) {
        assembly ("memory-safe") {
            extcodecopy(entry, node, add(KEYS_CODE_OFFSET, shl(6, blobIndex)), 64)
        }
    }

    /// @dev Sum the public keys of every set bit in `signersBitmap`.
    ///      `entry` is the packed registry slot; its low 160 bits are the SSTORE2 pointer
    ///      (extcodecopy truncates the upper fields automatically).
    ///      One assembly loop fuses: lowest-bit scan, key load, and Jacobian EC addition.
    /// @return aggPubKey The coalition key, or the zero point when the sum is the point at infinity.
    /// @return valid False when a set bit names no live node: it is past the last slot or on a hole,
    ///         and either reads as the zero point, which is no key. This is the bitmap's only bound
    ///         check, so it must run for every set bit.
    function aggregatePubKey(uint256 entry, uint256 signersBitmap)
        internal
        view
        returns (LibSecp256k1.Point memory aggPubKey, bool valid)
    {
        // Jacobian accumulator (ax, ay, az); az == 1 after the first signer.
        uint256 ax;
        uint256 ay;
        uint256 az;
        // Non-zero once a set bit named the zero point.
        uint256 vacant;

        assembly ("memory-safe") {
            // Return (x, y) for the lowest set bit in `mask`.
            // pos = index of that bit; extcodecopy reads 64 bytes into scratch 0x00.
            function readLowestKey(ptr, mask) -> x, y {
                // ffs(mask): isolate lowest set bit, then De Bruijn lookup → bit index.
                let bit := and(mask, add(not(mask), 1))
                let pos :=
                    shl(
                        5,
                        shr(
                            252,
                            shl(
                                shl(
                                    2,
                                    shr(
                                        250,
                                        mul(bit, 0xb6db6db6ddddddddd34d34d349249249210842108c6318c639ce739cffffffff)
                                    )
                                ),
                                0x8040405543005266443200005020610674053026020000107506200176117077
                            )
                        )
                    )
                pos := or(
                    pos,
                    byte(
                        and(div(0xd76453e0, shr(pos, bit)), 0x1f),
                        0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405
                    )
                )
                // Blob layout: STOP byte + ABI head, then node i at offset KEYS_CODE_OFFSET + 64*i.
                extcodecopy(ptr, 0x00, add(KEYS_CODE_OFFSET, shl(6, pos)), 64)
                x := mload(0x00)
                y := mload(0x20)
            }

            let P := 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
            let rem := signersBitmap

            // Mixed Jacobian+affine step: handles infinity, cancellation, doubling, and madd-2007-bl.
            function addMixed(x1, y1, z1, px, py, p) -> x3, y3, z3 {
                if iszero(z1) {
                    x3 := px
                    y3 := py
                    z3 := 1
                    leave
                }

                let z2 := mulmod(z1, z1, p)
                let z1cubed := mulmod(z2, z1, p)
                let h := addmod(mulmod(px, z2, p), sub(p, x1), p)

                if h {
                    let r := mulmod(2, addmod(mulmod(py, z1cubed, p), sub(p, y1), p), p)
                    let h2 := mulmod(h, h, p)
                    let i2 := mulmod(4, h2, p)
                    let v := mulmod(x1, i2, p)
                    let j := mulmod(h, i2, p)
                    let azh := addmod(z1, h, p)
                    z3 := addmod(mulmod(azh, azh, p), addmod(sub(p, z2), sub(p, h2), p), p)
                    x3 := addmod(mulmod(r, r, p), addmod(sub(p, j), sub(p, mulmod(2, v, p)), p), p)
                    y3 := mulmod(r, addmod(v, sub(p, x3), p), p)
                    y3 := addmod(y3, sub(p, mulmod(2, mulmod(y1, j, p), p)), p)
                    leave
                }

                let r := mulmod(2, addmod(mulmod(py, z1cubed, p), sub(p, y1), p), p)
                if iszero(r) {
                    let a := mulmod(x1, x1, p)
                    let b := mulmod(y1, y1, p)
                    let c := mulmod(b, b, p)
                    let d := addmod(x1, b, p)
                    d := mulmod(d, d, p)
                    d := addmod(addmod(d, sub(p, a), p), sub(p, c), p)
                    d := mulmod(2, d, p)
                    let e := mulmod(3, a, p)
                    let f := mulmod(e, e, p)
                    x3 := addmod(f, sub(p, mulmod(2, d, p)), p)
                    y3 := mulmod(e, addmod(d, sub(p, x3), p), p)
                    y3 := addmod(y3, sub(p, mulmod(8, c, p)), p)
                    z3 := mulmod(2, mulmod(y1, z1, p), p)
                    leave
                }

                x3 := 0
                y3 := 0
                z3 := 0
            }

            // Seed accumulator with the first signer (affine: z = 1).
            ax, ay := readLowestKey(entry, rem)
            vacant := iszero(or(ax, ay))
            az := 1
            rem := and(rem, sub(rem, 1)) // clear lowest bit

            for {} rem {} {
                let px, py := readLowestKey(entry, rem)
                vacant := or(vacant, iszero(or(px, py)))
                rem := and(rem, sub(rem, 1))
                ax, ay, az := addMixed(ax, ay, az, px, py, P)
            }
        }

        if (vacant != 0) return (LibSecp256k1.ZERO_POINT(), false);
        valid = true;
        // az == 0 means the running sum hit the point at infinity.
        if (az == 0) return (LibSecp256k1.ZERO_POINT(), true);
        aggPubKey = LibSecp256k1.toAffineModexpXYZ(ax, ay, az);
    }

    function packEntry(address pointer, uint256 nodeCount_, uint256 activatesAtTs, bool isLatest_)
        internal
        pure
        returns (uint256 entry)
    {
        entry = uint256(uint160(pointer)) | (nodeCount_ << NODE_COUNT_SHIFT) | (activatesAtTs << ACTIVATES_AT_SHIFT);
        if (isLatest_) entry |= IS_LATEST_MASK;
    }

    /// @dev Sets or clears the `isLatest` flag without touching any other packed field.
    function withIsLatest(uint256 entry, bool isLatest_) internal pure returns (uint256) {
        if (isLatest_) return entry | IS_LATEST_MASK;
        return entry & ~IS_LATEST_MASK;
    }

    /// @dev Key slots in the blob, holes included. A removed node leaves a hole (the zero point),
    ///      so this is not the number of live nodes. Trailing holes are trimmed.
    function nodeCount(uint256 entry) internal pure returns (uint256) {
        return (entry >> NODE_COUNT_SHIFT) & COUNT_MASK;
    }

    function activatesAt(uint256 entry) internal pure returns (uint256) {
        return (entry >> ACTIVATES_AT_SHIFT) & TIMESTAMP_MASK;
    }

    function isLatest(uint256 entry) internal pure returns (bool) {
        return (entry & IS_LATEST_MASK) != 0;
    }

    /// @dev The pointer occupies bits 0..159 by construction, so truncating to 160 bits *is* the field read.
    function pointerOf(uint256 entry) internal pure returns (address keysPtr) {
        // forge-lint: disable-next-line(unsafe-typecast)
        keysPtr = address(uint160(entry));
    }
}
