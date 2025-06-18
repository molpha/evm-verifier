// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {LibSecp256k1} from "./libs/LibSecp256k1.sol";
import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {SchnorrSetVerifierLib} from "./libs/SchnorrSetVerifierLib.sol";
import {INodesAggregator} from "./interfaces/INodesAggregator.sol";

import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract NodeAggregator is INodesAggregator, Ownable2Step {
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

    constructor(address initialOwner) Ownable(initialOwner) {
        LibSecp256k1.Point[] memory pubKeys = new LibSecp256k1.Point[](
            START_INDEX
        );
        pointer = SSTORE2.write(abi.encode(pubKeys));
    }

    function submit(uint256 feedId, uint256 value, uint256 timestamp, bytes calldata signature, uint256 bitmap) external {
        // TODO: implement
    }

    function verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold
    ) external view {
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


    function registerNode(LibSecp256k1.Point memory pubkey) external {
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

    function unregisterNode(address node) external {
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

    function getTotalSigners()
        external
        view
        override
        returns (uint256 totalSigners)
    {
        bytes memory pubKeys = SSTORE2.read(pointer);
        totalSigners = pubKeys.getNodesLength() - START_INDEX;
    }

    function getSignerSetHash() external view override returns (bytes32 hash) {
        hash = keccak256(SSTORE2.read(pointer));
    }

    function _getPubKeys()
        internal
        view
        returns (LibSecp256k1.Point[] memory pubKeys)
    {
        pubKeys = abi.decode(SSTORE2.read(pointer), (LibSecp256k1.Point[]));
    }

}