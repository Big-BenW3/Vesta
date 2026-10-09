// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EquityVault} from "../src/EquityVault.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {MockStock} from "../src/mocks/MockStock.sol";
import {ISwapRouter} from "../src/interfaces/ISwapRouter.sol";
import {IPyth, PythPrice} from "../src/interfaces/IPyth.sol";
import {StrategyCommitmentRegistry} from "../src/StrategyCommitmentRegistry.sol";

/// @notice 1:1 test double for Uniswap. Direction-agnostic: whatever comes in,
/// the same amount goes out. Funded per-token in setUp.
contract MockRouter is ISwapRouter {
    function exactInputSingle(ExactInputSingleParams calldata p)
        external
        payable
        override
        returns (uint256)
    {
        IERC20(p.tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        require(
            IERC20(p.tokenOut).balanceOf(address(this)) >= p.amountIn, "router dry"
        );
        IERC20(p.tokenOut).transfer(p.recipient, p.amountIn);
        require(p.amountIn >= p.amountOutMinimum, "slip");
        return p.amountIn;
    }
}

/// @notice Programmable Pyth double: fixed (price, expo) per feed id.
contract MockPyth is IPyth {
    mapping(bytes32 => PythPrice) prices;

    function setPrice(bytes32 id, int64 price, int32 expo) external {
        prices[id] = PythPrice(price, 0, expo, block.timestamp);
    }

    function updatePriceFeeds(bytes[] calldata) external payable override {}
    function getUpdateFee(bytes[] calldata) external pure override returns (uint256) {
        return 0;
    }
    function getPriceNoOlderThan(bytes32 id, uint256 age)
        external
        view
        override
        returns (PythPrice memory)
    {
        PythPrice memory p = prices[id];
        require(block.timestamp - p.publishTime <= age, "stale");
        return p;
    }
}

/// @notice Shared harness: factory -> one 2-stock vault (mNVDA/mMSFT 50/50),
/// router funded both directions, prices $100 expo -6 (1e6 base = $1 == 1 token).
contract VaultHarness is Test {
    MockStock usdc;
    MockStock nvda;
    MockStock msft;
    MockRouter router;
    MockPyth pyth;
    VaultFactory factory;
    EquityVault vault;
    StrategyCommitmentRegistry registry;

    address operator = address(0x0EE);
    address feeTo = address(0xFEE);
    address alice = address(0xA11CE);
    bytes32 constant NVDA_ID = keccak256("NVDA");
    bytes32 constant MSFT_ID = keccak256("MSFT");

    function setUp() public {
        usdc = new MockStock("Mock USDC", "mUSDC");
        nvda = new MockStock("Mock Nvidia", "mNVDA");
        msft = new MockStock("Mock Microsoft", "mMSFT");
        router = new MockRouter();
        pyth = new MockPyth();
        pyth.setPrice(NVDA_ID, 100_000_000, -6); // $100.00 in 6dp
        pyth.setPrice(MSFT_ID, 100_000_000, -6);

        // why: router needs inventory both directions for 1:1 test swaps.
        usdc.mint(address(router), 10_000_000_000);
        nvda.mint(address(router), 10_000_000_000);
        msft.mint(address(router), 10_000_000_000);

        factory = new VaultFactory(
            IERC20(address(usdc)),
            ISwapRouter(address(router)),
            3000,
            IPyth(address(pyth)),
            3600,
            50
        );
        registry = factory.registry();

        address[] memory tokens = new address[](2);
        tokens[0] = address(nvda);
        tokens[1] = address(msft);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        bytes32[] memory feeds = new bytes32[](2);
        feeds[0] = NVDA_ID;
        feeds[1] = MSFT_ID;
        address v = factory.createVault(
            VaultFactory.ThemeSpec("AI Mega Cap", "vAI-MEGA", tokens, weights, feeds, feeTo, 50),
            operator
        );
        vault = EquityVault(v);
        usdc.mint(alice, 1_000_000_000); // 1000 USDC
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
    }

    /// @notice Builds the canonical commitment hash for (nonce, timestamp, reasoning).
    function _commit(uint256 nonce_, uint256 ts, bytes memory reasoning)
        internal
        returns (bytes32 h)
    {
        h = keccak256(abi.encode(address(vault), nonce_, ts, keccak256(reasoning)));
        vm.prank(operator);
        registry.commit(h, address(vault), nonce_, ts);
    }

    function _mins() internal view returns (uint256[] memory m) {
        m = new uint256[](2); // zero floors: MockRouter enforces minOut itself
    }
}

/// @notice Deposit / redeem / allocation accounting.
contract VaultAccountingTest is VaultHarness {
    /// @notice First deposit mints 1:1 and — critically — performs NO swap.
    /// USDC sits idle until the agent allocates (async-allocate).
    function test_deposit_holds_idle_no_swap() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1_000_000_000, alice);
        assertEq(shares, 1_000_000_000);
        assertEq(usdc.balanceOf(address(vault)), 1_000_000_000);
        assertEq(nvda.balanceOf(address(vault)), 0);
    }

    /// @notice Zero deposit reverts instead of minting dust.
    function test_deposit_zero_reverts() public {
        vm.prank(alice);
        vm.expectRevert(EquityVault.ZeroAmount.selector);
        vault.deposit(0, alice);
    }

    /// @notice Full cycle: deposit -> rebalance allocates 50/50 -> redeem returns
    /// ~all USDC (1:1 router, minus only the fee skim).
    function test_round_trip_deposit_rebalance_redeem() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1_000_000_000, alice);

        bytes memory rsn = '{"weights":[5000,5000]}';
        bytes32 h = _commit(0, block.timestamp, rsn);
        uint256[] memory w = new uint256[](2);
        w[0] = 5000;
        w[1] = 5000;
        vm.prank(operator);
        vault.rebalance(h, 0, block.timestamp, w, new bytes[](0), _mins());
        assertGt(nvda.balanceOf(address(vault)), 0);
        assertGt(msft.balanceOf(address(vault)), 0);

        vm.prank(alice);
        uint256 out = vault.redeem(shares, alice, alice);
        // why: 1:1 mock router means only the fee skim leaks value.
        assertApproxEqAbs(out, 1_000_000_000, 1_000_000);
        assertEq(usdc.balanceOf(alice), out);
    }

    /// @notice Fee A: 1 day of accrual on 1000 USDC at 50bps/yr.
    /// expect = 1e9 * 50 * 86400 / (31536000 * 10000) = 13698 base units.
    function test_fee_skim_math() public {
        vm.prank(alice);
        vault.deposit(1_000_000_000, alice);
        skip(1 days);
        // why: the real agent pushes fresh updateData every tick — re-stamp the
        // mock feeds or the swap path correctly reverts on StalePrice instead.
        pyth.setPrice(NVDA_ID, 100_000_000, -6);
        pyth.setPrice(MSFT_ID, 100_000_000, -6);
        bytes32 h = _commit(0, block.timestamp, '{"w":1}');
        uint256[] memory w = new uint256[](2);
        w[0] = 5000;
        w[1] = 5000;
        vm.prank(operator);
        vault.rebalance(h, 0, block.timestamp, w, new bytes[](0), _mins());
        assertEq(usdc.balanceOf(feeTo), 0); // why: fee is minted SHARES, not pulled USDC
        assertApproxEqAbs(vault.balanceOf(feeTo), 13_698, 10);
    }

    /// @notice dt caps at 30 days: a year-idle vault mints 30 days of fee, not 365.
    /// expect = 1e9 * 50 * 2592000 / (31536000 * 10000) = 410958 base units.
    function test_fee_dt_capped_at_30_days() public {
        vm.prank(alice);
        vault.deposit(1_000_000_000, alice);
        skip(365 days);
        pyth.setPrice(NVDA_ID, 100_000_000, -6);
        pyth.setPrice(MSFT_ID, 100_000_000, -6);
        bytes32 h = _commit(0, block.timestamp, '{"w":1}');
        uint256[] memory w = new uint256[](2);
        w[0] = 5000;
        w[1] = 5000;
        vm.prank(operator);
        vault.rebalance(h, 0, block.timestamp, w, new bytes[](0), _mins());
        assertApproxEqAbs(vault.balanceOf(feeTo), 410_958, 100);
    }

    /// @notice Empty vault rebalances cleanly: no deposits, no fee, nonce still advances.
    function test_rebalance_empty_vault() public {
        bytes32 h = _commit(0, block.timestamp, '{"w":1}');
        uint256[] memory w = new uint256[](2);
        w[0] = 5000;
        w[1] = 5000;
        vm.prank(operator);
        vault.rebalance(h, 0, block.timestamp, w, new bytes[](0), _mins());
        assertEq(vault.nonce(), 1);
        assertEq(vault.balanceOf(feeTo), 0);
    }

    /// @notice Rebalanced event commits old weights, new weights and total value onchain.
    function test_rebalance_emits_event() public {
        vm.prank(alice);
        vault.deposit(1_000_000_000, alice);
        bytes32 h = _commit(0, block.timestamp, '{"w":1}');
        uint256[] memory w = new uint256[](2);
        w[0] = 5000;
        w[1] = 5000;
        vm.expectEmit(true, false, false, true);
        emit EquityVault.Rebalanced(0, w, w, 1_000_000_000);
        vm.prank(operator);
        vault.rebalance(h, 0, block.timestamp, w, new bytes[](0), _mins());
    }
}

