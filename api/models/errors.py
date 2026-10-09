"""Uniform error envelope: {"error": {"code", "message", "details"}}.

Every failure returns this shape — the frontend switches on `code`, never on
message text. 5xx messages are generic; traces stay server-side in logs.
"""

from __future__ import annotations

from fastapi import HTTPException
from fastapi.responses import JSONResponse


def envelope(code: str, message: str, details: dict | None = None) -> dict:
    """Build the envelope body."""
    return {"error": {"code": code, "message": message, "details": details or {}}}


def invalid_address(address: str) -> HTTPException:
    """400 — path/query address fails hex/checksum validation."""
    return HTTPException(400, envelope("INVALID_ADDRESS", f"Bad EVM address: {address}"))


def unauthorized() -> HTTPException:
    """401 — missing or wrong X-API-Key on agent routes."""
    return HTTPException(401, envelope("UNAUTHORIZED", "Agent key missing or invalid"))


def vault_not_found(address: str) -> HTTPException:
    """404 — well-formed address, unknown vault."""
    return HTTPException(404, envelope("VAULT_NOT_FOUND", f"No vault at {address}"))


def reasoning_not_found(vault: str, nonce: int) -> HTTPException:
    """404 — no stored reasoning for (vault, nonce)."""
    return HTTPException(
        404, envelope("REASONING_NOT_FOUND", f"No reasoning for nonce {nonce}")
    )


def nonce_conflict() -> HTTPException:
    """409 — POST nonce != onchain nonce, or different bytes under the same key."""
    return HTTPException(409, envelope("NONCE_CONFLICT", "Nonce already used or out of sync"))


def schema_invalid(details: dict) -> HTTPException:
    """422 — Pydantic/weight/timestamp violations."""
    return HTTPException(422, envelope("SCHEMA_INVALID", "Request failed validation", details))


def rate_limited(retry_after: int) -> HTTPException:
    """429 — per-IP budget spent. Retry-After header included."""
    return HTTPException(
        429,
        envelope("RATE_LIMITED", "Too many requests"),
        headers={"Retry-After": str(retry_after)},
    )


def upstream_rpc(service: str) -> HTTPException:
    """502 — Monad RPC or Hermes unreachable."""
    return HTTPException(502, envelope("UPSTREAM_RPC", f"{service} unreachable"))


def internal() -> HTTPException:
    """500 — generic message only; the trace goes to server logs."""
    return HTTPException(500, envelope("INTERNAL", "Unexpected error"))


async def envelope_middleware(request, call_next):
    """Guarantee: unhandled exceptions still return the envelope, never HTML/a stack."""
    try:
        return await call_next(request)
    except HTTPException as exc:
        body = exc.detail if isinstance(exc.detail, dict) else envelope("INTERNAL", str(exc.detail))
        return JSONResponse(status_code=exc.status_code, content=body, headers=exc.headers)
    except Exception:  # noqa: BLE001 — last-resort guard, logged upstream
        return JSONResponse(status_code=500, content=envelope("INTERNAL", "Unexpected error"))
