# Verification map — what is proven where

## Local (this machine, Python 3.14, no forge, no web3)

| Suite | Result |
|---|---|
| `pytest agent/tests api/tests` | **23/23 green** (strategy math, ethers-anchored hashing, store, routes, rate limits) |
| solc-js 0.8.24 + OZ 5 compile of `contracts/src` | **clean, 0 errors** |
| forge unit tests | **cannot run** — GitHub release downloads reset on this network |

## CI / Render (Python 3.11 image, forge present)

| Suite | Command |
|---|---|
| Contracts | `cd contracts && forge install && forge test` |
| Agent + API | `pip install -r agent/requirements.txt -r api/requirements.txt && pytest agent/tests api/tests` |
| E2E (testnet 10143) | `bash e2e/testnet_check.sh` |

## Known environment constraints (local)

* `web3`/`aiohttp`/`eth-account` have no Python 3.14 wheels here — agent/API code
  is written web3-optional (lazy imports, regex fallback) so everything except
  live submission runs locally. Submission paths execute on Render (3.11).
* Hash tests use `agent/tests/keccak_pure.py` (test-only) anchored to ethers v6
  golden vectors — production uses `eth_utils` on Render.
