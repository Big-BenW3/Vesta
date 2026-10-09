// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Minimal Pyth pull-oracle surface the vault needs. Reads use the last
/// onchain-pushed price; `rebalance()` pushes fresh prices first via updateData.
/// @dev Contract address is uniform across EVM chains (0x2880aB15…7B43).
struct PythPrice {
    int64 price;
    uint64 conf;
    int32 expo;
    uint256 publishTime;
}

interface IPyth {
    /// @notice Pushes Hermes-signed price updates. Costs `getUpdateFee` in native gas.
    function updatePriceFeeds(bytes[] calldata updateData) external payable;

    /// @notice updateData fee in wei.
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256);

    /// @notice Latest price for `id`, reverting if older than `age` seconds.
    function getPriceNoOlderThan(bytes32 id, uint256 age)
        external
        view
        returns (PythPrice memory);
}

/// @notice Read path the vault uses against the commitment registry.
interface IStrategyCommitmentRegistry {
    function verify(bytes32 hash, address vault, uint256 nonce, uint256 timestamp)
        external
        view
        returns (bool);
}
