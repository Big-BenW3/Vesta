#!/usr/bin/env bash
# E2E gate on Monad testnet (10143): deploy -> fund pools -> deposit 1000 USDC
# -> force rebalance -> verifier check -> redeem. Any step failing aborts.
# Requires: forge, cast, RPC_URL, AGENT_OPERATOR_KEY, env from .env.
set -euo pipefail
cd "$(dirname "$0")/../contracts"

echo "== 1/6 deploy (factory, mocks, 2 themes)"
forge script script/Deploy.s.sol --rpc-url "$RPC_URL" --broadcast

echo "== 2/6 seed pools (USDC/mSTOCK liquidity)"
forge script script/SeedPools.s.sol --rpc-url "$RPC_URL" --broadcast

VAULT_A=$(jq -r '.vaults[0].address' ../shared/deployments.json)
echo "== 3/6 deposit 1000 USDC into $VAULT_A"
cast send "$USDC_ADDR" "approve(address,uint256)" "$VAULT_A" 1000000000 --rpc-url "$RPC_URL" --private-key "$USER_KEY"
cast send "$VAULT_A" "deposit(uint256,address)" 1000000000 "$USER_ADDR" --rpc-url "$RPC_URL" --private-key "$USER_KEY"

echo "== 4/6 force rebalance via agent dry-run + single tick"
(cd ../agent && python3 -m dry_run)
(cd ../agent && AGENT_ONCE=1 python3 -m scheduler)

echo "== 5/6 verifier: latest nonce must verify"
NONCE=$(cast call "$VAULT_A" "nonce()" --rpc-url "$RPC_URL")
curl -sf "$API_URL/api/v1/reasoning/$VAULT_A/$NONCE" | jq -e '.nonce == '"$NONCE"' > /dev/null'

echo "== 6/6 redeem all shares back to USDC"
SHARES=$(cast call "$VAULT_A" "balanceOf(address)" "$USER_ADDR" --rpc-url "$RPC_URL")
cast send "$VAULT_A" "redeem(uint256,address,address)" "$SHARES" "$USER_ADDR" "$USER_ADDR" --rpc-url "$RPC_URL" --private-key "$USER_KEY"

echo "E2E GREEN"
