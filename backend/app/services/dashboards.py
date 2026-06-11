"""Dashboard aggregate queries (P32+P35). Spec: Architecture §5.8.

READ-ONLY: pure query functions returning plain dicts; no writes, no commits.
Every number is traceable to rows: confirmations are fetched and summed in
Python (pilot volumes are tiny — §5.8), so a wrong KPI can be debugged by
printing the rows that fed it. Decimals are serialized as str (never float).

Date attribution for confirmations: prefer ShiftContext.shift_date (the shift
the supervisor opened — §11.10); fall back to posted_at::date only for legacy
rows with shift_context_id IS NULL. Caveat: posted_at is timestamptz, so the
fallback date is the UTC date, not IST — acceptable for the rare fallback row.

Known proxies / decisions (documented, not hidden):
- imputed_scrap_value uses rejected_qty x material.price (finished-part price).
  TRUE scrap value needs BOM steel content x RM price (§5.8 mentions BOM) —
  that is the yield-engine's job (post-MVP §8); price-proxy is the MVP stand-in.
  Materials with price NULL contribute 0 (flagged via 'unpriced' reason rows).
- Confirmation base quantities count rows in any status ('posted' AND
  'corrected'): corrections are delta rows (invariant 6), the original keeps
  its base qty. Correction deltas are NOT folded in at MVP.
- approvals_pending EXCLUDES approval_type='override_review' — those get their
  own KPI (open_override_reviews, §11.2: overrides are never invisible).
- open_anomalies counts status IN ('open','in_review') — both still need action.
- unmatched_gate_entries: match_status='unmatched' AND status='open'
  (gr_done/cancelled entries are no longer actionable).
- sales() 'today' = server date (date.today()); billed values are summed from
  sales_invoice_lines (line-level truth), not the header total_value.
"""
import datetime as dt
from collections import defaultdict
from decimal import Decimal

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.config_tables import ReasonCode
from app.models.gate import GateEntry
from app.models.master import Line, Material
from app.models.outbound import Dispatch, SalesInvoice, SalesInvoiceLine
from app.models.planning import LinePlan
from app.models.production import ConfirmationHold, ProductionConfirmation, ShiftContext
from app.models.system import SapOutbox
from app.models.workflow import Anomaly, Approval

ZERO = Decimal("0")


def _pct(num: Decimal, den: Decimal) -> str | None:
    """num/den as percentage, 2 dp, str. None when denominator is 0 (no plan /
    no production) — the UI shows '—', never a fake 0%."""
    if not den:
        return None
    return str((num / den * 100).quantize(Decimal("0.01")))


def _money(v: Decimal) -> str:
    return str(v.quantize(Decimal("0.01")))


def _confirmations_for(db: Session, on_date: dt.date) -> list[ProductionConfirmation]:
    """All confirmations attributed to on_date (shift_date preferred — see header)."""
    conf_date = func.coalesce(ShiftContext.shift_date,
                              func.date(ProductionConfirmation.posted_at))
    return (
        db.query(ProductionConfirmation)
        .outerjoin(ShiftContext,
                   ProductionConfirmation.shift_context_id == ShiftContext.id)
        .filter(conf_date == on_date)
        .order_by(ProductionConfirmation.id)
        .all()
    )


def _line_names(db: Session, line_ids: set[int]) -> dict[int, str]:
    if not line_ids:
        return {}
    rows = db.query(Line.id, Line.name).filter(Line.id.in_(line_ids)).all()
    return dict(rows)


def _reason_labels(db: Session, reason_ids: set[int]) -> dict[int, ReasonCode]:
    if not reason_ids:
        return {}
    rows = db.query(ReasonCode).filter(ReasonCode.id.in_(reason_ids)).all()
    return {r.id: r for r in rows}


# --- achievement -------------------------------------------------------------

