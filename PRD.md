# Vesta — Verifiable AI-Managed Tokenized Equity Vaults

> **Working name:** Vesta (placeholder; final brand TBD before Colosseum submission)
> **Version:** V1 — Hackathon-grade MVP for Monad Metropolis (deadline Oct 13, 2026) and Colosseum (deadline Nov 2, 2026)
> **Date:** October 3, 2026
> **Author:** Product (Mavis session for the user)

---

## 0. How to read this document

This is the single source of truth for Vesta V1. Every decision is locked. Scope is frozen to the six features below. Nothing outside this scope ships for the hackathons. After both hackathons, V2 planning begins separately.

The document is structured so a developer, a judge, and a non-technical reader can each find what they need:

- Sections 1, 2, 6, 7, 8 are written for a **mixed audience** (technical terms are always defined inline).
- Sections 3, 4, 5 are written for **engineers** building it.
- Section 9 (Build Plan) is written for **the team** executing it.

---

## 1. Product Overview

### 1.1 The problem, in plain English

Today, a person can buy a tokenized share of Nvidia (xStocks on Monad). It sits in their wallet and earns 0%. In traditional finance, every Nvidia holder can sell a "covered call" against their holding and earn 1–3% per month in extra income. That primitive does not exist onchain for tokenized stocks. Worse, the few "AI-managed" crypto products that do exist (Bankr, Bluwhale, Virtuals-style agents) are **black boxes** — you cannot verify what the AI is actually doing with your money.

The market is therefore in a strange state: $1.5B in tokenized US stocks live onchain, 422% YoY growth, but **zero yield, zero transparency on the AI agents that move them**.

### 1.2 The solution, in plain English

Vesta is a set of **themed tokenized-equity vaults** on Monad. A user deposits USDC, and the vault automatically buys a curated basket of tokenized US stocks (e.g. "AI Mega Cap": NVDA, MSFT, GOOGL, META, AMD). An off-chain **AI agent** watches market data and rebalances the basket. Before every rebalance, the agent **commits a cryptographic fingerprint of its reasoning on-chain**, so anyone can verify the AI did what it said it would do. The user gets a non-custodial vault share representing their slice of the basket, redeemable any time for the underlying assets.

### 1.3 The product, in one sentence

> **Vesta = a non-custodial tokenized-stock basket vault on Monad, actively managed by an AI agent whose strategy is publicly committed on-chain before every move.**

### 1.4 Why it wins

- **Originality:** No product combines non-custodial vault + active AI rebalancing + verifiable strategy commitment. Cesto (Colosseum winner) does static baskets, no AI. Bankr/Bluwhale are AI agents but custodial and black-box. The "verifiable AI" wedge is unoccupied.
- **Buildable in 10 days:** Every primitive (xStocks ERC-20, Pyth, Uniswap V3, USDC, Chainlink) is already live on Monad mainnet. No new infrastructure needed.
- **Real demand:** 422% YoY growth in tokenized stocks. 97% of tokenized RWAs sit idle. Vesta turns idle tokenized stocks into productive assets with transparent AI management.
- **Two-hackathon fit:** Monad (Onchain Finance & Trading track) and Colosseum (open to all chains; judged on Novelty + Business plan).

---

## 2. Glossary — every term, technical and plain English

### 2.1 Asset & chain terms

**Monad** (technical)
A high-performance Layer 1 blockchain (i.e. an independent base network, not built on top of Ethereum but compatible with it). It runs the same smart-contract language as Ethereum (Solidity), but processes transactions in parallel (i.e. many transactions at the same time, not one-by-one). It targets 10,000 transactions per second with ~300ms blocks and ~600ms finality. "Finality" means the moment a transaction is permanent and cannot be reversed.

**Monad** (plain English)
A very fast, cheap version of Ethereum that any Ethereum app can run on without rewriting code. Think "Ethereum with a turbo engine."

**EVM / EVM-compatible** (technical)
EVM = Ethereum Virtual Machine, the runtime that executes smart contracts on Ethereum. "EVM-compatible" means a chain can run the same smart contracts (written in Solidity) without modification.

**EVM** (plain English)
"The language Ethereum apps speak." Monad speaks the same language, so any Ethereum tool or app works on Monad.

**RWA (Real World Asset)** (technical)
A token issued on a blockchain that represents a claim on an off-chain, traditionally non-blockchain asset (real estate, equities, bonds, commodities, etc.). The token is the onchain representation; the underlying asset is held by a regulated custodian.

**RWA** (plain English)
A digital token that stands in for a real thing in the physical world — like a share of a house, or a US Treasury bond.

**Tokenized stock** (technical)
An ERC-20 or SPL token on a blockchain that represents 1 share (or fraction thereof) of a publicly traded equity. The token is issued by a regulated entity that holds the underlying share in custody. Each token is fully backed 1:1 by a real share.

**Tokenized stock** (plain English)
A crypto token that acts exactly like a real share of Apple or Nvidia. The token is worth the same as the real share because the issuer actually bought the real share and is holding it for you.

**xStocks** (technical)
The tokenized-stock product family issued by Backed Finance (a Swiss-regulated company). xStocks are ERC-20 tokens on multiple EVM chains including Ethereum, Arbitrum, Base, and Monad. They are 1:1 backed by the underlying equity held by a licensed custodian.

**xStocks** (plain English)
A real product (by a regulated company) that lets you hold tokenized Apple, Nvidia, Tesla, etc. on EVM chains. On Monad, "xNVDA" is a token that behaves like one share of Nvidia.

**USDC** (technical)
A fully collateralized stablecoin pegged 1:1 to the US dollar, issued by Circle. It is an ERC-20 token available on Monad mainnet. Used as the deposit asset for Vesta vaults.

**USDC** (plain English)
A digital dollar. One USDC = $1. Always redeemable for a real dollar.

### 2.2 DeFi primitives

**Vault** (technical)
A smart contract that accepts deposits, holds assets, and issues share tokens representing a pro-rata claim on those assets. The most common standard is ERC-4626.

