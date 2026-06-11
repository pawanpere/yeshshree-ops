"""Stock balances, ops_mode policy & SAP stock reconcile (P23).
Spec: Architecture §4.6 (stock_ledger/stock_balances), §11.1 (parallel-run policy,
ADJUST reconcile), ADR-003.

Decisions (documented per packet brief):
- `stock_balances` is computed by aggregate query here, not a DB VIEW: §4.6 says
  "balances are a view; materialize only if ever slow" — an aggregate over the small
  pilot ledger keeps SQLite verify-lite + Postgres identical with zero DDL.
- AT_VENDOR balances group by vendor; every other location groups vendor to NULL
  (the §4.6 view definition: "+ vendor for AT_VENDOR").
- days_of_cover: avg daily consumption = Σ|negative RM movements in the last 30 days|
  / 30 calendar days. No negative history (or zero) → None — never a fake number.
- check_stock NEVER blocks in parallel_run (CLAUDE.md invariant 11, ADR-003): callers
  post anyway and record the soft anomaly `stock_insufficient_warned`; in
  'authoritative' mode `blocking=True` and the caller aborts with STOCK_INSUFFICIENT.
- reconcile writes one ADJUST ledger row per drifted material×location (delta only,
  ref_type='import_job') + one audit.record each — never an UPDATE (invariant 2).
  Re-running the same snapshot produces zero adjustments (delta = 0) by construction.
- snapshot rows with unknown sap_code are counted as failed in the import job, never
  guessed — master data import owns creating materials.
"""
import datetime as dt
from decimal import Decimal

from sqlalchemy import case, func
from sqlalchemy.orm import Session

from app.core.audit import record
from app.core.deps import CurrentUser, _error
from app.importers import sap_stock
from app.models.config_tables import AppSetting
from app.models.inventory import StockLedger
from app.models.master import Material
from app.models.system import ImportJob
from app.services import files
from app.services.anomaly import to_decimal

QTY = Decimal("0.001")   # NUMERIC(14,3)
DAYS = Decimal("0.1")
CONSUMPTION_WINDOW_DAYS = 30


def balances(db: Session, material_id: int | None = None, location: str | None = None,
             vendor_id: int | None = None) -> list[dict]:
    """SUM(qty) grouped by (material, location[, vendor for AT_VENDOR]) — §4.6 view."""
    vend = case((StockLedger.location == "AT_VENDOR", StockLedger.vendor_id),
                else_=None).label("vendor_id")
    q = db.query(StockLedger.material_id, StockLedger.location, vend,
                 func.sum(StockLedger.qty).label("qty"))
    if material_id is not None:
        q = q.filter(StockLedger.material_id == material_id)
    if location is not None:
        q = q.filter(StockLedger.location == location)
    if vendor_id is not None:  # a vendor filter only ever means AT_VENDOR stock
        q = q.filter(StockLedger.location == "AT_VENDOR",
                     StockLedger.vendor_id == vendor_id)
    rows = (q.group_by(StockLedger.material_id, StockLedger.location, vend)
            .order_by(StockLedger.material_id, StockLedger.location).all())
    return [{"material_id": m, "location": loc, "vendor_id": v,
             "qty": to_decimal(qty or 0).quantize(QTY)}
            for m, loc, v, qty in rows]


def balance_qty(db: Session, material_id: int, location: str = "RM",
                vendor_id: int | None = None) -> Decimal:
    """Single (material, location[, vendor]) balance as a Decimal."""
    q = db.query(func.coalesce(func.sum(StockLedger.qty), 0)).filter(
        StockLedger.material_id == material_id, StockLedger.location == location)
    if vendor_id is not None:
        q = q.filter(StockLedger.vendor_id == vendor_id)
    return to_decimal(q.scalar() or 0).quantize(QTY)


def days_of_cover(db: Session, material_id: int) -> Decimal | None:
    """RM balance ÷ avg daily consumption (last 30 days of negative RM movements).
    No consumption history → None (never invent a cover number)."""
    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=CONSUMPTION_WINDOW_DAYS)
    consumed = db.query(func.coalesce(func.sum(-StockLedger.qty), 0)).filter(
        StockLedger.material_id == material_id,
        StockLedger.location == "RM",
        StockLedger.qty < 0,
        StockLedger.created_at >= cutoff,
    ).scalar()
    consumed = to_decimal(consumed or 0)
    if consumed <= 0:
        return None
    avg_daily = consumed / Decimal(CONSUMPTION_WINDOW_DAYS)
    return (balance_qty(db, material_id, "RM") / avg_daily).quantize(DAYS)


