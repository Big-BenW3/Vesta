// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Minimal Uniswap V3 swap surface the vault needs. The full periphery
/// is unnecessary — one exact-input function with slippage protection.
/// @dev Bound at construction to the testnet deployment address recorded in
/// shared/deployments.json. Mainnet addresses are EMPTY on testnet.
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps amountIn of tokenIn for tokenOut, reverting below minimum out.
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}
