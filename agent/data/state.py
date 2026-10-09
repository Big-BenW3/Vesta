"""Onchain vault reads: composition, idle cash, nonce, supply.

ABIs load from shared/abis at runtime (exported from contracts, never hand-copied).
Every read is a pure view — this module never signs or sends.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from web3 import Web3

ABI_DIR = Path(__file__).resolve().parents[2] / "shared" / "abis"


@dataclass(frozen=True)
class VaultState:
    """One vault snapshot the strategy consumes."""

    address: str
    nonce: int
    total_supply: int
    idle_usdc: int
    holdings: dict[str, int]  # token address -> base units
    target_weights_bps: list[int]
    underlyings: list[str]


def _load_abi(name: str) -> list:
    path = ABI_DIR / f"{name}.json"
    if not path.exists():
        raise FileNotFoundError(
            f"{path} missing — export ABIs from contracts first (see backend.md section 7)"
        )
    return json.loads(path.read_text())


def read_vault(
    w3: Web3, vault_address: str, usdc_address: str, underlyings: list[str]
) -> VaultState:
    """Snapshot a vault. `underlyings` comes from shared/deployments.json metadata.

    Raises on RPC failure — callers treat it as skip-tick.
    """
    vault = w3.eth.contract(
        address=Web3.to_checksum_address(vault_address), abi=_load_abi("EquityVault")
    )
    usdc = w3.eth.contract(
        address=Web3.to_checksum_address(usdc_address), abi=_load_abi("ERC20")
    )
    erc20_abi = _load_abi("ERC20")
    n = len(underlyings)
    return VaultState(
        address=vault_address,
        nonce=vault.functions.nonce().call(),
        total_supply=vault.functions.totalSupply().call(),
        idle_usdc=usdc.functions.balanceOf(vault_address).call(),
        holdings={
            t: w3.eth.contract(address=t, abi=erc20_abi).functions.balanceOf(vault_address).call()
            for t in underlyings
        },
        target_weights_bps=[vault.functions.targetWeightsBps(i).call() for i in range(n)],
        underlyings=underlyings,
    )
