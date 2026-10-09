"""Read-only tick: prints target weights per vault, sends no transactions.

CI asserts the printed weights equal docs/STRATEGY.md's worked example when run
against the fixture prices (see tests/test_strategy.py for the same numbers).
"""

from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from data import market
from strategy import drift, momentum_vol


def main() -> int:
    hermes = os.environ.get("HERMES_URL", "https://hermes.pyth.network")
    deployments = json.load(open("shared/deployments.json"))
    for vault in deployments.get("vaults", []):
        symbols = {t: f"Equity.US.{t[1:]}/USD" for t in vault["tickers"]}
        closes = {t: market.get_daily_closes(hermes, s) for t, s in symbols.items()}
        weights, explain = momentum_vol.compute_weights(closes)
        current = vault.get("weightsBps", [0] * len(weights))
        ordered = [weights[t] for t in vault["tickers"]]
        fire = drift.should_rebalance(current, ordered)
        print(f"{vault['name']}: drift={drift.max_drift_bps(current, ordered)}bps "
              f"fire={fire} weights={ordered} fallback={explain['fallback']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
