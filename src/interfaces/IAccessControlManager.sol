// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

interface IAccessControlManager is IAccessControl {
    /// @notice admin role
    /// @dev role allowed to add and remove new roles
    function ADMIN_ROLE() external view returns (bytes32);

    /// @notice feeds manager role
    function FEEDS_MANAGER() external view returns (bytes32);

    /// @notice nodes manager role
    function NODES_MANAGER() external view returns (bytes32);

    /// @notice verify if account has protocol admin role, and revert otherwise
    /// @param account account to verify
    function verifyProtocolAdmin(address account) external view;

    /// @notice verify if account has feeds manager role, and revert otherwise
    /// @param account account to verify
    function verifyFeedsManager(address account) external view;

    /// @notice verify if account has nodes manager role, and revert otherwise
    /// @param account account to verify
    function verifyNodesManager(address account) external view;
}
