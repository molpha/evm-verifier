// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {IVerifier} from "../interfaces/IVerifier.sol";
import {LibSecp256k1} from "./LibSecp256k1.sol";
import {NodeGroupBitmapLib} from "./NodeGroupBitmapLib.sol";

/// @title VerifierLib
/// @notice Registry-entry packing and the pure/view math behind `Verifier.verify`.
library VerifierLib {
    /// @dev SSTORE2 blob index of the first encoded point: 1 STOP byte + 64-byte array head.
    uint256 private constant KEYS_CODE_OFFSET = 65;

    bytes32 private constant MESSAGE_PREFIX = keccak256("MOLPHA_MESSAGE_V1");
    bytes32 private constant SELECTION_SEED_PREFIX = keccak256("MOLPHA_SELECTION_V1");

    /// @dev Packed registry entry (registry-v2):
    ///      bits   0..159   SSTORE2 pointer
    ///      bits 160..168   nodeCount (9)
    ///      bits 169..177   redundancyBuffer (9)
    ///      bits 178..186   compromisedIn (9)
    ///      bits 187..195   reserved (9)
    ///      bits 196..235   activatesAt unix seconds (40)
    ///      bit  236         isLatest (1)
    ///      bits 237..255   reserved (19)
    uint256 private constant NODE_COUNT_SHIFT = 160;
    uint256 private constant BUFFER_SHIFT = 169;
    uint256 private constant COMPROMISED_SHIFT = 178;
    uint256 private constant ACTIVATES_AT_SHIFT = 196;
    uint256 private constant IS_LATEST_SHIFT = 236;
    uint256 private constant COUNT_MASK = 0x1ff;
    uint256 private constant TIMESTAMP_MASK = 0xffffffffff;
    uint256 private constant IS_LATEST_MASK = uint256(1) << IS_LATEST_SHIFT;

    function constructMessage(IVerifier.DataUpdate calldata dataUpdate, uint256 signersBitmap)
        internal
        pure
        returns (bytes32 message)
    {
        message = keccak256(
            abi.encodePacked(
                MESSAGE_PREFIX,
                dataUpdate.sourceId,
                dataUpdate.registryVersion,
                dataUpdate.signaturesRequired,
                signersBitmap,
                dataUpdate.value,
                dataUpdate.canonicalTimestamp
            )
        );
    }

    function getSelectionSeed(IVerifier.DataUpdate calldata dataUpdate) internal pure returns (bytes32 selectionSeed) {
        selectionSeed = keccak256(
            abi.encodePacked(
                SELECTION_SEED_PREFIX, dataUpdate.sourceId, dataUpdate.registryVersion, dataUpdate.canonicalTimestamp
            )
        );
    }

    /// @dev Every signer must sit inside the round's deterministically derived selection group.
    ///      Compromised signers are handled separately by discounting them from the threshold
    ///      count (registry-v2 §6.4), never by rejecting them here.
    function selectionOk(IVerifier.DataUpdate calldata dataUpdate, uint256 entry, uint256 signersBitmap)
        internal
        pure
        returns (bool valid)
    {
        uint256 n = nodeCount(entry);
        if (n == 0) return false;

        uint256 groupSize = dataUpdate.signaturesRequired + buffer(entry);
        if (groupSize > n) groupSize = n;

        uint256 selectionBitmap = NodeGroupBitmapLib.derive(getSelectionSeed(dataUpdate), n, groupSize);
        valid = signersBitmap & ~selectionBitmap == 0;
    }

    /// @dev Reads a single key straight out of the SSTORE2 blob, without materialising the
    ///      whole array in memory. `entry` is the packed slot; `extcodecopy` truncates its
    ///      address operand to 160 bits, so the upper fields are discarded for free.
    ///      Out-of-range indices read as zeros — callers must bounds-check against `nodeCount`.
    function nodeAt(uint256 entry, uint256 blobIndex) internal view returns (LibSecp256k1.Point memory node) {
        assembly ("memory-safe") {
            extcodecopy(entry, node, add(KEYS_CODE_OFFSET, shl(6, blobIndex)), 64)
        }
    }

    /// @dev Sum the public keys of every set bit in `signersBitmap`.
    ///      `entry` is the packed registry slot; its low 160 bits are the SSTORE2 pointer
    ///      (extcodecopy truncates the upper fields automatically).
    ///      One assembly loop fuses: lowest-bit scan, key load, and Jacobian EC addition.
    function aggregatePubKey(uint256 entry, uint256 signersBitmap)
        internal
        view
        returns (LibSecp256k1.Point memory aggPubKey)
    {
        // Jacobian accumulator (ax, ay, az); az == 1 after the first signer.
        uint256 ax;
        uint256 ay;
        uint256 az;

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

            // Seed accumulator with the first signer (affine: z = 1).
            ax, ay := readLowestKey(entry, rem)
            az := 1
            rem := and(rem, sub(rem, 1)) // clear lowest bit

            for {} rem {} {
                let px, py := readLowestKey(entry, rem)
                rem := and(rem, sub(rem, 1))

                // madd-2007-bl: add affine (px, py) into Jacobian (ax, ay, az).
                let z2 := mulmod(az, az, P)
                let z3 := mulmod(z2, az, P)
                let h := addmod(mulmod(px, z2, P), sub(P, ax), P) // x2*Z1^2 - X1
                let h2 := mulmod(h, h, P)
                let i2 := mulmod(4, h2, P)
                let v := mulmod(ax, i2, P)
                let j := mulmod(h, i2, P)
                let r := mulmod(2, addmod(mulmod(py, z3, P), sub(P, ay), P), P) // 2*(y2*Z1^3 - Y1)

                let azh := addmod(az, h, P)
                az := addmod(mulmod(azh, azh, P), addmod(sub(P, z2), sub(P, h2), P), P) // Z3

                let nax := addmod(mulmod(r, r, P), addmod(sub(P, j), sub(P, mulmod(2, v, P)), P), P) // X3
                ay := addmod(mulmod(r, addmod(v, sub(P, nax), P), P), sub(P, mulmod(2, mulmod(ay, j, P), P)), P) // Y3
                ax := nax
            }
        }

        // az == 0 means the running sum hit the point at infinity.
        if (az == 0) return (LibSecp256k1.ZERO_POINT());
        aggPubKey = LibSecp256k1.toAffineModexpXYZ(ax, ay, az);
    }

    function packEntry(
        address pointer,
        uint256 nodeCount_,
        uint256 buffer_,
        uint256 compromisedIn_,
        uint256 activatesAtTs,
        bool isLatest_
    ) internal pure returns (uint256 entry) {
        entry = uint256(uint160(pointer)) | (nodeCount_ << NODE_COUNT_SHIFT) | (buffer_ << BUFFER_SHIFT)
            | (compromisedIn_ << COMPROMISED_SHIFT) | (activatesAtTs << ACTIVATES_AT_SHIFT);
        if (isLatest_) entry |= IS_LATEST_MASK;
    }

    /// @dev Replaces only the `compromisedIn` field, leaving every other field bit-identical.
    function withCompromisedIn(uint256 entry, uint256 compromisedIn_) internal pure returns (uint256) {
        return (entry & ~(COUNT_MASK << COMPROMISED_SHIFT)) | (compromisedIn_ << COMPROMISED_SHIFT);
    }

    /// @dev Sets or clears the `isLatest` flag without touching any other packed field.
    function withIsLatest(uint256 entry, bool isLatest_) internal pure returns (uint256) {
        if (isLatest_) return entry | IS_LATEST_MASK;
        return entry & ~IS_LATEST_MASK;
    }

    function nodeCount(uint256 entry) internal pure returns (uint256) {
        return (entry >> NODE_COUNT_SHIFT) & COUNT_MASK;
    }

    function buffer(uint256 entry) internal pure returns (uint256) {
        return (entry >> BUFFER_SHIFT) & COUNT_MASK;
    }

    function compromisedIn(uint256 entry) internal pure returns (uint256) {
        return (entry >> COMPROMISED_SHIFT) & COUNT_MASK;
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
