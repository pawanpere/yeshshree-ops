"""FastAPI app factory. Routers register here; they contain HTTP concerns only —
all business logic lives in app/services/ (CLAUDE.md invariants)."""
import uuid

from fastapi import FastAPI, Request
from sqlalchemy import text

from app.api.auth import router as auth_router
from app.core import audit
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


@app.middleware("http")
async def audit_middleware(request: Request, call_next):
    """Invariant 1: every mutating request leaves an audit row — even failed ones.
    Bodies are never stored (passwords/PINs). Field-level diffs are the services' job
    via audit.record(). Audit failure must never take the request down with it."""
    response = await call_next(request)
    if audit.is_mutating(request.method) and not request.url.path.startswith("/openapi"):
        try:
            from app.core.db import get_engine as _ge
            from sqlalchemy.orm import Session
            with Session(_ge()) as s:
                audit.write_request_audit(s, request=request,
                                          response_status=response.status_code)
                s.commit()
        except Exception:
            import structlog
            structlog.get_logger().error("audit_write_failed", path=request.url.path)
    return response


app.include_router(auth_router)


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
