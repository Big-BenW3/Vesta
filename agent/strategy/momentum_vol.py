"""V1 strategy: momentum + inverse-volatility weighting (see docs/STRATEGY.md).

mom_i = now/ago - 1; vol_i = stdev(daily returns); raw_i = max(0, mom_i)/vol_i;
weights = raw/sum -> BPS with largest-remainder so the total is exactly 10_000.
"""

from __future__ import annotations

import statistics

BPS = 10_000


def compute_weights(closes: dict[str, list[float]]) -> tuple[dict[str, int], dict]:
    """Per-ticker closes (oldest-first) -> (BPS weights, explain dict for reasoning JSON).

    Degenerate all-negative momentum falls back to equal-weight and says so.
    """
    if not closes:
        raise ValueError("empty price map")
    momentum: dict[str, float] = {}
    volatility: dict[str, float] = {}
    for ticker, px in closes.items():
        if len(px) < 2 or any(p <= 0 for p in px):
            raise ValueError(f"ragged closes for {ticker}")
        momentum[ticker] = px[-1] / px[0] - 1
        rets = [px[i] / px[i - 1] - 1 for i in range(1, len(px))]
        # why: floor at 1e-9 — a flat line must not divide by zero, just ranks as calm.
        volatility[ticker] = statistics.pstdev(rets) if len(rets) > 1 else 1e-9
        if volatility[ticker] <= 0:
            volatility[ticker] = 1e-9

    raw = {t: max(0.0, momentum[t]) / volatility[t] for t in closes}
    total = sum(raw.values())
    explain: dict = {
        "momentum": momentum,
        "volatility": volatility,
        "fallback": None,
    }
    if total <= 0:
        # why: every loser -> equal-weight rather than a zero vector the vault rejects.
        n = len(closes)
        weights = {t: BPS // n for t in closes}
        weights[sorted(closes)[0]] += BPS - sum(weights.values())
        explain["fallback"] = "equal-weight"
        return weights, explain

    exact = {t: raw[t] / total * BPS for t in closes}
    weights = {t: int(exact[t]) for t in closes}  # floor first...
    dust = BPS - sum(weights.values())
    for t in sorted(closes, key=lambda k: exact[k] - weights[k], reverse=True)[:dust]:
        weights[t] += 1  # ...then largest remainder takes the dust
    assert sum(weights.values()) == BPS
    return weights, explain
