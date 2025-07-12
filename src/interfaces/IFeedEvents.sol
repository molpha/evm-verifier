// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IFeedEvents
/// @notice Events for the Feed contract
interface IFeedEvents {
    /// @notice emitted when new answer is published
    /// @param value new answer value
    /// @param timestamp new answer timestamp
    event LogAnswerPublished(bytes value, uint64 indexed timestamp);

    /// @notice emitted when feed CID is changed
    /// @param ipfsCID new ipfsCID
    event LogCIDChanged(string ipfsCID);

    /// @notice emitted when feed frequency is changed
    /// @param frequency new frequency
    /// @param pricePerSecondScaled new price per second scaled
    event LogFrequencyChanged(uint256 frequency, uint256 pricePerSecondScaled);

    /// @notice emitted when feed minSignaturesThreshold is changed
    /// @param minSignaturesThreshold new minSignaturesThreshold
    /// @param pricePerSecondScaled new price per second scaled
    event LogMinSignaturesThresholdChanged(uint256 minSignaturesThreshold, uint256 pricePerSecondScaled);

    /// @notice emitted when feed config is changed
    /// @param frequency new frequency
    /// @param minSignaturesThreshold new minSignaturesThreshold
    /// @param pricePerSecondScaled new price per second scaled
    /// @param ipfsCID new ipfsCID
    event LogFeedConfigChanged(uint256 frequency, uint256 minSignaturesThreshold, uint256 pricePerSecondScaled, string ipfsCID);
}
