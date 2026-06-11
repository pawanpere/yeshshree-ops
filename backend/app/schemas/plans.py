"""Schedule + plan-view schemas (P11–P13). Decimal everywhere, never float
(CLAUDE.md invariant 9). The CSV row shape mirrors importers/schedule_csv.py —
both are PROVISIONAL until the real Bajaj sample arrives (Domain_QA Q1)."""
from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class _Read(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --- schedules ---
class ScheduleLineIn(BaseModel):
    """Manual JSON entry path (provisional — Domain_QA Q1). Identify the part by
    material_id OR sap_code; family drives the Yeshshree/Laxmi split."""
    material_id: int | None = None
    sap_code: str | None = None
    model_family: str
    bucket_date: date
    qty: Decimal = Field(gt=0)


class ScheduleCreate(BaseModel):
    customer_id: int
    period: str = Field(pattern=r"^\d{4}-\d{2}$")  # YYYY-MM
    lines: list[ScheduleLineIn]
    source_file_id: int | None = None


class ScheduleRead(_Read):
    id: int
    customer_id: int
    period: str
    version: int
    status: str
    source_file_id: int | None
    created_by: int
    released_by: int | None
    released_at: datetime | None


class ScheduleLineRead(_Read):
    id: int
    schedule_id: int
    model_family: str
    material_id: int | None
    bucket_date: date
    qty: Decimal


class ScheduleUploadResult(BaseModel):
    """Upload outcome: the created draft (when any row parsed) + EVERY row error."""
    schedule: ScheduleRead | None
    rows_ok: int
    row_errors: list[dict]


class DiffRead(BaseModel):
    schedule_id: int
    version: int
    diff: dict  # {vs_version, entries:[{model_family,material_id,bucket_date,old,new,delta}], totals}


class SanityRead(BaseModel):
    schedule_id: int
    version: int
    sanity: dict  # {checks:[{code,severity,message_en,message_mr,details}], checked_at}


class ReleaseRequest(BaseModel):
    confirm_warnings: bool = False  # §11.13: warns block until explicitly confirmed


class ReleaseReport(BaseModel):
    schedule_id: int
    version: int
    plans_created: int
    calloffs_created: int
    unmapped: list[dict]    # schedule lines whose material has no line_materials row
    no_vendor: list[dict]   # BOM components with no open PO → vendor unknown
    cloned_from_version: int | None = None  # set by re-release


# --- plan views (P13) ---
class PlanRow(BaseModel):
    """Frozen response shape: confirmed_* are placeholder zeros until the
    production packet joins confirmations; remaining = planned − confirmed_good."""
    plan_id: int
    plan_date: date
    line_id: int
    line_name: str
    material_id: int
    sap_code: str
    description: str
    revision: int
    planned_qty: Decimal
    confirmed_good: Decimal
    confirmed_reject: Decimal
    remaining: Decimal


class SupervisorRow(PlanRow):
    production_order_id: int | None
    sap_order_no: str | None


class PpcLine(BaseModel):
    line_id: int
    line_name: str
    plans: list[PlanRow]
