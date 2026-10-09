"""GET /agent/status — worker health for the reasoning panel."""

from __future__ import annotations

import time

from fastapi import APIRouter, Depends

from core.config import Settings, load
from core.security import rate_limit
from models import store
from models.schemas import AgentStatus

router = APIRouter(dependencies=[Depends(rate_limit)])
CADENCE_S = 300


@router.get("/agent/status", response_model=AgentStatus)
def agent_status(settings: Settings = Depends(load)) -> AgentStatus:
    """Last rebalance, next scheduled tick, chain id. Healthy = tick seen in 2x cadence."""
    last = store.last_rebalance(settings.sqlite_path)
    last_ts = last["created_at"] if last else 0
    last_nonce = last["nonce"] if last else 0
    return AgentStatus(
        chainId=settings.chain_id,
        lastRebalance=last_ts,
        lastNonce=last_nonce,
        nextScheduled=int(time.time()) + CADENCE_S,
        healthy=(time.time() - last_ts) < 2 * CADENCE_S if last else False,
    )
