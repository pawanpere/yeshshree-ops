"""FastAPI app factory. Routers register here; they contain HTTP concerns only —
all business logic lives in app/services/ (CLAUDE.md invariants)."""
import uuid

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.api.approvals import router as approvals_router
from app.api.auth import router as auth_router
from app.api.config import router as config_router
from app.api.dashboards import router as dashboards_router
from app.api.gate import router as gate_router
from app.api.inventory import router as inventory_router
from app.api.master import router as master_router
from app.api.notifications import router as notifications_router
from app.api.outbound import router as outbound_router
from app.api.plans import router as plans_router
from app.api.production import router as production_router
from app.api.receiving import router as receiving_router
from app.api.scans import scans_router, system_router
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


# CORS — added last so it is the OUTERMOST layer (it must answer preflight OPTIONS
# before auth/audit run). Only the Flutter WEB build is cross-origin; a real Android
# build uses native HTTP and never triggers CORS. Explicit prod origins come from
# CORS_ORIGINS; cors_allow_localhost reflects any localhost:<port> for dev/preview.
_cors = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in _cors.cors_origins.split(",") if o.strip()],
    allow_origin_regex=(r"https?://(localhost|127\.0\.0\.1)(:\d+)?"
                        if _cors.cors_allow_localhost else None),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-Request-Id"],
)


app.include_router(auth_router)
app.include_router(master_router)
app.include_router(config_router)
app.include_router(gate_router)
app.include_router(scans_router)
app.include_router(system_router)
app.include_router(receiving_router)
app.include_router(plans_router)
app.include_router(inventory_router)
app.include_router(approvals_router)
app.include_router(notifications_router)
app.include_router(production_router)
app.include_router(outbound_router)
app.include_router(dashboards_router)

# Reconciliation/export router registered below import to avoid circulars
from app.api.exports import router as exports_router  # noqa: E402
app.include_router(exports_router)


@app.get("/api/v1/system/healthz", tags=["system"])
def healthz() -> dict:
    """DB reachability + storage driver + outbox backlog (Architecture §7).
    degraded when: DB down, storage unwritable, or any outbox row is 'failed'."""
    db_ok, storage_ok = True, True
    outbox = {"pending": 0, "batched": 0, "failed": 0}
    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
        from sqlalchemy.orm import Session
        from app.sap_sync.batcher import backlog
        with Session(get_engine()) as s:
            outbox = backlog(s)
    except Exception:
        db_ok = False
    try:
        s = get_settings()
        if s.s3_endpoint:
            import boto3
            boto3.client("s3", endpoint_url=s.s3_endpoint,
                         aws_access_key_id=s.s3_access_key,
                         aws_secret_access_key=s.s3_secret_key
                         ).head_bucket(Bucket=s.s3_bucket)
        else:
            from pathlib import Path
            probe = Path("filestore") / ".healthz"
            probe.parent.mkdir(parents=True, exist_ok=True)
            probe.write_text("ok")
    except Exception:
        storage_ok = False
    healthy = db_ok and storage_ok and outbox["failed"] == 0
    return {"status": "ok" if healthy else "degraded", "db": db_ok,
            "storage": storage_ok, "outbox": outbox}


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
