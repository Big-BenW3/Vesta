"""Request safety: checksum addresses, constant-time API keys, rate limits.

Reads are public but budgeted; the single POST route is agent-key only.
"""

from __future__ import annotations

import secrets
import time
from collections import defaultdict

import re

from fastapi import Header, HTTPException, Request

from models.errors import unauthorized

_ADDRESS_RE = re.compile(r"^0x[0-9a-fA-F]{40}$")


def checksum(address: str) -> str:
    """Validate + normalise an EVM address. Raises 400 INVALID_ADDRESS.

    Full EIP-55 casing needs web3 (present on the Render image); without it,
    shape-validated addresses pass through lowercased (store lowercases anyway).
    """
    if not _ADDRESS_RE.match(address or ""):
        from models.errors import invalid_address

        raise invalid_address(address)
    try:
        from web3 import Web3

        return Web3.to_checksum_address(address)
    except ImportError:
        return address.lower()

WINDOW_S = 60
READ_LIMIT = 60  # why: 60 req/min/IP — generous for a demo panel, fatal for a scraper
WRITE_LIMIT = 20  # why: reasoning POSTs + verifier page are heavier; budget tighter
_hits: dict[str, list[float]] = defaultdict(list)


def require_agent_key(x_api_key: str = Header(default="")) -> str:
    """Gate POST /reasoning. Missing/bad key -> 401, compared in constant time."""
    from core.config import load

    expected = load().agent_api_key
    if not x_api_key or not secrets.compare_digest(x_api_key, expected):
        raise unauthorized()
    return x_api_key


def check_rate_limit(ip: str, limit: int = READ_LIMIT) -> None:
    """Sliding-window budget per IP. Over budget -> 429 with Retry-After."""
    from models.errors import rate_limited

    now = time.time()
    window = [t for t in _hits[(ip, limit)] if now - t < WINDOW_S]
    _hits[(ip, limit)] = window
    if len(window) >= limit:
        raise rate_limited(int(WINDOW_S - (now - window[0])))
    window.append(now)


async def rate_limit(request: Request) -> None:  # FastAPI dependency: reads, 60/min
    """Dependency wrapper extracting the client IP."""
    ip = request.client.host if request.client else "unknown"
    check_rate_limit(ip, READ_LIMIT)


async def rate_limit_strict(request: Request) -> None:  # FastAPI dependency: writes/heavy, 20/min
    """Dependency wrapper for POST /reasoning and /verifier."""
    ip = request.client.host if request.client else "unknown"
    check_rate_limit(ip, WRITE_LIMIT)
