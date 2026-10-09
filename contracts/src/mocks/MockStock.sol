// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Faucet-style mock of a Backed xStock for Monad testnet. Same ERC-20
/// interface as the real asset, so vault/swap/accounting code is identical —
/// only the token address changes on mainnet.
/// @dev 6 decimals to match USDC and keep vault math in one fixed point.
/// Open mint() is TESTNET-ONLY and must never deploy to mainnet. UI labels
/// holdings of this token DEMO ASSETS.
contract MockStock is ERC20 {
    /// @notice Human ticker, e.g. "mNVDA". @param name_ Full name, e.g. "Mock Nvidia".
    /// @param symbol_ Ticker, e.g. "mNVDA".
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    /// @notice Testnet faucet: anyone may mint. Capped per-call to avoid accidents.
    /// @param to Recipient. @param amount Base units (6 decimals).
    function mint(address to, uint256 amount) external {
        require(to != address(0), "zero to");
        require(amount > 0 && amount <= 1_000_000_000_000, "bad amount"); // max 1M tokens/call
        _mint(to, amount);
    }

    /// @dev Matches USDC (6) instead of the ERC-20 default (18).
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
