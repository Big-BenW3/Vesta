# Vesta Architecture (testnet)

Monad testnet (`10143`) only. Three trust zones: onchain vaults, offchain agent,
read-cache API. The frontend (partner-owned `web/`) never touches private keys.

```text
                    +------------------ Render ------------------+
                    |  agent (worker)        api (web service)   |
                    |  5-min loop            /api/v1 + SQLite    |
                    +----+-------------+------------+-----------+
                         |             |            |
                    commit|        rebalance   POST reasoning    RPC reads
                         v             v            |            |
+---------------------------------------------------------------- Monad 10143 --+
|  StrategyCommitmentRegistry <--- EquityVault x2 (vAI-MEGA, vENERGY)           |
|        ^  sole commitment store     |  holds USDC + mSTOCK, ERC-4626         |
|        |                            v                                       |
|  VaultFactory (CREATE2, theme registry)  Uniswap V3 pools (USDC/mSTOCK)      |
|  Pyth 0x2880… (prices, pull)   Circle USDC 0x534b… (deposit asset)            |
+-----------------------------------------------------------------------------+
Hermes https://hermes.pyth.network (offchain price history + updateData)
```

## Money flow

1. User `approve` + `deposit(USDC)` -> vault holds **idle USDC**, mints shares 1:1
   on first deposit (async-allocate: no swap inside deposit).
2. Every 5 min the agent compares target vs actual weights. Drift >= 200 BPS:
   reasoning JSON -> `POST /api/v1/reasoning` -> `Registry.commit` ->
   `vault.rebalance` (fee skim, then sells overweight, buys underweight).
3. User `redeem` burns shares; vault sells a pro-rata slice to USDC and pays out.

## Trust model (V1, honest)

* Operator EOA is a single Render-held key: it can rebalance and skim the 0.5%
  fee, but cannot steal principal (no function moves assets to itself; all swaps
  settle into the vault). Key rotation = redeploy (documented V2 item: KMS/multisig).
* Commitments are fraud-PROVABLE, not fraud-PROOF: anyone recomputing the hash
  from published reasoning catches a lying operator after the fact (see VERIFIER.md).
* Pyth staleness is bounded by `priceMaxAge` on swaps and `maxAgeSec` (900s) on
  commitments. `withdrawableUSDC()` is an estimate, never settlement truth.

## What lives where

* Onchain (truth): balances, weights, nonces, commitments, fees, themes.
* SQLite (cache): theme metadata, reasoning JSON blobs, rebalance log.
  Rebuildable from `VaultCreated` + `StrategyCommitted` + `Rebalanced` events.
* `shared/deployments.json` + `shared/abis/`: the only address/ABI source for
  agent, API, and frontend. Testnet->mainnet is a config swap, not a rewrite.
