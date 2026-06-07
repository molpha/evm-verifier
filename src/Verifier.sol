// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {LibSecp256k1} from "./libs/LibSecp256k1.sol";
import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";
import {PubkeyBlobLib} from "./libs/PubkeyBlobLib.sol";
import {BitmapLib} from "./libs/BitmapLib.sol";
import {NodeGroupBitmapLib} from "./libs/NodeGroupBitmapLib.sol";

/// @title Verifier
/// @notice Registry for managing nodes and verifying Schnorr signatures
/// @dev Uses SSTORE2 for efficient storage of node public keys, supports up to 256 nodes
contract Verifier is IVerifier {
    using MessageHashUtils for bytes32;
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using PubkeyBlobLib for bytes;
    using BitmapLib for uint256;

    uint256 constant MAX_NODES = 256;
    uint256 constant START_INDEX = 1;
    uint256 private constant ROUND_MASK = type(uint32).max;
    uint256 private constant KEYS_ARRAY_HEAD = 64;
    uint256 private constant SSTORE2_DATA_OFFSET = 1;
    uint256 private constant POINT_COORD_BYTES = 64;

    bytes32 private constant POP_DOMAIN = keccak256("MOLPHA_VALIDATOR_V1");
    bytes32 private constant SELECTION_SEED_PREFIX = keccak256("MOLPHA_SELECTION_V1");
    bytes32 private constant MESSAGE_PREFIX = keccak256("MOLPHA_MESSAGE_V1");

    mapping(address node => uint256 index) public nodeIndexes;

    address[] public registryPointers;

    /// @notice Per-index coordinates for O(1) removal aggregate update.
    mapping(uint256 index => uint256 x) public nodeKeyX;
    mapping(uint256 index => uint256 y) public nodeKeyY;

    uint256 public redundancyBuffer;

    address public protocolAdmin;

    modifier onlyProtocolAdmin() {
        require(msg.sender == protocolAdmin, "Not protocol admin");
        _;
    }

    constructor(address initialProtocolAdmin, uint256 initialRedundancyBuffer) {
        redundancyBuffer = initialRedundancyBuffer;
        protocolAdmin = initialProtocolAdmin;

        LibSecp256k1.Point[] memory emptyArray = new LibSecp256k1.Point[](1);
        emptyArray[0] = LibSecp256k1.ZERO_POINT();
        registryPointers.push(SSTORE2.write(abi.encode(emptyArray)));
    }

    /// @inheritdoc IVerifier
    function verify(DataUpdate calldata dataUpdate, SchnorrSignature calldata schnorrData)
        external
        view
        returns (bool isVerified)
    {
        bytes32 selectionSeed = keccak256(
            abi.encodePacked(
                SELECTION_SEED_PREFIX, 
                dataUpdate.jobId, 
                dataUpdate.registryVersion,
                dataUpdate.canonicalTimestamp
            )
        );

        address keysPtr = registryPointers[dataUpdate.registryVersion];

        /// @dev Index 0 holds the aggregate key; indices `1..keysLen-1` are registered nodes.
        uint256 keysLen = _blobEncodedKeysLength(keysPtr);
        if (keysLen <= 1) revert("No nodes");
        uint256 nodeCount = keysLen - 1;

        if (dataUpdate.signaturesRequired == 0) revert("Zero signatures required");
        if (schnorrData.signersBitmap == 0) revert("Zero signers bitmap");
        if (schnorrData.signature == 0) revert("Zero signature");
        if (schnorrData.commitment == address(0)) revert("Zero commitment");

        uint256 grpSize = dataUpdate.signaturesRequired + redundancyBuffer;
        grpSize = grpSize > nodeCount ? nodeCount : grpSize;

        uint256 signerCount = schnorrData.signersBitmap.popCount();
        if (signerCount < dataUpdate.signaturesRequired) revert("Not enough signatures");

        uint256 selectionBitmap = NodeGroupBitmapLib.derive(selectionSeed, nodeCount, grpSize);

        if (schnorrData.signersBitmap & ~selectionBitmap != 0) revert("Signer not selected");

        // Ascending 1-based index order: peel lowest set bit from `rem` each iteration.
        bool aggInit;
        uint256 ax;
        uint256 ay;
        uint256 az;
        uint256 rem = schnorrData.signersBitmap;
        while (rem != 0) {
            uint256 bit;
            uint256 pos;
            unchecked {
                bit = rem & (~rem + 1);
                pos = bit.ctzPow2();
                rem ^= bit;
            }

            uint256 signerIndex = pos + 1;
            (uint256 epx, uint256 epy) = _readNodeKeyXY(keysPtr, signerIndex);
            if (!aggInit) {
                (ax, ay, az) = (epx, epy, 1);
                aggInit = true;
            } else {
                (ax, ay, az) = LibSecp256k1.addAffinePointToXYZ(ax, ay, az, epx, epy);
            }
        }

        LibSecp256k1.Point memory aggPubKey = LibSecp256k1.toAffineModexpXYZ(ax, ay, az);

        isVerified = aggPubKey.verifySignatureTrusted(
            _constructMessage(dataUpdate, schnorrData.signersBitmap), schnorrData.signature, schnorrData.commitment
        );
    }

    /// @inheritdoc IVerifier
    function addNode(bytes memory compressedPubKey, SchnorrProof calldata pop) external onlyProtocolAdmin {
        LibSecp256k1.Point memory pubkey = LibSecp256k1.decompress(compressedPubKey);
        if (pubkey.isZeroPoint()) revert("Invalid public key");
        if (pubkey.toAddress() == address(0)) revert("Zero address");
        _verifyPop(pubkey, compressedPubKey, pop);

        uint256 registryVersion = registryPointers.length - 1;
        address keysPtr = registryPointers[registryVersion];
        bytes memory keysBlob = SSTORE2.read(keysPtr);

        uint256 nextIndex = keysBlob.getNodesLength();
        if (nextIndex - START_INDEX >= MAX_NODES) revert("Max nodes reached");

        address node = pubkey.toAddress();

        if (nodeIndexes[node] != 0) revert("Node already added");

        LibSecp256k1.Point memory agg;
        if (nextIndex == START_INDEX) {
            agg = pubkey;
        } else {
            LibSecp256k1.Point memory currAgg = keysBlob.getNode(0);
            (uint256 ax, uint256 ay, uint256 az) =
                LibSecp256k1.addAffinePointToXYZ(currAgg.x, currAgg.y, 1, pubkey.x, pubkey.y);
            agg = LibSecp256k1.toAffineModexpXYZ(ax, ay, az);
        }

        keysBlob.addPubkeyWithAggregate(pubkey, agg);
        address newPointer = SSTORE2.write(keysBlob);
        registryPointers.push(newPointer);

        nodeIndexes[node] = nextIndex;
        nodeKeyX[nextIndex] = pubkey.x;
        nodeKeyY[nextIndex] = pubkey.y;

        emit LogNodeAdded(node, nextIndex, newPointer);
    }

    function removeNode(address node) external onlyProtocolAdmin {
        uint256 index = nodeIndexes[node];
        if (index == 0) revert("Not node");

        uint256 registryVersion = registryPointers.length - 1;
        address keysPtr = registryPointers[registryVersion];

        bytes memory keysBlob = SSTORE2.read(keysPtr);
        uint256 len = keysBlob.getNodesLength();
        if (index >= len) revert("Bad index");

        uint256 px = nodeKeyX[index];
        uint256 py = nodeKeyY[index];
        LibSecp256k1.Point memory nextAgg;
        if (len == START_INDEX + 1) {
            nextAgg = LibSecp256k1.ZERO_POINT();
        } else {
            uint256 negY = LibSecp256k1.fieldP() - py;
            LibSecp256k1.Point memory currAgg = keysBlob.getNode(0);
            (uint256 ax, uint256 ay, uint256 az) = LibSecp256k1.addAffinePointToXYZ(currAgg.x, currAgg.y, 1, px, negY);
            nextAgg = LibSecp256k1.toAffineModexpXYZ(ax, ay, az);
        }

        if (index != len - 1) {
            LibSecp256k1.Point memory swappedNode = keysBlob.getNode(len - 1);
            keysBlob.setNode(index, swappedNode);
            nodeIndexes[swappedNode.toAddress()] = index;
            nodeKeyX[index] = swappedNode.x;
            nodeKeyY[index] = swappedNode.y;
        }

        keysBlob.removePubkeyWithAggregate(index, nextAgg);
        address newPointer = SSTORE2.write(keysBlob);
        registryPointers.push(newPointer);
        delete nodeKeyX[len - 1];
        delete nodeKeyY[len - 1];
        delete nodeIndexes[node];

        emit LogNodeRemoved(node, index, newPointer);
    }

    /// @inheritdoc IVerifier
    function transferProtocolAdmin(address newProtocolAdmin) external override onlyProtocolAdmin {
        if (newProtocolAdmin == address(0)) revert("Zero admin");
        address previousAdmin = protocolAdmin;
        protocolAdmin = newProtocolAdmin;
        emit LogProtocolAdminTransferred(previousAdmin, newProtocolAdmin);
    }

    /// @inheritdoc IVerifier
    function setRedundancyBuffer(uint256 newRedundancyBuffer) external override onlyProtocolAdmin {
        redundancyBuffer = newRedundancyBuffer;
        emit LogRedundancyBufferUpdated(newRedundancyBuffer);
    }

    /// @inheritdoc IVerifier
    function getRegistryVersion() external view returns (uint256 registryVersion) {
        registryVersion = registryPointers.length - 1;
    }

    /// @inheritdoc IVerifier
    function getRegistryPointer() external view returns (address registryPointer) {
        uint256 registryVersion = registryPointers.length - 1;
        registryPointer = registryPointers[registryVersion];
    }   

    /// @inheritdoc IVerifier
    function getRegistryPointer(uint256 registryVersion) external view returns (address registryPointer) {
        registryPointer = registryPointers[registryVersion];
    }

    function isNode(address node) external view returns (bool isActive) {
        isActive = nodeIndexes[node] != 0;
    }

    /// @inheritdoc IVerifier
    function getTotalNodes() external view override returns (uint256 totalSigners) {
        uint256 registryVersion = registryPointers.length - 1;
        address keysPtr = registryPointers[registryVersion];
        totalSigners = _blobEncodedKeysLength(keysPtr);
    }

    function getNodesSetHash() external view override returns (bytes32 hash) {
        uint256 registryVersion = registryPointers.length - 1;
        address keysPtr = registryPointers[registryVersion];
        hash = keccak256(SSTORE2.read(keysPtr));
    }

    /// @inheritdoc IVerifier
    function getAggregateKey() external view override returns (uint256 x, uint256 y) {
        uint256 registryVersion = registryPointers.length - 1;
        address keysPtr = registryPointers[registryVersion];
        bytes memory keysBlob = SSTORE2.read(keysPtr);
        LibSecp256k1.Point memory aggregate = keysBlob.getNode(0);
        x = aggregate.x;
        y = aggregate.y;
    }

    /// @inheritdoc IVerifier
    function getNodeIndex(address node) external view returns (uint256 index) {
        index = nodeIndexes[node];
    }

    /// @dev Derives the dynamic array length from the SSTORE2 bytecode size.
    ///      SSTORE2 stores one STOP byte before the payload, and
    ///      `abi.encode(LibSecp256k1.Point[])` is `0x40 + len * 0x40` bytes.
    function _blobEncodedKeysLength(address ptr) private view returns (uint256 keysLen) {
        unchecked {
            keysLen = (ptr.code.length - SSTORE2_DATA_OFFSET - KEYS_ARRAY_HEAD) / POINT_COORD_BYTES;
        }
    }

    /// @dev Reads one affine key (64 bytes) from the SSTORE2 `abi.encode(LibSecp256k1.Point[])` blob.
    function _readNodeKeyXY(address ptr, uint256 idx) private view returns (uint256 x, uint256 y) {
        uint256 codeStart = SSTORE2_DATA_OFFSET + KEYS_ARRAY_HEAD + idx * 64;
        assembly ("memory-safe") {
            let scratch := mload(0x40)
            extcodecopy(ptr, scratch, codeStart, 64)
            x := mload(scratch)
            y := mload(add(scratch, 32))
        }
    }

    function _constructMessage(DataUpdate calldata dataUpdate, uint256 signersBitmap)
        internal
        pure
        returns (bytes32 message)
    {
        message = keccak256(
                abi.encodePacked(
                    MESSAGE_PREFIX,
                    dataUpdate.jobId,
                    dataUpdate.registryVersion,
                    dataUpdate.signaturesRequired,
                    signersBitmap,
                    dataUpdate.value,
                    dataUpdate.canonicalTimestamp
                )
            );
    }

    function _verifyPop(LibSecp256k1.Point memory pubkey, bytes memory compressedPubKey, SchnorrProof calldata pop)
        private
        view
    {
        bytes32 digest =
            keccak256(abi.encodePacked(POP_DOMAIN, address(this), compressedPubKey));
        bool isValid = pubkey.verifySignature(digest, pop.signature, pop.commitment);
        if (!isValid) revert("Invalid PoP");
    }
}
