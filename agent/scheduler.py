"""5-minute scheduler: full tick per vault (read -> strategise -> maybe rebalance).

Skips ticks on RPC/Hermes failure (logs, exits 0 — a missed tick is cheaper than
a bad trade). Commitments are written only when a trade follows.
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from web3 import Web3

from data import market
from data.state import read_vault
from exec.rebalance import canonical_reasoning, commitment_hash, now, submit_rebalance
from strategy import drift, momentum_vol

log = logging.getLogger("vesta-agent")
CADENCE_S = 300


def tick(w3: Web3, cfg: dict, vault_cfg: dict) -> str:
    """One vault, one tick. Returns a human-readable outcome line."""
    state = read_vault(w3, vault_cfg["address"], cfg["usdc"], vault_cfg["underlyings"])
    symbols = {t: f"Equity.US.{t[1:]}/USD" for t in vault_cfg["tickers"]}
    closes = {t: market.get_daily_closes(cfg["hermes"], s) for t, s in symbols.items()}
    weights, explain = momentum_vol.compute_weights(closes)
    ordered = [weights[t] for t in vault_cfg["tickers"]]
    current = _current_bps(state)
    if not drift.should_rebalance(current, ordered):
        return f"{vault_cfg['name']}: no rebalance needed"
    ts = now()
    prices = market.get_latest_prices(cfg["hermes"], vault_cfg["feedIds"])
    reasoning = canonical_reasoning(
        state.address, state.nonce, ts, prices,
        {t: state.holdings[a] for t, a in zip(vault_cfg["tickers"], state.underlyings)},
        explain["momentum"], explain["volatility"], weights,
        f"momentum/vol rebalance, fallback={explain['fallback']}",
    )
    h = commitment_hash(state.address, state.nonce, ts, reasoning)
    update_data = market.get_price_update_data(cfg["hermes"], vault_cfg["feedIds"])
    commit_tx, reb_tx = submit_rebalance(
        w3, state.address, cfg["registry"], cfg["operatorKey"], state.nonce, ts,
        h, ordered, update_data, [0] * len(ordered),
        cfg["apiUrl"], cfg["apiKey"], reasoning,
    )
    return f"{vault_cfg['name']}: rebalanced nonce={state.nonce} {commit_tx[:10]}.. {reb_tx[:10]}.."


def _current_bps(state) -> list[int]:
    """Onchain composition in BPS from holdings + latest-known prices."""
    # why: agent-side estimate only — settlement truth stays onchain in the vault.
    total = state.idle_usdc + sum(state.holdings.values())
    if total == 0:
        return [0] * len(state.underlyings)
    return [h * 10_000 // total for h in [state.holdings[t] for t in state.underlyings]]


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    cfg = {
        "rpc": os.environ["RPC_URL"],
        "usdc": os.environ["USDC_ADDR"],
        "registry": os.environ["REGISTRY_ADDR"],
        "operatorKey": os.environ["AGENT_OPERATOR_KEY"],
        "apiUrl": os.environ.get("API_URL", "http://localhost:8000"),
        "apiKey": os.environ["AGENT_API_KEY"],
        "hermes": os.environ.get("HERMES_URL", "https://hermes.pyth.network"),
    }
    deployments = json.load(open("shared/deployments.json"))
    w3 = Web3(Web3.HTTPProvider(cfg["rpc"]))
    once = os.environ.get("AGENT_ONCE") == "1"
    while True:
        for v in deployments.get("vaults", []):
            try:
                log.info(tick(w3, cfg, v))
            except Exception as exc:  # noqa: BLE001 — skip-tick, never half-trade
                log.warning("tick skipped: %s", exc)
        if once:
            return
        time.sleep(CADENCE_S)


if __name__ == "__main__":
    main()
