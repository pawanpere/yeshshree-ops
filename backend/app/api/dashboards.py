"""Dashboards router (P32+P35). HTTP concerns ONLY — all aggregate math lives in
services/dashboards.py (CLAUDE.md). READ-ONLY: GET endpoints, internal roles.

ETag/304 (Architecture §5.8): Flutter polls every 30-60 s; we md5 the JSON
payload into an ETag and answer If-None-Match hits with an empty 304, so an
unchanged dashboard costs nothing to ship.

NOTE: register in app/main.py with `app.include_router(dashboards_router)` —
wiring main.py is outside this packet's file list (tests mount it themselves)."""
import datetime as dt
import hashlib
import json

from fastapi import APIRouter, Depends, Query, Request, Response
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, require
from app.schemas import dashboards as s
from app.services import dashboards as svc

router = APIRouter(prefix="/api/v1/dashboards", tags=["dashboards"])

INTERNAL = ("admin", "management", "planning", "plant_ops", "supervisor")
read_guard = require(*INTERNAL)


def _etag_json(request: Request, model: BaseModel) -> Response:
    """Shared ETag helper: canonical JSON -> md5 ETag; If-None-Match hit -> 304.
    sort_keys + compact separators make the hash stable across dict ordering."""
    payload = model.model_dump(mode="json")
    body = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    etag = f'"{hashlib.md5(body.encode("utf-8")).hexdigest()}"'
    if request.headers.get("If-None-Match") == etag:
        return Response(status_code=304, headers={"ETag": etag})
    return Response(content=body, media_type="application/json",
                    headers={"ETag": etag})


@router.get("/achievement", response_model=s.AchievementOut)
def achievement(request: Request, date: dt.date | None = Query(None),
                db: Session = Depends(get_db),
                user: CurrentUser = Depends(read_guard)):
    """Plan vs confirmed per line for a day (default: today)."""
    return _etag_json(request, s.AchievementOut.model_validate(
        svc.achievement(db, date or dt.date.today())))


@router.get("/yield", response_model=s.YieldOut)
def yield_dashboard(request: Request, date: dt.date | None = Query(None),
                    db: Session = Depends(get_db),
                    user: CurrentUser = Depends(read_guard)):
    """Good vs rejected by line/shift + reject reasons + imputed scrap value."""
    return _etag_json(request, s.YieldOut.model_validate(
        svc.yield_report(db, date or dt.date.today())))


@router.get("/sales", response_model=s.SalesOut)
def sales(request: Request,
          month: str | None = Query(None, pattern=r"^\d{4}-\d{2}$"),
          db: Session = Depends(get_db),
          user: CurrentUser = Depends(read_guard)):
    """Billed today / MTD from confirmed invoices (default month: current)."""
    return _etag_json(request, s.SalesOut.model_validate(
        svc.sales(db, month or dt.date.today().strftime("%Y-%m"))))


@router.get("/overview", response_model=s.OverviewOut)
def overview(request: Request, date: dt.date | None = Query(None),
             db: Session = Depends(get_db),
             user: CurrentUser = Depends(read_guard)):
    """Management one-screen KPIs (default: today)."""
    return _etag_json(request, s.OverviewOut.model_validate(
        svc.overview(db, date or dt.date.today())))
