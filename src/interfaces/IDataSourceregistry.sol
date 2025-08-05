// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IDataSourceRegistry
/// @notice Interface for the DataSourceRegistry contract
interface IDataSourceRegistry {
    struct DataSource {
        DataSourceType dataSourceType;
        string source;
        address owner;
        string name;
    }

    enum DataSourceType {
        Public,
        Personal
    }

    /// @notice Emitted when a new data source is created
    /// @param dataSourceId The ID of the data source
    /// @param owner The address of the data source owner
    /// @param dataSourceType The type of the data source
    /// @param source The source of the data source
    /// @param name The name of the data source
    event DataSourceCreated(bytes32 indexed dataSourceId, address indexed owner, DataSourceType indexed dataSourceType, string source, string name);

    /// @notice Emitted when a data source is verified
    /// @param dataSourceId The ID of the data source
    event DataSourceVerified(bytes32 indexed dataSourceId);

    /// @notice Thrown when the provided signature is invalid
    error InvalidSignature();

    /// @notice Thrown when a data source is not found
    /// @param dataSourceId The ID of the data source
    error DataSourceNotFound(bytes32 dataSourceId);

    /// @notice Thrown when a data source already exists
    /// @param dataSourceId The ID of the data source
    error DataSourceAlreadyExists(bytes32 dataSourceId);

    /// @notice Thrown when the provided data source ID is invalid
    /// @param dataSourceId The invalid data source ID
    error InvalidDataSourceId(bytes32 dataSourceId);

    /// @notice Create a new data source
    /// @param dataSource The data source to create
    function createDataSource(DataSource calldata dataSource, bytes calldata signature) external returns (bytes32);

    /// @notice Get a data source by its ID
    /// @param dataSourceId The ID of the data source
    /// @return The data source struct
    function getDataSource(bytes32 dataSourceId) external view returns (DataSource memory);

    /// @notice Get the data source ID for a data source
    /// @param dataSource The data source
    /// @return The data source ID
    function getDataSourceId(DataSource calldata dataSource) external view returns (bytes32);
}