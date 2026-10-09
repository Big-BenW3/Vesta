# Vesta V1 Strategy: momentum + inverse-volatility

Deterministic, documented, re-derivable. No ML, no black box — a judge with the
same price inputs must get the same weights.

## Formula (per theme member `i`)

```text
mom_i = price_now / price_30d_ago - 1
vol_i = stdev(daily_returns_i, 30d)        # sample stdev, zero-vol floors to 1e-9
raw_i = max(0, mom_i) / vol_i             # losers get exactly zero
w_i   = raw_i / sum(raw_j) -> BPS         # largest-remainder on dust so sum == 10_000
```

All-negative momentum is degenerate (every `raw_i = 0`): fallback is equal-weight
and the reasoning JSON records `"fallback": "equal-weight"`. Never divide by zero,
never ship weights summing to anything but 10_000.

## Worked example (CI asserts this exact output)

Prices: NVDA 120 -> 134.40 (+12%), MSFT 400 -> 424 (+6%), AMD 150 -> 145.50 (-3%).
Daily-return stdevs: NVDA 0.020, MSFT 0.015, AMD 0.025.

```text
raw_NVDA = 0.12 / 0.020 = 6.0
raw_MSFT = 0.06 / 0.015 = 4.0
raw_AMD  = max(0, -0.03) / 0.025 = 0.0
sum = 10.0 -> NVDA 6000 BPS, MSFT 4000 BPS, AMD 0 BPS
```

Drift check vs current [3000, 2500, 1000...]: max deviation 3000 BPS >= 200 BPS
threshold -> rebalance fires. A 199 BPS deviation would log `no rebalance needed`
and exit without writing any commitment (commitments only ever precede trades).

## Data

30 daily closes per underlying from Hermes `Equity.US.*` feeds (24/7
`Equity.Index.*` fallback when the market is shut). Each mock stock maps 1:1 to
its real feed: `mNVDA` <- `Equity.US.NVDA/USD`, etc. (full map in Deploy.s.sol).
