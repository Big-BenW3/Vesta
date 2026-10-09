# Verifiable AI: the commitment flow

## Claim

Every rebalance is preceded by an onchain fingerprint of the exact reasoning
that produced it. Anyone can recompute the fingerprint from the published
reasoning and prove the agent did what it said — or prove it lied.

## Flow

```text
1. agent builds reasoning.json:
   { vault, nonce, timestamp, inputPrices, inputCompositions,
     computedMomentum, computedVolatility, targetWeights, explanation }
2. hash = keccak256(abi.encode(vault, nonce, timestamp, keccak256(reasoning.json)))
3. agent POSTs reasoning.json -> api (stored, immutable, keyed by (vault, nonce))
4. agent sends Registry.commit(hash, vault, nonce, timestamp)      [TX 1]
5. agent sends vault.rebalance(hash, nonce, timestamp, newWeights, ...)  [TX 2]
   vault checks registry.verify(...) + nonce == vault.nonce + freshness,
   executes swaps, stores newWeights, emits Rebalanced, nonce++.
```

## Fraud proof (worked)

Published JSON says `targetWeights: [3200, 2400, 1900, 1600, 900]`, nonce 42.
Recompute the hash locally -> equals the `StrategyCommitted` event for
(vault, 42). Then read the vault's stored `targetWeightsBps` and the
`Rebalanced(42, ...)` event: weights match the JSON -> honest ✅.
Any mismatch (vault moved to 40% NVDA while JSON said 32%) -> provable cheat ❌.
Editing even one digit of the JSON changes `keccak256(reasoning)` and fails
`verify` -> forged reasoning is self-exposing.

## Why the vault takes newWeights as an argument

The EVM cannot read the API, so the operator passes `newWeights` into
`rebalance()`. Trust does NOT come from that argument — it comes from the
after-the-fact check above: stored weights + events vs published JSON vs
onchain hash. The operator key can submit wrong weights, but cannot hide it.
Nonce binding (one nonce, one execution) stops one honest reasoning from
authorising ten dishonest trades.
