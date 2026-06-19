"""Dev CORS: the Flutter WEB build runs on http://localhost:<port> and must reach
the API cross-origin. A real Android build uses native HTTP (no CORS). Production
stays closed unless CORS_ORIGINS lists explicit origins."""
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_preflight_from_localhost_is_allowed():
    r = client.options(
        "/api/v1/auth/login",
        headers={
            "Origin": "http://localhost:8140",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,content-type",
        },
    )
    assert r.status_code == 200
    assert r.headers.get("access-control-allow-origin") == "http://localhost:8140"


def test_simple_get_reflects_localhost_origin():
    # Any localhost port is reflected (the preview server port varies run-to-run).
    r = client.get("/api/v1/system/min-version",
                   headers={"Origin": "http://localhost:9999"})
    assert r.status_code == 200
    assert r.headers.get("access-control-allow-origin") == "http://localhost:9999"


def test_non_localhost_origin_gets_no_cors_header():
    # Default config has no explicit cors_origins → a random web origin is NOT allowed.
    r = client.get("/api/v1/system/min-version",
                   headers={"Origin": "http://evil.example.com"})
    assert "access-control-allow-origin" not in {k.lower() for k in r.headers}
