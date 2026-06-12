"""Schedules + plans routers (P11–P13). HTTP concerns ONLY — versioning, diff,
sanity, release math live in services/plans.py (CLAUDE.md). Reads: internal roles;
writes: planning/admin. NOTE: register in app/main.py with
`app.include_router(plans_router)` — wiring main.py is outside this packet's file
list (tests mount it themselves)."""
from datetime import date

from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, _error, require
from app.importers.schedule_csv import parse_schedule_csv
from app.models.planning import Schedule, ScheduleLine
from app.schemas import plans as s
from app.services import plans as svc
from app.services.files import save_file
from app.services.master import get_or_404

router = APIRouter(prefix="/api/v1", tags=["plans"])

INTERNAL = ("admin", "management", "planning", "plant_ops", "supervisor")
read_guard = require(*INTERNAL)
write_guard = require("admin", "planning")


# --- schedules ---
@router.post("/schedules", response_model=s.ScheduleRead, status_code=201)
def create_schedule(body: s.ScheduleCreate, db: Session = Depends(get_db),
                    user: CurrentUser = Depends(write_guard)):
    """Manual JSON entry path (provisional until the Bajaj sample — Domain_QA Q1)."""
    return svc.create_schedule(db, user, customer_id=body.customer_id,
                               period=body.period,
                               lines=[ln.model_dump() for ln in body.lines],
                               source_file_id=body.source_file_id)


@router.post("/schedules/upload", response_model=s.ScheduleUploadResult,
             status_code=201)
def upload_schedule(customer_id: int = Form(...), period: str = Form(...),
                    file: UploadFile = File(...), db: Session = Depends(get_db),
                    user: CurrentUser = Depends(write_guard)):
    """Provisional-CSV upload → parser → draft schedule. Row errors are returned,
    never raised — except when NO row parses, which is a 422."""
    content = file.file.read()
    rows, errors = parse_schedule_csv(content)
    if not rows:
        raise _error("CSV_NO_ROWS", "No valid rows in the uploaded CSV",
                     "अपलोड केलेल्या CSV मध्ये वैध ओळी नाहीत", 422,
                     {"row_errors": errors})
    stored = save_file(db, content=content, filename=file.filename or "schedule.csv",
                       kind="import", mime=file.content_type, uploaded_by=user.id)
    schedule = svc.create_schedule(db, user, customer_id=customer_id, period=period,
                                   lines=rows, source_file_id=stored.id)
    return {"schedule": schedule, "rows_ok": len(rows), "row_errors": errors}


@router.post("/schedules/upload-xlsx", status_code=201)
def upload_schedule_xlsx(customer_id: int = Form(...), period: str = Form(...),
                         file: UploadFile = File(...), db: Session = Depends(get_db),
                         user: CurrentUser = Depends(write_guard)):
    """THE REAL Bajaj format ('3 Wh Production Plan' workbook — golden sample in
    data/). Vehicle-model rows × week buckets → VEHICLE-level schedule lines
    (material_id NULL); release explodes them via model_part_factors (Domain_QA Q1).
    Family overrides come from app_settings['model_family_map']. Response carries
    parse errors, skipped models, and the workbook's material→line sheet for admin
    review — applying that mapping to lines/line_materials stays a human action."""
    from app.importers.schedule_xlsx import parse_line_map, parse_monthly_plan
    from app.models.config_tables import AppSetting

    content = file.file.read()
    overrides_row = db.get(AppSetting, "model_family_map")
    overrides = overrides_row.value if overrides_row else None
    rows, errors = parse_monthly_plan(content, period, family_overrides=overrides)
    if not rows:
        raise _error("XLSX_NO_ROWS", "No schedule rows found in the workbook",
                     "वर्कबुकमध्ये वेळापत्रक ओळी सापडल्या नाहीत", 422,
                     {"errors": errors})
    stored = save_file(db, content=content, filename=file.filename or "schedule.xlsx",
                       kind="import", mime=file.content_type, uploaded_by=user.id)
    lines = [{"model_family": r["family"], "bucket_date": b["bucket_date"],
              "qty": b["qty"]}
             for r in rows for b in r["buckets"]]
    schedule = svc.create_schedule(db, user, customer_id=customer_id, period=period,
                                   lines=lines, source_file_id=stored.id)
    return {
        "schedule_id": schedule.id, "version": schedule.version,
        "models_parsed": len(rows), "lines_created": len(lines),
        "families": sorted({r["family"] for r in rows}),
        "parse_errors": errors,
        "line_map_preview": parse_line_map(content)[:80],
    }


