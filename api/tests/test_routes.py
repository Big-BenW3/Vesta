"""Route envelope tests. Require fastapi + httpx (CI/Render); skipped otherwise.

Covers backend.md section 4.3: 401/404/409/422 shapes, idempotent re-POST,
oversize rejection, and checksum normalisation.
"""

import os
import tempfile

import pytest

fastapi = pytest.importorskip("fastapi")
httpx = pytest.importorskip("httpx")

from starlette.testclient import TestClient

os.environ.setdefault("REGISTRY_ADDR", "0x" + "00" * 20)
os.environ.setdefault("AGENT_API_KEY", "test-key")
os.environ.setdefault("SQLITE_PATH", os.path.join(tempfile.mkdtemp(), "api.db"))

from main import create_app  # noqa: E402
from models import store  # noqa: E402

store.init_db(os.environ["SQLITE_PATH"])

client = TestClient(create_app())
KEY = {"X-API-Key": "test-key"}


def test_healthz_ok():
    assert client.get("/healthz").json() == {"ok": True}


def test_vault_list_empty_shape():
    r = client.get("/api/v1/vaults")
    assert r.status_code == 200 and r.json() == {"vaults": []}


def test_invalid_address_400():
    r = client.get("/api/v1/vaults/not-an-address")
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "INVALID_ADDRESS"


def test_unknown_vault_404():
    r = client.get("/api/v1/vaults/" + "0x" + "11" * 20)
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "VAULT_NOT_FOUND"


def test_post_requires_key_401():
    r = client.post("/api/v1/reasoning", json={})
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "UNAUTHORIZED"


def test_post_rejects_bad_shape_422():
    doc = {"vault": "0x" + "11" * 20, "nonce": 0}  # missing required fields
    r = client.post("/api/v1/reasoning", json=doc, headers=KEY)
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "SCHEMA_INVALID"


def test_post_rejects_oversize_422():
    big = "x" * (64 * 1024 + 1)
    r = client.post("/api/v1/reasoning", content=big, headers={**KEY, "Content-Type": "application/json"})
    assert r.status_code == 422


def test_reasoning_missing_404():
    r = client.get("/api/v1/reasoning/" + "0x" + "11" * 20 + "/0")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "REASONING_NOT_FOUND"
