# Vesta Backend Plan (Backend.md)

> Scope: everything except `web/` (partner-owned, stays empty from backend side).
> Chain: **Monad testnet only** (chain ID `10143`). Colosseum/Base rows in the PRD are out.
> Decisions locked: real Circle testnet USDC + mock stocks, Registry-only commitments,
> async-allocate deposits, fee option A (time-pro-rated skim), Render hosting, monorepo.

---

## 0. Locked constants

| Item | Value |
|---|---|
| Testnet chain ID | `10143` (`0x279f`), RPC `https://testnet-rpc.monad.xyz` |
| USDC (Circle testnet) | `0x534b2f3A21130d7a60830c2Df862319e593943A3` (faucet: `faucet.circle.com`) |
| Pyth (EVM proxy, same all chains) | `0x2880aB155794e7179c9eE2e38200202908C17B43` |
| Hermes (offchain, chain-agnostic) | `https://hermes.pyth.network` |
| Uniswap V3 | Testnet deployment addresses resolved at build time from Uniswap web app Testnet Mode; mainnet addresses (`0x204f…`, `0xfe31…`) are EMPTY on testnet (verified via `eth_getCode`). Never hardcode mainnet addresses |
| Fee | `managementFeeBps = 50` (0.5 %/yr), `SECONDS_PER_YEAR = 31_536_000` |
| Rebalance cadence / drift | every 5 min, `driftThresholdBps = 200` |
| Commit staleness bound | `maxAgeSec = 900` (15 min) |
| API base | `/api/v1` (versioned; `/api/v0` never ships) |

---

## 1. Monorepo layout (backend owns all but `web/`)

```text
vesta/
  contracts/                 # Foundry project (forge build/test/deploy)
    src/
      VaultFactory.sol
      EquityVault.sol
      StrategyCommitmentRegistry.sol
      mocks/MockStock.sol    # faucet-style ERC20: mNVDA, mMSFT, ...
    script/
      Deploy.s.sol           # deploys Registry, Factory, 2 themes; writes shared/deployments.json
      SeedPools.s.sol        # creates USDC/mSTOCK pools + seed liquidity on testnet Uniswap
    test/
      EquityVault.t.sol      # deposit/redeem/rebalance/fee/reverts
      Registry.t.sol         # commit/verify/replay
      Factory.t.sol          # CREATE2 + VaultCreated
  agent/                     # Python 3.11 rebalancer (Render background worker)
    data/market.py           # Hermes prices + onchain reads
    data/state.py            # vault composition reads
    strategy/momentum_vol.py # momentum + inverse-volatility weights
    strategy/drift.py        # target-vs-actual comparison
    exec/rebalance.py        # commit + rebalance tx submission
    dry_run.py               # read-only: prints targets, sends nothing
    requirements.txt
    Dockerfile
  api/                       # FastAPI + SQLite (Render web service)
    main.py                  # app factory, lifespan, middleware, router mounting
    routers/vault_routes.py
    routers/reasoning_routes.py
    routers/agent_routes.py
    models/schemas.py        # Pydantic v2 request/response models
    models/store.py          # SQLite access layer (parameterised queries only)
    core/config.py           # env loading, no secrets in code
    core/security.py         # API-key guard, rate limit, address normalisation
    static/verifier.html     # paste hash + JSON -> checkmark/cross
    requirements.txt
    Dockerfile
  shared/                    # single source of truth, written by deploy scripts
    deployments.json         # { chainId, usdc, pyth, uniRouter, uniFactory, registry, factory, vaults[] }
    abis/*.json              # exported from contracts; agent + web consume, never hand-copy
  docs/
    ARCHITECTURE.md
    STRATEGY.md              # formula + hand-worked example (judge can re-derive)
    VERIFIER.md              # commitment crypto flow + worked example
  web/                       # PARTNER-OWNED. Backend writes nothing here
  .env.example
```

Commenting rule (enforced in review): Solidity uses NatSpec (`@notice/@dev/@param`) on
every external/public function and state var; Python uses one-line docstrings on every
public function plus `# why:` comments on non-obvious math. No dead code, no commented-out code.

---

## 2. Onchain — contracts

### 2.1 `StrategyCommitmentRegistry.sol` (~60 LOC) — sole commitment store

