"""Strategy + hashing guarantees. Mirrors docs/STRATEGY.md's worked example exactly."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from exec.rebalance import canonical_reasoning, commitment_hash
from strategy import drift, momentum_vol

import exec.rebalance as reb_mod
from tests.keccak_pure import checksum_address as pure_checksum
from tests.keccak_pure import keccak256 as pure_keccak

# why: no compiled keccak backend exists on this machine — the pure helper stands
# in ONLY for tests, after proving itself against ethers vectors below.
reb_mod.keccak = pure_keccak
reb_mod.to_checksum_address = pure_checksum

# Golden vectors from ethers v6 (independent implementation), vectors.js.
VECTORS = {
    b"": "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
    b"abc": "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
    b'{"nonce":42,"timestamp":1700000000,"vault":"0x1111111111111111111111111111111111111111"}':
        "69abd62d9757fbdde30b2bf989aadcbd6a0f9f4aa123a66a7fcc445631681022",
}


def test_pure_keccak_matches_ethers():
    for raw, expect in VECTORS.items():
        assert pure_keccak(raw).hex() == expect


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


def test_commitment_matches_ethers_golden():
    # why: end-to-end layout proof — abi.encode order + double-hash, exactly as
    # the vault's formula, reproduced by an independent implementation.
    vault = "0x" + "11" * 20
    digest = commitment_hash(vault, 42, 1_700_000_000, b'{"nonce":42}')
    assert digest.hex() == "e3c9a02736fadf655df93b3758037f70688febe4d9c15b5023e4bc80243617c6"


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
