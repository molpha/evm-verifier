// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test, console2} from "forge-std/Test.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {Validator} from "../src/Validator.sol";
import {IValidator} from "../src/interfaces/IValidator.sol";
import {IValidatorStructs} from "../src/interfaces/IValidatorStructs.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {NodeGroupBitmapLib} from "../src/libs/NodeGroupBitmapLib.sol";
import {LibSchnorrTestSign} from "./libs/LibSchnorrTestSign.sol";

// Matches private constants in `Validator.sol` (same string literals).
bytes32 constant POP_DOMAIN = keccak256("MOLPHA_VALIDATOR_V1");
bytes32 constant MESSAGE_PREFIX = keccak256("MOLPHA_MESSAGE_V1");
bytes32 constant SELECTION_SEED_PREFIX = keccak256("MOLPHA_SELECTION_V1");

/// @title ValidatorTest
/// @dev `verify` gas benchmarks measure execution only (`gasleft()` delta). Calldata + 21k base are printed for reference.
contract ValidatorTest is Test {
    using MessageHashUtils for bytes32;
    using LibSecp256k1 for LibSecp256k1.Point;

    uint256 internal constant BASE_TX_GAS = 21_000;

    Validator internal v;
    uint256[] internal secrets;
    LibSecp256k1.Point[] internal pubPoints;

    function setUp() public {
        v = new Validator();
        v.initialize();
    }

    function _sk(uint256 slot) internal pure returns (uint256) {
        uint256 q = LibSecp256k1.Q();
        return (uint256(keccak256(abi.encodePacked("VALIDATOR_TEST_SK", slot))) % (q - 1)) + 1;
    }

    function _pop(address validatorAddr, bytes memory compressed, uint256 sk)
        internal
        pure
        returns (IValidatorStructs.SchnorrProof memory pop)
    {
        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, validatorAddr, compressed));
        LibSecp256k1.Point memory pk = LibSecp256k1.mulAffine(LibSecp256k1.G(), sk);
        (bytes32 sig, address cmt) = LibSchnorrTestSign.sign(pk, sk, digest, 0);
        pop = IValidatorStructs.SchnorrProof({signature: sig, commitment: cmt});
    }

    /// @notice Registered node count: blob slot 0 is aggregate; nodes occupy `1..keysLen-1`.
    function _registeredNodeCount(Validator validator) internal view returns (uint256 n) {
        uint256 keysLen = validator.getTotalNodes();
        n = keysLen > 1 ? keysLen - 1 : 0;
    }

    function _addNodes(Validator validator, uint256 numNodes) internal {
        delete secrets;
        delete pubPoints;
        secrets = new uint256[](numNodes);
        pubPoints = new LibSecp256k1.Point[](numNodes);
        for (uint256 i; i < numNodes; ++i) {
            secrets[i] = _sk(i + 1);
            pubPoints[i] = LibSecp256k1.mulAffine(LibSecp256k1.G(), secrets[i]);
            bytes memory compressed = LibSecp256k1.compress(pubPoints[i]);
            validator.addNode(compressed, _pop(address(validator), compressed, secrets[i]));
        }
    }

    /// @dev Uses contract storage `secrets` populated by `_addNodes`.
    function _sumSecretsStorage(uint256[] memory idx1based) internal view returns (uint256 skEff) {
        uint256 Q = LibSecp256k1.Q();
        for (uint256 i; i < idx1based.length; ++i) {
            uint256 idx = idx1based[i];
            skEff = addmod(skEff, secrets[idx - 1], Q);
        }
    }

    function _sumPubkeys(LibSecp256k1.Point[] memory pts) internal view returns (LibSecp256k1.Point memory agg) {
        require(pts.length != 0, "empty");
        agg = pts[0];
        for (uint256 i = 1; i < pts.length; ++i) {
            (uint256 ax, uint256 ay, uint256 az) = LibSecp256k1.addAffinePointToXYZ(agg.x, agg.y, 1, pts[i].x, pts[i].y);
            agg = LibSecp256k1.toAffineModexpXYZ(ax, ay, az);
        }
    }

    function _roundId(IValidatorStructs.DataUpdate memory du) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(MESSAGE_PREFIX, du.jobId, du.registryVersion, du.canonicalTimestamp));
    }

    function _selectionSeed(IValidatorStructs.DataUpdate memory du) internal pure returns (bytes32) {
        bytes32 rid = _roundId(du);
        return keccak256(abi.encodePacked(SELECTION_SEED_PREFIX, du.jobId, du.registryVersion, rid));
    }

    function _constructMessage(IValidatorStructs.DataUpdate memory du, uint256 signersBitmap)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
                abi.encodePacked(
                    MESSAGE_PREFIX,
                    du.jobId,
                    du.registryVersion,
                    du.signaturesRequired,
                    signersBitmap,
                    du.value,
                    du.canonicalTimestamp
                )
            );
    }

    /// @dev Collect the first `need` signer indices (1-based) whose bits are set in `bitmap`.
    function _pickSignerIndices(uint256 bitmap, uint256 nRegistered, uint256 need)
        internal
        pure
        returns (uint256[] memory idx1based)
    {
        idx1based = new uint256[](need);
        uint256 found;
        for (uint256 pos = 0; pos < nRegistered && found < need; ++pos) {
            if (bitmap & (uint256(1) << pos) != 0) {
                idx1based[found++] = pos + 1;
            }
        }
        require(found == need, "pickSignerIndices");
    }

    function _pubkeysForIndices(uint256[] memory idx1based) internal view returns (LibSecp256k1.Point[] memory pts) {
        pts = new LibSecp256k1.Point[](idx1based.length);
        for (uint256 i; i < idx1based.length; ++i) {
            pts[i] = pubPoints[idx1based[i] - 1];
        }
    }

    function _buildVerify(
        Validator validator,
        uint256 sigReq,
        bytes32 jobId,
        bytes32 value,
        uint64 canonicalTs
    ) internal view returns (IValidatorStructs.DataUpdate memory du, IValidatorStructs.SchnorrSignature memory sch) {
        du = IValidatorStructs.DataUpdate({
            jobId: jobId,
            registryVersion: uint32(validator.getRegistryVersion()),
            signaturesRequired: uint32(sigReq),
            value: value,
            canonicalTimestamp: canonicalTs
        });

        uint256 nReg = _registeredNodeCount(validator);
        uint256 grpSize = sigReq + validator.redundancyBuffer();
        bytes32 selSeed = _selectionSeed(du);
        uint256 selectionBitmap = NodeGroupBitmapLib.derive(selSeed, nReg, grpSize);

        uint256[] memory idxs = _pickSignerIndices(selectionBitmap, nReg, sigReq);
        LibSecp256k1.Point[] memory pts = _pubkeysForIndices(idxs);
        LibSecp256k1.Point memory aggPk = _sumPubkeys(pts);

        uint256 signerBits;
        for (uint256 i; i < idxs.length; ++i) {
            signerBits |= uint256(1) << (idxs[i] - 1);
        }

        bytes32 msgHash = _constructMessage(du, signerBits);
        uint256 skEff = _sumSecretsStorage(idxs);
        (bytes32 sig, address cmt) = LibSchnorrTestSign.sign(aggPk, skEff, msgHash, 0);

        sch = IValidatorStructs.SchnorrSignature({signature: sig, commitment: cmt, signersBitmap: signerBits});
    }

    function _calldataCost(bytes memory data) internal pure returns (uint256 cost) {
        for (uint256 i; i < data.length; ++i) {
            cost += (data[i] == 0) ? 4 : 16;
        }
    }

    // --- initialize / admin ---

    function test_initialize_sets_admin_and_defaults() public view {
        assertEq(v.protocolAdmin(), address(this));
        assertEq(v.redundancyBuffer(), 2);
        assertEq(v.getTotalNodes(), 1);
    }

    function test_addNode_emits_and_registers() public {
        uint256 sk = _sk(1);
        LibSecp256k1.Point memory pk = LibSecp256k1.mulAffine(LibSecp256k1.G(), sk);
        bytes memory compressed = LibSecp256k1.compress(pk);
        address nodeAddr = pk.toAddress();

        v.addNode(compressed, _pop(address(v), compressed, sk));

        assertTrue(v.isNode(nodeAddr));
        assertEq(v.getNodeIndex(nodeAddr), 1);
        assertEq(v.getTotalNodes(), 2);

        (uint256 ax, uint256 ay) = v.getAggregateKey();
        assertEq(ax, pk.x);
        assertEq(ay, pk.y);
    }

    function test_addNode_revert_duplicate() public {
        uint256 sk = _sk(1);
        LibSecp256k1.Point memory pk = LibSecp256k1.mulAffine(LibSecp256k1.G(), sk);
        bytes memory compressed = LibSecp256k1.compress(pk);
        v.addNode(compressed, _pop(address(v), compressed, sk));
        IValidatorStructs.SchnorrProof memory popAgain = _pop(address(v), compressed, sk);
        vm.expectRevert(bytes("Node already added"));
        v.addNode(compressed, popAgain);
    }

    function test_addNode_revert_not_admin() public {
        uint256 sk = _sk(1);
        LibSecp256k1.Point memory pk = LibSecp256k1.mulAffine(LibSecp256k1.G(), sk);
        bytes memory compressed = LibSecp256k1.compress(pk);
        IValidatorStructs.SchnorrProof memory pop = _pop(address(v), compressed, sk);
        address alice = address(0xA11CE);
        vm.expectRevert(bytes("Not protocol admin"));
        vm.prank(alice);
        v.addNode(compressed, pop);
    }

    function test_removeNode_revert_not_admin() public {
        uint256 sk = _sk(1);
        LibSecp256k1.Point memory pk = LibSecp256k1.mulAffine(LibSecp256k1.G(), sk);
        bytes memory compressed = LibSecp256k1.compress(pk);
        address nodeAddr = pk.toAddress();
        v.addNode(compressed, _pop(address(v), compressed, sk));

        vm.prank(address(0xB0B));
        vm.expectRevert(bytes("Not protocol admin"));
        v.removeNode(nodeAddr);
    }

    function test_removeNode_revert_not_registered() public {
        vm.expectRevert(bytes("Not node"));
        v.removeNode(address(0xDEAD));
    }

    function test_removeNode_last_resets_aggregate() public {
        uint256 sk = _sk(1);
        LibSecp256k1.Point memory pk = LibSecp256k1.mulAffine(LibSecp256k1.G(), sk);
        bytes memory compressed = LibSecp256k1.compress(pk);
        address nodeAddr = pk.toAddress();
        v.addNode(compressed, _pop(address(v), compressed, sk));

        v.removeNode(nodeAddr);
        assertFalse(v.isNode(nodeAddr));

        (uint256 ax, uint256 ay) = v.getAggregateKey();
        assertEq(ax, 0);
        assertEq(ay, 0);
        assertEq(v.getTotalNodes(), 1);
    }

    function test_removeNode_swap_middle() public {
        _addNodes(v, 3);
        address middle = pubPoints[1].toAddress();
        uint256 ptrBefore = uint256(uint160(v.getRegistryPointer()));

        v.removeNode(middle);

        assertFalse(v.isNode(middle));
        assertEq(v.getTotalNodes(), 3);

        // Third node's address should now occupy index 2 (former middle slot after swap-with-last).
        address last = pubPoints[2].toAddress();
        assertEq(v.getNodeIndex(last), 2);
        assertTrue(uint256(uint160(v.getRegistryPointer())) != ptrBefore);
    }

    function test_getNodesSetHash_stable_for_same_set() public {
        _addNodes(v, 2);
        bytes32 h1 = v.getNodesSetHash();
        bytes32 h2 = v.getNodesSetHash();
        assertEq(h1, h2);
    }

    // --- verify ---

    function test_verify_revert_no_nodes() public {
        IValidatorStructs.DataUpdate memory du = IValidatorStructs.DataUpdate({
            jobId: bytes32(uint256(1)),
            registryVersion: 0,
            signaturesRequired: 1,
            value: bytes32(uint256(3)),
            canonicalTimestamp: uint64(block.timestamp)
        });
        IValidatorStructs.SchnorrSignature memory sch;

        vm.expectRevert(bytes("No nodes"));
        v.verify(du, sch);
    }

    function test_verify_happy_path() public {
        uint256 numNodes = 5;
        uint256 sigReq = 3;
        _addNodes(v, numNodes);

        (IValidatorStructs.DataUpdate memory du, IValidatorStructs.SchnorrSignature memory sch) =
            _buildVerify(v, sigReq, bytes32("job-a"), bytes32("val"), uint64(1700000000));

        assertTrue(v.verify(du, sch));
    }

    function test_verify_returns_false_for_tampered_signature() public {
        _addNodes(v, 5);

        (IValidatorStructs.DataUpdate memory du, IValidatorStructs.SchnorrSignature memory sch) =
            _buildVerify(v, 3, bytes32("job-b"), bytes32("val"), uint64(1700000001));

        sch.signature = bytes32(uint256(sch.signature) ^ 1);
        assertFalse(v.verify(du, sch));
    }

    function test_verify_returns_false_for_tampered_signatures_required() public {
        _addNodes(v, 5);

        for (uint256 salt = 1; salt < 1000; ++salt) {
            (IValidatorStructs.DataUpdate memory du, IValidatorStructs.SchnorrSignature memory sch) =
                _buildVerify(v, 3, bytes32(salt), bytes32("val"), uint64(1700000001));

            IValidatorStructs.DataUpdate memory tampered = du;
            tampered.signaturesRequired = 2;

            uint256 selectionBitmap = NodeGroupBitmapLib.derive(_selectionSeed(tampered), 5, 4);
            if (sch.signersBitmap & ~selectionBitmap == 0) {
                assertFalse(v.verify(tampered, sch));
                return;
            }
        }

        fail();
    }

    function test_verify_revert_zero_signatures_required() public {
        _addNodes(v, 5);

        IValidatorStructs.DataUpdate memory du = IValidatorStructs.DataUpdate({
            jobId: bytes32("zero-threshold"),
            registryVersion: uint32(v.getRegistryVersion()),
            signaturesRequired: 0,
            value: bytes32("val"),
            canonicalTimestamp: uint64(1700000001)
        });
        IValidatorStructs.SchnorrSignature memory sch;

        vm.expectRevert(bytes("Zero signatures required"));
        v.verify(du, sch);
    }

    function test_verify_revert_zero_signature_inputs() public {
        _addNodes(v, 5);

        (IValidatorStructs.DataUpdate memory du, IValidatorStructs.SchnorrSignature memory sch) =
            _buildVerify(v, 3, bytes32("job-zero"), bytes32("val"), uint64(1700000001));

        IValidatorStructs.SchnorrSignature memory zeroSigners = IValidatorStructs.SchnorrSignature({
            signature: sch.signature, commitment: sch.commitment, signersBitmap: 0
        });
        vm.expectRevert(bytes("Zero signers bitmap"));
        v.verify(du, zeroSigners);

        IValidatorStructs.SchnorrSignature memory zeroSignature = IValidatorStructs.SchnorrSignature({
            signature: 0, commitment: sch.commitment, signersBitmap: sch.signersBitmap
        });
        vm.expectRevert(bytes("Zero signature"));
        v.verify(du, zeroSignature);

        IValidatorStructs.SchnorrSignature memory zeroCommitment = IValidatorStructs.SchnorrSignature({
            signature: sch.signature, commitment: address(0), signersBitmap: sch.signersBitmap
        });
        vm.expectRevert(bytes("Zero commitment"));
        v.verify(du, zeroCommitment);
    }

    function test_verify_revert_not_enough_signatures() public {
        _addNodes(v, 5);

        (IValidatorStructs.DataUpdate memory du, IValidatorStructs.SchnorrSignature memory sch) =
            _buildVerify(v, 3, bytes32("job-c"), bytes32("val"), uint64(1700000002));

        // Drop one signer bit → popCount 2 < 3
        sch.signersBitmap &= ~uint256(1);

        vm.expectRevert(bytes("Not enough signatures"));
        v.verify(du, sch);
    }

    function test_verify_revert_signer_not_in_selection() public {
        _addNodes(v, 6);

        (IValidatorStructs.DataUpdate memory du, IValidatorStructs.SchnorrSignature memory sch) =
            _buildVerify(v, 3, bytes32("job-d"), bytes32("val"), uint64(1700000003));

        // Flip a bit that is not in the selection bitmap for this update.
        sch.signersBitmap ^= uint256(1) << 255;

        vm.expectRevert(bytes("Signer not selected"));
        v.verify(du, sch);
    }

    function test_verify_caps_group_size_when_buffer_exceeds_nodes() public {
        _addNodes(v, 2);
        // redundancyBuffer=2 → uncapped grpSize = 4, capped to nodeCount = 2
        IValidatorStructs.DataUpdate memory du = IValidatorStructs.DataUpdate({
            jobId: bytes32("x"),
            registryVersion: uint32(v.getRegistryVersion()),
            signaturesRequired: 2,
            value: bytes32(0),
            canonicalTimestamp: 1
        });
        IValidatorStructs.SchnorrSignature memory sch;
        sch.signersBitmap = 3;
        sch.signature = bytes32(uint256(1));
        sch.commitment = address(1);

        assertFalse(v.verify(du, sch));
    }

    function test_fuzz_verify_matches_selection_bitmap(uint256 jobSalt, uint64 ts) public {
        ts = uint64(bound(ts, 1, type(uint64).max));
        _addNodes(v, 8);

        (IValidatorStructs.DataUpdate memory du, IValidatorStructs.SchnorrSignature memory sch) =
            _buildVerify(v, 4, bytes32(jobSalt), bytes32(uint256(888)), ts);

        assertTrue(v.verify(du, sch));
    }

    // --- gas (execution + estimated total) ---

    function _benchVerify(uint256 numNodes, uint256 sigReq, bytes32 jobId) internal {
        vm.pauseGasMetering();
        Validator vv = new Validator();
        vv.initialize();
        _addNodes(vv, numNodes);

        (IValidatorStructs.DataUpdate memory du, IValidatorStructs.SchnorrSignature memory sch) =
            _buildVerify(vv, sigReq, jobId, bytes32("val"), uint64(1700000100));

        bytes memory cd = abi.encodeCall(IValidator.verify, (du, sch));
        uint256 cdCost = _calldataCost(cd);
        vm.resumeGasMetering();

        uint256 gasBefore = gasleft();
        vv.verify(du, sch);
        uint256 exec = gasBefore - gasleft();

        vm.pauseGasMetering();
        uint256 totalEst = exec + cdCost + BASE_TX_GAS;
        console2.log("nodes", numNodes);
        console2.log("sigReq", sigReq);
        console2.log("exec_gas", exec);
        console2.log("calldata_gas", cdCost);
        console2.log("total_est_with_base_and_calldata", totalEst);
        vm.resumeGasMetering();
    }

    function test_gas_verify_5_nodes_threshold_3() public {
        _benchVerify(5, 3, bytes32("gas-5-3"));
    }

    function test_gas_verify_10_nodes_threshold_5() public {
        _benchVerify(10, 5, bytes32("gas-10-5"));
    }

    function test_gas_verify_20_nodes_threshold_8() public {
        _benchVerify(20, 8, bytes32("gas-20-8"));
    }

    function test_fixture_solana_compat_10nodes_8signers() public {
        uint256 numNodes = 10;
        uint256 sigReq = 8;

        // Setup: register 10 nodes (deterministic keys).
        _addNodes(v, numNodes);
        assertEq(_registeredNodeCount(v), numNodes);

        // Build a deterministic data update.
        IValidatorStructs.DataUpdate memory du = IValidatorStructs.DataUpdate({
            jobId: bytes32("solana-compat-job"),
            registryVersion: uint32(v.getRegistryVersion()),
            signaturesRequired: uint32(sigReq),
            value: bytes32("solana-compat-val"),
            canonicalTimestamp: uint64(1_700_000_123)
        });

        // Selection + signer list (must be 8 signers from 10 nodes).
        uint256 grpSize = sigReq + v.redundancyBuffer();
        bytes32 selSeed = _selectionSeed(du);
        uint256 selectionBitmap = NodeGroupBitmapLib.derive(selSeed, numNodes, grpSize);
        uint256[] memory idxs = _pickSignerIndices(selectionBitmap, numNodes, sigReq);

        uint256 signersBitmap;
        for (uint256 i; i < idxs.length; ++i) {
            signersBitmap |= uint256(1) << (idxs[i] - 1);
        }

        // Aggregate pubkey + signature over the constructed message.
        LibSecp256k1.Point[] memory pts = _pubkeysForIndices(idxs);
        LibSecp256k1.Point memory aggPk = _sumPubkeys(pts);
        bytes32 msgHash = _constructMessage(du, signersBitmap);
        uint256 skEff = _sumSecretsStorage(idxs);
        (bytes32 sig, address cmt) = LibSchnorrTestSign.sign(aggPk, skEff, msgHash, 0);
        IValidatorStructs.SchnorrSignature memory sch =
            IValidatorStructs.SchnorrSignature({signature: sig, commitment: cmt, signersBitmap: signersBitmap});

        // Sanity: on-chain verify must pass.
        assertTrue(v.verify(du, sch));

        // Build node pubkey fixtures (compressed pubkeys).
        bytes[] memory nodePubkeys = new bytes[](numNodes);
        for (uint256 i; i < numNodes; ++i) {
            nodePubkeys[i] = LibSecp256k1.compress(pubPoints[i]);
        }

        // Emit a single JSON object fixture to stdout.
        string memory out = "{";
        out = string.concat(out, '"registeredNodeCount":', vm.toString(numNodes), ",");
        out = string.concat(out, '"registryVersion":', vm.toString(uint256(du.registryVersion)), ",");

        out = string.concat(out, '"nodeIndexesOneBased":[');
        for (uint256 i; i < idxs.length; ++i) {
            out = string.concat(out, vm.toString(idxs[i]));
            if (i + 1 < idxs.length) out = string.concat(out, ",");
        }
        out = string.concat(out, "],");

        out = string.concat(out, '"nodePubkeys":[');
        for (uint256 i; i < nodePubkeys.length; ++i) {
            out = string.concat(out, '"', vm.toString(nodePubkeys[i]), '"');
            if (i + 1 < nodePubkeys.length) out = string.concat(out, ",");
        }
        out = string.concat(out, "],");

        out = string.concat(out, '"secretKeys":[');
        for (uint256 i; i < idxs.length; ++i) {
            out = string.concat(out, '"', vm.toString(secrets[i]), '"');
            // out = string.concat(out, vm.toString(secrets[idxs[i] - 1]));
            if (i + 1 < idxs.length) out = string.concat(out, ",");
        }
        out = string.concat(out, "],");

        out = string.concat(out, '"dataUpdate":{');
        out = string.concat(out, '"jobId":"', vm.toString(du.jobId), '",');
        out = string.concat(out, '"registryVersion":', vm.toString(uint256(du.registryVersion)), ",");
        out = string.concat(out, '"signaturesRequired":', vm.toString(sigReq), ",");
        out = string.concat(out, '"value":"', vm.toString(du.value), '",');
        out = string.concat(out, '"canonicalTimestamp":', vm.toString(uint256(du.canonicalTimestamp)));
        out = string.concat(out, "},");

        out = string.concat(out, '"schnorrSignature":{');
        out = string.concat(out, '"signature":"', vm.toString(sch.signature), '",');
        out = string.concat(out, '"commitment":"', vm.toString(sch.commitment), '",');
        out = string.concat(out, '"signersBitmap":', vm.toString(sch.signersBitmap));
        out = string.concat(out, "}");

        out = string.concat(out, "}");
        console2.log(out);
    }
}
