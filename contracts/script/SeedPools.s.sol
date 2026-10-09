// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/IERC20.sol";
import {MockStock} from "../src/mocks/MockStock.sol";

/// @notice Minimal Uniswap V3 surfaces for testnet pool bootstrapping.
interface IV3Factory {
    function getPool(address a, address b, uint24 fee) external view returns (address);
    function createPool(address a, address b, uint24 fee) external returns (address);
}

interface INPM {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function createAndInitializePoolIfNecessary(address a, address b, uint24 fee, uint160 px)
        external
        payable
        returns (address);
    function mint(MintParams calldata p)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

/// @notice Creates USDC/mSTOCK 0.3% pools and seeds full-range liquidity so
/// deposit/redeem/rebalance swaps execute on testnet.
/// @dev Run AFTER Deploy.s.sol, with pool addresses read from shared/deployments.json
/// (STOCKS_JSON env = JSON array of the 10 mock addresses). Run:
/// `forge script script/SeedPools.s.sol --rpc-url $RPC_URL --broadcast`.
/// 1:1 init price (6dp/6dp) + full-range ticks: depth over precision for a demo.
contract SeedPools is Script {
    uint24 constant FEE = 3000;
    // why: full-range (-887220, 887220) maximises fill probability for demo-size
    // swaps; tight ranges are a V2 optimisation, not a hackathon need.
    int24 constant TICK_MIN = -887220;
    int24 constant TICK_MAX = 887220;

    function run() external {
        address usdc = vm.envAddress("USDC_ADDR");
        address factory = vm.envAddress("UNI_FACTORY_ADDR");
        address npm = vm.envAddress("UNI_NPM_ADDR");
        address[] memory stocks = vm.envAddress("STOCK_ADDRS", ",");
        uint256 seedUSDC = vm.envUint("SEED_USDC"); // base units per pool, e.g. 5000000000
        vm.startBroadcast();
        for (uint256 i; i < stocks.length; ++i) {
            address pool = IV3Factory(factory).getPool(usdc, stocks[i], FEE);
            if (pool == address(0)) {
                pool = INPM(npm).createAndInitializePoolIfNecessary(
                    usdc, stocks[i], FEE, 79228162514264337593543950336 // 2**96 = 1:1
                );
            }
            (address t0, address t1) =
                usdc < stocks[i] ? (usdc, stocks[i]) : (stocks[i], usdc);
            // why: USDC is real Circle testnet USDC — pre-fund the deployer via
            // faucet.circle.com. Only the mock leg mints freely.
            MockStock(stocks[i]).mint(msg.sender, seedUSDC);
            IERC20(usdc).approve(npm, seedUSDC);
            IERC20(stocks[i]).approve(npm, seedUSDC);
            INPM(npm).mint(
                INPM.MintParams(t0, t1, FEE, TICK_MIN, TICK_MAX, seedUSDC, seedUSDC, 0, 0, msg.sender, block.timestamp + 3600)
            );
            console.log("pool", pool);
        }
        vm.stopBroadcast();
    }
}
