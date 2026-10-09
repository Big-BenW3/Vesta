"""Strategy + hashing guarantees. Mirrors docs/STRATEGY.md's worked example exactly."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from exec.rebalance import canonical_reasoning, commitment_hash
from strategy import drift, momentum_vol


def _closes():
    # NVDA +12%, MSFT +6%, AMD -3% over 30 closes; vols 0.020/0.015/0.025 approx.
    import math
    import random

    rng = random.Random(7)
    specs = {"mNVDA": (120.0, 134.40, 0.020), "mMSFT": (400.0, 424.0, 0.015), "mAMD": (150.0, 145.50, 0.025)}
    out = {}
    for t, (a, b, v) in specs.items():
        steps = [a + (b - a) * i / 29 for i in range(30)]
        out[t] = [max(0.01, p + rng.gauss(0, p * v * 0.3)) for p in steps]
        out[t][0], out[t][-1] = a, b
    return out


def test_worked_example_weights():
    weights, explain = momentum_vol.compute_weights(_closes())
    assert sum(weights.values()) == 10_000
    assert weights["mNVDA"] > weights["mMSFT"] > weights["mAMD"] == 0
    assert explain["fallback"] is None


def test_all_losers_fall_back_equal_weight():
    closes = {"mA": [100.0, 99.0, 98.0], "mB": [50.0, 49.0, 48.0]}
    weights, explain = momentum_vol.compute_weights(closes)
    assert sum(weights.values()) == 10_000
    assert explain["fallback"] == "equal-weight"


def test_drift_threshold_edges():
    assert drift.max_drift_bps([3000], [3199]) == 199
    assert drift.should_rebalance([3000], [3199]) is False  # 199 logs and exits
    assert drift.should_rebalance([3000], [3200]) is True  # exactly 200 fires


def test_reasoning_hash_stable_and_sensitive():
    kw = dict(
        vault="0x" + "11" * 20, nonce=42, timestamp=1_700_000_000,
        prices={"mNVDA": 134.4}, compositions={"mNVDA": 100},
        momentum={"mNVDA": 0.12}, volatility={"mNVDA": 0.02},
        target_weights_bps={"mNVDA": 10_000}, explanation="t",
    )
    r1 = canonical_reasoning(**kw)
    assert canonical_reasoning(**kw) == r1  # deterministic
    kw2 = dict(kw, target_weights_bps={"mNVDA": 9_999})
    assert canonical_reasoning(**kw2) != r1  # one digit flips the bytes
    h1 = commitment_hash(kw["vault"], kw["nonce"], kw["timestamp"], r1)
    assert len(h1) == 32
    assert commitment_hash(kw["vault"], kw["nonce"], kw["timestamp"], r1) == h1
