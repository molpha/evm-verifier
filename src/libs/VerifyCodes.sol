// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4 <0.9.0;

/// @title VerifyCodes
/// @notice Result codes returned by `Verifier.verify`
/// @dev Codes 0–10 match registry-v2 / Cairo / Solana. Do not renumber.
library VerifyCodes {
    uint8 internal constant R_OK = 0;
    /// @dev Reserved. Never returned by this implementation; kept so codes are never renumbered.
    uint8 internal constant R_FEED_WITNESS = 1;
    uint8 internal constant R_BAD_REGISTRY_VERSION = 2;
    uint8 internal constant R_MALFORMED = 3;
    uint8 internal constant R_NOT_YET_ACTIVE = 4;
    uint8 internal constant R_VERSION_EXPIRED = 5;
    uint8 internal constant R_COMPROMISED_QUORUM = 6;
    uint8 internal constant R_BAD_QUORUM = 7;
    uint8 internal constant R_BAD_AGGREGATE = 8;
    uint8 internal constant R_BAD_SIGNATURE = 9;
    uint8 internal constant R_STALE = 10;
}
