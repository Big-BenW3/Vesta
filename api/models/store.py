"""SQLite read-cache layer. Parameterised queries only — no f-string SQL, ever.

Tables are a rebuildable index of onchain events, NOT the source of truth:
vaults <~ VaultCreated, reasoning <~ agent POSTs, rebalances <~ Rebalanced.
"""

from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from typing import Iterator

SCHEMA = """
CREATE TABLE IF NOT EXISTS vaults(
  address TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  symbol TEXT NOT NULL,
  underlyings TEXT NOT NULL,
  weights TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS reasoning(
  vault TEXT NOT NULL,
  nonce INTEGER NOT NULL,
  timestamp INTEGER NOT NULL,
  json TEXT NOT NULL,
  tx_hash TEXT NOT NULL DEFAULT '0x',
  PRIMARY KEY (vault, nonce)
);
CREATE TABLE IF NOT EXISTS rebalances(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  vault TEXT NOT NULL,
  nonce INTEGER NOT NULL,
  tx_hash TEXT NOT NULL DEFAULT '0x',
  created_at INTEGER NOT NULL
);
"""


@contextmanager
def connect(path: str, read_only: bool = False) -> Iterator[sqlite3.Connection]:
    """Open the DB (read-only for GET handlers). Yields rows as dicts."""
    uri = f"file:{path}?mode=ro" if read_only else path
    con = sqlite3.connect(uri, uri=read_only, check_same_thread=False)
    try:
        con.row_factory = sqlite3.Row
        yield con
    finally:
        con.close()


def init_db(path: str) -> None:
    """Create tables if missing. Idempotent — safe on every boot."""
    with connect(path) as con:
        con.executescript(SCHEMA)


def upsert_vault(path: str, address: str, name: str, symbol: str,
                 underlyings: list[str], weights: list[int], created_at: int) -> None:
    """Insert or replace one vault row (deploy sync path)."""
    with connect(path) as con:
        con.execute(
            "INSERT OR REPLACE INTO vaults(address,name,symbol,underlyings,weights,created_at)"
            " VALUES (?,?,?,?,?,?)",
            (address.lower(), name, symbol, json.dumps(underlyings),
             json.dumps(weights), created_at),
        )
        con.commit()


def list_vaults(path: str, limit: int, offset: int) -> list[dict]:
    """Paginated vault rows, insertion order. Callers clamp limit/offset first."""
    with connect(path, read_only=True) as con:
        rows = con.execute(
            "SELECT * FROM vaults ORDER BY rowid LIMIT ? OFFSET ?", (limit, offset)
        ).fetchall()
    return [dict(r) for r in rows]


def get_vault(path: str, address: str) -> dict | None:
    """One vault row or None (caller maps None -> 404 VAULT_NOT_FOUND)."""
    with connect(path, read_only=True) as con:
        row = con.execute(
            "SELECT * FROM vaults WHERE address = ?", (address.lower(),)
        ).fetchone()
    return dict(row) if row else None


def store_reasoning(path: str, vault: str, nonce: int, timestamp: int,
                     doc_json: str, tx_hash: str) -> str:
    """Insert reasoning. Returns 'inserted' | 'identical' | 'conflict'.

    Tamper evidence: same (vault, nonce) with DIFFERENT bytes is a conflict,
    never an overwrite.
    """
    with connect(path) as con:
        row = con.execute(
            "SELECT json FROM reasoning WHERE vault = ? AND nonce = ?",
            (vault.lower(), nonce),
        ).fetchone()
        if row:
            return "identical" if row["json"] == doc_json else "conflict"
        con.execute(
            "INSERT INTO reasoning(vault,nonce,timestamp,json,tx_hash) VALUES (?,?,?,?,?)",
            (vault.lower(), nonce, timestamp, doc_json, tx_hash),
        )
        con.commit()
        return "inserted"


def get_reasoning(path: str, vault: str, nonce: int) -> dict | None:
    """One reasoning row or None (caller maps None -> 404 REASONING_NOT_FOUND)."""
    with connect(path, read_only=True) as con:
        row = con.execute(
            "SELECT * FROM reasoning WHERE vault = ? AND nonce = ?",
            (vault.lower(), nonce),
        ).fetchone()
    return dict(row) if row else None


def record_rebalance(path: str, vault: str, nonce: int, tx_hash: str, created_at: int) -> None:
    """Append to the rebalance log (event indexer path)."""
    with connect(path) as con:
        con.execute(
            "INSERT INTO rebalances(vault,nonce,tx_hash,created_at) VALUES (?,?,?,?)",
            (vault.lower(), nonce, tx_hash, created_at),
        )
        con.commit()


def last_rebalance(path: str) -> dict | None:
    """Newest rebalance row or None (fresh DB). Drives GET /agent/status."""
    with connect(path, read_only=True) as con:
        row = con.execute(
            "SELECT * FROM rebalances ORDER BY id DESC LIMIT 1"
        ).fetchone()
    return dict(row) if row else None
