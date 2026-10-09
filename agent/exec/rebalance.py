"""Execution layer: reasoning -> hash -> POST -> commit -> rebalance.

Hash MUST equal the vault's formula:
  keccak256(abi.encode(vault, nonce, timestamp, keccak256(reasoningJson)))
with reasoningJson canonicalised (sorted keys, no whitespace) — the verifier
page and any auditor re-derive the same bytes. Any deviation breaks verification.
"""

from __future__ import annotations

import json
import time

import httpx
from eth_abi import encode
from web3 import Web3

from data.state import VaultState


def canonical_reasoning(
    vault: str,
    nonce: int,
    timestamp: int,
    prices: dict[str, float],
    compositions: dict[str, int],
    momentum: dict[str, float],
    volatility: dict[str, float],
    target_weights_bps: dict[str, int],
    explanation: str,
) -> bytes:
    """Canonical reasoning bytes. Sorted keys + compact separators, always."""
    doc = {
        "vault": Web3.to_checksum_address(vault),
        "nonce": nonce,
        "timestamp": timestamp,
        "inputPrices": prices,
        "inputCompositions": compositions,
        "computedMomentum": momentum,
        "computedVolatility": volatility,
        "targetWeights": target_weights_bps,
        "explanation": explanation,
    }
    return json.dumps(doc, sort_keys=True, separators=(",", ":")).encode()


def commitment_hash(vault: str, nonce: int, timestamp: int, reasoning: bytes) -> bytes:
    """Solidity-compatible commitment fingerprint."""
    inner = Web3.keccak(reasoning)
    return Web3.keccak(
        encode(
            ["address", "uint256", "uint256", "bytes32"],
            [Web3.to_checksum_address(vault), nonce, timestamp, inner],
        )
    )


def post_reasoning(api_url: str, api_key: str, reasoning: bytes, tx_hash: str = "0x") -> None:
    """Store reasoning in the API before committing onchain. 409 on nonce conflict."""
    doc = json.loads(reasoning)
    doc["txHash"] = tx_hash
    resp = httpx.post(
        f"{api_url}/api/v1/reasoning",
        json=doc,
        headers={"X-API-Key": api_key},
        timeout=15.0,
    )
    if resp.status_code == 409:
        raise RuntimeError("nonce conflict — operator state diverged, aborting")
    resp.raise_for_status()


def submit_rebalance(
    w3: Web3,
    vault_address: str,
    registry_address: str,
    operator_key: str,
    nonce: int,
    timestamp: int,
    commitment: bytes,
    new_weights: list[int],
    price_update_data: list[bytes],
    min_amount_out: list[int],
    api_url: str,
    api_key: str,
    reasoning: bytes,
) -> tuple[str, str]:
    """POST reasoning, then TX1 commit, then TX2 rebalance. Returns (commit_tx, reb_tx)."""
    acct = w3.eth.account.from_key(operator_key)
    vault = w3.eth.contract(address=vault_address, abi=_vault_abi())
    registry = w3.eth.contract(address=registry_address, abi=_registry_abi())

    post_reasoning(api_url, api_key, reasoning)

    tx1 = registry.functions.commit(
        commitment, vault_address, nonce, timestamp
    ).build_transaction({"from": acct.address, "nonce": w3.eth.get_transaction_count(acct.address)})
    commit_tx = w3.eth.send_raw_transaction(acct.sign_transaction(tx1).raw_transaction)
    w3.eth.wait_for_transaction_receipt(commit_tx, timeout=120)

    # why: value covers the Pyth update fee; dust refunds to the operator onchain.
    pyth_addr = vault.functions.pyth().call()
    pyth = w3.eth.contract(address=pyth_addr, abi=_pyth_abi())
    value = pyth.functions.getUpdateFee(price_update_data).call()

    tx2 = vault.functions.rebalance(
        commitment, nonce, timestamp, new_weights, price_update_data, min_amount_out
    ).build_transaction(
        {"from": acct.address, "nonce": w3.eth.get_transaction_count(acct.address), "value": value}
    )
    reb_tx = w3.eth.send_raw_transaction(acct.sign_transaction(tx2).raw_transaction)
    w3.eth.wait_for_transaction_receipt(reb_tx, timeout=180)
    return commit_tx.hex(), reb_tx.hex()


def _vault_abi() -> list:
    return _read_abi("EquityVault")


def _registry_abi() -> list:
    return _read_abi("StrategyCommitmentRegistry")


def _pyth_abi() -> list:
    return [
        {
            "inputs": [{"name": "updateData", "type": "bytes[]"}],
            "name": "getUpdateFee",
            "outputs": [{"name": "", "type": "uint256"}],
            "stateMutability": "view",
            "type": "function",
        }
    ]


def _read_abi(name: str) -> list:
    from pathlib import Path

    path = Path(__file__).resolve().parents[2] / "shared" / "abis" / f"{name}.json"
    return json.loads(path.read_text())


def now() -> int:
    """Single timestamp source for a tick (commit + rebalance share it)."""
    return int(time.time())
