// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/IERC20.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {EquityVault} from "../src/EquityVault.sol";
import {MockStock} from "../src/mocks/MockStock.sol";
import {ISwapRouter} from "../src/interfaces/ISwapRouter.sol";
import {IPyth} from "../src/interfaces/IPyth.sol";
import {StrategyCommitmentRegistry} from "../src/StrategyCommitmentRegistry.sol";

/// @notice Factory guarantees: validation, CREATE2 determinism, operator wiring.
contract FactoryTest is Test {
    MockStock usdc;
    MockStock nvda;
    VaultFactory factory;
    address operator = address(0x0EE);

    function setUp() public {
        usdc = new MockStock("Mock USDC", "mUSDC");
        nvda = new MockStock("Mock Nvidia", "mNVDA");
        factory = new VaultFactory(
            IERC20(address(usdc)),
            ISwapRouter(address(0x907)),
            3000,
            IPyth(address(0x974)),
            3600,
            50
        );
    }

    function _spec() internal view returns (VaultFactory.ThemeSpec memory s) {
        address[] memory t = new address[](1);
        t[0] = address(nvda);
        uint256[] memory w = new uint256[](1);
        w[0] = 10_000;
        bytes32[] memory f = new bytes32[](1);
        f[0] = keccak256("NVDA");
        s = VaultFactory.ThemeSpec("Single", "vONE", t, w, f, address(0xFEE), 50);
    }

    /// @notice One call deploys, records themeId, and wires the operator in the registry.
    function test_create_vault_wires_everything() public {
        address v = factory.createVault(_spec(), operator);
        assertTrue(v != address(0));
        VaultFactory.ThemeSpec memory s = _spec();
        bytes32 themeId = keccak256(
            abi.encode(
                "Single",
                "vONE",
                s.underlying,
                s.targetWeightsBps,
                s.pythPriceIds,
                s.feeRecipient,
                s.managementFeeBps
            )
        );
        assertEq(factory.vaults(themeId), v);
        assertEq(factory.registry().operators(v), operator);
        assertEq(EquityVault(v).managementFeeBps(), 50);
    }

    /// @notice Same theme twice reverts — themes are singletons by identity.
    function test_revert_duplicate_theme() public {
        factory.createVault(_spec(), operator);
        vm.expectRevert(VaultFactory.AlreadyCreated.selector);
        factory.createVault(_spec(), operator);
    }

    /// @notice Weights not summing to 10_000 revert at the factory, never onchain.
    function test_revert_bad_weights() public {
        VaultFactory.ThemeSpec memory s = _spec();
        s.targetWeightsBps[0] = 9_999;
        vm.expectRevert(VaultFactory.BadWeights.selector);
        factory.createVault(s, operator);
    }

    /// @notice Ragged arrays revert before any deployment is attempted.
    function test_revert_length_mismatch() public {
        VaultFactory.ThemeSpec memory s = _spec();
        s.pythPriceIds = new bytes32[](0);
        vm.expectRevert(VaultFactory.LengthMismatch.selector);
        factory.createVault(s, operator);
    }
}
