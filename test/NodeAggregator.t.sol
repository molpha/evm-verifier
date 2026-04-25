// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {AccessControlManager} from "../src/AccessControlManager.sol";
import {INodeRegistry, INodeRegistryStructs} from "../src/interfaces/INodeRegistry.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {LibSchnorrTestSign} from "./libs/LibSchnorrTestSign.sol";
import {DummyFeed} from "./mocks/DummyFeed.sol";

contract NodeAggregatorTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using MessageHashUtils for bytes32;

    NodeRegistry registry;
    AccessControlManager acl;

    uint256 internal constant D1 = 0xA11CE;
    uint256 internal constant D2 = 0xB0B;
    uint256 internal constant D3 = 0xC0C;
    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_NODE_REGISTRATION_V1");

    function setUp() public {
        registry = new NodeRegistry();
        acl = new AccessControlManager();

        acl.initialize(address(this));
        acl.grantRole(acl.NODE_REGISTRY(), address(this));

        registry.initialize(address(acl));
    }

    function test_registerNode_InvalidKeyLength_Revert() public {
        bytes memory zero = new bytes(0);
        vm.expectRevert("invalid length");
        registry.addNode(zero, hex"");
    }

    function test_registerAndUnregisterNode_Works() public {
        LibSecp256k1.Point memory g = LibSecp256k1.G();
        registry.addNode(LibSecp256k1.compress(g), _popSig(address(registry), LibSecp256k1.compress(g), 1));
        assertTrue(registry.isNode(g.toAddress()));
        assertEq(registry.getTotalNodes(), 1);

        registry.removeNode(g.toAddress());
        assertFalse(registry.isNode(g.toAddress()));
        assertEq(registry.getTotalNodes(), 0);
    }

    function testFuzz_verifySignature_InvalidSignersBitmap(uint256 a, uint256 b) public {
        LibSecp256k1.Point memory g = LibSecp256k1.G();
        registry.addNode(LibSecp256k1.compress(g), _popSig(address(registry), LibSecp256k1.compress(g), 1));
        // One node → only bit 0 may be set; bit 4 is out of range for nodeCount 1.
        INodeRegistryStructs.SchnorrSignature memory s = INodeRegistryStructs.SchnorrSignature({
            signature: bytes32(uint256(1)),
            commitment: address(1),
            signersBitmap: bytes32(uint256(1) << 4)
        });
        bytes32 msgHash = keccak256(abi.encodePacked(a, b));
        vm.expectRevert("Invalid signers bitmap");
        registry.verifySignature(msgHash, s, 1, uint32(0), bytes32(0), 1);
    }

    function _threeNodes()
        internal
        returns (LibSecp256k1.Point memory p1, LibSecp256k1.Point memory p2, LibSecp256k1.Point memory p3)
    {
        p1 = LibSecp256k1.mulAffine(LibSecp256k1.G(), D1);
        p2 = LibSecp256k1.mulAffine(LibSecp256k1.G(), D2);
        p3 = LibSecp256k1.mulAffine(LibSecp256k1.G(), D3);
        bytes memory c1 = LibSecp256k1.compress(p1);
        bytes memory c2 = LibSecp256k1.compress(p2);
        bytes memory c3 = LibSecp256k1.compress(p3);
        registry.addNode(c1, _popSig(address(registry), c1, D1));
        registry.addNode(c2, _popSig(address(registry), c2, D2));
        registry.addNode(c3, _popSig(address(registry), c3, D3));
    }

    function _popSig(address registryAddr, bytes memory compressedPubKey, uint256 sk) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, registryAddr, compressedPubKey)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _constructMessage(INodeRegistryStructs.DataUpdate memory u) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(u.jobId, u.value, u.timestamp, u.round)).toEthSignedMessageHash();
    }

    /// @dev Intent C: Schnorr aggregate pubkey and effective secret for node 1 in a 3-node registry (L_reg over all three).
    function _aggAndSkEffThreeNodes(
        LibSecp256k1.Point memory p1,
        LibSecp256k1.Point memory p2,
        LibSecp256k1.Point memory p3
    ) internal pure returns (LibSecp256k1.Point memory agg, uint256 skEff) {
        LibSecp256k1.Point[] memory all = new LibSecp256k1.Point[](3);
        all[0] = p1;
        all[1] = p2;
        all[2] = p3;
        skEff = LibSchnorrTestSign.effectiveSecretRegistryL(all, p1, D1);
        agg = LibSecp256k1.mulAffine(LibSecp256k1.G(), skEff);
    }

    function test_publish_reverts_zeroFeed() public {
        _threeNodes();
        bytes32 jobId = keccak256("job");
        registry.initializeJob(jobId, uint64(block.timestamp));
        uint32[] memory pm = new uint32[](3);

        INodeRegistryStructs.DataUpdate memory u =
            INodeRegistryStructs.DataUpdate({feed: address(0), jobId: jobId, value: hex"01", timestamp: 1, round: 1});
        INodeRegistryStructs.SchnorrSignature memory s = INodeRegistryStructs.SchnorrSignature({
            signature: bytes32(uint256(1)),
            commitment: address(1),
            signersBitmap: bytes32(uint256(1))
        });

        vm.expectRevert("Zero address");
        registry.publish(u, s);
    }

    function test_publish_reverts_jobNotInitialized() public {
        _threeNodes();
        DummyFeed feed = new DummyFeed();
        feed.setMinSignaturesThreshold(1);

        (,, bytes32 jobId,) = feed.getFeedConfig();
        uint32[] memory pm = new uint32[](3);

        INodeRegistryStructs.DataUpdate memory u =
            INodeRegistryStructs.DataUpdate({feed: address(feed), jobId: jobId, value: hex"01", timestamp: 1, round: 1});
        INodeRegistryStructs.SchnorrSignature memory s = INodeRegistryStructs.SchnorrSignature({
            signature: bytes32(uint256(1)),
            commitment: address(1),
            signersBitmap: bytes32(uint256(1))
        });

        vm.expectRevert("Job not initialized");
        registry.publish(u, s);
    }

    function test_publish_reverts_invalidFeedJobId() public {
        _threeNodes();
        DummyFeed feed = new DummyFeed();
        feed.setMinSignaturesThreshold(1);
        bytes32 jobId = keccak256("other");
        registry.initializeJob(jobId, uint64(block.timestamp));

        uint32[] memory pm = new uint32[](3);
        INodeRegistryStructs.DataUpdate memory u =
            INodeRegistryStructs.DataUpdate({feed: address(feed), jobId: jobId, value: hex"01", timestamp: 1, round: 1});
        INodeRegistryStructs.SchnorrSignature memory s = INodeRegistryStructs.SchnorrSignature({
            signature: bytes32(uint256(1)),
            commitment: address(1),
            signersBitmap: bytes32(uint256(1))
        });

        vm.expectRevert("Invalid feed");
        registry.publish(u, s);
    }

    function test_publish_reverts_invalidRound() public {
        (LibSecp256k1.Point memory p1, LibSecp256k1.Point memory p2, LibSecp256k1.Point memory p3) = _threeNodes();
        DummyFeed feed = new DummyFeed();
        feed.setMinSignaturesThreshold(1);
        (,, bytes32 jobId,) = feed.getFeedConfig();
        vm.warp(1_000_000);
        registry.initializeJob(jobId, uint64(block.timestamp));

        bytes32 message = _constructMessage(
            INodeRegistryStructs.DataUpdate({feed: address(feed), jobId: jobId, value: hex"01", timestamp: 2, round: 2})
        );

        (LibSecp256k1.Point memory agg, uint256 skEff) = _aggAndSkEffThreeNodes(p1, p2, p3);
        LibSecp256k1.Point memory check = LibSecp256k1.mulAffine(LibSecp256k1.G(), skEff);
        assertEq(check.x, agg.x);
        assertEq(check.y, agg.y);

        (bytes32 sig, address cmt) = LibSchnorrTestSign.sign(agg, skEff, message, 0);
        INodeRegistryStructs.SchnorrSignature memory schn =
            INodeRegistryStructs.SchnorrSignature({signature: sig, commitment: cmt, signersBitmap: bytes32(uint256(1))});

        uint32[] memory pm = new uint32[](3);
        INodeRegistryStructs.DataUpdate memory u =
            INodeRegistryStructs.DataUpdate({feed: address(feed), jobId: jobId, value: hex"01", timestamp: 2, round: 2});

        vm.expectRevert("Invalid round");
        registry.publish(u, schn);
    }

    function test_publish_reverts_noNodes() public {
        DummyFeed feed = new DummyFeed();
        feed.setMinSignaturesThreshold(1);
        (,, bytes32 jobId,) = feed.getFeedConfig();
        vm.warp(1_000_000);
        registry.initializeJob(jobId, uint64(block.timestamp));

        uint32[] memory pm = new uint32[](0);
        INodeRegistryStructs.DataUpdate memory u =
            INodeRegistryStructs.DataUpdate({feed: address(feed), jobId: jobId, value: hex"01", timestamp: 2, round: 1});
        INodeRegistryStructs.SchnorrSignature memory schn = INodeRegistryStructs.SchnorrSignature({
            signature: bytes32(uint256(1)),
            commitment: address(1),
            signersBitmap: bytes32(uint256(1))
        });

        vm.expectRevert("No nodes");
        registry.publish(u, schn);
    }

    function test_publish_reverts_invalidSignature() public {
        _threeNodes();
        DummyFeed feed = new DummyFeed();
        feed.setMinSignaturesThreshold(1);
        (,, bytes32 jobId,) = feed.getFeedConfig();
        vm.warp(1_000_000);
        registry.initializeJob(jobId, uint64(block.timestamp));

        INodeRegistryStructs.DataUpdate memory u =
            INodeRegistryStructs.DataUpdate({feed: address(feed), jobId: jobId, value: hex"01", timestamp: 2, round: 1});
        INodeRegistryStructs.SchnorrSignature memory schn = INodeRegistryStructs.SchnorrSignature({
            signature: bytes32(uint256(1)),
            commitment: address(2),
            signersBitmap: bytes32(uint256(1))
        });

        uint32[] memory pm = new uint32[](3);

        vm.expectRevert("Invalid signature");
        registry.publish(u, schn);
    }

    function test_publish_success_updatesFeedJobAndParticipation() public {
        (LibSecp256k1.Point memory p1, LibSecp256k1.Point memory p2, LibSecp256k1.Point memory p3) = _threeNodes();
        DummyFeed feed = new DummyFeed();
        feed.setMinSignaturesThreshold(1);
        (,, bytes32 jobId,) = feed.getFeedConfig();
        vm.warp(1_000_000);
        registry.initializeJob(jobId, uint64(block.timestamp));
        bytes32 seedBefore = registry.getJobSeed(jobId);
        assertEq(registry.getJobRound(jobId), 0);

        bytes memory value = abi.encodePacked(uint256(42));
        uint64 ts = 9_999;
        INodeRegistryStructs.DataUpdate memory u =
            INodeRegistryStructs.DataUpdate({feed: address(feed), jobId: jobId, value: value, timestamp: ts, round: 1});
        bytes32 message = _constructMessage(u);

        (LibSecp256k1.Point memory agg, uint256 skEff) = _aggAndSkEffThreeNodes(p1, p2, p3);
        (bytes32 sig, address cmt) = LibSchnorrTestSign.sign(agg, skEff, message, 0);

        INodeRegistryStructs.SchnorrSignature memory schn =
            INodeRegistryStructs.SchnorrSignature({signature: sig, commitment: cmt, signersBitmap: bytes32(uint256(1))});

        uint32[] memory pm = new uint32[](3);

        registry.publish(u, schn);

        assertEq(registry.getJobRound(jobId), 1);
        // getJobSeed() returns the 224-bit truncated seed (low 32 bits of keccak zeroed).
        bytes32 expectedSeed =
            bytes32(uint256(keccak256(abi.encodePacked(seedBefore, value, ts))) & ~uint256(type(uint32).max));
        assertEq(registry.getJobSeed(jobId), expectedSeed);
        (bytes memory vOut, uint256 tOut) = feed.getLatest();
        assertEq(vOut, value);
        assertEq(tOut, ts);

        // addNode() seeds each index with 1 to avoid a cold sstore on first publish; only signer index 1 increments here.
        assertEq(registry.participationCounts(1), 2);
        assertEq(registry.participationCounts(2), 1);
        assertEq(registry.participationCounts(3), 1);
    }
}
