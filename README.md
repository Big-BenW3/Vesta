# Vesta — Verifiable AI-Managed Tokenized Equity Vaults (backend monorepo)

Non-custodial tokenized-stock basket vaults on **Monad testnet** (`10143`),
managed by a deterministic offchain AI agent whose reasoning is committed
onchain before every rebalance.

* Product spec: [`PRD.md`](PRD.md)
* Backend build plan: [`backend.md`](backend.md)

## Layout

```text
contracts/  Foundry — VaultFactory, EquityVault, StrategyCommitmentRegistry, mocks
agent/      Python 3.11+ — 5-minute rebalancer (Render background worker)
api/        FastAPI + SQLite — versioned /api/v1 reads + reasoning store (Render web service)
shared/     deployments.json + exported ABIs — single source of truth, read by all
docs/       ARCHITECTURE.md, STRATEGY.md, VERIFIER.md
web/        PARTNER-OWNED frontend — backend writes nothing here
```

## Quickstart (Phase 1 definition of done)

```bash
# contracts
cd contracts && forge build && forge test

# api (Python 3.11+)
cd api && pip install -r requirements.txt && uvicorn main:app --reload

# agent dry-run (read-only, sends no transactions)
cd agent && pip install -r requirements.txt && python -m dry_run
```

Configuration lives in `.env` (see `.env.example`). Secrets never enter the repo.
