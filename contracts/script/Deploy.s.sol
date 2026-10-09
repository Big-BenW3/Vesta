// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/IERC20.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {EquityVault} from "../src/EquityVault.sol";
import {MockStock} from "../src/mocks/MockStock.sol";
import {ISwapRouter} from "../src/interfaces/ISwapRouter.sol";
import {IPyth} from "../src/interfaces/IPyth.sol";

/// @notice Testnet deployment: factory + 10 mock stocks + 2 themes.
/// @dev Reads USDC/Pyth/router from env (see .env.example); writes every address
/// to shared/deployments.json via the shell wrapper (forge cannot write outside
/// broadcast/). Run: `forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast`.
/// Real xStocks replace MockStock on mainnet — same ERC-20 interface, zero logic change.
contract Deploy is Script {
    // why: mainnet xStocks are permissioned (no testnet faucet), so testnet runs mocks.
    string[10] tickers = [
        "mNVDA",
        "mMSFT",
        "mGOOGL",
        "mMETA",
        "mAMD",
        "mTSLA",
        "mENPH",
        "mFSLR",
        "mNEE",
        "mBP"
    ];
    string[10] names = [
        "Mock Nvidia",
        "Mock Microsoft",
        "Mock Alphabet",
        "Mock Meta",
        "Mock AMD",
        "Mock Tesla",
        "Mock Enphase",
        "Mock First Solar",
        "Mock NextEra",
        "Mock BP"
    ];
    // why: each mock is priced by its REAL Pyth equity feed — strategy runs on live data.
    string[10] feeds = [
        "Equity.US.NVDA/USD",
        "Equity.US.MSFT/USD",
        "Equity.US.GOOGL/USD",
        "Equity.US.META/USD",
        "Equity.US.AMD/USD",
        "Equity.US.TSLA/USD",
        "Equity.US.ENPH/USD",
        "Equity.US.FSLR/USD",
        "Equity.US.NEE/USD",
        "Equity.US.BP/USD"
    ];

    function run() external {
        address usdc = vm.envAddress("USDC_ADDR");
        address router = vm.envAddress("UNI_ROUTER_ADDR");
        address pyth = vm.envAddress("PYTH_ADDR");
        address operator = vm.envAddress("AGENT_OPERATOR");
        address feeTo = vm.envAddress("FEE_RECIPIENT");
        vm.startBroadcast();

        VaultFactory factory = new VaultFactory(
            IERC20(usdc), ISwapRouter(router), 3000, IPyth(pyth), 3600, 50
        );

        address[] memory stocks = new address[](10);
        for (uint256 i; i < 10; ++i) {
            stocks[i] = address(new MockStock(names[i], tickers[i]));
        }

        // why: feed IDs are the real Hermes Equity.US.* IDs (queried offchain),
        // passed via env so the script never invents oracle identities.
        bytes32[10] memory ids = [
            vm.envBytes32("FEED_NVDA"),
            vm.envBytes32("FEED_MSFT"),
            vm.envBytes32("FEED_GOOGL"),
            vm.envBytes32("FEED_META"),
            vm.envBytes32("FEED_AMD"),
            vm.envBytes32("FEED_TSLA"),
            vm.envBytes32("FEED_ENPH"),
            vm.envBytes32("FEED_FSLR"),
            vm.envBytes32("FEED_NEE"),
            vm.envBytes32("FEED_BP")
        ];

        // Theme A: AI Mega Cap — [3000,2500,2000,1500,1000].
        address[] memory a = new address[](5);
        uint256[] memory wa = new uint256[](5);
        bytes32[] memory fa = new bytes32[](5);
        uint256[5] memory wAv = [uint256(3000), 2500, 2000, 1500, 1000];
        for (uint256 i; i < 5; ++i) {
            a[i] = stocks[i];
            wa[i] = wAv[i];
            fa[i] = ids[i];
        }
        address vaultA = factory.createVault(
            VaultFactory.ThemeSpec("AI Mega Cap", "vAI-MEGA", a, wa, fa, feeTo, 50),
            operator
        );

        // Theme B: Energy Transition — [3500,1500,1500,2000,1500].
        address[] memory b = new address[](5);
        uint256[] memory wb = new uint256[](5);
        bytes32[] memory fb = new bytes32[](5);
        uint256[5] memory wBv = [uint256(3500), 1500, 1500, 2000, 1500];
        for (uint256 i; i < 5; ++i) {
            b[i] = stocks[5 + i];
            wb[i] = wBv[i];
            fb[i] = ids[5 + i];
        }
        address vaultB = factory.createVault(
            VaultFactory.ThemeSpec("Energy Transition", "vENERGY", b, wb, fb, feeTo, 50),
            operator
        );
        vm.stopBroadcast();

        console.log("factory", address(factory));
        console.log("registry", address(factory.registry()));
        console.log("vaultA", vaultA);
        console.log("vaultB", vaultB);
        // why: copy these four lines into shared/deployments.json — the agent, API
        // and frontend all read that file, never hardcoded addresses.
    }
}
