// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IFeed} from "../../src/interfaces/IFeed.sol";
import {IFeedStructs} from "../../src/interfaces/IFeedStructs.sol";
import {ISubscriptionRegistry} from "../../src/interfaces/ISubscriptionRegistry.sol";
import {INodeRegistry} from "../../src/interfaces/INodeRegistry.sol";
import {INodeRegistryStructs} from "../../src/interfaces/INodeRegistryStructs.sol";

contract DummyFeed is IFeed {
    IFeedStructs.Answer internal _latestAnswer;
    uint256 internal _minSignaturesThreshold;
    uint256 internal _frequency;
    address internal _owner;
    IFeed.FeedType internal _feedType;
    string internal _ipfsCID;
    uint256 internal _pricePerSecondScaled;
    bytes32 internal _jobId;
    bytes32 internal _dataSourceId;

    mapping(address => uint256) internal _consumers;

    constructor() {
        _owner = msg.sender;
        _feedType = IFeed.FeedType.PUBLIC;
        _frequency = 3600;
        _ipfsCID = "QmTest";
        _pricePerSecondScaled = 1000;
        _jobId = bytes32(uint256(1));
        _dataSourceId = bytes32(uint256(2));
    }

    function initialize(bytes32 /*metadataHash*/, uint256 minSignaturesThresholdParam) external {
        _minSignaturesThreshold = minSignaturesThresholdParam;
    }

    function setMinSignaturesThreshold(uint256 minSignaturesThresholdParam) external {
        _minSignaturesThreshold = minSignaturesThresholdParam;
    }

    function publish(IFeedStructs.Answer calldata answer) external {
        _latestAnswer = answer;
    }

    function getFeedConfig() external view override returns (uint256 frequency, uint256 signaturesRequired, bytes32 jobId, bytes32 dataSourceId) {
        return (_frequency, _minSignaturesThreshold, _jobId, _dataSourceId);
    }

    function addConsumer(address consumer, uint256 dueTime) external {
        _consumers[consumer] = dueTime;
    }

    function removeConsumer(address consumer) external {
        delete _consumers[consumer];
    }

    function setConsumers(address[] calldata consumersToAdd, uint256 dueTime, address[] calldata consumersToRemove) external {
        for (uint256 i = 0; i < consumersToAdd.length; i++) {
            _consumers[consumersToAdd[i]] = dueTime;
        }

        for (uint256 i = 0; i < consumersToRemove.length; i++) {
            delete _consumers[consumersToRemove[i]];
        }
    }

    function setCID(string calldata cid) external {
        _ipfsCID = cid;
    }

    function getPricePerSecondScaled() external view returns (uint256) {
        return _pricePerSecondScaled;
    }

    function getOwner() external view returns (address) {
        return _owner;
    }

    function getFeedType() external view returns (IFeed.FeedType) {
        return _feedType;
    }

    function getDataSourceId() external view returns (bytes32) {
        return _dataSourceId;
    }

    function getLatest() external view returns (bytes memory value, uint256 timestamp) {
        Answer memory a = _latestAnswer;
        return (a.value, a.timestamp);
    }

    function getLastUpdated() external view returns (uint256 timestamp) {
        return _latestAnswer.timestamp;
    }

    function getSubscriptionRegistry() external pure returns (ISubscriptionRegistry) {
        return ISubscriptionRegistry(address(0));
    }

    function getEntry(uint256 index) external view returns (bytes memory, uint256) {
        IFeedStructs.Answer memory a = _latestAnswer;
        return (a.value, a.timestamp);
    }

    // Helper methods for testing
    function getMetadataHash() external pure returns (bytes32) {
        return bytes32(0);
    }

    function getConfig() external view returns (uint256, uint256) {
        return (_frequency, _minSignaturesThreshold);
    }

    function setFeedType(IFeed.FeedType feedType) external {
        _feedType = feedType;
    }

    function setOwner(address owner) external {
        _owner = owner;
    }

    function setPricePerSecondScaled(uint256 price) external {
        _pricePerSecondScaled = price;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IFeed).interfaceId;
    }
}
