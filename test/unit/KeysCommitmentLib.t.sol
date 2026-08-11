// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {SSTORE2} from "solady/utils/SSTORE2.sol";

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {KeysCommitmentLib} from "../../src/libs/KeysCommitmentLib.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {Verifier} from "../../src/Verifier.sol";
import {VerifierTestBase} from "../shared/VerifierTestBase.sol";

/// @dev The commitment is the cross-chain identity of a registry version — it is folded into the
///      chained registry root, so any drift between it and the actual key blob would let two
///      different node sets present the same root.
contract KeysCommitmentLibTest is VerifierTestBase {
    using LibSecp256k1 for LibSecp256k1.Point;

    function test_emptyCommitment_isTheHashOfNoCoordinates() public view {
        assertEq(KeysCommitmentLib.emptyCommitment(), keccak256(""));
        // Genesis publishes an empty key array and must land on the same value.
        assertEq(_keysCommitmentAt(verifier, 0), keccak256(""));
    }

    function test_commitment_matchesIndependentCoordinateHash() public {
        _addNodes(verifier, 3);

        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](3);
        points[0] = pubkeys[0];
        points[1] = pubkeys[1];
        points[2] = pubkeys[2];

        assertEq(_keysCommitmentAt(verifier), _keysCommitmentOf(points));
    }

    /// @dev Only the coordinate region is hashed, so ABI framing must not reach the digest.
    ///      Otherwise a re-encoding of the same keys would change the registry root.
    function test_commitment_ignoresTheAbiOffsetWord() public {
        _addNodes(verifier, 2);
        bytes memory blob = SSTORE2.read(verifier.getRegistryPointer());
        bytes32 expected = KeysCommitmentLib.commitment(blob);

        assembly ("memory-safe") {
            mstore(add(blob, 0x20), 0xdeadbeef)
        }

        assertEq(KeysCommitmentLib.commitment(blob), expected, "framing must not reach the digest");
    }

    /// @dev The digest covers exactly `nodeCount * 64` bytes, so bytes sitting past the last point
    ///      are outside it — a longer buffer holding the same keys commits identically.
    function test_commitment_ignoresBytesPastTheLastPoint() public {
        _addNodes(verifier, 2);
        bytes memory blob = SSTORE2.read(verifier.getRegistryPointer());
        bytes32 expected = KeysCommitmentLib.commitment(blob);

        bytes memory padded = bytes.concat(blob, hex"ffffffffffffffff");
        assertEq(KeysCommitmentLib.commitment(padded), expected, "trailing bytes are outside the digest");
    }

    /// @dev Order is part of the commitment: the signer bitmap addresses nodes by blob index, so
    ///      two registries holding the same keys in different slots are genuinely different sets.
    function test_commitment_isOrderSensitiveForIdenticalMembership() public {
        Verifier ascending = new Verifier(address(this), 2);
        Verifier descending = new Verifier(address(this), 2);

        uint256 secretA = _secret(101);
        uint256 secretB = _secret(102);
        bytes memory keyA = LibSecp256k1.compress(LibSecp256k1.mulAffine(LibSecp256k1.G(), secretA));
        bytes memory keyB = LibSecp256k1.compress(LibSecp256k1.mulAffine(LibSecp256k1.G(), secretB));

        ascending.addNode(keyA, _proofOfPossession(address(ascending), keyA, secretA));
        ascending.addNode(keyB, _proofOfPossession(address(ascending), keyB, secretB));

        descending.addNode(keyB, _proofOfPossession(address(descending), keyB, secretB));
        descending.addNode(keyA, _proofOfPossession(address(descending), keyA, secretA));

        assertTrue(
            _keysCommitmentAt(ascending) != _keysCommitmentAt(descending), "commitments must distinguish key order"
        );
        assertTrue(
            ascending.getRegistryRoot() != descending.getRegistryRoot(), "the ordering must reach the registry root"
        );
    }

    /// @dev Swap-and-pop reorders the blob, so removing a middle node must move the commitment even
    ///      though the removal itself is what changed the membership.
    function test_commitment_tracksSwapAndPopReordering() public {
        _addNodes(verifier, 3);
        bytes32 beforeRemoval = _keysCommitmentAt(verifier);

        _removeNode(verifier, 1);

        LibSecp256k1.Point[] memory expected = new LibSecp256k1.Point[](2);
        expected[0] = pubkeys[0];
        expected[1] = pubkeys[2];

        assertTrue(_keysCommitmentAt(verifier) != beforeRemoval, "removal must move the commitment");
        assertEq(_keysCommitmentAt(verifier), _keysCommitmentOf(expected), "post-swap blob order");
    }

    /// @dev Historical versions are immutable, so their commitments must keep resolving to the
    ///      key set that was live at the time, not to the current one.
    function test_commitment_ofHistoricalVersionSurvivesLaterMutations() public {
        _addNodes(verifier, 2);
        uint256 historicalVersion = verifier.getRegistryVersion();
        bytes32 historicalCommitment = _keysCommitmentAt(verifier, historicalVersion);

        _appendNode(verifier, 50);
        _removeNode(verifier, 0);

        assertEq(_keysCommitmentAt(verifier, historicalVersion), historicalCommitment, "history is frozen");
        assertTrue(_keysCommitmentAt(verifier) != historicalCommitment, "the live version has moved on");
    }

    /// @dev A buffer change publishes a new version without touching the key set, so the
    ///      commitment must repeat while the chained root still advances.
    function test_commitment_isUnchangedByANonKeyMutation() public {
        _addNodes(verifier, 2);
        bytes32 commitmentBefore = _keysCommitmentAt(verifier);
        bytes32 rootBefore = verifier.getRegistryRoot();

        verifier.setRedundancyBuffer(4);

        assertEq(_keysCommitmentAt(verifier), commitmentBefore, "key set did not change");
        assertTrue(verifier.getRegistryRoot() != rootBefore, "the version still advances");
    }

    function testFuzz_commitment_equalsIndependentHashForAnyNodeCount(uint8 countSeed) public {
        uint256 count = (uint256(countSeed) % 8) + 1;
        _addNodes(verifier, count);

        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](count);
        for (uint256 i; i < count; ++i) {
            points[i] = pubkeys[i];
        }

        assertEq(_keysCommitmentAt(verifier), _keysCommitmentOf(points));
    }
}
