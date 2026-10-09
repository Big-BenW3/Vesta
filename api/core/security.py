"""Request safety: checksum addresses, constant-time API keys, rate limits.

Reads are public but budgeted; the single POST route is agent-key only.
"""

from __future__ import annotations

import secrets
import time
from collections import defaultdict

from fastapi import Header, HTTPException
from web3 import Web3

from models.errors import unauthorized

WINDOW_S = 60
READ_LIMIT = 60  # why: 60 req/min/IP — generous for a demo panel, fatal for a scraper
_hits: dict[str, list[float]] = defaultdict(list)


def checksum(address: str) -> str:
    """Validate + normalise an EVM address. Raises 400 INVALID_ADDRESS."""
    try:
        return Web3.to_checksum_address(address)
    except Exception:  # noqa: BLE001 — any parse failure is a 400
        from models.errors import invalid_address

        raise invalid_address(address)


def require_agent_key(x_api_key: str = Header(default="")) -> str:
    """Gate POST /reasoning. Missing/bad key -> 401, compared in constant time."""
    from core.config import load

    expected = load().agent_api_key
    if not x_api_key or not secrets.compare_digest(x_api_key, expected):
        raise unauthorized()
    return x_api_key


def check_rate_limit(ip: str) -> None:
    """Sliding-window budget per IP. Over budget -> 429 with Retry-After."""
    from models.errors import rate_limited

    now = time.time()
    window = [t for t in _hits[ip] if now - t < WINDOW_S]
    _hits[ip] = window
    if len(window) >= READ_LIMIT:
        raise rate_limited(int(WINDOW_S - (now - window[0])))
    window.append(now)


async def rate_limit(request) -> None:  # FastAPI dependency
    """Dependency wrapper extracting the client IP."""
    ip = request.client.host if request.client else "unknown"
    check_rate_limit(ip)
