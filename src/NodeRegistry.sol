// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";
import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {SchnorrSetVerifierLib} from "./libs/SchnorrSetVerifierLib.sol";
import {INodeRegistry} from "./interfaces/INodeRegistry.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {IFeedStructs} from "./interfaces/IFeedStructs.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";

/// @title NodeRegistry
/// @notice Registry for managing nodes and verifying Schnorr signatures
/// @dev Uses SSTORE2 for efficient storage of node public keys, supports up to 256 nodes
contract NodeRegistry is INodeRegistry, ERC165, Initializable {
    using MessageHashUtils for bytes32;
    using ERC165Checker for address;
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    using SchnorrSetVerifierLib for bytes;

    /// @notice Maximum number of allowed signers that can be stored in the signer set.
    /// with SSTORE2 we can store up to 382 signers, but we limit to 256 to use bitmaps
    uint256 constant MAX_NODES = 256;

    /// @notice Index from which valid signer entries start.
    /// @dev We use 1-based indexing, so index 0 is reserved and unused.
    ///      This helps avoid confusion with default zero values.
    uint256 constant START_INDEX = 1;

    /// @notice mapping of signer addresses to their indexes in the signers array
    mapping(address node => uint256 index) public nodeIndexes;

    /// @notice pointer to signers array stored with SSTORE2, signers[0] is empty cause we use 1-based indexing
    address public pointer;

    IAccessControlManager public _accessControlManager;

    modifier onlyProtocolAdmin {
        _accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    function initialize(address accessControlManager) external override initializer {
        _accessControlManager = IAccessControlManager(accessControlManager);
        _accessControlManager.verifyProtocolAdmin(msg.sender);

        // Initialize with empty array that has one empty slot at index 0
        LibSecp256k1.Point[] memory emptyArray = new LibSecp256k1.Point[](1);
        // emptyArray[0] remains zero point (default)
        pointer = SSTORE2.write(abi.encode(emptyArray));
    }

    function publish(
        DataUpdate calldata dataUpdate,
        SchnorrSignature calldata schnorrData
    ) external {
        require(dataUpdate.feed != address(0), ZeroAddress());

        uint256 minSignaturesThreshold = IFeed(dataUpdate.feed).getMinSignaturesThreshold();

        bytes32 message = _constructMessage(dataUpdate);
        _verifySignature(message, schnorrData, minSignaturesThreshold);

        IFeed(dataUpdate.feed).publish(
            IFeedStructs.Answer({
                value: dataUpdate.value,
                timestamp: dataUpdate.timestamp
            })
        );
    }

    /// @inheritdoc INodeRegistry
    function verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold
    ) external view {
        _verifySignature(message, schnorrData, minSignaturesThreshold);
    }

    /// @inheritdoc INodeRegistry
    function addNode(LibSecp256k1.Point memory pubkey) external onlyProtocolAdmin {
        if (pubkey.isZeroPoint()) revert InvalidPublicKey();
        if (pubkey.toAddress() == address(0)) revert ZeroAddress();

        bytes memory pubKeys = SSTORE2.read(pointer); // encoded array of signer pubKeys

        uint256 nodesAmount = pubKeys.getNodesLength();
        if (nodesAmount == MAX_NODES) revert MaxNodesReached();

        address node = pubkey.toAddress();

        if (nodeIndexes[node] != 0) revert NodeAlreadyAdded(node);

        nodeIndexes[node] = nodesAmount;

        // add signer to array and update length
        pubKeys.addNode(pubkey);

        address newPointer = SSTORE2.write(pubKeys);
        pointer = newPointer;

        emit LogNodeAdded(node, nodesAmount, newPointer);
    }

    function removeNode(address node) external onlyProtocolAdmin {
        uint256 index = nodeIndexes[node];
        if (index == 0) revert NotNode(node);

        // encoded array of signer pubKeys
        bytes memory pubKeys = SSTORE2.read(pointer);

        // remove signer from array and update length
        bool orderChanged = pubKeys.removeNode(index);

        if (orderChanged) {
            address movedNode = pubKeys.getNode(index).toAddress();
            nodeIndexes[movedNode] = index;
        }

        address newPointer = SSTORE2.write(pubKeys);
        pointer = newPointer;
        delete nodeIndexes[node];

        emit LogNodeRemoved(node, index, newPointer);
    }

    function isNode(address node) external view returns (bool isActive) {
        isActive = nodeIndexes[node] != 0;
    }

    /// @inheritdoc INodeRegistry
    function getTotalNodes()
        external
        view
        override
        returns (uint256 totalSigners)
    {
        bytes memory pubKeys = SSTORE2.read(pointer);
        totalSigners = pubKeys.getNodesLength() - START_INDEX;
    }

    function getNodesSetHash() external view override returns (bytes32 hash) {
        hash = keccak256(SSTORE2.read(pointer));
    }

    /// @inheritdoc INodeRegistry
    function getNodeIndex(address node) external view returns (uint256 index) {
        index = nodeIndexes[node];
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(INodeRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold
    ) internal view {
        if (schnorrData.signature == bytes32(0)) revert InvalidSignature();
        if (schnorrData.signers.length == 0) revert InvalidSignersOrder();
        if (schnorrData.commitment == address(0)) revert InvalidCommitment();

        uint256 numberSigners = schnorrData.signers.length;

        if (numberSigners < minSignaturesThreshold) {
            revert NotEnoughSignatures(numberSigners, minSignaturesThreshold);
        }

        LibSecp256k1.Point[] memory pubKeys = _getPubKeys();
        uint256 signerSetLength = pubKeys.length;
        uint256 firstIndex = schnorrData.signers[0];
        if (firstIndex == 0 || firstIndex >= signerSetLength)
            revert InvalidIndex(firstIndex);
        LibSecp256k1.JacobianPoint memory aggPubKey = pubKeys[
            schnorrData.signers[0]
        ].toJacobian();

        for (uint256 i = START_INDEX; i < numberSigners; i++) {
            uint256 signerIndex = schnorrData.signers[i];

            if (signerIndex == 0 || signerIndex >= signerSetLength)
                revert InvalidIndex(signerIndex);
            if (signerIndex <= schnorrData.signers[i - 1])
                revert InvalidSignersOrder();

            aggPubKey.addAffinePoint(pubKeys[schnorrData.signers[i]]);
        }

        bool isValid = aggPubKey.toAffine().verifySignature(
            message,
            schnorrData.signature,
            schnorrData.commitment
        );
        if (!isValid) revert InvalidSignature();
    }

    function _getPubKeys()
        internal
        view
        returns (LibSecp256k1.Point[] memory pubKeys)
    {
        pubKeys = abi.decode(SSTORE2.read(pointer), (LibSecp256k1.Point[]));
    }

    function _constructMessage(
        DataUpdate calldata dataUpdate
    ) internal pure returns (bytes32 message) {
        message = keccak256(
            abi.encodePacked(
                dataUpdate.feed,
                dataUpdate.value,
                dataUpdate.timestamp
            )
        ).toEthSignedMessageHash();
    }
}
