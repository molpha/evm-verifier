// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
// import {IFeedRegistryStructs} from "./interfaces/IFeedRegistryStructs.sol";
// import {INodesRegistry} from "./interfaces/INodesRegistry.sol";
import {ISubscriptionRegistry} from "./interfaces/ISubscriptionRegistry.sol";
// import {ITreasury} from "./interfaces/ITreasury.sol";
import {INodeRegistry} from "./interfaces/INodeRegistry.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {PricingHelper} from "./libs/PricingHelper.sol";

// TODO: think about aggregator deactivation flow
contract Feed is IFeed, ERC165 {
    using ERC165Checker for address;
    using MessageHashUtils for bytes32;

    uint256 internal constant MAX_FREQUENCY = 1 days;
    uint256 internal constant MIN_FREQUENCY = 1 minutes;
    uint256 internal constant PERSONAL_FEED_PRICE_MULTIPLIER = 3;

    IAccessControlManager internal immutable _accessControlManager;
    // INodesRegistry internal immutable _nodesRegistry;
    ISubscriptionRegistry internal immutable _subscriptionRegistry;
    // ITreasury internal immutable _treasury;
    INodeRegistry internal immutable _nodeRegistry;

    address internal immutable _owner;
    FeedType internal immutable _feedType;

    // we use immutable for public feeds to save storage slots
    uint256 internal immutable _frequencyImmutable;
    uint256 internal immutable _signaturesRequiredImmutable;

    uint256 internal _frequency;
    uint256 internal _signaturesRequired;

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

    modifier onlyPublisher() {
        // if (msg.sender != address(_publisher)) {
        //     revert NotPublisher (msg.sender);
        // }
        _;
    }

    /// @dev only for personal feeds, public feeds have immutable config
    modifier onlyFeedOwner() {
        require(msg.sender == _owner, NotFeedOwner(msg.sender));
        require(_feedType == FeedType.PERSONAL, NotPersonalFeed());
        _;
    }

    modifier onlyFeedManager() {
        _accessControlManager.verifyFeedManager(msg.sender);
        _;
    }

    constructor(
        FeedType feedType,
        IAccessControlManager accessControlManager,
        INodeRegistry nodeRegistry,
        ISubscriptionRegistry subscriptionRegistry,
        address owner,
        uint256 signaturesRequired, // must be 0 for public feeds; TODO: think about this and implement properly
        uint256 frequency,
        string memory ipfsCID
    ) {
        address(accessControlManager).shouldSupport(
            type(IAccessControlManager).interfaceId
        );
        address(nodeRegistry).shouldSupport(type(INodeRegistry).interfaceId);
        address(subscriptionRegistry).shouldSupport(
            type(ISubscriptionRegistry).interfaceId
        );

        _accessControlManager = accessControlManager;
        _subscriptionRegistry = subscriptionRegistry;
        _nodeRegistry = nodeRegistry;

        _feedType = feedType;
        _owner = owner;
        if (feedType == FeedType.PERSONAL) {
            _frequencyImmutable = frequency;
            _signaturesRequiredImmutable = signaturesRequired;
        } else {
            _frequency = frequency;
            _signaturesRequired = signaturesRequired;
        } 
        _ipfsCID = ipfsCID;
        _pricePerSecondScaled = PricingHelper.calculatePrice(frequency, signaturesRequired, feedType);
    }

    /// @inheritdoc IFeed
    function publishAnswer(
        Answer calldata answer,
        INodeRegistry.SchnorrSignature calldata schnorrData
    ) external {
        _nodeRegistry.verifySignature(
            _constructMessage(answer),
            schnorrData,
            _getMinSignaturesThreshold()
        );

        _answers.push(answer);
        emit LogAnswerPublished(answer.value, answer.timestamp);
    }

    /// @inheritdoc IFeed
    function updateFeedConfig(
        uint256 frequency,
        uint256 signaturesRequired,
        string calldata ipfsCID
    ) external override onlyFeedOwner {
        require(
            frequency >= MIN_FREQUENCY &&
                frequency <= MAX_FREQUENCY,
            InvalidFrequency(frequency)
        );
        // TODO: add max minSignaturesThreshol`d -> total amout of registered nodes
        require(
            signaturesRequired > 0,
            InvalidMinSignaturesThreshold(signaturesRequired)
        );
        require(
            keccak256(bytes(ipfsCID)) != keccak256(bytes("")),
            InvalidCID(ipfsCID)
        );

        uint256 pricePerSecondScaled = PricingHelper.calculatePrice(frequency, signaturesRequired, _feedType);

        _frequency = frequency;
        _signaturesRequired = signaturesRequired;
        _pricePerSecondScaled = pricePerSecondScaled;
        _ipfsCID = ipfsCID;

        emit LogFeedConfigChanged(
            frequency,
            signaturesRequired,
            pricePerSecondScaled,
            ipfsCID
        );
    }

    /// @inheritdoc IFeed
    function setFrequency(uint256 frequency) external override onlyFeedOwner {
        require(
            frequency >= MIN_FREQUENCY && frequency <= MAX_FREQUENCY,
            InvalidFrequency(frequency)
        );

        uint256 newPrice = PricingHelper.calculatePrice(frequency, _getMinSignaturesThreshold(), _feedType);

        _pricePerSecondScaled = newPrice;
        _frequency = frequency;

        emit LogFrequencyChanged(frequency, newPrice);
    }

    /// @inheritdoc IFeed
    function setMinSignaturesThreshold(uint256 signaturesRequired) external override onlyFeedOwner {
        // TODO: add max signaturesRequired -> total amout of registered nodes
        require(
            signaturesRequired > 0,
            InvalidMinSignaturesThreshold(signaturesRequired)
        );

        uint256 newPrice = PricingHelper.calculatePrice(_getFrequency(), signaturesRequired, _feedType);
        
        _pricePerSecondScaled = newPrice;
        _signaturesRequired = signaturesRequired;

        emit LogMinSignaturesThresholdChanged(signaturesRequired, newPrice);
    }

    /// @inheritdoc IFeed
    function setCID(string calldata cid) external override onlyFeedOwner {
        require(
            keccak256(bytes(cid)) != keccak256(bytes("")),
            InvalidCID(cid)
        );

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

    function getLastUpdated()
        external
        view
        override
        returns (uint256 timestamp)
    {
        uint256 length = _answers.length;
        if (length == 0) {
            return 0;
        }
        return _answers[length - 1].timestamp;
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
        return _getMinSignaturesThreshold();
    }

    function getOwner() external view override returns (address owner) {
        return _owner;
    }

    function getFeedType() external view override returns (FeedType feedType) {
        return _feedType;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IFeed).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _constructMessage(
        Answer calldata answer
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(address(this), answer.value, answer.timestamp)
            ).toEthSignedMessageHash();
    }

    // check if immutable is set, if not - use the one from storage
    function _getMinSignaturesThreshold() internal view returns (uint256 signaturesRequired) {
        signaturesRequired = _feedType == FeedType.PERSONAL ? _signaturesRequired : _signaturesRequiredImmutable;
    }

    function _getFrequency() internal view returns (uint256 frequency) {
        frequency = _feedType == FeedType.PERSONAL ? _frequency : _frequencyImmutable;
    }

    function _validateAnswer(Answer calldata answer) internal view {
        if (keccak256(answer.value) == keccak256(bytes(""))) {
            revert ZeroValue();
        }
        uint256 length = _answers.length;
        if (length > 0 && answer.timestamp <= _answers[length - 1].timestamp) {
            revert PastTimestamp(
                answer.timestamp,
                _answers[length - 1].timestamp
            );
        }
        if (answer.timestamp > block.timestamp) {
            revert FutureTimestamp(answer.timestamp, block.timestamp);
        }
    }
}
