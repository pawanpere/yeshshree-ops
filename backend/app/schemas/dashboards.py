"""Dashboard response schemas (P32+P35). Explicit fields — the generated Dart
client gets real types, not bags of Any. All quantities/money/percentages are
str (Decimal-as-string, CLAUDE.md invariant 9); pct fields are None when the
denominator is 0 (no plan / no production) so the UI can show '—'."""
import datetime as dt

from pydantic import BaseModel


# --- achievement ---
class ShiftSplit(BaseModel):
    good: str
    rejected: str


class TopDowntimeReason(BaseModel):
    reason_code: str | None   # None = legacy confirmation without a reason code
    label_en: str | None
    minutes: int


class AchievementLine(BaseModel):
    line_id: int
    line_name: str
    planned: str
    confirmed_good: str
    confirmed_rejected: str
    pct: str | None
    shifts: dict[str, ShiftSplit]   # keys 'A'/'B' (CHECK on shift_contexts)
    downtime_total_min: int
    top_downtime_reason: TopDowntimeReason | None


class AchievementTotals(BaseModel):
    planned: str
    confirmed_good: str
    confirmed_rejected: str
    pct: str | None


class AchievementOut(BaseModel):
    date: dt.date
    lines: list[AchievementLine]
    totals: AchievementTotals


# --- yield ---
class YieldRow(BaseModel):
    line_id: int
    line_name: str
    shift: str
    good: str
    rejected: str
    yield_pct: str | None


class RejectReason(BaseModel):
    reason_code: str | None
    label_en: str | None
    qty: str


class YieldOverall(BaseModel):
    good: str
    rejected: str
    yield_pct: str | None


class YieldOut(BaseModel):
    date: dt.date
    rows: list[YieldRow]
    reject_reasons: list[RejectReason]
    imputed_scrap_value: str   # PROXY: rejected x material.price (see service)
    overall: YieldOverall


# --- sales ---
class BilledBucket(BaseModel):
    pcs: str
    value: str


class SalesMaterialRow(BaseModel):
    material_id: int
    sap_code: str
    description: str
    today_pcs: str
    mtd_pcs: str
    mtd_value: str


class SalesOut(BaseModel):
    month: str
    billed_today: BilledBucket
    billed_mtd: BilledBucket
    materials: list[SalesMaterialRow]
    awaiting_invoice: int   # open dispatches not yet invoiced


# --- overview ---
class OpenAnomalies(BaseModel):
    total: int
    hard: int


class OutboxBacklog(BaseModel):
    pending: int
    failed: int


class OverviewOut(BaseModel):
    date: dt.date
    achievement_pct: str | None
    billed_today_value: str
    yield_pct: str | None
    open_anomalies: OpenAnomalies
    approvals_pending: int          # excludes override_review (own KPI below)
    open_override_reviews: int      # §11.2: overrides are never invisible
    unmatched_gate_entries: int
    outbox_backlog: OutboxBacklog
    holds_open: int
