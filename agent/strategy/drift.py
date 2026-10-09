"""Drift gate: rebalance only when allocation is stale enough to matter."""

from __future__ import annotations

DRIFT_THRESHOLD_BPS = 200


def max_drift_bps(current_bps: list[int], target_bps: list[int]) -> int:
    """Largest absolute deviation across legs. Mismatched lengths = infinite drift."""
    if len(current_bps) != len(target_bps):
        raise ValueError("weight vector length mismatch")
    return max(abs(c - t) for c, t in zip(current_bps, target_bps))


def should_rebalance(current_bps: list[int], target_bps: list[int]) -> bool:
    """True only at/above threshold — 199 BPS logs and exits with no commitment."""
    return max_drift_bps(current_bps, target_bps) >= DRIFT_THRESHOLD_BPS
