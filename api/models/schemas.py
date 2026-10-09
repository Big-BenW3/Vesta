"""Pydantic v2 models: validated in, validated out (RORO).

Unknown fields are forbidden everywhere — the frontend fails loudly on drift
instead of silently dropping data. Bodies cap at 64KB at the router layer.
"""

from __future__ import annotations

from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

Strict = ConfigDict(extra="forbid")
MAX_BODY_BYTES = 64 * 1024


class VaultSummary(BaseModel):
    """One row of GET /vaults."""

    model_config = Strict

    address: str
    name: str
    symbol: str
    underlyings: list[str]
    targetWeightsBps: list[int]
    aumEstimate: str  # why: string — USDC base units can exceed float precision
    lastRebalance: int
    nonce: int


class VaultDetail(VaultSummary):
    """Full state of GET /vaults/{address}."""

    model_config = Strict

    actualWeightsBps: list[int]
    idleUsdc: str
    totalSupply: str
    feeRecipient: str
    managementFeeBps: int


class ReasoningDoc(BaseModel):
    """The agent's published reasoning for one (vault, nonce). Immutable once stored."""

    model_config = Strict

    vault: str
    nonce: Annotated[int, Field(ge=0)]
    timestamp: int
    inputPrices: dict[str, float]
    inputCompositions: dict[str, int]
    computedMomentum: dict[str, float]
    computedVolatility: dict[str, float]
    targetWeights: dict[str, int]
    explanation: str
    txHash: str = "0x"


class AgentStatus(BaseModel):
    """GET /agent/status — worker health for the reasoning panel."""

    model_config = Strict

    chainId: int
    lastRebalance: int
    lastNonce: int
    nextScheduled: int
    healthy: bool
