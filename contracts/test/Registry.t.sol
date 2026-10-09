// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StrategyCommitmentRegistry} from "../src/StrategyCommitmentRegistry.sol";

/// @notice Behavioural spec for the commitment primitive. Every test maps to a
/// guarantee the verifier page and EquityVault.rebalance() rely on.
contract RegistryTest is Test {
    StrategyCommitmentRegistry registry;
    address factory = address(0xFaa);
    address operator = address(0x0EE);
    address vault = address(0xBA17);

    bytes32 constant HASH = keccak256("reasoning-0");

    function setUp() public {
        registry = new StrategyCommitmentRegistry(factory);
        vm.prank(factory);
        registry.registerOperator(vault, operator);
    }

    /// @notice Happy path: operator commits, verify() confirms the exact tuple.
    function test_commit_and_verify() public {
        vm.prank(operator);
        registry.commit(HASH, vault, 0, block.timestamp);
        assertTrue(registry.verify(HASH, vault, 0, block.timestamp));
    }

    /// @notice latestCommitment() tracks the highest nonce, returns zeros pre-genesis.
    function test_latest_commitment_tracks_nonce() public {
        (bytes32 h,,) = registry.latestCommitment(vault);
        assertEq(h, bytes32(0));
        vm.startPrank(operator);
        registry.commit(HASH, vault, 0, block.timestamp);
        registry.commit(keccak256("reasoning-1"), vault, 1, block.timestamp);
        vm.stopPrank();
        (bytes32 lh, uint256 ln,) = registry.latestCommitment(vault);
        assertEq(ln, 1);
        assertEq(lh, keccak256("reasoning-1"));
    }

    /// @notice A stranger cannot commit for a vault they do not operate.
    function test_revert_non_operator() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(StrategyCommitmentRegistry.NotOperator.selector);
        registry.commit(HASH, vault, 0, block.timestamp);
    }

    /// @notice Same (vault, nonce) twice is a replay — second write reverts so one
    /// reasoning JSON can never authorise two rebalances.
    function test_revert_replayed_nonce() public {
        vm.startPrank(operator);
        registry.commit(HASH, vault, 0, block.timestamp);
        vm.expectRevert(StrategyCommitmentRegistry.ReplayedNonce.selector);
        registry.commit(keccak256("other"), vault, 0, block.timestamp);
        vm.stopPrank();
    }

    /// @notice Zero hash carries no fingerprint — rejected at write, not at verify.
    function test_revert_zero_hash() public {
        vm.prank(operator);
        vm.expectRevert(StrategyCommitmentRegistry.ZeroHash.selector);
        registry.commit(bytes32(0), vault, 0, block.timestamp);
    }

    /// @notice Commitments cannot be pre-dated into the future (60s skew tolerance).
    function test_revert_future_timestamp() public {
        vm.prank(operator);
        vm.expectRevert(StrategyCommitmentRegistry.FutureTimestamp.selector);
        registry.commit(HASH, vault, 0, block.timestamp + 61);
    }

    /// @notice verify() is exact-match: wrong hash, nonce, or timestamp all fail closed.
    function test_verify_exact_match_only() public {
        vm.prank(operator);
        registry.commit(HASH, vault, 0, block.timestamp);
        assertFalse(registry.verify(keccak256("forged"), vault, 0, block.timestamp));
        assertFalse(registry.verify(HASH, vault, 1, block.timestamp));
        assertFalse(registry.verify(HASH, vault, 0, block.timestamp + 1));
        assertFalse(registry.verify(HASH, address(0x0BAD), 0, block.timestamp));
    }

    /// @notice registerOperator is factory-only and one-shot per vault.
    function test_register_operator_guards() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(StrategyCommitmentRegistry.NotFactory.selector);
        registry.registerOperator(address(0x1), operator);
        vm.prank(factory);
        vm.expectRevert(StrategyCommitmentRegistry.AlreadyRegistered.selector);
        registry.registerOperator(vault, operator);
    }
}
