// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/IERC20.sol";
import {EquityVault} from "./EquityVault.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IPyth, IStrategyCommitmentRegistry} from "./interfaces/IPyth.sol";
import {StrategyCommitmentRegistry} from "./StrategyCommitmentRegistry.sol";

/// @notice Permissionless theme launcher and onchain registry of every Vesta
/// vault. One transaction: spec in, CREATE2 vault out at a deterministic address.
/// @dev CREATE2 salt binds (creator, themeId) so the same theme redeploys to the
/// same address on any chain — testnet addresses predict mainnet ones.
contract VaultFactory {
    /// @notice Full theme definition. Arrays are parallel: underlying[i] <->
    /// targetWeightsBps[i] <-> pythPriceIds[i].
    struct ThemeSpec {
        string name;
        string symbol;
        address[] underlying;
        uint256[] targetWeightsBps;
        bytes32[] pythPriceIds;
        address feeRecipient;
        uint256 managementFeeBps;
    }

    /// @notice Immutable DEX/oracle wiring every vault shares (testnet values).
    ISwapRouter public immutable uniRouter;
    uint24 public immutable poolFee;
    IPyth public immutable pyth;
    uint256 public immutable priceMaxAge;
    uint256 public immutable maxSlippageBps;
    IERC20 public immutable usdc;
    StrategyCommitmentRegistry public immutable registry;

    /// @notice themeId => vault. Zero means never created.
    mapping(bytes32 => address) public vaults;

    /// @param vault The deployed vault. @param creator Who called createVault.
    /// @param themeId keccak256(name, symbol, underlying, weights) — the theme's identity.
    event VaultCreated(address indexed vault, address indexed creator, bytes32 indexed themeId);

    error LengthMismatch();
    error BadWeights();
    error ZeroAddress();
    error AlreadyCreated();

    /// @param usdc_ Circle testnet USDC. @param router_ Testnet swap router.
    /// @param poolFee_ Pool tier. @param pyth_ Pyth. @param priceMaxAge_ Swap price freshness.
    /// @param maxSlippageBps_ Swap guard. Deploys its own registry first.
    constructor(
        IERC20 usdc_,
        ISwapRouter router_,
        uint24 poolFee_,
        IPyth pyth_,
        uint256 priceMaxAge_,
        uint256 maxSlippageBps_
    ) {
        if (
            address(usdc_) == address(0) || address(router_) == address(0)
                || address(pyth_) == address(0)
        ) revert ZeroAddress();
        usdc = usdc_;
        uniRouter = router_;
        poolFee = poolFee_;
        pyth = pyth_;
        priceMaxAge = priceMaxAge_;
        maxSlippageBps = maxSlippageBps_;
        registry = new StrategyCommitmentRegistry(address(this));
    }

    /// @notice Deploys a themed vault. Validates the spec, CREATE2-deploys, registers
    /// the operator in the registry, records themeId => vault.
    /// @param spec Theme definition. @param operator Agent EOA for this vault.
    /// @return vault The new EquityVault address.
    function createVault(ThemeSpec calldata spec, address operator)
        external
        returns (address vault)
    {
        if (
            spec.underlying.length == 0 || spec.underlying.length != spec.targetWeightsBps.length
                || spec.underlying.length != spec.pythPriceIds.length
        ) revert LengthMismatch();
        uint256 sum;
        for (uint256 i; i < spec.targetWeightsBps.length; ++i) {
            if (spec.underlying[i] == address(0)) revert ZeroAddress();
            sum += spec.targetWeightsBps[i];
        }
        if (sum != 10_000) revert BadWeights();
        if (spec.feeRecipient == address(0) || operator == address(0)) revert ZeroAddress();

        // why: identity covers feeds + fee too — same basket on different oracle
        // feeds (or fee tiers) is a different theme, not a duplicate.
        bytes32 themeId = keccak256(
            abi.encode(
                spec.name,
                spec.symbol,
                spec.underlying,
                spec.targetWeightsBps,
                spec.pythPriceIds,
                spec.feeRecipient,
                spec.managementFeeBps
            )
        );
        if (vaults[themeId] != address(0)) revert AlreadyCreated();

        IERC20[] memory underlyings = new IERC20[](spec.underlying.length);
        for (uint256 i; i < spec.underlying.length; ++i) {
            underlyings[i] = IERC20(spec.underlying[i]);
        }
        bytes32 salt = keccak256(abi.encode(msg.sender, themeId));
        vault = address(
            new EquityVault{salt: salt}(
                usdc,
                underlyings,
                spec.targetWeightsBps,
                uniRouter,
                poolFee,
                pyth,
                spec.pythPriceIds,
                priceMaxAge,
                maxSlippageBps,
                IStrategyCommitmentRegistry(address(registry)),
                operator,
                spec.feeRecipient,
                spec.managementFeeBps,
                spec.name,
                spec.symbol
            )
        );
        registry.registerOperator(vault, operator);
        vaults[themeId] = vault;
        emit VaultCreated(vault, msg.sender, themeId);
    }
}
