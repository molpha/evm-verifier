// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IFeed} from "../../src/interfaces/IFeed.sol";
import {IFeedStructs} from "../../src/interfaces/IFeedStructs.sol";
import {ISubscriptionRegistry} from "../../src/interfaces/ISubscriptionRegistry.sol";
import {INodeRegistry} from "../../src/interfaces/INodeRegistry.sol";
import {INodeRegistryStructs} from "../../src/interfaces/INodeRegistryStructs.sol";

contract DummyFeed is IFeed {
    IFeedStructs.Answer[] internal answers;
    uint256 internal _minSignaturesThreshold;
    uint256 internal _frequency;
    address internal _owner;
    IFeed.FeedType internal _feedType;
    string internal _ipfsCID;

    constructor() {
        _owner = msg.sender;
        _feedType = IFeed.FeedType.PUBLIC;
        _frequency = 3600;
        _ipfsCID = "QmTest";
    }

    function initialize(bytes32 metadataHash, uint256 minSignaturesThresholdParam) external {
        _minSignaturesThreshold = minSignaturesThresholdParam;
    }

    function publishAnswer(
        IFeedStructs.Answer calldata answer,
        INodeRegistryStructs.SchnorrSignature calldata
    ) external {
        answers.push(answer);
    }

    function setMinSignaturesThreshold(uint256 minSignaturesThresholdParam) external {
        _minSignaturesThreshold = minSignaturesThresholdParam;
    }

    function setFrequency(uint256 frequency) external {
        _frequency = frequency;
    }

    function setCID(string calldata cid) external {
        _ipfsCID = cid;
    }

    function updateFeedConfig(uint256 frequency, uint256 signaturesRequired, string calldata cid) external {
        _frequency = frequency;
        _minSignaturesThreshold = signaturesRequired;
        _ipfsCID = cid;
    }

    function getMinSignaturesThreshold() external view returns (uint256) {
        return _minSignaturesThreshold;
    }

    function getOwner() external view returns (address) {
        return _owner;
    }

    function getFeedType() external view returns (IFeed.FeedType) {
        return _feedType;
    }

    function getLatest() external view returns (bytes memory value, uint256 timestamp) {
        if (answers.length == 0) return ("", 0);
        IFeedStructs.Answer memory a = answers[answers.length - 1];
        return (a.value, a.timestamp);
    }

    function getLastUpdated() external view returns (uint256 timestamp) {
        if (answers.length == 0) return 0;
        return answers[answers.length - 1].timestamp;
    }

    function getSubscriptionRegistry() external view returns (ISubscriptionRegistry) {
        return ISubscriptionRegistry(address(0));
    }

    function getEntry(uint256 index) external view returns (bytes memory, uint256) {
        IFeedStructs.Answer memory a = answers[index];
        return (a.value, a.timestamp);
    }

    function getMetadataHash() external view returns (bytes32) {
        return bytes32(0);
    }

    function getConfig() external view returns (uint256, uint256) {
        return (_frequency, _minSignaturesThreshold);
    }

    function getFrequency() external view returns (uint256) {
        return _frequency;
    }

    function setFeedType(IFeed.FeedType feedType) external {
        _feedType = feedType;
    }

    function setOwner(address owner) external {
        _owner = owner;
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return interfaceId == type(IFeed).interfaceId;
    }
}
