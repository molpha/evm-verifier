// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";

contract AccessControlManager is AccessControl, IAccessControlManager, Initializable {
    bytes32 public constant override FEEDS_MANAGER = keccak256("FEEDS_MANAGER");
    bytes32 public constant override NODES_MANAGER = keccak256("NODES_MANAGER");

    function initialize(address _protocolAdmin) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, _protocolAdmin);
    }

    /// @inheritdoc IAccessControlManager
    function verifyProtocolAdmin(address account) external view override {
        _checkRole(DEFAULT_ADMIN_ROLE, account);
    }

    /// @inheritdoc IAccessControlManager
    function verifyFeedsManager(address account) external view override {
        _checkRole(FEEDS_MANAGER, account);
    }

    /// @inheritdoc IAccessControlManager
    function verifyNodesManager(address account) external view override {
        _checkRole(NODES_MANAGER, account);
    }

    function ADMIN_ROLE() public pure override returns (bytes32) {
        return DEFAULT_ADMIN_ROLE;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControlManager).interfaceId || super.supportsInterface(interfaceId);
    }
}