@router.get("/schedules", response_model=list[s.ScheduleRead])
def list_schedules(period: str | None = None, customer_id: int | None = None,
                   db: Session = Depends(get_db),
                   _: CurrentUser = Depends(read_guard)):
    q = db.query(Schedule)
    if period:
        q = q.filter_by(period=period)
    if customer_id:
        q = q.filter_by(customer_id=customer_id)
    return q.order_by(Schedule.period.desc(), Schedule.version.desc()).all()


@router.get("/schedules/{schedule_id}/lines", response_model=list[s.ScheduleLineRead])
def get_schedule_lines(schedule_id: int, db: Session = Depends(get_db),
                       _: CurrentUser = Depends(read_guard)):
    get_or_404(db, Schedule, schedule_id, "schedule")
    return (db.query(ScheduleLine).filter_by(schedule_id=schedule_id)
            .order_by(ScheduleLine.bucket_date, ScheduleLine.id).all())


@router.get("/schedules/{schedule_id}/diff", response_model=s.DiffRead)
def get_diff(schedule_id: int, db: Session = Depends(get_db),
             _: CurrentUser = Depends(read_guard)):
    sched = get_or_404(db, Schedule, schedule_id, "schedule")
    return {"schedule_id": sched.id, "version": sched.version, "diff": sched.diff or {}}


@router.get("/schedules/{schedule_id}/sanity", response_model=s.SanityRead)
def get_sanity(schedule_id: int, db: Session = Depends(get_db),
               _: CurrentUser = Depends(read_guard)):
    """Recomputed on read — the planner sees the verdict for the CURRENT config,
    not a stale snapshot (release stores its own snapshot in schedules.sanity)."""
    sched = get_or_404(db, Schedule, schedule_id, "schedule")
    return {"schedule_id": sched.id, "version": sched.version,
            "sanity": svc.sanity_checks(db, sched)}


@router.post("/schedules/{schedule_id}/release", response_model=s.ReleaseReport)
def release_schedule(schedule_id: int, body: s.ReleaseRequest,
                     db: Session = Depends(get_db),
                     user: CurrentUser = Depends(write_guard)):
    return svc.release(db, user, schedule_id, confirm_warnings=body.confirm_warnings)


@router.post("/schedules/{schedule_id}/re-release", response_model=s.ReleaseReport)
def re_release_schedule(schedule_id: int, db: Session = Depends(get_db),
                        user: CurrentUser = Depends(write_guard)):
    """§11.13 rollback: clone old version as a new one and release it. Never deletes."""
    return svc.re_release(db, user, schedule_id)


# --- plan views (P13) ---
# NOTE: the query param is named `date` per Architecture §6 — the annotation still
# resolves to datetime.date (signature annotations evaluate before params bind).
@router.get("/plans/line-plans", response_model=list[s.PlanRow])
def line_plans(date: date, line_id: int | None = None,  # noqa: A002 — query param name fixed by spec
               db: Session = Depends(get_db), _: CurrentUser = Depends(read_guard)):
    return svc.line_plans(db, date, line_id)


@router.get("/plans/ppc-view", response_model=list[s.PpcLine])
def ppc_view(date: date, db: Session = Depends(get_db),  # noqa: A002
             _: CurrentUser = Depends(read_guard)):
    return svc.ppc_view(db, date)


@router.get("/plans/supervisor-view", response_model=list[s.SupervisorRow])
def supervisor_view(line_id: int, date: date, db: Session = Depends(get_db),  # noqa: A002
                    _: CurrentUser = Depends(read_guard)):
    return svc.supervisor_view(db, line_id, date)