```solidity
// @notice Sole store of AI strategy commitments. The vault never stores hashes itself.
struct Commitment { bytes32 hash; uint256 nonce; uint256 timestamp; bool exists; }
mapping(address vault => mapping(uint256 nonce => Commitment)) public commitments;
mapping(address vault => uint256) public latestNonce;

event StrategyCommitted(address indexed vault, bytes32 indexed hash, uint256 nonce, uint256 timestamp);

// @notice Records a commitment. Only the registered operator for `vault` may call.
// @dev Reverts on replay (nonce already used), future timestamps, or zero hash.
function commit(bytes32 hash, address vault, uint256 nonce, uint256 timestamp) external;

// @notice Pure read used by EquityVault.rebalance and the public verifier page.
function verify(bytes32 hash, address vault, uint256 nonce, uint256 timestamp) external view returns (bool);
function latestCommitment(address vault) external view returns (bytes32 hash, uint256 nonce, uint256 timestamp);
```

Custom errors (not strings): `NotOperator()`, `ReplayedNonce()`, `FutureTimestamp()`,
`ZeroHash()`, `UnknownCommitment()`. Hash formula (locked):
`keccak256(abi.encode(vault, nonce, timestamp, keccak256(reasoningJsonBytes)))`.

### 2.2 `EquityVault.sol` (~250 LOC) — ERC-4626, async-allocate, fee A

State (all documented with `@dev` units: BPS base 10_000, timestamps unix seconds):

```solidity
IERC20 public immutable USDC;             // Circle testnet USDC
IERC20[] public underlyings;              // mock stocks (mainnet: real xStocks, same interface)
uint256[] public targetWeightsBps;        // sums to 10_000
ISwapRouter public immutable uniRouter;   // testnet address from shared/deployments.json
IPyth public immutable pyth;               // 0x2880… (uniform both chains)
bytes32[] public pythPriceIds;            // Equity.US.* feed IDs, one per underlying
address public agentOperator;             // Render worker EOA (single key, V1)
uint256 public managementFeeBps;          // 50
address public feeRecipient;
uint256 public lastRebalanceTimestamp;    // init'd on first deposit (fee dt guard)
uint256 public nonce;                     // vault-owned; incremented only in rebalance()
uint256 public highWaterMark;             // informational (reserved for V2 performance fee)
```

Key functions:

* `deposit(uint256 assets, address receiver) -> shares` — pulls USDC, holds it as **idle USDC** (async-allocate: NO swap inside deposit; the agent allocates idle cash on the next rebalance). Mints `convertToShares(assets)`. Guards: `assets > 0`, first deposit sets `lastRebalanceTimestamp`.
* `redeem(uint256 shares, address receiver, address owner) -> assets` — burns shares, sells pro-rata slice of each holding to USDC via Uniswap (slippage-protected), sends USDC. Follows checks-effects-interactions + `nonReentrant`.
* `rebalance(bytes32 commitment, uint256 maxAgeSec, bytes[] priceUpdateData, uint256[] minAmountOut)` — `agentOperator` only. Steps: (1) fee skim first (fee A below), (2) `registry.verify()` gate, (3) nonce/timestamp/staleness reverts, (4) compute deltas target-vs-current, (5) swap idle USDC + overweight legs into underweight legs, (6) update `targetWeightsBps`, `lastRebalanceTimestamp = block.timestamp`, `nonce++`. Atomic: any leg reverting reverts all.
* `withdrawableUSDC() view -> uint256` — **display/estimate only** (reads last onchain-pushed Pyth prices; a view cannot pull). Never settlement truth; settlement truth is what Uniswap returned. Documented staleness bound `maxAgeSec`.

Fee A (locked): `feeShares = totalSupply * managementFeeBps * dt / (SECONDS_PER_YEAR * 10_000)` where `dt = block.timestamp - lastRebalanceTimestamp`, minted to `feeRecipient` at the top of `rebalance()`. Cap `dt` (e.g. 30 days) so a long-idle vault cannot mint absurd shares on the next tick.

Revert conditions (custom errors): `NotOperator()`, `UnknownCommitment()`, `NonceMismatch()`, `StaleCommitment()`, `WrongVault()`, `ZeroAmount()`, `FeeCapExceeded()`, `SlippageExceeded()`, plus OpenZeppelin `ReentrancyGuard` and `SafeERC20`.

### 2.3 `VaultFactory.sol` (~80 LOC)