**Vault** (plain English)
A digital piggy bank. You put money in, you get a token back that represents your share. When you redeem, you get your share of whatever is inside.

**ERC-4626** (technical)
An Ethereum token standard for tokenized vaults. It defines a standard interface so any vault is composable (i.e. it can plug into any other DeFi app without custom code) with the rest of DeFi (DEXs, lending protocols, aggregators, etc.). A vault implementing ERC-4626 has `deposit()`, `withdraw()`, `redeem()`, `totalAssets()`, `convertToShares()` functions.

**ERC-4626** (plain English)
A shared "shape" that all vaults must follow. Because every vault uses the same shape, any other app knows how to read it. It's the difference between every piggy bank having the same size opening versus every piggy bank being a different size — ERC-4626 makes them all the same.

**Uniswap V3** (technical)
A decentralized exchange (DEX) on Ethereum and EVM chains. It uses a "concentrated liquidity" model where liquidity providers (people who put up the tokens the exchange uses) can specify price ranges for their liquidity. Traders swap against this liquidity.

**Uniswap V3** (plain English)
An automatic currency exchange that runs on the blockchain. You can swap USDC for xNVDA without a human in the middle.

**AMM (Automated Market Maker)** (technical)
A type of DEX where the exchange rate is set by a mathematical formula (in Uniswap V3's case, by the amount of each token in a liquidity pool) rather than by an order book. Trades happen against the pool.

**AMM** (plain English)
A robot exchanger. You put in token A, it gives you token B based on a formula. No human trader, no order book.

**Liquidity pool** (technical)
A smart contract holding two (or more) tokens that traders swap against. Liquidity providers deposit tokens into the pool and earn a share of the trading fees.

**Liquidity pool** (plain English)
A bucket of two tokens that traders swap between. People who fill the bucket earn fees.

**Swap** (technical)
A single transaction that exchanges one token for another via a liquidity pool or aggregator. On Vesta, "swap" means exchanging USDC for xStocks (or vice versa) via Uniswap on Monad.

**Swap** (plain English)
A trade. USDC in, xNVDA out. One transaction.

### 2.3 Oracle & data

**Pyth Network** (technical)
A first-party oracle network that streams low-latency price data (crypto, equities, FX, commodities) from major trading firms and exchanges. On Monad, Pyth is a "pull oracle" — the user (or a keeper bot) pulls a fresh price into the same transaction that uses it. Prices refresh every ~400ms.

**Pyth Network** (plain English)
A live price feed for the blockchain. The AI agent and the vault use it to know what xNVDA is worth right now.

**Oracle** (technical)
A service that brings off-chain data (like real-world stock prices) onto the blockchain in a way the smart contract can trust. The data is signed cryptographically and verified on-chain.

**Oracle** (plain English)
A messenger that takes real-world information (like a stock price) and delivers it to a smart contract, with proof it hasn't been tampered with.

**Pull oracle** (technical)
An oracle design where the consumer (the smart contract or its relayer) actively fetches a fresh price update when needed, rather than the oracle pushing updates on a schedule. Cheaper and more flexible; ideal for high-frequency DeFi on Monad.

**Pull oracle** (plain English)
The price feed waits to be asked. The vault asks "what's the price right now?" right before it does a swap, and gets the freshest answer.

### 2.4 AI & strategy

**AI agent** (technical)
An autonomous software service that reads inputs (market data, on-chain state, etc.), applies a reasoning model (rules-based, statistical, or LLM-driven), and produces outputs (target portfolio weights, rebalance transactions). In Vesta's V1, the agent is a Python service that runs off-chain, signs transactions with a custodial key, and submits them to the on-chain vault.

**AI agent** (plain English)
A small program that watches the market and decides when to buy or sell. It runs on a normal server (off-chain), not on Monad itself, because AI models are too big/expensive to run inside a smart contract.

**Strategy** (technical)
A deterministic (always gives the same answer for the same inputs) function from inputs (current prices, current weights, target theme) to outputs (target weights for each asset). Vesta's V1 strategy is "momentum + volatility targeting" — explained fully in Section 3.4.

**Strategy** (plain English)
The rules the AI follows to decide what to buy. Like a recipe: given these ingredients (market data), produce this dish (target portfolio).

**Strategy commitment** (technical)
A cryptographic commitment to the agent's reasoning: the agent computes `keccak256(strategyHash ‖ timestamp ‖ nonce ‖ vaultAddress)`, signs it with its operator key, and submits the hash to the `StrategyCommitmentRegistry` smart contract *before* the rebalance transaction executes. The full reasoning (in JSON) is published off-chain (e.g. signed message in IPFS or just on a public endpoint). Anyone can recompute the hash and verify the on-chain commitment matches the off-chain reasoning.

**Strategy commitment** (plain English)
A "fingerprint" the AI writes on the blockchain before it makes a trade. The AI also publishes its full reasoning somewhere public. Anyone can check that the fingerprint matches the reasoning. If they don't match, the AI cheated.

**Verifiable AI** (technical + plain English combined)
A pattern where an AI agent's actions are cryptographically tied to a publicly disclosed reasoning, such that the agent cannot claim it "did something different" after the fact. It's the equivalent of "show your work" but mathematically enforced.

### 2.5 Business terms

**TVL (Total Value Locked)** (technical)
The total USD value of all assets deposited into a protocol's smart contracts. A standard health metric for DeFi.

**TVL** (plain English)
How much money is sitting in the product. Higher TVL = more trust.

**AUM (Assets Under Management)** (technical)
The total value of assets a fund or protocol manages on behalf of users. For Vesta, AUM = the sum of `totalAssets()` across all vaults. AUM is the basis for management-fee revenue.

**AUM** (plain English)
Same as TVL for our purposes. How much we manage.

**Management fee** (technical)
A recurring fee, usually expressed as an annualized percentage of AUM, charged by a fund for active management. In Vesta, this is implemented by minting new vault shares to a fee-recipient address each period (the "fee skim" pattern).

**Management fee** (plain English)
A small annual fee (e.g. 0.5%) charged on whatever is in the vault. Like what a hedge fund charges, but automatic and transparent.

**Thematic basket / theme** (technical)
A named collection of tokenized equities grouped by an investment thesis (e.g. "AI Mega Cap" = NVDA + MSFT + GOOGL + META + AMD). Each theme is its own deployed vault contract.

**Theme** (plain English)
A "kit" of stocks the AI manages together. "AI Mega Cap" is a kit of the biggest AI companies. Each kit is its own vault you can put money in.

---

## 3. V1 Features (the six)

### 3.1 F1 — VaultFactory

**What it is (plain English):** A smart contract that deploys a new themed vault in one transaction. Think of it as a vending machine: pick a theme, press a button, get a new vault.

**What it is (technical):** A `VaultFactory` contract that takes a `ThemeSpec` struct (name, symbol, list of underlying tokenized-stock addresses, target weights, fee recipient) and `CREATE2`-deploys a new `EquityVault` instance. `CREATE2` is a deterministic deployment method that lets the same factory produce the same vault address from the same inputs across chains.

**Inputs:**
- `name` (string) — e.g. "AI Mega Cap"
- `symbol` (string) — e.g. "vAI-MEGA"
- `underlying[]` (address[]) — e.g. `[xNVDA, xMSFT, xGOOGL, xMETA, xAMD]`
- `targetWeights[]` (uint256[] in BPS) — e.g. `[3000, 2500, 2000, 1500, 1000]` (sums to 10000 = 100%)
- `feeRecipient` (address)
- `managementFeeBps` (uint256) — e.g. `50` (0.5% annualized)

**Outputs:** Emits `VaultCreated(address vault, address creator, bytes32 themeId)`.

**Why it matters:** New themes can be launched permissionlessly. The factory is the on-chain registry of every Vesta theme ever created.

**Why now:** Enables the demo ("browse themes, deposit") and sets up future user-created themes for V2 without a contract upgrade.

### 3.2 F2 — EquityVault (ERC-4626)

**What it is (plain English):** The actual piggy bank. Users deposit USDC, the vault swaps the USDC into the themed basket of tokenized stocks, and mints them a vault share (e.g. vAI-MEGA) representing their slice. They can redeem the share any time for the underlying assets (sold back to USDC).

**What it is (technical):** An ERC-4626-compliant vault that:
1. On `deposit(assets, receiver)`: swaps `assets` USDC into the target basket of xStocks via Uniswap V3 on Monad (using a configured router, swapping incrementally to minimize slippage). Mints vault shares to `receiver` based on `convertToShares(assets)`.
2. On `redeem(shares, receiver, owner)`: burns `shares`, swaps the corresponding pro-rata slice of each underlying xStock back to USDC via Uniswap, sends USDC to `receiver`.
3. Implements a fee skim: each `rebalance()`, a configurable management fee in BPS is taken from new yield (if any) and minted as vault shares to the `feeRecipient`.
4. Holds all xStock positions in its own balance. No external custody.

**State variables:**
- `IERC20 public immutable USDC`
- `IERC20[] public underlyings`
- `uint256[] public targetWeightsBps`
- `ISwapRouter public immutable uniRouter`
- `IPyth public immutable pyth`
- `bytes32[] public pythPriceIds`
- `address public agentOperator` (singleton address authorized to call `rebalance()`)
- `uint256 public managementFeeBps`
- `address public feeRecipient`
- `mapping(bytes32 => bool) public commitments;` (commitment hash → exists)
- `uint256 public lastRebalanceTimestamp;`
- `uint256 public nonce;`

**Key functions:**
- `deposit(uint256 assets, address receiver) → uint256 shares`
- `redeem(uint256 shares, address receiver, address owner) → uint256 assets`
- `rebalance(bytes32 commitment, uint256 maxAgeSec)` — called by the agent. Reverts if `commitment` is not in the registry. Executes the swap path.
- `commitStrategy(bytes32 commitmentHash)` — called by the agent's signer. Records the hash.
- `withdrawableUSDC() view → uint256` — current USDC value of all holdings (uses Pyth prices).
- Standard ERC-4626 accessors.

**Why it matters:** This is the user's touchpoint. Standard ERC-4626 means it composes with the rest of Monad DeFi (Aave, Pendle, etc.) for free.

**Why now:** The contract surface is small (~250 LOC) and the interface is universal, so it is the most testable and demoable piece.

### 3.3 F3 — AI Rebalancer (off-chain Python service)

**What it is (plain English):** A small program running on a normal server (not on Monad). Every N minutes, it looks at the vault's current composition, reads live stock prices, and decides whether to rebalance the basket. If yes, it writes a "fingerprint" on Monad describing its reasoning, then submits a rebalance transaction.

**What it is (technical):** A Python service (`agent/rebalancer.py`) with three modules:
1. **Data layer (`data/market.py`)** — pulls Pyth prices via Hermes (Pyth's HTTP API), pulls current vault state via JSON-RPC.
2. **Strategy layer (`strategy/momentum_vol.py`)** — implements the V1 strategy: a combination of 30-day momentum (recent performance relative to other theme members) and inverse-volatility weighting (stocks with lower recent volatility get higher weight). Output: `targetWeightsBps[]`.
3. **Execution layer (`exec/rebalance.py`)** — signs and submits three transactions in order:
   a. `commitStrategy(hash)` on `StrategyCommitmentRegistry`
   b. Publishes the off-chain reasoning JSON to IPFS or signed-message endpoint
   c. `rebalance(commitmentHash, maxAgeSec)` on the vault

**The V1 strategy (momentum + inverse volatility):**

For each stock in the theme:
- `mom_i = (price_i_now / price_i_30d_ago) - 1`
- `vol_i = stdev(daily_returns_i, 30d)`
- `raw_i = max(0, mom_i) / vol_i`
- `weight_i = raw_i / sum(raw_j) `, then converted to BPS

This is documented in `/agent/STRATEGY.md` with a worked example. Judges can read the rule and re-derive the weights from the same inputs.

**Operator key:** The rebalancer holds a single EOA (externally owned account) private key with the `AGENT_OPERATOR_ROLE`. The role is a single address (not a multisig) for V1, to maximize demo simplicity. The role is renouncable post-hackathon for V2.

**Cadence:** Checks every 5 minutes; rebalances only if any target weight has drifted by more than `driftThresholdBps` (default = 200 BPS = 2% from target).

**Why it matters:** This is the "AI" in Vesta. It is real, deterministic, and explainable — not a fake LLM wrapper.

**Why now:** A real strategy (not a buzzword) is the only way to defend the "verifiable AI" thesis against a skeptical judge.

### 3.4 F4 — StrategyCommitmentRegistry

**What it is (plain English):** A small smart contract that stores the AI's "fingerprints." Before every rebalance, the AI writes a hash. After the rebalance, anyone can read the hash and compare it to the AI's published reasoning. If the AI said "I will rebalance NVDA from 30% to 25%" but actually moved it to 40%, the hashes won't match, and the cheat is provable.

**What it is (technical):** A standalone `StrategyCommitmentRegistry` contract:
- `commit(bytes32 hash, address vault, uint256 nonce, uint256 timestamp)` — called by the agent. Stores the commitment and emits `StrategyCommitted(vault, hash, nonce, timestamp)`.
- `verify(bytes32 hash, address vault, uint256 nonce, uint256 timestamp) view → bool`
- `latestCommitment(address vault) view → (bytes32 hash, uint256 nonce, uint256 timestamp)`

The hash is computed off-chain as:
```
hash = keccak256(
  abi.encode(
    vault,
    nonce,
    timestamp,
    keccak256(reasoningJsonBytes)  // the full reasoning, off-chain published
  )
)
```

The off-chain reasoning is published as a signed JSON file via:
- The Vesta API endpoint `/api/reasoning/{nonce}.json`
- Optionally, IPFS for permanence

Anyone (user, judge, auditor) can:
1. Read the on-chain `commit` event.
2. Fetch the off-chain JSON from the API.
3. Recompute the hash.
4. Compare.

**Why it matters:** This is the originality wedge. It is the difference between "trust me, the AI did the right thing" and "the AI's actions are provable." This is what makes Vesta "verifiable AI" and not "yet another black-box bot."

**Why now:** No protocol does this. Filing this pattern as a precedent is itself a competitive moat.

### 3.5 F5 — Frontend (web)

**What it is (plain English):** A website where users browse themes, deposit USDC, and — most importantly — see what the AI is thinking in real time. The "AI Reasoning Panel" is the demo's hero.

**What it is (technical):** A Next.js 14 app (App Router), deployed on Vercel. Wallet connection via RainbowKit + wagmi v2. Three primary screens (see Section 5 for full screen list). State is read directly from the contracts; the rebalancer state is read from the Vesta API.

**Pages:**
- `/` — Vaults grid (Section 5.1)
- `/vault/[address]` — Vault detail (Section 5.2)
- `/about` — Pitch and explainer (Section 5.3)

**Why it matters:** The reasoning panel is the click that makes a judge go "oh, that's different."

**Why now:** Without it, Vesta is just a vault. With it, Vesta is a story.

### 3.6 F6 — Two pre-bundled themes

**What it is (plain English):** Two real, ready-to-use themes that the demo shows. Not placeholders — actual curated baskets with documented investment theses.

**What it is (technical):** Two pre-deployed vaults via `VaultFactory`:

**Theme A: "AI Mega Cap"** (`vAI-MEGA`)
- Underlyings: xNVDA, xMSFT, xGOOGL, xMETA, xAMD
- Initial target weights: `[3000, 2500, 2000, 1500, 1000]`
- Thesis: "The five largest US-listed companies whose primary business is or enables AI infrastructure and applications."

**Theme B: "Energy Transition"** (`vENERGY`)
- Underlyings: xTSLA, xENPH (Enphase), xFSLR (First Solar), xNEE (NextEra Energy), xBP (BP)
- Initial target weights: `[3500, 1500, 1500, 2000, 1500]`
- Thesis: "A basket spanning EV, solar, utilities, and traditional energy — sized to ride the multi-decade transition away from fossil fuels."

**Note for the demo:** If xStocks on Monad mainnet is not yet live at hackathon time, both themes are deployed against **mock ERC-20 tokenized stocks with the same interface** (symbol `mNVDA`, `mMSFT`, etc.), clearly labeled "DEMO ASSETS" in the UI. Architecture is identical; only the underlying token contract changes. This is standard hackathon practice and accepted by judges.

**Why it matters:** Pre-bundled themes make the demo 30 seconds long. User-customized themes (V2) are not in scope.

**Why now:** Without them, the demo requires a setup step the judge doesn't want to do.

---

## 4. Architecture

### 4.1 Layer diagram (logical)

```
┌─────────────────────────────────────────────────────────────┐
│  Frontend (Next.js, Vercel)                                  │
│  - Vaults grid, vault detail, about                          │
│  - Wallet: RainbowKit + wagmi v2                             │
│  - Reads: Monad RPC, Vesta API                               │
└──────────────────┬──────────────────────────────────────────┘
                   │ RPC reads / writes
┌──────────────────▼──────────────────────────────────────────┐
│  Monad Mainnet (EVM)                                         │
│                                                              │
│  ┌────────────────────────┐  ┌────────────────────────┐     │
│  │ VaultFactory           │  │ StrategyCommitment-    │     │
│  │ (deploys new vaults)   │  │ Registry               │     │
│  └──────────┬─────────────┘  └──────────▲──────────────┘     │
│             │ CREATE2                    │                  │
│  ┌──────────▼─────────────┐              │                  │
│  │ EquityVault (×N)       │──────────────┘                  │
│  │ - ERC-4626             │                                 │
│  │ - holds xStocks / USDC │                                 │
│  │ - rebalance()          │                                 │
│  └─────▲──────▲───────────┘                                 │
│        │      │ swaps                                       │
│  ┌─────┴──────┴───────────────────────────────────────┐    │
│  │  Uniswap V3 (Monad) — USDC ↔ xStocks pools          │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Pyth Oracle (Monad) — USDC/USD + equity prices     │    │
│  └────────────────────────────────────────────────────┘    │
│  ┌────────────────────────────────────────────────────┐    │
│  │  USDC (Circle) — deposit / payout asset              │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Off-chain (Vesta backend)                                   │
│                                                              │
│  ┌────────────────────┐  ┌────────────────────────────┐     │
│  │ AI Rebalancer      │  │ Vesta API (FastAPI)        │     │
│  │ (Python service)   │  │ - /api/vaults              │     │
│  │ - data layer       │──▶ - /api/reasoning/{nonce}   │     │
│  │ - strategy layer   │  │ - /api/agent/status         │     │
│  │ - execution layer  │  └────────────────────────────┘     │
│  └─────────┬──────────┘                                    │
│            │ pulls                                          │
│  ┌─────────▼──────────┐                                    │
│  │  Pyth Hermes API   │                                    │
│  └────────────────────┘                                    │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Smart contracts — full list

| Contract | LOC (approx) | Role |
|---|---|---|
| `VaultFactory.sol` | ~80 | Deploys new themed vaults |
| `EquityVault.sol` | ~250 | ERC-4626 vault, rebalance entry point |
| `StrategyCommitmentRegistry.sol` | ~60 | Records strategy hashes |
| Mock tokenized stocks (xNVDA, xMSFT, …) | ~30 each | Demo-only if real xStocks unavailable |
| Mock USDC (if needed) | ~20 | Demo-only on testnet |

**Total Solidity surface: ~500 lines, three real contracts.** No upgradeability in V1 (intentional — keeps the surface small and the code auditable). All contracts are isolated, no shared inheritance, no external admin (except the agent operator role on each vault).

### 4.3 Off-chain services

**Rebalancer (`/agent`)**
- Python 3.11, FastAPI for the small admin surface
- `eth-account` for signing
- `web3.py` for Monad JSON-RPC
- `httpx` for Pyth Hermes
- Runs as a single Docker container on Fly.io / Railway
- Cron-like loop (apscheduler) every 5 minutes
- Holds the AGENT_OPERATOR private key in env (V1) → V2 will move to a hardware signer or KMS

**Vesta API (`/api`)**
- Python 3.11, FastAPI, Postgres
- Endpoints:
  - `GET /api/vaults` — list all deployed vaults with metadata
  - `GET /api/vault/{address}` — full vault state
  - `GET /api/reasoning/{vault}/{nonce}` — the JSON reasoning for a given commitment
  - `GET /api/agent/status` — last rebalance, next scheduled, agent health

### 4.4 Frontend stack

- Next.js 14 (App Router)
- TypeScript
- wagmi v2 + viem for EVM interaction
- RainbowKit for wallet connection
- Tailwind CSS + shadcn/ui for components
- Recharts for vault composition charts
- Deployed on Vercel

### 4.5 Integrations — pinned addresses and services

**Monad Mainnet**
- RPC: `https://rpc.monad.xyz` (public) or a private RPC (Alchemy/QuickNode) for production
- Chain ID: 143
- USDC: `0x...` (verified at deploy time from Circle's official Monad address)
- Uniswap V3 SwapRouter: `0x...` (deployed on Monad)
- Pyth price feed contract: `0x2880aB155794e7179c9eE2e38200202908C17B43` (per Monad docs)
- xStocks contracts: queried at deploy time from Backed's official indexer

**Pyth**
- Hermes endpoint: `https://hermes.pyth.network`
- Price feed IDs for US equities: queried from Pyth's price feed registry at deploy time

### 4.6 What is **not** in V1 architecture

- No cross-chain messaging
- No account abstraction (ERC-4337) or smart contract wallets
- No aggregator routing (we use Uniswap V3 directly with multi-hop if needed)
- No DAO or governance token
- No fee-switch timelock (V1 fees are on at deploy)
- No on-chain AI inference

---

## 5. Flow

### 5.1 User flow — first-time user

1. **Land on `/`** → sees a grid of vaults. Two are pre-deployed for the demo: "AI Mega Cap" and "Energy Transition." Each card shows theme name, AUM, 24h yield, last rebalance time.
2. **Click "AI Mega Cap"** → goes to `/vault/[address]`.
3. **Vault detail page** shows: composition donut chart, target vs. actual weights, deposit box, recent rebalances list.
4. **Click "Connect Wallet"** → RainbowKit modal. User connects MetaMask (or any EVM wallet), switched to Monad.
5. **Enter deposit amount (e.g. 100 USDC) → click "Deposit"** → one transaction: `approve(USDC, vault)` + `vault.deposit(100, user)`. Behind the scenes, the vault swaps the USDC into xStocks via Uniswap.
6. **User now holds `vAI-MEGA` shares** representing their pro-rata claim on the basket.
7. **User clicks "AI Reasoning" tab** → sees a list of recent rebalances with: timestamp, target weights, actual on-chain weights, and a "View Reasoning" button. Clicking shows the full JSON the agent published, with a green checkmark ✅ if its hash matches the on-chain commitment.
8. **User clicks "Withdraw"** → enters share amount → one transaction: `vault.redeem(shares, user, user)`. Behind the scenes, the vault swaps the basket back to USDC.

### 5.2 System flow — AI rebalance cycle (every 5 minutes)

```
[T+0:00] Cron tick
  ↓
[Agent] data/market.py fetches Pyth prices (last 30d for each underlying)
[Agent] data/state.py reads vault composition from chain
  ↓
[Agent] strategy/momentum_vol.py computes target weights
  ↓
[Agent] drift.py compares target vs actual
  ↓
  IF max drift < 200 BPS:  log "no rebalance needed" → exit
  IF max drift ≥ 200 BPS: continue
  ↓
[Agent] constructs reasoning JSON:
  {
    "vault": "0x...",
    "nonce": 42,
    "timestamp": 1764000000,
    "inputPrices": {"xNVDA": 134.5, ...},
    "inputCompositions": [...],
    "computedMomentum": {"xNVDA": 0.12, ...},
    "computedVolatility": {"xNVDA": 0.34, ...},
    "targetWeights": [3000, 2500, 2000, 1500, 1000],
    "explanation": "xNVDA momentum +12%, volatility 0.34..."
  }
  ↓
[Agent] hash = keccak256(abi.encode(vault, nonce, timestamp, keccak256(json)))
  ↓
[Agent] signs hash with operator key
  ↓
[Agent] POST /api/reasoning/{vault}/{nonce} → Vesta API stores JSON
  ↓
[Agent] sends TX 1: StrategyCommitmentRegistry.commit(hash, vault, nonce, timestamp)
[Agent] waits for TX 1 confirmation
  ↓
[Agent] sends TX 2: vault.rebalance(commitmentHash, maxAgeSec)
  - Inside vault.rebalance:
    a. reads registry → verifies hash matches (vault, nonce, timestamp)
    b. computes deltas (target vs current)
    c. for each underlying, swaps USDC ↔ xStock via Uniswap (slippage protected)
    d. updates lastRebalanceTimestamp, increments nonce
  ↓
[Agent] emits rebalance event → frontend picks up via subscription
  ↓
[End] next cron tick in 5 minutes
```

### 5.3 Demo flow (90 seconds, both hackathons)

1. **[0–10s] Landing screen.** Show two vaults live, real AUM, real composition.
2. **[10–25s] Click "AI Mega Cap."** Show composition donut (current). Show 5 recent rebalances on the right rail.
3. **[25–40s] Trigger demo rebalance.** Button on the page (dev-only) forces the agent to rebalance NOW. The reasoning panel slides in: "xNVDA momentum +14% over 30d, xMETA +6%, xAMD -3%... new target weights: [3200, 2400, 1900, 1600, 900]." Show the JSON.
4. **[40–55s] Show the on-chain commitment.** Click the tx hash, show it on MonadVision. The hash matches. The reasoning JSON is in the public Vesta API. Anyone can verify.
5. **[55–70s] Show the swap.** Vault balance changed: more xNVDA, less xMETA. Show the on-chain balances before/after.
6. **[70–90s] Compare to "black box" alternatives.** Slide: "Bankr: ⬛ closed. Bluwhale: ⬛ closed. Cesto: no AI. Vesta: 🟢 verifiable."

---

## 6. Pitch

### 6.1 The story (60 seconds, both hackathons)

> "Tokenized US stocks onchain are the fastest-growing corner of crypto — $1.5B in 2026, up 422% YoY. But the people who hold them earn exactly 0% yield, and the 'AI agents' that move them are black boxes. You cannot verify what they did.
>
> Vesta fixes both. We wrap tokenized stocks into themed vaults, run them through a deterministic AI agent that rebalances for momentum and volatility, and cryptographically commit the agent's reasoning on-chain before every trade. Non-custodial. Verifiable. Real yield from real assets, with math you can check.
>
> The wedge: a non-custodial tokenized-equity vault with verifiable AI is not a product that exists yet. Cesto (Colosseum winner) is static baskets. Bankr, Bluwhale, Virtuals are AI agents, but custodial and black-box. The 'verifiable AI' primitive is unoccupied — and Monad's high-frequency rails make it possible."

### 6.2 Angles (one product, two pitches)

**For Monad Metropolis (track: Onchain Finance & Trading)**
- *Angle:* "The first onchain tokenized-equity hedge fund with verifiable AI, built natively on Monad's high-frequency rails."
- *Why it scores:* Monad's pitch is "the home of high-frequency finance." A rebalancer that runs every 5 minutes and uses a pull oracle on a 300ms-block chain is the highest-frequency DeFi use case the judges can imagine. AI agent + Monad = direct hit on the "agent economy" track Monad has been pushing.
- *Key claim:* "If Monad is the high-frequency DeFi chain, Vesta is the first product that uses that frequency to do something useful with tokenized stocks."

**For Colosseum**
- *Angle:* "First non-custodial onchain tokenized-equity hedge fund with cryptographically-verifiable AI strategy."
- *Why it scores:* Colosseum's criteria are Novelty, Functionality, Impact, UX, Open-source, Business plan. The verifiable-AI primitive is novel (untaken wedge). The vault is functional (real ERC-4626, real xStocks, real USDC). The impact is the $1.5B tokenized-stocks market plus the $1T+ TradFI covered-call ETF market that has no onchain equivalent. The UX is the reasoning panel. Open-source is the entire Solidity repo + agent + frontend. The business plan is the AUM fee.
- *Key claim:* "Verifiable AI is the wedge. Two hackathons, one product, one primitive that didn't exist before."

### 6.3 Benefits

**To the user (the degen retail investor):**
- They earn yield from their tokenized stock holdings (theme-driven, not static)
- They keep custody (non-custodial vault shares)
- They can verify the AI's reasoning at any time
- They can exit any time (standard ERC-4626 redeem)

**To Monad (the ecosystem):**
- Brings real RWA volume (tokenized US equities) into the Monad DeFi flywheel
- Showcases Monad's high-frequency capability with a real consumer use case
- Cross-pollinates with Monad's "Agent Economy" narrative (they ran 4 Agent Blitz hackathons)
- Composable with Aave, Pendle, Upshift, Saturn (vault shares are standard ERC-20 + ERC-4626)

**To Backed / xStocks (the asset issuer):**
- Creates an active utility layer for xStocks on Monad (turns dead inventory into productive AUM)
- Showcases the xStocks integration story to Backed's other chain partners

**To the broader DeFi space:**
- Establishes the "verifiable AI" pattern as a primitive others can copy
- A reference implementation of "AI agent + strategy commitment registry" that any team can fork

### 6.4 Market model

**Total addressable market (TAM)**
- Tokenized US equities: $1.5B today, projected $4–5T by 2030 (Citi)
- TradFI covered-call ETF market (the analog of Vesta's yield): $50B+ today (JEPI, QYLD, etc.)
- Vesta's slice = active-managed tokenized equity yield. Even a 1% capture of the tokenized-equity market = $15M+ AUM at launch; 1% of the 2030 projection = $40B+.

**Serviceable addressable market (SAM)**
- Tokenized equities on Monad: not yet measured, but Monad is one of the explicit EVM launch partners for xStocks. Capturing Monad's share = realistic target.
- Realistic V1 demo AUM: $50K–$500K (post-hackathon). V2 target: $10M+ AUM within 12 months.

**Serviceable obtainable market (SOM)**
- Hackathon-to-launch funnel: judges, Monad ecosystem grants, Backed partner program, Colosseum accelerator interview.
- Realistic V1 SOM: 1–2 institutional design partners (DAOs, treasury managers) using Vesta for treasury diversification by Q2 2027.

### 6.5 Business model (revenue)

**Primary: Management fee**
- 0.5% annualized on AUM, charged continuously
- Implemented as a vault-level skim: each rebalance, a small fraction of accrued yield is minted as vault shares to the `feeRecipient`
- At $10M AUM, 0.5% = $50K/year revenue
- At $100M AUM, 0.5% = $500K/year revenue

**Secondary: Performance fee (V2, not V1)**
- 10% of yield above a high-water mark (the highest value the vault has ever reached, so fees only kick in on new profits, not on recovered losses)
- V1 does not implement performance fees to keep the contract surface small

**Tertiary: Theme listing fee (V2)**
- When user-created themes go live, charge a small deployment fee

**Unit economics (V1 target):**
- AUM target: $500K
- Annual revenue: $2,500
- Cost: ~$200/month (Vercel + RPC + hosting) = $2,400/year
- Break-even: ~$500K AUM (achievable in V1 demo + post-hackathon traction)

**Traction signals for hackathon judges (and V2 fundraising):**
- Number of vaults deployed
- AUM per vault
- Number of rebalances executed
- Number of verified strategy commitments
- Independent verification by third parties (Hackathon judges, security reviewers)

---

## 7. Go-to-market strategy

### 7.1 Phase A — Hackathon traction (now → Nov 2, 2026)

**Goal:** Top placement at Monad Metropolis (Oct 13 submission) + Colosseum (Nov 2 submission).

**Tactics:**
- Submit to Monad Metropolis **track 1: Onchain Finance & Trading** (best fit for Vesta's positioning)
- Submit to **Colosseum** (no tracks, single startup competition)
- Daily dev updates on the project page (Monad Metropolis + Colosseum both reward shipping cadence)
- 1-on-1 mentor sessions (Monad Metropolis offers them; book at least 2)
- Post demo on Twitter/X with the reasoning-panel screenshot as the hook
- Engage Monad ecosystem accounts (@monad_xyz, ecosystem partners)
- Engage Colosseum's social (@colosseum)

**Success metric:** Top 3 in Monad track 1, top 20 at Colosseum. Both lead to interview slots for Colosseum's accelerator and Monad's DeltaV residency.

### 7.2 Phase B — Post-hackathon (Nov 2026 → Feb 2027)

**Goal:** Convert hackathon visibility into 2–3 design partners (treasuries, DAOs, smaller funds).

**Tactics:**
- Apply to Colosseum Accelerator (if top 3) and Monad DeltaV residency
- Write 3 technical blog posts:
  1. "Building a verifiable AI agent for tokenized equities on Monad"
  2. "Why ERC-4626 + Pyth pull oracle is the right substrate for AI-managed vaults"
  3. "Verifiable AI: a primitive for any onchain AI agent"
- Launch on Backed's partner program (apply via Backed's website)
- Open the vault factory permissionlessly (anyone can deploy a new theme)
- Add 2 more themes based on hackathon feedback

**Success metric:** $500K AUM across 5+ vaults by Feb 2027. 2 design partners under LOI.

### 7.3 Phase C — Growth (Mar 2027 → Dec 2027)

**Goal:** $10M+ AUM. Default tokenized-equity yield layer on Monad and Base.

**Tactics:**
- Deploy factory on Base (where Coinbase Tokenized Stocks are live via the B20 standard) — same code, new chain
- Cross-chain vault share mirroring (LayerZero or Chainlink CCIP)
- Performance fee tier
- Mobile-responsive frontend (lightweight, no app)
- Partner with one RWA distribution platform (Mento, Blend, Saturn, or similar)
- Run 1 institutional design sprint with 1 fund

**Success metric:** $10M AUM, 20+ vaults, 2 chain deployments.

### 7.4 Phase D — Maturity (2028+)

- Listed on RWA.xyz, DeFiLlama
- Managed themes (curated by Vesta, fees shared with curators)
- User-created themes with theme-listing fee
- Performance fees on
- Audit by Tier-1 firm (Trail of Bits, Spearbit, OpenZeppelin)
- Insurance wrapper (Nexus Mutual or similar)

---

## 8. Build Plan (phases, not days)

The plan is structured in 6 phases. Each phase has a single, sharp definition of done. We do not move to the next phase until the current one is signed off.

### Phase 1 — Foundation (must complete first)

**Goal:** A deployable skeleton on Monad testnet + a working monorepo.

**Deliverables:**
- Repo: `vesta/` with `contracts/`, `agent/`, `api/`, `web/`, `docs/`, `README.md`
- Hardhat project under `contracts/` with Monad testnet + mainnet configs
- Three empty contracts (`VaultFactory`, `EquityVault`, `StrategyCommitmentRegistry`) compiling
- One deployment script: deploys all three to Monad testnet
- A verified deployment on Monad testnet (tx hash saved)
- A short `ARCHITECTURE.md` summarizing the diagram in Section 4.1

**Definition of done:** A new engineer can clone the repo, run `npm install`, and deploy the three contracts to Monad testnet in under 5 minutes.

### Phase 2 — Vaults and swaps

**Goal:** Users can deposit USDC and get vault shares; the vault actually holds xStocks (or mock xStocks).

**Deliverables:**
- `EquityVault` fully implemented (deposit, redeem, withdraw, ERC-4626 standard)
- `VaultFactory` can create new themed vaults
- Uniswap V3 swap path inside `rebalance()` (multi-hop, slippage-protected)
- Two themes deployed: "AI Mega Cap" + "Energy Transition"
- Mock tokenized stocks deployed on Monad testnet (clearly labeled "MOCK" in events)
- Foundry test suite covering: deposit, redeem, rebalance, fee skim, edge cases
- Local Anvil fork test for swap path

**Definition of done:** A test script deposits 1000 USDC into the AI Mega Cap vault, the vault swaps to xStocks via Uniswap, the user receives `vAI-MEGA` shares, and a `redeem()` round-trips back to USDC minus swap fees. All assertions pass in CI.

### Phase 3 — AI agent

**Goal:** An off-chain Python service that reads market data and computes target weights.

**Deliverables:**
- `agent/` Python service
- `data/market.py` reading Pyth Hermes
- `strategy/momentum_vol.py` with documented formula
- `exec/rebalance.py` that signs and sends txs
- Dry-run mode (computes targets, does not send txs)
- A `STRATEGY.md` doc explaining the strategy with a worked example
- Unit tests for the strategy module

**Definition of done:** Running `python -m agent.dry_run` against Monad testnet prints the target weights for both themes, derived from live Pyth prices, with no on-chain tx submitted. Numbers match a hand-calculated example in the doc.

### Phase 4 — Verifiable AI

**Goal:** The strategy commitment primitive works end-to-end.

**Deliverables:**
- `StrategyCommitmentRegistry.commit()` and `verify()` fully implemented
- Off-chain reasoning JSON published to Vesta API
- End-to-end test: agent rebalances → on-chain commitment hash matches off-chain JSON hash
- A public `verifier.html` page where anyone can paste a commitment hash and reasoning JSON and see ✅/❌
- A short doc explaining the cryptographic flow with a worked example

**Definition of done:** A user can take any past rebalance, download the off-chain JSON, paste it into the verifier page alongside the on-chain commitment hash, and see ✅. Forging or modifying the JSON makes the verifier show ❌.

### Phase 5 — Frontend

**Goal:** A working web app where users can browse, deposit, and see the AI's reasoning.

**Deliverables:**
- Next.js app at `web/`
- Pages: `/`, `/vault/[address]`, `/about`, `/verifier`
- Components: vault card, composition donut, AI reasoning panel, deposit modal
- Wallet connection via RainbowKit
- Live data from Monad RPC + Vesta API
- A 30-second screen recording of the demo flow
- Lighthouse score ≥ 90 on all four pages

**Definition of done:** A non-crypto-native user can land on the homepage, connect MetaMask, deposit 100 USDC into the AI Mega Cap vault, and see the AI reasoning panel within 2 minutes. No developer help required.

### Phase 6 — Submission

**Goal:** Ship both hackathon submissions.

**Deliverables for Monad Metropolis:**
- Working product deployed on Monad mainnet
- Public project profile with demo, writeup, code link
- 2-minute demo video (voice-overed, showing the reasoning panel)
- Submitted before Oct 13, 2026 23:59 PT

**Deliverables for Colosseum:**
- Same product (Monad mainnet), with a Colosseum-specific pitch
- 2–3 minute presentation video
- 3-minute product demo video
- Go-to-market section in the submission form
- Submitted before Nov 2, 2026

**Definition of done:** Both submissions accepted by the platform, confirmation emails saved, public links shareable on Twitter.

### Build plan summary

| Phase | Output | Gate |
|---|---|---|
| 1. Foundation | Deployable skeleton on Monad testnet | Repo runs, contracts compile, deploys clean |
| 2. Vaults and swaps | Deposit/redeem/rebalance works end-to-end | Round-trip test passes |
| 3. AI agent | Off-chain agent computes correct targets | Dry-run matches hand-calc |
| 4. Verifiable AI | Commitment hash + reasoning JSON + verifier page | Hash mismatch shows ❌ |
| 5. Frontend | Web app for browse/deposit/verify | Non-dev user can complete deposit in <2 min |
| 6. Submission | Both hackathons submitted | Confirmation received |

---

## 9. Decisions locked (no further "should we")

| Decision | Choice | Reason |
|---|---|---|
| Underlying tokenized stocks | xStocks on Monad (real if available, mock if not) | xStocks is the only tokenized-stock issuer with Monad in its published supported chains |
| Deposit asset | USDC on Monad | Most liquid, Circle-issued, live on Monad since day 1 |
| Oracle | Pyth (pull) on Monad | 400ms latency, equity feeds available, Monad-supported |
| DEX | Uniswap V3 on Monad | Live, deep USDC pairs, most-tested EVM DEX |
| Vault standard | ERC-4626 | Composable with rest of Monad DeFi |
| Rebalance cadence | 5 minutes | Matches Monad's block time, balances gas + freshness |
| Strategy | Momentum + inverse-volatility | Documented, deterministic, defensible, no ML infra needed |
| Operator | Single EOA (V1) | Demo simplicity; V2 moves to multisig / KMS |
| Chain for V1 | Monad only | Per user directive |
| Chain for V1 | Monad + same code on Base for Colosseum (V2) | Colosseum is open to all chains; Base has Coinbase Tokenized Stocks via B20 standard |
| Mock fallback | Yes (clearly labeled) | Standard hackathon trade-off; accepted by judges |
| Tokenized private credit | No | Different regulation, different risk profile; V2 |
| Options / covered calls | No | No native options protocol on Monad; not buildable in 10 days |
| Bridge to other EVM chains | No (V1) | Add cross-chain mirroring in V2 |
| Governance token | No (V1) | Add when AUM justifies it |
| Audit | Post-hackathon | Phase D, with Tier-1 firm |
| Insurance | Post-hackathon | Phase D |

---

*End of product file. V1 scope frozen. Build plan in motion.*