def ops_mode(db: Session) -> str:
    """app_settings['ops_mode'].mode — defaults to 'parallel_run' (ADR-003: the safe
    mode is the one that never blocks; authoritative is an explicit human decision)."""
    row = db.get(AppSetting, "ops_mode")
    if row and isinstance(row.value, dict) and row.value.get("mode") in (
            "parallel_run", "authoritative"):
        return row.value["mode"]
    return "parallel_run"


def check_stock(db: Session, material_id: int, qty: Decimal, location: str = "RM") -> dict:
    """§11.1 policy check. blocking=True ONLY when insufficient AND authoritative.
    In parallel_run the caller posts anyway and records the soft anomaly
    `stock_insufficient_warned` (invariant 11)."""
    bal = balance_qty(db, material_id, location)
    sufficient = bal >= to_decimal(qty)
    mode = ops_mode(db)
    return {
        "sufficient": sufficient,
        "balance": bal,
        "mode": mode,
        "blocking": (not sufficient) and mode == "authoritative",
    }


def reconcile_sap_stock(db: Session, rows: list[dict], import_job_id: int,
                        user_id: int) -> dict:
    """§11.1: diff SAP snapshot vs our balances per material(+location, default RM);
    drift → one ADJUST ledger row (qty=delta) — fully audited, never an UPDATE.
    Writes into the CALLER's transaction (caller commits). Returns counts."""
    adjustments, failed = 0, 0
    for row in rows:
        material = (db.query(Material)
                    .filter_by(sap_code=str(row["sap_code"])).one_or_none())
        if material is None:
            failed += 1
            continue
        location = row.get("location") or "RM"
        snapshot_qty = to_decimal(row["qty"]).quantize(QTY)
        current = balance_qty(db, material.id, location)
        delta = (snapshot_qty - current).quantize(QTY)
        if delta == 0:
            continue
        led = StockLedger(material_id=material.id, location=location, movement="ADJUST",
                          qty=delta, uom=material.uom, vendor_id=None,
                          ref_type="import_job", ref_id=import_job_id,
                          created_by=user_id)
        db.add(led)
        db.flush()
        record(db, user_id=user_id, entity="stock_ledger", entity_id=led.id,
               action="create", before=None,
               after={"movement": "ADJUST", "material_sap_code": material.sap_code,
                      "location": location, "delta": str(delta),
                      "snapshot_qty": str(snapshot_qty), "app_balance": str(current),
                      "import_job_id": import_job_id})
        adjustments += 1
    return {"adjustments": adjustments, "rows_failed": failed}


def import_sap_stock(db: Session, user: CurrentUser, *, content: bytes,
                     filename: str, mime: str | None) -> dict:
    """Upload → files row → import_jobs(kind='sap_stock') → reconcile, ONE transaction."""
    try:
        rows = sap_stock.parse_stock_snapshot(content)
    except ValueError as exc:
        raise _error("IMPORT_PARSE_FAILED",
                     f"Could not parse stock snapshot: {exc}",
                     "साठा स्नॅपशॉट फाइल वाचता आली नाही", 422, {"filename": filename})
    if not rows:
        raise _error("IMPORT_EMPTY", "No stock rows found in the file",
                     "फाइलमध्ये साठा नोंदी सापडल्या नाहीत", 422, {"filename": filename})
    file_row = files.save_file(db, content=content, filename=filename or "sap_stock",
                               kind="import", mime=mime, uploaded_by=user.id)
    job = ImportJob(kind="sap_stock", file_id=file_row.id, status="running",
                    created_by=user.id)
    db.add(job)
    db.flush()
    result = reconcile_sap_stock(db, rows, job.id, user.id)
    job.rows_total = len(rows)
    job.rows_failed = result["rows_failed"]
    job.rows_ok = len(rows) - result["rows_failed"]
    job.status = "completed"
    record(db, user_id=user.id, entity="import_jobs", entity_id=job.id, action="create",
           before=None, after={"kind": "sap_stock", "rows_total": job.rows_total,
                               "rows_ok": job.rows_ok, "rows_failed": job.rows_failed,
                               "adjustments": result["adjustments"]})
    db.commit()
    return {"import_job_id": job.id, "rows_total": job.rows_total,
            "rows_ok": job.rows_ok, "rows_failed": job.rows_failed,
            "adjustments": result["adjustments"]}
