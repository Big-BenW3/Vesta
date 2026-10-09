// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Sole store of AI strategy commitments. The vault never stores hashes
/// itself — it cross-calls {verify} inside `rebalance()`. One write, one
/// revocation point, one event stream for the reasoning panel to index.
/// @dev Hash formula (locked): keccak256(abi.encode(vault, nonce, timestamp,
/// keccak256(reasoningJsonBytes))). Nonce space is per-vault: each
/// (vault, nonce) pair commits exactly once, which binds one reasoning JSON
/// to one onchain rebalance and makes replay impossible.
contract StrategyCommitmentRegistry {
    /// @notice A single recorded commitment. `exists` distinguishes a stored
    /// zero-hash edge (rejected at write) from an empty slot.
    struct Commitment {
        bytes32 hash;
        uint256 nonce;
        uint256 timestamp;
        bool exists;
    }

    /// @notice vault => nonce => Commitment. The only commitment state in Vesta.
    mapping(address vault => mapping(uint256 nonce => Commitment)) public commitments;

    /// @notice vault => highest nonce committed. Read by the agent to build the next hash.
    mapping(address vault => uint256) public latestNonce;

    /// @notice vault => operator EOA allowed to commit for it. Set once at vault creation.
    mapping(address vault => address) public operators;

    /// @notice Emitted on every commitment. Indexed so the API/frontend can tail it.
    /// @param vault The vault the commitment authorises a rebalance on.
    /// @param hash keccak256(abi.encode(vault, nonce, timestamp, keccak256(reasoningJson))).
    /// @param nonce Vault-owned sequence number. Consumed exactly once.
    /// @param timestamp Unix seconds the reasoning was produced. Bounded by maxAgeSec at execution.
    event StrategyCommitted(
        address indexed vault, bytes32 indexed hash, uint256 nonce, uint256 timestamp
    );

    /// @notice Records which EOA may commit for a vault. Called once by the factory.
    /// @dev Zero address or re-registration reverts; rotation is a redeploy in V1.
    error NotFactory();
    error ZeroAddress();
    error AlreadyRegistered();

    /// @notice commit() failures.
    error NotOperator();
    error ZeroHash();
    error ReplayedNonce();
    error FutureTimestamp();

    address public immutable factory;

    /// @param _factory The VaultFactory allowed to register vault operators.
    constructor(address _factory) {
        if (_factory == address(0)) revert ZeroAddress();
        factory = _factory;
    }

    /// @notice Registers the operator EOA for a newly created vault.
    /// @param vault The vault address. @param operator The agent EOA.
    function registerOperator(address vault, address operator) external {
        if (msg.sender != factory) revert NotFactory();
        if (vault == address(0) || operator == address(0)) revert ZeroAddress();
        if (operators[vault] != address(0)) revert AlreadyRegistered();
        operators[vault] = operator;
    }

    /// @notice Records a strategy commitment before its rebalance executes.
    /// @param hash The reasoning fingerprint. @param vault Target vault.
    /// @param nonce Must be unused for this vault. @param timestamp Reasoning time, not in the future.
    /// @dev Only the vault's registered operator may call. Nonce gaps are allowed
    /// (a skipped nonce simply never executes) but replays are not.
    function commit(bytes32 hash, address vault, uint256 nonce, uint256 timestamp)
        external
    {
        if (msg.sender != operators[vault]) revert NotOperator();
        if (hash == bytes32(0)) revert ZeroHash();
        if (commitments[vault][nonce].exists) revert ReplayedNonce();
        // why: 60s tolerance covers clock skew between Render worker and block producers.
        if (timestamp > block.timestamp + 60) revert FutureTimestamp();
        commitments[vault][nonce] =
            Commitment({hash: hash, nonce: nonce, timestamp: timestamp, exists: true});
        if (nonce > latestNonce[vault]) latestNonce[vault] = nonce;
        emit StrategyCommitted(vault, hash, nonce, timestamp);
    }

    /// @notice Read path for EquityVault.rebalance() and the public verifier page.
    /// @return True only if the exact (hash, vault, nonce, timestamp) tuple was committed.
    function verify(bytes32 hash, address vault, uint256 nonce, uint256 timestamp)
        external
        view
        returns (bool)
    {
        Commitment memory c = commitments[vault][nonce];
        return c.exists && c.hash == hash && c.timestamp == timestamp;
    }

    /// @notice Newest commitment for a vault. Returns zeros when none exists yet.
    function latestCommitment(address vault)
        external
        view
        returns (bytes32 hash, uint256 nonce, uint256 timestamp)
    {
        uint256 n = latestNonce[vault];
        Commitment memory c = commitments[vault][n];
        if (!c.exists) return (bytes32(0), 0, 0);
        return (c.hash, c.nonce, c.timestamp);
    }
}
