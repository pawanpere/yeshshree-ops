"""FastAPI app factory. Routers register here; they contain HTTP concerns only —
all business logic lives in app/services/ (CLAUDE.md invariants)."""
import uuid

from fastapi import FastAPI, Request
from sqlalchemy import text

from app.core.config import get_settings
from app.core.db import get_engine

app = FastAPI(
    title="Yeshshree Operations API",
    version="0.1.0",
    docs_url="/docs",
    openapi_url="/openapi.json",
)


@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    """Every request gets a request_id; audit rows and logs carry it (Architecture §7)."""
    request.state.request_id = request.headers.get("X-Request-Id", str(uuid.uuid4()))
    response = await call_next(request)
    response.headers["X-Request-Id"] = request.state.request_id
    return response


@app.get("/api/v1/system/healthz", tags=["system"])
def healthz() -> dict:
    """DB reachability + (later) storage + outbox backlog. Architecture §7."""
    db_ok = True
    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception:
        db_ok = False
    return {"status": "ok" if db_ok else "degraded", "db": db_ok}


@app.get("/api/v1/system/min-version", tags=["system"])
def min_version() -> dict:
    """Version handshake (Architecture §11.15): app checks on launch;
    below min_version → force-update screen."""
    s = get_settings()
    return {
        "min_version": s.app_min_version,
        "latest_version": s.app_latest_version,
        "apk_url": s.apk_url,
    }
