"""Pyth Hermes market data: latest prices, 30d history, onchain update payloads.

All reads have timeouts + retries and validate before returning — a rebalance
must never execute on a bad print. Hermes is chain-agnostic, so this module is
identical on testnet and mainnet.
"""

from __future__ import annotations

import time

import httpx

TIMEOUT_S = 10.0
RETRIES = 3
# why: Pyth confidence intervals wider than 2% of price mean a thin/ragged feed.
MAX_CONF_BPS = 200


def _get(client: httpx.Client, url: str, params: dict) -> dict:
    """GET with backoff. Honors 429 Retry-After; raises RuntimeError when exhausted."""
    last: Exception | None = None
    for attempt in range(RETRIES):
        try:
            resp = client.get(url, params=params, timeout=TIMEOUT_S)
            if resp.status_code == 429:
                # why: Hermes throttles burst history reads — wait what it asks, then retry.
                wait = float(resp.headers.get("Retry-After", 2**attempt))
                time.sleep(min(wait, 30.0))
                continue
            resp.raise_for_status()
            return resp.json()
        except Exception as exc:  # noqa: BLE001 — retried, then raised uniformly
            last = exc
            time.sleep(2**attempt)
    raise RuntimeError(f"hermes unreachable: {url} ({last})")


def _to_float(price: int, expo: int) -> float:
    """Raw (price, expo) pair to float. Rejects non-positive prints."""
    value = price * (10**expo)
    if value <= 0:
        raise ValueError(f"non-positive price print: {price}e{expo}")
    return value


def get_latest_prices(hermes_url: str, feed_ids: list[str]) -> dict[str, float]:
    """Latest mid price per feed id. Skips feeds failing the confidence clamp."""
    out: dict[str, float] = {}
    with httpx.Client() as client:
        data = _get(
            client,
            f"{hermes_url}/v2/updates/price/latest",
            {"ids[]": feed_ids},
        )
    for entry in data.get("parsed", []):
        fid = entry["id"]
        px = entry["price"]
        conf_bps = abs(px["conf"]) * 10_000 // abs(px["price"])
        if conf_bps > MAX_CONF_BPS:
            continue  # why: wide confidence = unreliable print, skip the feed
        out[fid] = _to_float(int(px["price"]), int(px["expo"]))
    if not out:
        raise RuntimeError("no usable price feeds")
    return out


def get_daily_closes(hermes_url: str, symbol: str, days: int = 30) -> list[float]:
    """Daily closes oldest-first via the Pyth benchmarks shim (TradingView shape)."""
    now = int(time.time())
    params = {
        "symbol": symbol,  # e.g. "Equity.US.NVDA/USD"
        "resolution": "D",
        "from": now - days * 86400 * 2,  # why: 2x window, weekends/holidays drop bars
        "to": now,
    }
    with httpx.Client() as client:
        data = _get(client, "https://benchmarks.pyth.network/v1/shims/tradingview/history", params)
    if data.get("s") != "ok" or not data.get("c"):
        raise RuntimeError(f"no history for {symbol}")
    closes = [float(c) for c in data["c"][-days:]]
    if len(closes) < 2 or any(c <= 0 for c in closes):
        raise ValueError(f"ragged history for {symbol}")
    return closes


def get_price_update_data(hermes_url: str, feed_ids: list[str]) -> list[bytes]:
    """Fresh signed updateData blobs for vault.rebalance()'s Pyth pull."""
    with httpx.Client() as client:
        data = _get(
            client,
            f"{hermes_url}/v2/updates/price/latest",
            {"ids[]": feed_ids},
        )
    blobs = data.get("binary", {}).get("data", [])
    if len(blobs) != len(feed_ids):
        raise RuntimeError("incomplete updateData set")
    return [bytes.fromhex(b) if not b.startswith("0x") else bytes.fromhex(b[2:]) for b in blobs]
