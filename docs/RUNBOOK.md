# Demo-day runbook (90 seconds, Monad testnet)

## T-1 day: chain state

1. `bash e2e/testnet_check.sh` green on 10143 (deploys + pools + round-trip).
2. Confirm `shared/deployments.json` holds registry, factory, both vaults, router.
3. Confirm Render: API `/healthz` ok, worker logs show `no rebalance needed` ticks.
4. Fund demo wallet: faucet MON (gas) + Circle faucet USDC (deposit).

## The 90 seconds

| Time | Action | Proof on screen |
|---|---|---|
| 0–10s | API `/api/v1/vaults`: two themes, real AUM | vault list |
| 10–25s | Vault detail: composition, target vs actual | numbers match chain |
| 25–40s | Force one rebalance (worker `AGENT_ONCE=1`); reasoning panel slides in with momentum/vol explanation | reasoning JSON |
| 40–55s | `/verifier`: recompute hash -> ✅ against `StrategyCommitted` event on MonadVision testnet | green check |
| 55–70s | Balances before/after: overweight sold, underweight bought | `Rebalanced` event |
| 70–90s | Black-box slide: Bankr ⬛ closed, Cesto static, Vesta 🟢 verifiable | narrative |

## If anything breaks live

* RPC down: API returns `502 UPSTREAM_RPC` envelope (never a hang) — narrate the
  cached reasoning panel instead; hosted JSON still verifies against old events.
* No drift: lower nothing — show the `no rebalance needed` tick as honesty proof,
  then force-tick with a one-off threshold override documented in the log line.
* Key safety: demo wallet holds testnet funds only; operator key stays in Render env.
