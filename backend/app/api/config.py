"""Config router (P10) — the §5.11 admin screen's API. Writes: admin/planning, audited.
These tables drive behaviour everywhere (reason codes → confirm screen; tolerances → GR;
calendar → shift close; settings → ops_mode and thresholds)."""
from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from app.core.audit import record
from app.core.db import get_db
from app.core.deps import CurrentUser, require
from app.models.config_tables import (AppSetting, MaterialGroupTolerance, Mill,
                                      ModelFamilySplit, PlanCalendar, ReasonCode)
from app.services.master import apply_update, create_with_audit, get_or_404

router = APIRouter(prefix="/api/v1/config", tags=["config"])

INTERNAL = ("admin", "management", "planning", "plant_ops", "supervisor")
read_guard = require(*INTERNAL)
write_guard = require("admin", "planning")


class _Read(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --- reason codes ---
class ReasonCodeRead(_Read):
    id: int
    kind: str
    code: str
    label_en: str
    label_mr: str | None
    sort: int | None
    is_active: bool


class ReasonCodeCreate(BaseModel):
    kind: str
    code: str
    label_en: str
    label_mr: str | None = None
    sort: int = 0


class ReasonCodeUpdate(BaseModel):
    label_en: str | None = None
    label_mr: str | None = None
    sort: int | None = None
    is_active: bool | None = None


@router.get("/reason-codes", response_model=list[ReasonCodeRead])
def list_reason_codes(kind: str | None = None, db: Session = Depends(get_db),
                      _: CurrentUser = Depends(read_guard)):
    q = db.query(ReasonCode)
    if kind:
        q = q.filter_by(kind=kind)
    return q.order_by(ReasonCode.kind, ReasonCode.sort, ReasonCode.code).all()


@router.post("/reason-codes", response_model=ReasonCodeRead, status_code=201)
def create_reason_code(body: ReasonCodeCreate, db: Session = Depends(get_db),
                       user: CurrentUser = Depends(write_guard)):
    return create_with_audit(db, ReasonCode(**body.model_dump()), user, "reason_codes")


@router.patch("/reason-codes/{code_id}", response_model=ReasonCodeRead)
def update_reason_code(code_id: int, body: ReasonCodeUpdate,
                       db: Session = Depends(get_db),
                       user: CurrentUser = Depends(write_guard)):
    obj = get_or_404(db, ReasonCode, code_id, "reason code")
    apply_update(db, obj, body.model_dump(exclude_unset=True), user, "reason_codes",
                 allowed={"label_en", "label_mr", "sort", "is_active"})
    return obj


# --- model family splits ---
class SplitRead(_Read):
    id: int
    family: str
    yesh_pct: int
    laxmi_pct: int
    effective_from: date


class SplitCreate(BaseModel):
    family: str
    yesh_pct: int
    laxmi_pct: int
    effective_from: date


@router.get("/splits", response_model=list[SplitRead])
def list_splits(db: Session = Depends(get_db), _: CurrentUser = Depends(read_guard)):
    return db.query(ModelFamilySplit).order_by(
        ModelFamilySplit.family, ModelFamilySplit.effective_from).all()


@router.post("/splits", response_model=SplitRead, status_code=201)
def create_split(body: SplitCreate, db: Session = Depends(get_db),
                 user: CurrentUser = Depends(write_guard)):
    """New effective-dated row — history is never edited (release math pins its split)."""
    from app.core.deps import _error
    if body.yesh_pct + body.laxmi_pct != 100:
        raise _error("SPLIT_NOT_100", "Split must total 100%",
                     "विभागणी 100% असली पाहिजे", 422,
                     {"total": body.yesh_pct + body.laxmi_pct})
    return create_with_audit(db, ModelFamilySplit(**body.model_dump()), user,
                             "model_family_splits")


# --- mills ---
class MillRead(_Read):
    id: int
    name: str
    lead_days: int | None
    moq_mt: Decimal | None
    sourcing: str | None


class MillUpsert(BaseModel):
    name: str
    lead_days: int | None = None
    moq_mt: Decimal | None = None
    sourcing: str | None = None


@router.get("/mills", response_model=list[MillRead])
def list_mills(db: Session = Depends(get_db), _: CurrentUser = Depends(read_guard)):
    return db.query(Mill).order_by(Mill.name).all()


@router.post("/mills", response_model=MillRead, status_code=201)
def create_mill(body: MillUpsert, db: Session = Depends(get_db),
                user: CurrentUser = Depends(write_guard)):
    return create_with_audit(db, Mill(**body.model_dump()), user, "mills")


@router.patch("/mills/{mill_id}", response_model=MillRead)
def update_mill(mill_id: int, body: MillUpsert, db: Session = Depends(get_db),
                user: CurrentUser = Depends(write_guard)):
    obj = get_or_404(db, Mill, mill_id, "mill")
    apply_update(db, obj, body.model_dump(exclude_unset=True), user, "mills",
                 allowed={"name", "lead_days", "moq_mt", "sourcing"})
    return obj


# --- tolerances (§11.7) ---
class ToleranceRead(_Read):
    id: int
    mat_group: str
    uom: str
    pct_tolerance: Decimal
    is_active: bool


class ToleranceCreate(BaseModel):
    mat_group: str
    uom: str
    pct_tolerance: Decimal


class ToleranceUpdate(BaseModel):
    pct_tolerance: Decimal | None = None
    is_active: bool | None = None


@router.get("/tolerances", response_model=list[ToleranceRead])
def list_tolerances(db: Session = Depends(get_db), _: CurrentUser = Depends(read_guard)):
    return db.query(MaterialGroupTolerance).order_by(
        MaterialGroupTolerance.mat_group).all()


@router.post("/tolerances", response_model=ToleranceRead, status_code=201)
def create_tolerance(body: ToleranceCreate, db: Session = Depends(get_db),
                     user: CurrentUser = Depends(write_guard)):
    return create_with_audit(db, MaterialGroupTolerance(**body.model_dump()), user,
                             "material_group_tolerances")


@router.patch("/tolerances/{tol_id}", response_model=ToleranceRead)
def update_tolerance(tol_id: int, body: ToleranceUpdate, db: Session = Depends(get_db),
                     user: CurrentUser = Depends(write_guard)):
    obj = get_or_404(db, MaterialGroupTolerance, tol_id, "tolerance")
    apply_update(db, obj, body.model_dump(exclude_unset=True), user,
                 "material_group_tolerances", allowed={"pct_tolerance", "is_active"})
    return obj


# --- calendar ---
class CalendarDay(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    cal_date: date
    is_working: bool
    shifts: dict | None = None


@router.get("/calendar", response_model=list[CalendarDay])
def get_calendar(month: str, db: Session = Depends(get_db),
                 _: CurrentUser = Depends(read_guard)):
    """month = YYYY-MM"""
    return (db.query(PlanCalendar)
            .filter(PlanCalendar.cal_date >= date.fromisoformat(f"{month}-01"))
            .filter(PlanCalendar.cal_date < _next_month(month))
            .order_by(PlanCalendar.cal_date).all())


def _next_month(month: str) -> date:
    y, m = int(month[:4]), int(month[5:7])
    return date(y + (m == 12), (m % 12) + 1, 1)


@router.put("/calendar", response_model=list[CalendarDay])
def put_calendar(days: list[CalendarDay], db: Session = Depends(get_db),
                 user: CurrentUser = Depends(write_guard)):
    """Bulk upsert — the admin screen saves a whole month at once."""
    changed = []
    for d in days:
        row = db.get(PlanCalendar, d.cal_date)
        if row is None:
            db.add(PlanCalendar(cal_date=d.cal_date, is_working=d.is_working,
                                shifts=d.shifts))
            changed.append(str(d.cal_date))
        elif row.is_working != d.is_working or row.shifts != d.shifts:
            row.is_working, row.shifts = d.is_working, d.shifts
            changed.append(str(d.cal_date))
    if changed:
        record(db, user_id=user.id, entity="plan_calendar", entity_id=0,
               action="update", before=None, after={"days_changed": changed})
    db.commit()
    return days


# --- app settings ---
class SettingRead(_Read):
    key: str
    value: dict
    description: str | None


class SettingPut(BaseModel):
    value: dict


@router.get("/settings", response_model=list[SettingRead])
def list_settings(db: Session = Depends(get_db), _: CurrentUser = Depends(read_guard)):
    return db.query(AppSetting).order_by(AppSetting.key).all()


@router.put("/settings/{key}", response_model=SettingRead)
def put_setting(key: str, body: SettingPut, db: Session = Depends(get_db),
                user: CurrentUser = Depends(write_guard)):
    """ops_mode lives here — switching parallel_run → authoritative is a BUSINESS
    decision (playbook §7 human checkpoint), the API just records who flipped it."""
    obj = db.get(AppSetting, key)
    from app.core.deps import _error
    if obj is None:
        raise _error("NOT_FOUND", f"setting {key} not found", "सापडले नाही", 404)
    if obj.value != body.value:
        record(db, user_id=user.id, entity="app_settings", entity_id=0,
               action="update", before={"key": key, "value": obj.value},
               after={"key": key, "value": body.value})
        obj.value = body.value
        obj.updated_by = user.id
    db.commit()
    return obj
