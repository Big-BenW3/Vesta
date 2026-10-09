"""Reasoning store: GET public, POST agent-only.

POST safety, in order: API key -> 64KB cap -> Pydantic shape -> weights sum to
10_000 -> timestamp within +/-5min -> nonce equals onchain vault.nonce() ->
idempotent insert. First failure wins, with the envelope code from backend.md.
"""

from __future__ import annotations

import json
import time

from fastapi import APIRouter, Depends, Request

from core.config import Settings, load
from core.security import checksum, rate_limit, rate_limit_strict, require_agent_key
from models import store
from models.errors import (
    nonce_conflict,
    reasoning_not_found,
    schema_invalid,
    upstream_rpc,
    vault_not_found,
)
from models.schemas import MAX_BODY_BYTES, ReasoningDoc

router = APIRouter(dependencies=[Depends(rate_limit_strict)])

TIMESTAMP_SKEW_S = 300


@router.get("/reasoning/{vault}/{nonce}")
def get_reasoning(vault: str, nonce: int, settings: Settings = Depends(load)) -> dict:
    """Fetch one published reasoning JSON. 404 when never posted."""
    addr = checksum(vault)
    if nonce < 0:
        raise schema_invalid({"nonce": "must be >= 0"})
    row = store.get_reasoning(settings.sqlite_path, addr, nonce)
    if row is None:
        raise reasoning_not_found(addr, nonce)
    return json.loads(row["json"])


@router.post("/reasoning", status_code=200)
async def post_reasoning(
    request: Request,
    settings: Settings = Depends(load),
    _key: str = Depends(require_agent_key),
) -> dict:
    """Agent-only store. Idempotent on (vault, nonce); conflicts are 409, never overwrites."""
    raw = await request.body()
    if len(raw) > MAX_BODY_BYTES:
        raise schema_invalid({"body": f"exceeds {MAX_BODY_BYTES} bytes"})
    try:
        doc = ReasoningDoc.model_validate_json(raw)
    except Exception as exc:  # noqa: BLE001 — Pydantic shapes the message
        raise schema_invalid({"validation": str(exc)})
    if sum(doc.targetWeights.values()) != 10_000:
        raise schema_invalid({"targetWeights": "must sum to 10_000 BPS"})
    if abs(time.time() - doc.timestamp) > TIMESTAMP_SKEW_S:
        raise schema_invalid({"timestamp": "outside +/-5min skew window"})

    addr = checksum(doc.vault)
    if store.get_vault(settings.sqlite_path, addr) is None:
        raise vault_not_found(addr)
    if not _nonce_matches(settings, addr, doc.nonce):
        raise nonce_conflict()

    canonical = doc.model_dump_json()
    outcome = store.store_reasoning(
        settings.sqlite_path, addr, doc.nonce, doc.timestamp, canonical, doc.txHash
    )
    if outcome == "conflict":
        raise nonce_conflict()
    return {"stored": outcome, "vault": addr, "nonce": doc.nonce}


def _nonce_matches(settings: Settings, vault: str, nonce: int) -> bool:
    """True when nonce equals the vault's onchain nonce. RPC down -> 502."""
    try:
        from pathlib import Path

        from web3 import Web3

        w3 = Web3(Web3.HTTPProvider(settings.rpc_url))
        abi = json.loads((Path("shared/abis/EquityVault.json")).read_text())
        onchain = w3.eth.contract(address=vault, abi=abi).functions.nonce().call()
        return onchain == nonce
    except ImportError:
        raise upstream_rpc("Monad RPC")
    except Exception:  # noqa: BLE001 — chain/ABI failure is a 502, not a 500
        raise upstream_rpc("Monad RPC")
