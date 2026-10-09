"""Runtime config: env only, validated at boot. No secrets in code, ever."""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    """All knobs the API reads. Missing secrets fail fast at startup."""

    rpc_url: str
    registry_addr: str
    agent_api_key: str
    cors_origins: tuple[str, ...]
    sqlite_path: str
    chain_id: int = 10143


def load() -> Settings:
    """Build settings from env. Raises RuntimeError naming the missing var."""
    def req(name: str) -> str:
        value = os.environ.get(name, "")
        if not value:
            raise RuntimeError(f"missing env: {name} (see .env.example)")
        return value

    origins = tuple(o.strip() for o in os.environ.get("CORS_ORIGINS", "").split(",") if o.strip())
    return Settings(
        rpc_url=os.environ.get("RPC_URL", "https://testnet-rpc.monad.xyz"),
        registry_addr=req("REGISTRY_ADDR"),
        agent_api_key=req("AGENT_API_KEY"),
        cors_origins=origins,
        sqlite_path=os.environ.get("SQLITE_PATH", "./vesta.db"),
    )
