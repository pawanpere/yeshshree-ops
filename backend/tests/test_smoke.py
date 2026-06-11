"""P01 acceptance: app boots; /healthz and /system/min-version respond."""
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_healthz():
    r = client.get("/api/v1/system/healthz")
    assert r.status_code == 200
    assert r.json()["status"] in ("ok", "degraded")


def test_min_version_handshake():
    r = client.get("/api/v1/system/min-version")
    assert r.status_code == 200
    body = r.json()
    assert {"min_version", "latest_version", "apk_url"} <= set(body)


def test_request_id_header_returned():
    r = client.get("/api/v1/system/healthz", headers={"X-Request-Id": "test-123"})
    assert r.headers["X-Request-Id"] == "test-123"
