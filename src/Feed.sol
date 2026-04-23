// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";

contract Feed is IFeed, ERC165 {
    using ERC165Checker for address;

    uint256 internal constant MAX_FREQUENCY = 1 days;
    uint256 internal constant MIN_FREQUENCY = 1 minutes;

    IAccessControlManager internal _accessControlManager;

    address internal immutable _owner;
    address internal immutable _nodeRegistry;
    FeedType internal immutable _feedType;
    bool internal immutable _isFree;
    bytes32 internal immutable _dataSourceId;

    // Feed config — set once at construction, no update path.
    // _frequency, _signaturesRequired, _jobId are value types and can be true Solidity
    // immutables (stored in bytecode, no SLOAD on read).
    uint256 internal immutable _frequency;
    uint256 internal immutable _signaturesRequired;
    bytes32 internal immutable _jobId;
    // _ipfsCID is a string: Solidity immutables are value-type only, so this lives in
    // storage but has no setter — functionally write-once.
    string internal _ipfsCID;

    Answer internal _latestAnswer;
    mapping(address => uint256) internal _consumers;

    modifier onlyValidConsumer() {
        require(_isFree || msg.sender == tx.origin || _consumers[msg.sender] >= block.timestamp, "Not consumer");
        _;
    }

    modifier onlyFeedOwnerOrSubRegistry() {
        if (msg.sender != _owner) {
            _accessControlManager.verifySubscriptionRegistry(msg.sender);
        }
        _;
    }

    constructor(CreateFeedParams memory params) {
        _validateFeedConfig(params);

        _accessControlManager = IAccessControlManager(params.accessControlManager);
        _nodeRegistry = params.nodeRegistry;
        _owner = params.owner;
        _feedType = params.feedType;
        _frequency = params.frequency;
        _signaturesRequired = params.signaturesRequired;
        _jobId = params.jobId;
        _ipfsCID = params.ipfsCID;
        _isFree = params.consumerPricePerSecondScaled == 0;
        _dataSourceId = params.dataSourceId;
    }

    /// @inheritdoc IFeed
    function publish(Answer calldata answer) external {
        require(msg.sender == _nodeRegistry, "Not node registry");
        require(answer.value.length > 0, "Zero value");
        require(answer.timestamp > _latestAnswer.timestamp, "Past timestamp");
        require(answer.timestamp <= block.timestamp, "Future timestamp");

        _latestAnswer = answer;
    }

    /// @inheritdoc IFeed
    function addConsumer(address consumer, uint256 dueTime) external override onlyFeedOwnerOrSubRegistry {
        require(dueTime > block.timestamp, "Past due time");
        _consumers[consumer] = dueTime;
        emit LogConsumerAdded(consumer, dueTime);
    }

    /// @inheritdoc IFeed
    function removeConsumer(address consumer) external override onlyFeedOwnerOrSubRegistry {
        if (_consumers[consumer] == 0) revert("Not consumer");
        delete _consumers[consumer];
        emit LogConsumerRemoved(consumer);
    }

    /// @inheritdoc IFeed
    function setConsumers(address[] calldata consumersToAdd, uint256 dueTime, address[] calldata consumersToRemove)
        external
        override
        onlyFeedOwnerOrSubRegistry
    {
        if (consumersToAdd.length > 0) {
            require(dueTime > block.timestamp, "Past due time");
            for (uint256 i = 0; i < consumersToAdd.length; i++) {
                _consumers[consumersToAdd[i]] = dueTime;
            }
        }

        if (consumersToRemove.length > 0) {
            for (uint256 i = 0; i < consumersToRemove.length; i++) {
                if (_consumers[consumersToRemove[i]] == 0) revert("Not consumer");
                delete _consumers[consumersToRemove[i]];
            }
        }

        emit LogConsumersSet(consumersToAdd, dueTime, consumersToRemove);
    }

    /// @inheritdoc IFeed
    function getLatest() external view override onlyValidConsumer returns (bytes memory value, uint256 timestamp) {
        if (_latestAnswer.timestamp == 0) {
            return ("", 0);
        }
        return (_latestAnswer.value, _latestAnswer.timestamp);
    }

    /// @inheritdoc IFeed
    function getEntry(uint256)
        external
        view
        override
        onlyValidConsumer
        returns (bytes memory value, uint256 timestamp)
    {
        require(_latestAnswer.timestamp != 0, "No data");
        return (_latestAnswer.value, _latestAnswer.timestamp);
    }

    function getLastUpdated() external view override returns (uint256 lastUpdated) {
        lastUpdated = _latestAnswer.timestamp;
    }

    /// @inheritdoc IFeed
    function getFeedConfig() external view override returns (uint256 frequency, uint256 signaturesRequired, bytes32 jobId, bytes32 dataSourceId) {
        return (_frequency, _signaturesRequired, _jobId, _dataSourceId);
    }

    /// @inheritdoc IFeed
    function getOwner() external view override returns (address owner) {
        return _owner;
    }

    /// @inheritdoc IFeed
    function getFeedType() external view override returns (FeedType feedType) {
        feedType = _feedType;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeed).interfaceId || super.supportsInterface(interfaceId);
    }

    function _validateFeedConfig(CreateFeedParams memory params) internal view {
        require(params.owner != address(0), "Zero address");
        require(params.nodeRegistry != address(0), "Zero node registry");
        params.accessControlManager.shouldSupport(type(IAccessControlManager).interfaceId);
        require(params.consumerPricePerSecondScaled == 0 || params.feedType == FeedType.PUBLIC, "Not personal feed");
        require(params.frequency >= MIN_FREQUENCY && params.frequency <= MAX_FREQUENCY, "Invalid frequency");
        require(params.signaturesRequired > 0, "Invalid signatures");
        require(params.jobId != bytes32(0), "Empty job ID");
        require(params.dataSourceId != bytes32(0), "Empty data source ID");
    }
}