`createVault(ThemeSpec)` with `ThemeSpec { name, symbol, underlying[], targetWeights[], pythPriceIds[], feeRecipient, managementFeeBps }` — validates arrays match, weights sum to 10_000, `CREATE2`-deploys `EquityVault`, emits `VaultCreated(vault, creator, themeId)`. Reverts: `LengthMismatch()`, `BadWeights()`, `ZeroAddress()`.

### 2.4 Mocks + themes

`MockStock.sol`: ERC-20, 6 decimals, open `mint()` (testnet only, labelled `DEMO`). Deploy 10: AI Mega Cap `mNVDA/mMSFT/mGOOGL/mMETA/mAMD` @ `[3000,2500,2000,1500,1000]`; Energy `mTSLA/mENPH/mFSLR/mNEE/mBP` @ `[3500,1500,1500,2000,1500]`. Each mock maps 1:1 to a real Pyth `Equity.US.*` feed for pricing/strategy.

---

## 3. Offchain — AI rebalancer (`agent/`)

Loop (`apscheduler`, 5 min) per vault:

1. `data/market.py`: fetch 30d daily closes per underlying from Hermes (`Equity.US.*` IDs; 24/7 `Equity.Index.*` fallback when market closed), fetch vault composition + idle USDC + `nonce` via RPC.
2. `strategy/momentum_vol.py`: `mom = px_now/px_30d - 1`; `vol = stdev(daily_returns)`; `raw = max(0,mom)/vol`; normalise to BPS (`sum == 10_000`, largest-remainder on dust).
3. `strategy/drift.py`: `max|target - actual| >= 200 BPS`? else log `no rebalance needed` and exit (no tx, no commit — commitments are only written when a trade follows).
4. Build `reasoning.json { vault, nonce, timestamp, inputPrices, inputCompositions, computedMomentum, computedVolatility, targetWeights, explanation }`.
5. `exec/rebalance.py`: `POST /api/v1/reasoning` (store JSON) → `Registry.commit(hash,…)` → wait receipt → `vault.rebalance(…)` with `minAmountOut` from Quoter + `priceUpdateData` for Pyth pull. One EOA (`AGENT_OPERATOR_KEY` env), sequential nonces, retry with replacement-by-fee once then alert.
6. `dry_run.py`: steps 1–4 only, prints table, exit 0. CI asserts dry-run weights equal the hand-worked `STRATEGY.md` example.

Input safety: all RPC/Hermes reads have timeouts (10 s), 3x retry with backoff, and clamps (reject negative/zero prices, reject weight vectors not summing to 10_000). Never submit a tx on unvalidated inputs.

---

## 4. Offchain — Vesta API (`api/`, FastAPI, versioned `/api/v1`)

### 4.1 Routes (all under `/api/v1`; trailing-slash-insensitive)

```text
GET  /api/v1/vaults                        # list themes: address, name, symbol, underlyings, weights, aumEstimate, lastRebalance
GET  /api/v1/vaults/{address}              # full vault state (composition actual vs target, nonce, fees accrued)
GET  /api/v1/reasoning/{vault}/{nonce}     # stored reasoning JSON for one commitment
POST /api/v1/reasoning                     # AGENT ONLY (API key): store one reasoning JSON, idempotent on (vault, nonce)
GET  /api/v1/agent/status                  # last rebalance, next scheduled, worker health, chain id
GET  /healthz                              # unauthenticated liveness (for Render)
GET  /verifier                             # static verifier.html
```

Pydantic v2 models for EVERYTHING — path params included (`VaultAddress` = 20-byte hex, checksum-normalised; `Nonce` = non-negative int). Query pagination: `limit` default 20, max 100, `offset >= 0`. Unknown fields rejected (`extra = "forbid"`). All DB access via parameterised queries; no f-string SQL, no `eval`, no pickle.

### 4.2 Auth & safety (routes are safe by construction)

