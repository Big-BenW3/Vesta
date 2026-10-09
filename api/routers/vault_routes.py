"""GET /vaults — theme list and vault detail.

List/static fields come from SQLite (fast); live numbers (AUM, nonce) read
onchain per request and degrade to 502 UPSTREAM_RPC when the RPC is down —
never silently stale.
"""

from __future__ import annotations

import json

from fastapi import APIRouter, Depends, Query

from core.config import Settings, load
from core.security import checksum, rate_limit
from models import store
from models.errors import upstream_rpc, vault_not_found

router = APIRouter(dependencies=[Depends(rate_limit)])


def _w3():
    """Web3 client or None when the dependency is unavailable (CI without web3)."""
    try:
        from web3 import Web3

        return Web3(Web3.HTTPProvider(load().rpc_url))
    except ImportError:
        return None


@router.get("/vaults")
def list_vaults(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    settings: Settings = Depends(load),
) -> dict:
    """Paginated themes with stored metadata + newest rebalance timestamp."""
    vaults = store.list_vaults(settings.sqlite_path, limit, offset)
    last = store.last_rebalance(settings.sqlite_path)
    return {
        "vaults": [
            {
                "address": v["address"],
                "name": v["name"],
                "symbol": v["symbol"],
                "underlyings": json.loads(v["underlyings"]),
                "targetWeightsBps": json.loads(v["weights"]),
                "lastRebalance": last["created_at"] if last else v["created_at"],
            }
            for v in vaults
        ]
    }


@router.get("/vaults/{address}")
def vault_detail(address: str, settings: Settings = Depends(load)) -> dict:
    """Full state: stored metadata + live onchain numbers."""
    addr = checksum(address)
    row = store.get_vault(settings.sqlite_path, addr)
    if row is None:
        raise vault_not_found(addr)
    w3 = _w3()
    if w3 is None or not w3.is_connected():
        raise upstream_rpc("Monad RPC")
    try:
        from pathlib import Path

        abi = json.loads((Path("shared/abis/EquityVault.json")).read_text())
        vault = w3.eth.contract(address=addr, abi=abi)
        nonce = vault.functions.nonce().call()
        supply = vault.functions.totalSupply().call()
        aum = vault.functions.withdrawableUSDC().call()
        idle = vault.functions.USDC().call()
    except Exception:  # noqa: BLE001 — any chain/ABI failure is a 502, not a 500
        raise upstream_rpc("Monad RPC")
    return {
        "address": addr,
        "name": row["name"],
        "symbol": row["symbol"],
        "underlyings": json.loads(row["underlyings"]),
        "targetWeightsBps": json.loads(row["weights"]),
        "nonce": nonce,
        "totalSupply": str(supply),
        "aumEstimate": str(aum),
        "idleUsdc": str(idle),
    }
