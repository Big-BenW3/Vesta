// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IPyth, PythPrice, IStrategyCommitmentRegistry} from "./interfaces/IPyth.sol";

/// @notice ERC-4626 vault holding a themed basket of tokenized stocks (testnet:
/// mock stocks; mainnet: real xStocks — identical ERC-20 interface).
/// Deposits hold IDLE USDC (async-allocate); the agent operator allocates idle
/// cash and reweights the basket inside `rebalance()`. Management fee (option A,
/// time-pro-rated) is skimmed as new shares at the top of every rebalance.
/// @dev Settlement truth is what Uniswap returned. Pyth prices are display and
/// slippage math only — a view cannot pull a fresh Pyth price.
contract EquityVault is ERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public constant BPS = 10_000;
    uint256 public constant SECONDS_PER_YEAR = 31_536_000;
    uint256 public constant MAX_FEE_DT = 30 days; // why: caps fee mint after long-idle vaults
    uint256 public constant MAX_FEE_BPS = 200; // why: 2%/yr ceiling, set at factory time

    /// @notice Circle USDC — the single deposit/payout asset.
    IERC20 public immutable USDC;
    /// @notice Basket tokens, parallel to targetWeightsBps and pythPriceIds.
    IERC20[] public underlyings;
    /// @notice Current target allocation, BPS, always sums to 10_000.
    uint256[] public targetWeightsBps;
    /// @notice Uniswap V3 router (testnet deployment; never a mainnet address here).
    ISwapRouter public immutable uniRouter;
    /// @notice Single pool fee tier for all USDC<->stock pairs in V1.
    uint24 public immutable poolFee;
    /// @notice Pyth oracle + per-underlying feed IDs + max price age for swaps.
    IPyth public immutable pyth;
    bytes32[] public pythPriceIds;
    uint256 public immutable priceMaxAge;
    /// @notice Max acceptable swap slippage, BPS (e.g. 50 = 0.5%).
    uint256 public immutable maxSlippageBps;

    /// @notice Commitment registry (sole commitment store) + agent EOA + fee sink.
    IStrategyCommitmentRegistry public immutable registry;
    address public immutable agentOperator;
    address public immutable feeRecipient;
    /// @notice Annualised management fee, BPS (50 = 0.5%/yr).
    uint256 public immutable managementFeeBps;

    /// @notice Fee clock. Set at construction so the first dt is bounded.
    uint256 public lastRebalanceTimestamp;
    /// @notice Vault-owned sequence number. Incremented only on successful rebalance.
    /// The agent reads it to build the NEXT commitment — never invents its own.
    uint256 public nonce;

    event Rebalanced(
        uint256 indexed nonce, uint256[] oldWeights, uint256[] newWeights, uint256 totalValue
    );
    event FeeSkimmed(uint256 shares, uint256 dt);

    error NotOperator();
    error UnknownCommitment();
    error NonceMismatch();
    error StaleCommitment();
    error ZeroAmount();
    error ZeroAddress();
    error LengthMismatch();
    error BadWeights();
    error FeeTooHigh();
    error StalePrice();
    error SlippageExceeded();
    error UnderfundedFee();

    /// @param asset_ Circle USDC. @param underlyings_ Basket tokens.
    /// @param weights_ BPS targets summing to 10_000. @param router_ Testnet swap router.
    /// @param poolFee_ Uniswap fee tier. @param pyth_ Pyth contract. @param priceIds_ Feed per underlying.
    /// @param priceMaxAge_ Freshness required for swap pricing. @param maxSlippageBps_ Slippage guard.
    /// @param registry_ Commitment registry. @param operator_ Agent EOA. @param feeRecipient_ Fee sink.
    /// @param feeBps_ Annualised fee (<= 200). @param name_ Share token name. @param symbol_ Share symbol.
    constructor(
        IERC20 asset_,
        IERC20[] memory underlyings_,
        uint256[] memory weights_,
        ISwapRouter router_,
        uint24 poolFee_,
        IPyth pyth_,
        bytes32[] memory priceIds_,
        uint256 priceMaxAge_,
        uint256 maxSlippageBps_,
        IStrategyCommitmentRegistry registry_,
        address operator_,
        address feeRecipient_,
        uint256 feeBps_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC4626(asset_) {
        if (
            underlyings_.length == 0 || underlyings_.length != weights_.length
                || underlyings_.length != priceIds_.length
        ) revert LengthMismatch();
        uint256 sum;
        for (uint256 i; i < weights_.length; ++i) sum += weights_[i];
        if (sum != BPS) revert BadWeights();
        if (
            address(router_) == address(0) || address(pyth_) == address(0)
                || address(registry_) == address(0) || operator_ == address(0)
                || feeRecipient_ == address(0)
        ) revert ZeroAddress();
        if (feeBps_ > MAX_FEE_BPS) revert FeeTooHigh();
        USDC = asset_;
        underlyings = underlyings_;
        targetWeightsBps = weights_;
        uniRouter = router_;
        poolFee = poolFee_;
        pyth = pyth_;
        pythPriceIds = priceIds_;
        priceMaxAge = priceMaxAge_;
        maxSlippageBps = maxSlippageBps_;
        registry = registry_;
        agentOperator = operator_;
        feeRecipient = feeRecipient_;
        managementFeeBps = feeBps_;
        lastRebalanceTimestamp = block.timestamp;
    }

    // ── ERC-4626: async-allocate deposit, swap-backed redeem ──────────────

    /// @notice Total basket value in USDC base units (estimate: last pushed Pyth prices).
    function totalAssets() public view override returns (uint256) {
        return withdrawableUSDC();
    }

    /// @notice Display/estimate only. Sums idle USDC + each holding at its Pyth price.
    /// @dev Never settlement truth — settlement is what Uniswap returned on the way out.
    function withdrawableUSDC() public view returns (uint256) {
        uint256 total = USDC.balanceOf(address(this));
        for (uint256 i; i < underlyings.length; ++i) {
            (uint256 px, int32 expo) = _price(pythPriceIds[i], type(uint256).max);
            if (px == 0) continue; // why: display must not brick on one stale feed
            total += _toUSDC(underlyings[i].balanceOf(address(this)), px, expo);
        }
        return total;
    }

    /// @notice Standard deposit. USDC stays IDLE — no swap inside (agent allocates later).
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        returns (uint256)
    {
        if (assets == 0) revert ZeroAmount();
        return super.deposit(assets, receiver);
    }

    /// @notice Burns shares, first selling a pro-rata slice of stocks to free the USDC.
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256)
    {
        if (assets == 0) revert ZeroAmount();
        _freeUSDC(assets);
        return super.withdraw(assets, receiver, owner);
    }

    /// @notice Same as withdraw, share-denominated.
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256)
    {
        if (shares == 0) revert ZeroAmount();
        _freeUSDC(previewRedeem(shares));
        return super.redeem(shares, receiver, owner);
    }

    // ── Rebalance (agent only) ────────────────────────────────────────────

    /// @notice Allocates idle USDC and reweights to newWeights. Atomic: any leg
    /// reverting reverts the whole rebalance.
    /// @param commitmentHash Must equal the Registry commitment for (vault, nonce, timestamp).
    /// @param nonce_ Must equal vault.nonce (consumed exactly once). @param timestamp Reasoning time.
    /// @param newWeights BPS targets for AFTER the rebalance (sums to 10_000).
    /// @param priceUpdateData Hermes-signed Pyth updates (msg.value pays the Pyth fee).
    /// @param minAmountOut Per-underlying slippage floor for sells, parallel to underlyings.
    /// @dev Fraud binding: newWeights are operator-provided, but the published reasoning
    /// JSON commits to the same weights — stored weights + Rebalanced event vs published
    /// JSON is the public fraud proof (see VERIFIER.md).
    function rebalance(
        bytes32 commitmentHash,
        uint256 nonce_,
        uint256 timestamp,
        uint256[] calldata newWeights,
        bytes[] calldata priceUpdateData,
        uint256[] calldata minAmountOut
    ) external payable nonReentrant {
        if (msg.sender != agentOperator) revert NotOperator();
        if (!registry.verify(commitmentHash, address(this), nonce_, timestamp)) {
            revert UnknownCommitment();
        }
        if (nonce_ != nonce) revert NonceMismatch();
        if (block.timestamp > timestamp + 900) revert StaleCommitment(); // maxAgeSec = 15min
        if (newWeights.length != underlyings.length) revert LengthMismatch();
        uint256 sum;
        for (uint256 i; i < newWeights.length; ++i) sum += newWeights[i];
        if (sum != BPS) revert BadWeights();
        if (minAmountOut.length != underlyings.length) revert LengthMismatch();

        _skimFee();
        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        if (msg.value < fee) revert UnderfundedFee();
        pyth.updatePriceFeeds{value: fee}(priceUpdateData);
        // why: refund dust MON so the operator key never leaks value into the vault.
        if (msg.value > fee) {
            (bool ok,) = msg.sender.call{value: msg.value - fee}("");
            require(ok, "refund failed");
        }

        uint256 totalValue = withdrawableUSDC();
        // Phase 1: sell overweight legs into USDC.
        for (uint256 i; i < underlyings.length; ++i) {
            (uint256 px, int32 expo) = _freshPrice(pythPriceIds[i]);
            uint256 cur = _toUSDC(underlyings[i].balanceOf(address(this)), px, expo);
            uint256 tgt = totalValue.mulDiv(newWeights[i], BPS, Math.Rounding.Floor);
            if (cur > tgt) {
                uint256 sellValue = cur - tgt;
                uint256 amountIn = _toBase(sellValue, px, expo);
                uint256 bal = underlyings[i].balanceOf(address(this));
                if (amountIn > bal) amountIn = bal;
                if (amountIn == 0) continue;
                uint256 out = _swap(address(underlyings[i]), address(USDC), amountIn, 0);
                if (out < minAmountOut[i]) revert SlippageExceeded();
            }
        }
        // Phase 2: spend USDC (idle + proceeds) into underweight legs.
        for (uint256 i; i < underlyings.length; ++i) {
            (uint256 px, int32 expo) = _freshPrice(pythPriceIds[i]);
            uint256 cur = _toUSDC(underlyings[i].balanceOf(address(this)), px, expo);
            uint256 tgt = totalValue.mulDiv(newWeights[i], BPS, Math.Rounding.Floor);
            if (tgt > cur) {
                uint256 buyValue = tgt - cur;
                uint256 idle = USDC.balanceOf(address(this));
                if (buyValue > idle) buyValue = idle;
                if (buyValue == 0) continue;
                _swap(address(USDC), address(underlyings[i]), buyValue, 0);
            }
        }

        uint256[] memory old = targetWeightsBps;
        targetWeightsBps = newWeights;
        lastRebalanceTimestamp = block.timestamp;
        unchecked {
            ++nonce;
        }
        emit Rebalanced(nonce_, old, newWeights, totalValue);
    }

    // ── Price upkeep (permissionless) ───────────────────────────────────

    /// @notice Pushes fresh Pyth prices without rebalancing. Anyone may call —
    /// without it, redeems brick when the agent is idle past priceMaxAge.
    /// @param priceUpdateData Hermes-signed updates. msg.value pays the Pyth fee, dust refunds.
    function poke(bytes[] calldata priceUpdateData) external payable nonReentrant {
        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        if (msg.value < fee) revert UnderfundedFee();
        pyth.updatePriceFeeds{value: fee}(priceUpdateData);
        if (msg.value > fee) {
            (bool ok,) = msg.sender.call{value: msg.value - fee}("");
            require(ok, "refund failed");
        }
    }

    // ── Fee A (time-pro-rated skim) ───────────────────────────────────────

    /// @notice Mints fee shares to feeRecipient for dt since the last skim.
    /// feeShares = totalSupply * feeBps * dt / (YEAR * 10_000). Capped dt.
    function _skimFee() internal {
        uint256 supply = totalSupply();
        if (supply == 0) {
            lastRebalanceTimestamp = block.timestamp;
            return;
        }
        uint256 dt = block.timestamp - lastRebalanceTimestamp;
        if (dt > MAX_FEE_DT) dt = MAX_FEE_DT;
        if (dt == 0) return;
        uint256 feeShares = supply.mulDiv(managementFeeBps * dt, SECONDS_PER_YEAR * BPS);
        lastRebalanceTimestamp = block.timestamp;
        if (feeShares == 0) return;
        _mint(feeRecipient, feeShares);
        emit FeeSkimmed(feeShares, dt);
    }

    // ── Internals ─────────────────────────────────────────────────────────

    /// @notice Sells just enough of each holding (pro-rata by value) to cover `needed` USDC.
    /// @dev Requires pushed prices fresher than priceMaxAge — anyone can `poke()` them first.
    function _freeUSDC(uint256 needed) internal {
        uint256 idle = USDC.balanceOf(address(this));
        if (idle >= needed) return;
        uint256 shortfall = needed - idle;
        uint256 stockValue;
        uint256[] memory values = new uint256[](underlyings.length);
        for (uint256 i; i < underlyings.length; ++i) {
            (uint256 px, int32 expo) = _price(pythPriceIds[i], priceMaxAge);
            uint256 v = _toUSDC(underlyings[i].balanceOf(address(this)), px, expo);
            values[i] = v;
            stockValue += v;
        }
        require(stockValue >= shortfall, "insufficient basket");
        for (uint256 i; i < underlyings.length; ++i) {
            if (values[i] == 0) continue;
            uint256 leg = shortfall.mulDiv(values[i], stockValue, Math.Rounding.Ceil);
            (uint256 px, int32 expo) = _price(pythPriceIds[i], priceMaxAge);
            uint256 amountIn = _toBase(leg, px, expo);
            uint256 bal = underlyings[i].balanceOf(address(this));
            if (amountIn > bal) amountIn = bal;
            if (amountIn == 0) continue;
            // why: minOut from the same Pyth print minus tolerance — onchain quoter
            // without an extra hop; Uniswap still enforces it.
            uint256 minOut = _toUSDC(amountIn, px, expo).mulDiv(BPS - maxSlippageBps, BPS);
            uint256 out = _swap(address(underlyings[i]), address(USDC), amountIn, minOut);
            shortfall = out >= shortfall ? 0 : shortfall - out;
            if (shortfall == 0) break;
        }
        require(USDC.balanceOf(address(this)) >= needed, "free failed");
    }

    /// @notice One Uniswap exact-input hop with prior approval. Returns amountOut.
    function _swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        internal
        returns (uint256)
    {
        IERC20(tokenIn).forceApprove(address(uniRouter), amountIn);
        return uniRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /// @notice Fresh price or revert (swap path). @return px>0 and expo.
    function _freshPrice(bytes32 id) internal view returns (uint256 px, int32 expo) {
        (px, expo) = _price(id, priceMaxAge);
        if (px == 0) revert StalePrice();
    }

    /// @notice Price read with explicit age bound (type(uint).max = display path).
    function _price(bytes32 id, uint256 age)
        internal
        view
        returns (uint256 px, int32 expo)
    {
        // why: try/catch keeps withdrawableUSDC (display) from bricking on one dead feed.
        try pyth.getPriceNoOlderThan(id, age) returns (PythPrice memory p) {
            if (p.price <= 0) return (0, 0);
            px = uint256(uint64(p.price));
            expo = p.expo;
        } catch {
            return (0, 0);
        }
    }

    /// @notice Base units (6dp token) -> USDC base units (6dp) at (px, expo).
    function _toUSDC(uint256 amount, uint256 px, int32 expo) internal pure returns (uint256) {
        if (expo >= 0) return amount.mulDiv(px * (10 ** uint32(expo)), 1);
        return amount.mulDiv(px, 10 ** uint32(-expo));
    }

    /// @notice USDC base units -> token base units at (px, expo). Rounds up (never under-buy dust).
    function _toBase(uint256 usdc, uint256 px, int32 expo) internal pure returns (uint256) {
        if (expo >= 0) return usdc.mulDiv(1, px * (10 ** uint32(expo)), Math.Rounding.Ceil);
        return usdc.mulDiv(10 ** uint32(-expo), px, Math.Rounding.Ceil);
    }

    /// @dev Blocks accidental native-token lockup (rebalance refunds MON dust already).
    receive() external payable {}
}
