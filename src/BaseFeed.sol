// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {ISubscriptionRegistry} from "./interfaces/ISubscriptionRegistry.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {PricingHelper} from "./libs/PricingHelper.sol";

// TODO: think about aggregator deactivation flow
abstract contract BaseFeed is IFeed, ERC165, Initializable {
    using ERC165Checker for address;

    uint256 internal constant MAX_FREQUENCY = 1 days;
    uint256 internal constant MIN_FREQUENCY = 1 minutes;
    uint256 internal constant PERSONAL_FEED_PRICE_MULTIPLIER = 3;

    IAccessControlManager internal _accessControlManager;
    ISubscriptionRegistry internal _subscriptionRegistry;

    address internal immutable _owner;
    FeedType internal immutable _feedType;

    uint256 internal _pricePerSecondScaled;
    string internal _ipfsCID;

    Answer[] internal _answers;

    modifier onlyValidConsumer() {
        require(
            _subscriptionRegistry.isSubscribed(msg.sender, address(this)) ||
                tx.origin == msg.sender,
            NotSubscribed(msg.sender)
        );
        _;
    }

    modifier onlyNodeRegistry() {
        _accessControlManager.verifyNodeRegistry(msg.sender);
        _;
    }

    modifier canUpdateFeedConfig() {
        require(msg.sender == _owner, NotFeedOwner(msg.sender));
        require(_feedType == FeedType.PERSONAL, NotPersonalFeed());
        _;
    }

    constructor(address owner, address accessControlManager, address subscriptionRegistry, IFeed.FeedType feedType) {
        require(owner != address(0), ZeroAddress());
        accessControlManager.shouldSupport(type(IAccessControlManager).interfaceId);
        subscriptionRegistry.shouldSupport(type(ISubscriptionRegistry).interfaceId);

        _owner = owner;
        _accessControlManager = IAccessControlManager(accessControlManager);
        _subscriptionRegistry = ISubscriptionRegistry(subscriptionRegistry);
        _feedType = feedType;
    }

    function initialize(address accessControlManager, address subscriptionRegistry) external initializer {
        accessControlManager.shouldSupport(type(IAccessControlManager).interfaceId);
        subscriptionRegistry.shouldSupport(type(ISubscriptionRegistry).interfaceId);

        _accessControlManager = IAccessControlManager(accessControlManager);
        _subscriptionRegistry = ISubscriptionRegistry(subscriptionRegistry);
    }

    /// @inheritdoc IFeed
    function publish(Answer calldata answer) external onlyNodeRegistry {
        require(answer.value.length > 0, ZeroValue());
        uint256 lastUpdated = _getLastUpdated();
        require(
            answer.timestamp > lastUpdated,
            PastTimestamp(answer.timestamp, lastUpdated)
        );
        require(
            answer.timestamp <= block.timestamp,
            FutureTimestamp(answer.timestamp, block.timestamp)
        );

        _answers.push(answer);
        emit LogAnswerPublished(answer.value, answer.timestamp);
    }

    /// @inheritdoc IFeed
    function updateFeedConfig(
        uint256 frequency,
        uint256 signaturesRequired,
        string calldata ipfsCID
    ) external override canUpdateFeedConfig {
        _setFeedConfig(frequency, signaturesRequired, ipfsCID);
    }

    /// @inheritdoc IFeed
    function setFrequency(uint256 frequency) external override canUpdateFeedConfig {
        _setFrequency(frequency);
    }

    /// @inheritdoc IFeed
    function setMinSignaturesThreshold(
        uint256 signaturesRequired
    ) external override canUpdateFeedConfig {
        _setSignaturesRequired(signaturesRequired);
    }

    /// @inheritdoc IFeed
    function setCID(string calldata cid) external override canUpdateFeedConfig {
        require(keccak256(bytes(cid)) != keccak256(bytes("")), InvalidCID(cid));

        _ipfsCID = cid;
        emit LogCIDChanged(cid);
    }

    /// @inheritdoc IFeed
    function getLatest()
        external
        view
        override
        onlyValidConsumer
        returns (bytes memory value, uint256 timestamp)
    {
        uint256 length = _answers.length;
        if (length == 0) {
            return ("", 0);
        }

        Answer memory latest = _answers[length - 1];
        return (latest.value, latest.timestamp);
    }

    /// @inheritdoc IFeed
    function getEntry(
        uint256 roundId
    )
        external
        view
        override
        onlyValidConsumer
        returns (bytes memory value, uint256 timestamp)
    {
        Answer memory a = _answers[roundId];
        return (a.value, a.timestamp);
    }

    function getLastUpdated() external view override returns (uint256 lastUpdated)
    {
        lastUpdated = _getLastUpdated();
    }

    /// @inheritdoc IFeed
    function getSubscriptionRegistry()
        external
        view
        override
        returns (ISubscriptionRegistry subscriptionRegistry)
    {
        return _subscriptionRegistry;
    }

    /// @inheritdoc IFeed
    function getMinSignaturesThreshold()
        external
        view
        override
        returns (uint256 signaturesRequired)
    {
        return _getSignaturesRequired();
    }

    function getOwner() external view override returns (address owner) {
        owner = _owner;
    }

    function getFeedType() external view override returns (FeedType feedType) {
        feedType = _feedType;
    }

    function getPricePerSecondScaled()
        external
        view
        override
        returns (uint256 pricePerSecondScaled)
    {
        pricePerSecondScaled = _pricePerSecondScaled;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IFeed).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _getLastUpdated() internal view returns (uint256 lastUpdated) {
        uint256 length = _answers.length;
        lastUpdated = length > 0 ? _answers[length - 1].timestamp : 0;
    }

    function _setFeedConfig(uint256 frequency, uint256 signaturesRequired, string calldata ipfsCID) internal virtual;

    function _setFrequency(uint256 frequency) internal virtual;

    function _setSignaturesRequired(uint256 signaturesRequired) internal virtual;

    function _getSignaturesRequired()
        internal
        view
        virtual
        returns (uint256 signaturesRequired);

    function _getFrequency() internal view virtual returns (uint256 frequency);
}