def achievement(db: Session, on_date: dt.date) -> dict:
    """Per line: planned (active line_plans) vs confirmed good/rejected, pct,
    per-shift split, downtime total + top downtime reason. §5.8."""
    plans = (db.query(LinePlan)
             .filter(LinePlan.plan_date == on_date, LinePlan.status == "active")
             .all())
    confs = _confirmations_for(db, on_date)

    planned: dict[int, Decimal] = defaultdict(lambda: ZERO)
    for p in plans:
        planned[p.line_id] += p.planned_qty

    good: dict[int, Decimal] = defaultdict(lambda: ZERO)
    rej: dict[int, Decimal] = defaultdict(lambda: ZERO)
    shifts: dict[int, dict[str, dict[str, Decimal]]] = defaultdict(
        lambda: {"A": {"good": ZERO, "rejected": ZERO},
                 "B": {"good": ZERO, "rejected": ZERO}})
    downtime: dict[int, int] = defaultdict(int)
    # (line_id, downtime_reason_id) -> minutes, for the per-line top reason
    dt_by_reason: dict[int, dict[int, int]] = defaultdict(lambda: defaultdict(int))
    for c in confs:
        good[c.line_id] += c.good_qty
        rej[c.line_id] += c.rejected_qty
        shifts[c.line_id][c.shift]["good"] += c.good_qty
        shifts[c.line_id][c.shift]["rejected"] += c.rejected_qty
        downtime[c.line_id] += c.downtime_min
        if c.downtime_min and c.downtime_reason_id is not None:
            dt_by_reason[c.line_id][c.downtime_reason_id] += c.downtime_min

    line_ids = set(planned) | set(good)
    names = _line_names(db, line_ids)
    reasons = _reason_labels(
        db, {rid for per_line in dt_by_reason.values() for rid in per_line})

    lines = []
    for lid in sorted(line_ids):
        top = None
        if dt_by_reason.get(lid):
            rid, minutes = max(dt_by_reason[lid].items(),
                               key=lambda kv: (kv[1], -kv[0]))
            rc = reasons.get(rid)
            top = {"reason_code": rc.code if rc else None,
                   "label_en": rc.label_en if rc else None,
                   "minutes": minutes}
        lines.append({
            "line_id": lid,
            "line_name": names.get(lid, ""),
            "planned": str(planned[lid]),
            "confirmed_good": str(good[lid]),
            "confirmed_rejected": str(rej[lid]),
            "pct": _pct(good[lid], planned[lid]),
            "shifts": {s: {"good": str(v["good"]), "rejected": str(v["rejected"])}
                       for s, v in shifts[lid].items()},
            "downtime_total_min": downtime[lid],
            "top_downtime_reason": top,
        })

    tot_planned = sum(planned.values(), ZERO)
    tot_good = sum(good.values(), ZERO)
    tot_rej = sum(rej.values(), ZERO)
    return {
        "date": on_date,
        "lines": lines,
        "totals": {
            "planned": str(tot_planned),
            "confirmed_good": str(tot_good),
            "confirmed_rejected": str(tot_rej),
            "pct": _pct(tot_good, tot_planned),
        },
    }


# --- yield -------------------------------------------------------------------

def yield_report(db: Session, on_date: dt.date) -> dict:
    """Good vs rejected per line+shift, reject-reason breakdown, imputed scrap
    value (price proxy — see module header). §5.8."""
    confs = _confirmations_for(db, on_date)

    by_ls: dict[tuple[int, str], dict[str, Decimal]] = defaultdict(
        lambda: {"good": ZERO, "rejected": ZERO})
    rej_by_reason: dict[int | None, Decimal] = defaultdict(lambda: ZERO)
    rej_by_material: dict[int, Decimal] = defaultdict(lambda: ZERO)
    for c in confs:
        agg = by_ls[(c.line_id, c.shift)]
        agg["good"] += c.good_qty
        agg["rejected"] += c.rejected_qty
        if c.rejected_qty:
            rej_by_reason[c.reject_reason_id] += c.rejected_qty
            rej_by_material[c.material_id] += c.rejected_qty

    names = _line_names(db, {lid for lid, _ in by_ls})
    reasons = _reason_labels(db, {rid for rid in rej_by_reason if rid is not None})

    rows = []
    for (lid, shift) in sorted(by_ls):
        agg = by_ls[(lid, shift)]
        rows.append({
            "line_id": lid,
            "line_name": names.get(lid, ""),
            "shift": shift,
            "good": str(agg["good"]),
            "rejected": str(agg["rejected"]),
            "yield_pct": _pct(agg["good"], agg["good"] + agg["rejected"]),
        })

    reject_reasons = []
    for rid in sorted(rej_by_reason, key=lambda r: (r is None, r)):
        rc = reasons.get(rid) if rid is not None else None
        reject_reasons.append({
            "reason_code": rc.code if rc else None,   # None = legacy row w/o reason
            "label_en": rc.label_en if rc else None,
            "qty": str(rej_by_reason[rid]),
        })
    reject_reasons.sort(key=lambda r: Decimal(r["qty"]), reverse=True)

    # Imputed scrap value: rejected x material price. PROXY — see module header.
    prices: dict[int, Decimal | None] = dict(
        db.query(Material.id, Material.price)
        .filter(Material.id.in_(rej_by_material or {0})).all())
    scrap_value = sum(
        (qty * (prices.get(mid) or ZERO) for mid, qty in rej_by_material.items()),
        ZERO)

    tot_good = sum((a["good"] for a in by_ls.values()), ZERO)
    tot_rej = sum((a["rejected"] for a in by_ls.values()), ZERO)
    return {
        "date": on_date,
        "rows": rows,
        "reject_reasons": reject_reasons,
        "imputed_scrap_value": _money(scrap_value),
        "overall": {
            "good": str(tot_good),
            "rejected": str(tot_rej),
            "yield_pct": _pct(tot_good, tot_good + tot_rej),
        },
    }


# --- sales -------------------------------------------------------------------

