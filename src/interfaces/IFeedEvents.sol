// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IFeedEvents
/// @notice Events for the Feed contract
interface IFeedEvents {
    /// @notice emitted when new answer is published
    /// @param value new answer value
    /// @param timestamp new answer timestamp
    event LogAnswerPublished(bytes value, uint64 indexed timestamp);

    /// @notice emitted when feed config is changed
    /// @param jobId new job ID
    /// @param frequency new frequency  
    /// @param minSignaturesThreshold new minSignaturesThreshold
    /// @param ipfsCID new IPFS CID
    event LogFeedConfigChanged(bytes32 indexed jobId, uint256 frequency, uint256 minSignaturesThreshold, string ipfsCID);

    /// @notice emitted when consumers are set
    /// @param consumersToAdd consumers to add
    /// @param dueTime due time
    /// @param consumersToRemove consumers to remove
    event LogConsumersSet(address[] consumersToAdd, uint256 dueTime, address[] consumersToRemove);

    /// @notice emitted when consumer is added
    /// @param consumer consumer address
    /// @param dueTime due time
    event LogConsumerAdded(address indexed consumer, uint256 dueTime);

    /// @notice emitted when consumer is removed
    /// @param consumer consumer address
    event LogConsumerRemoved(address indexed consumer);
}