/// @notice Every rebalance guard fires closed.
contract VaultGuardsTest is VaultHarness {
    function _w() internal pure returns (uint256[] memory w) {
        w = new uint256[](2);
        w[0] = 5000;
        w[1] = 5000;
    }

    function test_revert_non_operator() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(EquityVault.NotOperator.selector);
        vault.rebalance(bytes32(0), 0, block.timestamp, _w(), new bytes[](0), _mins());
    }

    function test_revert_unknown_commitment() public {
        vm.prank(operator);
        vm.expectRevert(EquityVault.UnknownCommitment.selector);
        vault.rebalance(keccak256("nope"), 0, block.timestamp, _w(), new bytes[](0), _mins());
    }

    function test_revert_nonce_mismatch() public {
        // why: commitment for nonce 1 while vault expects 0 — skips are never silently consumed.
        bytes32 h = _commit(1, block.timestamp, '{"w":1}');
        vm.prank(operator);
        vm.expectRevert(EquityVault.NonceMismatch.selector);
        vault.rebalance(h, 1, block.timestamp, _w(), new bytes[](0), _mins());
    }

    function test_revert_stale_commitment() public {
        uint256 old = block.timestamp;
        bytes32 h = _commit(0, old, '{"w":1}');
        skip(901); // past maxAgeSec 900
        vm.prank(operator);
        vm.expectRevert(EquityVault.StaleCommitment.selector);
        vault.rebalance(h, 0, old, _w(), new bytes[](0), _mins());
    }

    function test_revert_bad_weights() public {
        bytes32 h = _commit(0, block.timestamp, '{"w":1}');
        uint256[] memory bad = new uint256[](2);
        bad[0] = 6000;
        bad[1] = 6000;
        vm.prank(operator);
        vm.expectRevert(EquityVault.BadWeights.selector);
        vault.rebalance(h, 0, block.timestamp, bad, new bytes[](0), _mins());
    }

    function test_revert_slippage_floor() public {
        vm.prank(alice);
        vault.deposit(1_000_000_000, alice);
        // why: allocate first — an all-idle vault has no SELL leg, and buy legs
        // carry no floor, so the impossible floor must sit on a real sale.
        bytes32 h0 = _commit(0, block.timestamp, '{"w":1}');
        vm.prank(operator);
        vault.rebalance(h0, 0, block.timestamp, _w(), new bytes[](0), _mins());
        // Shift to 100% NVDA: forces a full MSFT sale against the floor below.
        uint256[] memory allNvda = new uint256[](2);
        allNvda[0] = 10_000;
        allNvda[1] = 0;
        bytes32 h = _commit(1, block.timestamp, '{"w":2}');
        uint256[] memory floors = new uint256[](2);
        floors[1] = type(uint256).max; // impossible floor on the MSFT sell leg
        vm.prank(operator);
        vm.expectRevert(EquityVault.SlippageExceeded.selector);
        vault.rebalance(h, 1, block.timestamp, allNvda, new bytes[](0), floors);
    }
}