def sales(db: Session, month: str) -> dict:
    """Billed today + MTD from CONFIRMED sales invoices, per-material rows,
    open-dispatch backlog. month = 'YYYY-MM'; 'today' = server date. §5.8."""
    year, mon = int(month[:4]), int(month[5:7])
    start = dt.date(year, mon, 1)
    end = dt.date(year + 1, 1, 1) if mon == 12 else dt.date(year, mon + 1, 1)
    today = dt.date.today()

    rows = (
        db.query(SalesInvoiceLine, SalesInvoice.invoice_date)
        .join(SalesInvoice, SalesInvoiceLine.invoice_id == SalesInvoice.id)
        .filter(SalesInvoice.status == "confirmed",
                SalesInvoice.invoice_date >= start,
                SalesInvoice.invoice_date < end)
        .order_by(SalesInvoiceLine.id)
        .all()
    )

    today_pcs = mtd_pcs = today_val = mtd_val = ZERO
    per_mat: dict[int, dict[str, Decimal]] = defaultdict(
        lambda: {"today_pcs": ZERO, "mtd_pcs": ZERO, "mtd_value": ZERO})
    for line, inv_date in rows:
        m = per_mat[line.material_id]
        m["mtd_pcs"] += line.qty
        m["mtd_value"] += line.value
        mtd_pcs += line.qty
        mtd_val += line.value
        if inv_date == today:
            m["today_pcs"] += line.qty
            today_pcs += line.qty
            today_val += line.value

    mats = {m.id: m for m in db.query(Material)
            .filter(Material.id.in_(per_mat or {0})).all()}
    materials = [{
        "material_id": mid,
        "sap_code": mats[mid].sap_code if mid in mats else "",
        "description": mats[mid].description if mid in mats else "",
        "today_pcs": str(agg["today_pcs"]),
        "mtd_pcs": str(agg["mtd_pcs"]),
        "mtd_value": _money(agg["mtd_value"]),
    } for mid, agg in sorted(per_mat.items())]

    awaiting = (db.query(func.count(Dispatch.id))
                .filter(Dispatch.status == "open").scalar() or 0)
    return {
        "month": month,
        "billed_today": {"pcs": str(today_pcs), "value": _money(today_val)},
        "billed_mtd": {"pcs": str(mtd_pcs), "value": _money(mtd_val)},
        "materials": materials,
        "awaiting_invoice": int(awaiting),
    }


# --- overview ----------------------------------------------------------------

def overview(db: Session, on_date: dt.date) -> dict:
    """One-screen management KPIs. Reuses achievement/yield so the headline
    numbers can never disagree with the detail dashboards. §5.8 + §11.2."""
    ach = achievement(db, on_date)
    yld = yield_report(db, on_date)

    billed_rows = (
        db.query(SalesInvoiceLine.value)
        .join(SalesInvoice, SalesInvoiceLine.invoice_id == SalesInvoice.id)
        .filter(SalesInvoice.status == "confirmed",
                SalesInvoice.invoice_date == on_date)
        .all()
    )
    billed_today_value = sum((v for (v,) in billed_rows), ZERO)

    open_states = ("open", "in_review")
    anomalies_total = (db.query(func.count(Anomaly.id))
                       .filter(Anomaly.status.in_(open_states)).scalar() or 0)
    anomalies_hard = (db.query(func.count(Anomaly.id))
                      .filter(Anomaly.status.in_(open_states),
                              Anomaly.severity == "hard").scalar() or 0)
    approvals_pending = (db.query(func.count(Approval.id))
                         .filter(Approval.status == "pending",
                                 Approval.approval_type != "override_review")
                         .scalar() or 0)
    override_reviews = (db.query(func.count(Approval.id))
                        .filter(Approval.status == "pending",
                                Approval.approval_type == "override_review")
                        .scalar() or 0)
    unmatched = (db.query(func.count(GateEntry.id))
                 .filter(GateEntry.match_status == "unmatched",
                         GateEntry.status == "open").scalar() or 0)
    outbox_pending = (db.query(func.count(SapOutbox.id))
                      .filter(SapOutbox.status == "pending").scalar() or 0)
    outbox_failed = (db.query(func.count(SapOutbox.id))
                     .filter(SapOutbox.status == "failed").scalar() or 0)
    holds_open = (db.query(func.count(ConfirmationHold.id))
                  .filter(ConfirmationHold.status == "open").scalar() or 0)

    return {
        "date": on_date,
        "achievement_pct": ach["totals"]["pct"],
        "billed_today_value": _money(billed_today_value),
        "yield_pct": yld["overall"]["yield_pct"],
        "open_anomalies": {"total": int(anomalies_total), "hard": int(anomalies_hard)},
        "approvals_pending": int(approvals_pending),
        "open_override_reviews": int(override_reviews),
        "unmatched_gate_entries": int(unmatched),
        "outbox_backlog": {"pending": int(outbox_pending), "failed": int(outbox_failed)},
        "holds_open": int(holds_open),
    }