* Reads (`GET`) are public but **rate-limited** (60 req/min/IP, slow-path 429 with `Retry-After`) and **read-only** (SQLite connection opened read-only for GET handlers).
* `POST /reasoning` requires `X-API-Key` (Render env, `secrets.compare_digest`, rotated post-hackathon). Wrong/missing key → `401`. Key is agent-only; frontend never holds it.
* Body limits: JSON ≤ 64 KB, `nonce` must equal `vault.nonce()` onchain at write time (checked via RPC before insert; mismatch → `409 Conflict`), `timestamp` within ±5 min of server time (else `422`), `targetWeights` must sum to 10_000 (else `422`).
* Idempotency: `(vault, nonce)` unique; re-POST of identical bytes → `200` same record; different bytes same key → `409` (tamper evidence, never overwrite).
* SQLite is a **rebuildable read cache** (themes, reasoning blobs, rebalance log), NOT the source of truth — onchain events are. Schema:

```sql
vaults(address PK, name, symbol, underlyings JSON, weights JSON, created_at);
reasoning(vault, nonce, timestamp, json TEXT, tx_hash, PRIMARY KEY (vault, nonce));
rebalances(id INTEGER PK, vault, nonce, tx_hash, created_at);
```

* CORS: allowlist the Vercel frontend origin only; `allow_credentials = False`; security headers middleware (`X-Content-Type-Options`, `frame-ancestors 'none'` on API).
* Logging: structured logs with request IDs; 5xx logs full trace server-side, returns generic message to client (no stack leaks).

### 4.3 Error envelope (uniform, every error)

```json
{ "error": { "code": "VAULT_NOT_FOUND", "message": "No vault at 0x…", "details": {} } }
```

| HTTP | `code` | When |
|---|---|---|
| 400 | `INVALID_ADDRESS` | path/query address fails checksum/hex validation |
| 401 | `UNAUTHORIZED` | missing/bad `X-API-Key` on POST |
| 404 | `VAULT_NOT_FOUND` | address well-formed but unknown vault |
| 404 | `REASONING_NOT_FOUND` | no JSON for (vault, nonce) |
| 409 | `NONCE_CONFLICT` | POST nonce ≠ onchain nonce, or bytes differ for same key |
| 422 | `SCHEMA_INVALID` | Pydantic fail: weights ≠ 10_000, oversize body, bad timestamp |
| 429 | `RATE_LIMITED` | over per-IP budget (with `Retry-After`) |
| 502 | `UPSTREAM_RPC` | Monad RPC/Hermes unreachable (agent + status routes) |
| 500 | `INTERNAL` | anything else; generic message only |

Happy path returns `200` with plain JSON objects (RORO: Pydantic in, Pydantic out). Early-return guard clauses; happy path last.

### 4.4 Verifier page

`GET /verifier` serves static HTML+JS: paste `(vault, nonce)` or full JSON → fetches onchain event + stored JSON → recomputes `keccak256` client-side → ✅/❌. Forged JSON deterministically shows ❌ (demo-proof of verifiable AI).

---

## 5. Testing (backend gates)

* `forge test`: deposit mints correct shares; redeem round-trips to USDC minus fees; rebalance executes only with valid Registry commitment; all 8 revert conditions; fee-A math vs hand-calc (dt=300 → ~0.048 shares per 1M supply); CREATE2 determinism; mock-stock decimals.
* Agent `pytest`: strategy unit tests equal `STRATEGY.md` worked example; drift threshold edges (199 vs 200 BPS); invalid-input clamps.
* API `httpx` tests: envelope codes table above (401/404/409/422/429), idempotent re-POST, oversize/extra-field rejection, checksum normalisation.
* E2E (testnet): deploy → seed pools → deposit 1000 USDC → force rebalance → verifier ✅ → redeem. Scripted, runnable in CI against 10143.

---

## 6. Deploy & ops (Render, testnet)

* `api` → Render Web Service (Starter $7/mo keeps alive; persistent disk for SQLite; env: `RPC_URL`, `REGISTRY_ADDR`, `AGENT_API_KEY`, `CORS_ORIGINS`).
* `agent` → Render Background Worker or Cron (5-min schedule; env adds `AGENT_OPERATOR_KEY`, `HERMES_URL`).
* Secrets only in Render env, never in repo (`.env.example` documents keys without values).
* Definition of done per backend phase: P1 skeleton deploys clean in <5 min from clone; P2 round-trip test greens; P3 `dry_run` matches hand-calc with no tx; P4 verifier flips ✅→❌ on forged JSON.

---

## 7. What backend owes the frontend (frozen interface)

`shared/deployments.json` + `shared/abis/*` + the five `GET /api/v1/*` shapes above. If a route or field must change, bump to `/api/v2` and keep serving `v1` through demo week — never break the partner silently.
