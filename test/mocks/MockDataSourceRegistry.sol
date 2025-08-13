// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IDataSourceRegistry} from "../../src/interfaces/IDataSourceRegistry.sol";
import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

contract MockDataSourceRegistry is IDataSourceRegistry, ERC165 {
    mapping(bytes32 => DataSource) private _dataSources;
    mapping(bytes32 => bool) private _dataSourceExists;

    function initialize(address /* _accessControlManager */) external {}

    function createDataSource(DataSource calldata dataSource, bytes calldata /* signature */) 
        external 
        returns (bytes32) 
    {
        bytes32 dataSourceId = _generateDataSourceId(dataSource);
        
        if (_dataSourceExists[dataSourceId]) {
            revert("DataSource exists");
        }

        // Mock implementation - skip signature verification
        // In real implementation, signature would be verified here
        
        _dataSources[dataSourceId] = dataSource;
        _dataSourceExists[dataSourceId] = true;
        
        emit DataSourceCreated(
            dataSourceId, 
            dataSource.owner, 
            dataSource.dataSourceType, 
            dataSource.source, 
            dataSource.name
        );

        return dataSourceId;
    }

    function getDataSource(bytes32 dataSourceId) 
        external 
        view 
        returns (DataSource memory) 
    {
        if (!_dataSourceExists[dataSourceId]) {
            revert("DataSource not found");
        }
        return _dataSources[dataSourceId];
    }

    function getDataSourceId(DataSource calldata dataSource) 
        external 
        pure 
        returns (bytes32) 
    {
        return _generateDataSourceId(dataSource);
    }

    function _generateDataSourceId(DataSource calldata dataSource) 
        internal 
        pure 
        returns (bytes32) 
    {
        return keccak256(abi.encodePacked(
            dataSource.dataSourceType, 
            dataSource.source, 
            dataSource.owner, 
            dataSource.name
        ));
    }

    // Helper method for testing - check if data source exists
    function exists(bytes32 dataSourceId) external view returns (bool) {
        return _dataSourceExists[dataSourceId];
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IDataSourceRegistry).interfaceId || super.supportsInterface(interfaceId);
    }
} 