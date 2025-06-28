// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

interface IAccessControlManager is IAccessControl {
    /// @notice admin role
    /// @dev role allowed to add and remove new roles
    function ADMIN_ROLE() external view returns (bytes32);

    /// @notice feeds manager role
    function FEED_MANAGER() external view returns (bytes32);

    /// @notice nodes manager role
    function NODE_MANAGER() external view returns (bytes32);

    /// @notice price manager role
    function PRICE_MANAGER() external view returns (bytes32);

    /// @notice verify if account has protocol admin role, and revert otherwise
    /// @param account account to verify
    function verifyProtocolAdmin(address account) external view;

    /// @notice verify if account has feeds manager role, and revert otherwise
    /// @param account account to verify
    function verifyFeedManager(address account) external view;

    /// @notice verify if account has node manager role, and revert otherwise
    /// @param account account to verify
    function verifyNodeManager(address account) external view;

    /// @notice verify if account has price manager role, and revert otherwise
    /// @param account account to verify
    function verifyPriceManager(address account) external view;
}
