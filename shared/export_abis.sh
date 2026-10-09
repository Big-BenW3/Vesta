#!/usr/bin/env bash
# Export contract ABIs into shared/abis (the only ABI source for agent/API/web).
set -euo pipefail
cd "$(dirname "$0")/contracts"
forge build
mkdir -p ../shared/abis
for c in EquityVault VaultFactory StrategyCommitmentRegistry MockStock; do
  forge inspect "$c" abi --json > "../shared/abis/$c.json"
done
forge inspect ERC20 abi --json > ../shared/abis/ERC20.json || \
  cp lib/openzeppelin-contracts/artifacts/@openzeppelin/contracts/token/ERC20/ERC20.sol/ERC20.json ../shared/abis/ 2>/dev/null || true
echo "abis exported"
