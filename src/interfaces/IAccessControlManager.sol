// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

interface IAccessControlManager is IAccessControl {
    /// @notice initialize the access control manager
    /// @param protocolAdmin the protocol admin address
    function initialize(address protocolAdmin) external;

    /// @notice node registry role
    function NODE_REGISTRY() external view returns (bytes32);

    /// @notice price manager role
    function PRICE_MANAGER() external view returns (bytes32);

    /// @notice feed registry role
    function FEED_REGISTRY() external view returns (bytes32);

    /// @notice subscription registry role
    function SUBSCRIPTION_REGISTRY() external view returns (bytes32);

    /// @notice verify if account has subscription registry role, and revert otherwise
    /// @param account account to verify
    function verifySubscriptionRegistry(address account) external view;

    /// @notice verify if account has protocol admin role, and revert otherwise
    /// @param account account to verify
    function verifyProtocolAdmin(address account) external view;

    /// @notice verify if account has price manager role, and revert otherwise
    /// @param account account to verify
    function verifyPriceManager(address account) external view;

    /// @notice verify if account has node registry role, and revert otherwise
    /// @param account account to verify
    function verifyNodeRegistry(address account) external view;

    /// @notice verify if account has feed registry role, and revert otherwise
    /// @param account account to verify
    function verifyFeedRegistry(address account) external view;
}
