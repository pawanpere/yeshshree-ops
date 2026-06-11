"""Schedules → release → line_plans + vendor_calloffs + plan read views (P11–P13).
Spec: Architecture §4.4 (tables), §11.13 (sanity + rollback-by-re-release), §6 routes.

⚠ PLAN MATH IS A DOCUMENTED PLACEHOLDER (Domain_QA.md Q1 ⛔): how Bajaj's schedule
maps to part numbers is unknown until the real sample file arrives. The cascade
below is written against the provisional row shape (part + family + date + qty) so
family-level vs part-level slots in either way once the sample lands:

    schedule line qty
      × yesh_pct/100 (latest model_family_splits row effective on the bucket date)
      → line_plans (line via line_materials mapping; unmapped parts reported, skipped)
      → BOM explode (bom_lines, scrap-credit lines skipped): component qty_per × planned
      → vendor = vendor of the LATEST open purchase_orders row for the component
        (no open PO → reported under 'no_vendor', skipped)
      → vendor_calloffs aggregated per (vendor, component, date)

Decisions (documented per packet brief):
- diff/sanity JSON store Decimals as strings (JSON columns can't hold Decimal).
- diff is computed vs the latest RELEASED version of the same (customer, period);
  no released predecessor → empty diff with vs_version null.
- SPLIT_MISSING checks the split's effective_from against the FAMILY'S FIRST
  (earliest) bucket date — if the earliest bucket is covered, all later ones are.
- revision is allocated per (plan_date, line_id): max existing revision + 1,
  superseded rows included, so history reads as a strict sequence (§11.13).
- a material mapped to several lines plans onto the LOWEST line id (deterministic);
  multi-line balancing is post-MVP.
- vendor_calloffs.status = 'released' (model declares no CHECK / default).
- superseding a schedule supersedes its still-active line_plans only; old
  vendor_calloffs rows stay as issued history (no status vocabulary for them yet).
"""
import datetime as dt
from decimal import Decimal

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.audit import record
from app.core.deps import CurrentUser, _error
from app.models.config_tables import ModelFamilySplit
from app.models.master import (Bom, BomLine, Customer, Line, LineMaterial, Material,
                               ProductionOrder, PurchaseOrder)
from app.models.planning import LinePlan, Schedule, ScheduleLine, VendorCalloff

QTY = Decimal("0.001")  # NUMERIC(14,3)


def _q(x: Decimal) -> str:
    return str(x.quantize(QTY))


# ---------------------------------------------------------------- create


def create_schedule(db: Session, user: CurrentUser, *, customer_id: int, period: str,
                    lines: list[dict], source_file_id: int | None = None) -> Schedule:
    """New draft version = max(version)+1 per (customer, period); lines stored;
    diff vs latest released version of the same period computed and stored."""
    if db.get(Customer, customer_id) is None:
        raise _error("NOT_FOUND", "Customer not found", "ग्राहक सापडला नाही", 404,
                     {"customer_id": customer_id})
    try:
        dt.date.fromisoformat(f"{period}-01")
    except ValueError:
        raise _error("BAD_PERIOD", "period must be YYYY-MM",
                     "कालावधी YYYY-MM असावा", 422, {"period": period})
    if not lines:
        raise _error("NO_LINES", "Schedule has no lines",
                     "वेळापत्रकात ओळी नाहीत", 422, {})

    resolved, unknown = [], []
    for ln in lines:
        material_id = ln.get("material_id")
        if material_id is None and ln.get("sap_code"):
            mat = db.query(Material).filter_by(sap_code=ln["sap_code"]).one_or_none()
            if mat is None:
                unknown.append(ln["sap_code"])
                continue
            material_id = mat.id
        elif material_id is not None and db.get(Material, material_id) is None:
            unknown.append(str(material_id))
            continue
        bucket = ln["bucket_date"]
        if isinstance(bucket, str):
            bucket = dt.date.fromisoformat(bucket)
        resolved.append({"material_id": material_id, "model_family": ln["model_family"],
                         "bucket_date": bucket, "qty": Decimal(str(ln["qty"]))})
    if unknown:
        raise _error("MATERIAL_UNKNOWN", f"Unknown materials: {', '.join(unknown)}",
                     "अज्ञात सामग्री", 422, {"sap_codes": unknown})

    version = (db.query(func.max(Schedule.version))
               .filter_by(customer_id=customer_id, period=period).scalar() or 0) + 1
    schedule = Schedule(customer_id=customer_id, period=period, version=version,
                        status="draft", source_file_id=source_file_id, diff={},
                        created_by=user.id)
    db.add(schedule)
    db.flush()
    for r in resolved:
        db.add(ScheduleLine(schedule_id=schedule.id, model_family=r["model_family"],
                            material_id=r["material_id"], bucket_date=r["bucket_date"],
                            qty=r["qty"]))
    db.flush()
    schedule.diff = _compute_diff(db, schedule)
    schedule.sanity = sanity_checks(db, schedule)
    record(db, user_id=user.id, entity="schedules", entity_id=schedule.id,
           action="create", before=None,
           after={"period": period, "version": version, "lines": len(resolved)})
    db.commit()
    db.refresh(schedule)
    return schedule


def _latest_released(db: Session, schedule: Schedule) -> Schedule | None:
    return (db.query(Schedule)
            .filter_by(customer_id=schedule.customer_id, period=schedule.period,
                       status="released")
            .filter(Schedule.id != schedule.id)
            .order_by(Schedule.version.desc()).first())


def _line_key_map(db: Session, schedule_id: int) -> dict[tuple, Decimal]:
    """(family, material_id, iso date) → summed qty for a schedule's lines."""
    out: dict[tuple, Decimal] = {}
    for ln in db.query(ScheduleLine).filter_by(schedule_id=schedule_id):
        key = (ln.model_family, ln.material_id, ln.bucket_date.isoformat())
        out[key] = out.get(key, Decimal("0")) + ln.qty
    return out


def _compute_diff(db: Session, schedule: Schedule) -> dict:
    """Per (family, material, date): old/new/delta vs the latest released version
    of the same period, plus totals. Empty entries when no released predecessor."""
    prev = _latest_released(db, schedule)
    new_map = _line_key_map(db, schedule.id)
    old_map = _line_key_map(db, prev.id) if prev else {}
    entries = []
    for key in sorted(set(new_map) | set(old_map)) if prev else []:
        old = old_map.get(key, Decimal("0"))
        new = new_map.get(key, Decimal("0"))
        if old == new:
            continue  # only changed cells make the diff; no baseline → empty diff
        family, material_id, date_s = key
        entries.append({"model_family": family, "material_id": material_id,
                        "bucket_date": date_s,
                        "old": _q(old), "new": _q(new), "delta": _q(new - old)})
    old_total = sum(old_map.values(), Decimal("0"))
    new_total = sum(new_map.values(), Decimal("0"))
    return {"vs_version": prev.version if prev else None, "entries": entries,
            "totals": {"old": _q(old_total), "new": _q(new_total),
                       "delta": _q(new_total - old_total)}}


# ---------------------------------------------------------------- sanity (§11.13)


def sanity_checks(db: Session, schedule: Schedule) -> dict:
    """§11.13 release sanity list, stored in schedules.sanity. Severities:
    'warn' needs confirm_warnings on release; 'hard' always blocks."""
    checks: list[dict] = []
    current_month = dt.date.today().strftime("%Y-%m")
    if schedule.period != current_month:
        checks.append({"code": "PERIOD_MISMATCH", "severity": "warn",
                       "message_en": f"Schedule period {schedule.period} is not the "
                                     f"current month {current_month}",
                       "message_mr": f"वेळापत्रक कालावधी {schedule.period} चालू महिना नाही",
                       "details": {"period": schedule.period, "current": current_month}})

    new_total = sum(_line_key_map(db, schedule.id).values(), Decimal("0"))
    prev = _latest_released(db, schedule)
    if prev is not None:
        old_total = sum(_line_key_map(db, prev.id).values(), Decimal("0"))
        if old_total > 0 and not (old_total / 2 <= new_total <= old_total * 3 / 2):
            checks.append({"code": "TOTAL_SWING", "severity": "warn",
                           "message_en": f"Total qty {new_total} is outside ±50% of "
                                         f"released v{prev.version} total {old_total}",
                           "message_mr": "एकूण संख्या मागील आवृत्तीच्या ±50% बाहेर आहे",
                           "details": {"old_total": _q(old_total),
                                       "new_total": _q(new_total),
                                       "vs_version": prev.version}})

    # SPLIT_MISSING: hard stop, names the family + config owner deep-link (§11.13).
    first_bucket: dict[str, dt.date] = {}
    for ln in db.query(ScheduleLine).filter_by(schedule_id=schedule.id):
        if ln.model_family not in first_bucket or ln.bucket_date < first_bucket[ln.model_family]:
            first_bucket[ln.model_family] = ln.bucket_date
    for family, first_date in sorted(first_bucket.items()):
        split = (db.query(ModelFamilySplit)
                 .filter(ModelFamilySplit.family == family,
                         ModelFamilySplit.effective_from <= first_date)
                 .order_by(ModelFamilySplit.effective_from.desc()).first())
        if split is None:
            checks.append({"code": "SPLIT_MISSING", "severity": "hard",
                           "message_en": f"Model family '{family}' has no applicable "
                                         f"Yeshshree/Laxmi split on {first_date} — "
                                         f"add one in Config → Splits (admin/planning)",
                           "message_mr": f"'{family}' साठी विभागणी कॉन्फिगर केलेली नाही — "
                                         f"कॉन्फिग → स्प्लिट्समध्ये जोडा",
                           "details": {"family": family,
                                       "first_bucket_date": first_date.isoformat(),
                                       "config_link": "/config/splits"}})
    return {"checks": checks, "checked_at": dt.datetime.now(dt.timezone.utc).isoformat()}


# ---------------------------------------------------------------- release


def _split_pct(db: Session, family: str, on_date: dt.date) -> Decimal | None:
    split = (db.query(ModelFamilySplit)
             .filter(ModelFamilySplit.family == family,
                     ModelFamilySplit.effective_from <= on_date)
             .order_by(ModelFamilySplit.effective_from.desc()).first())
    return Decimal(split.yesh_pct) if split else None


def release(db: Session, user: CurrentUser, schedule_id: int,
            confirm_warnings: bool = False) -> dict:
    """§11.13: sanity → (422 on hard / unconfirmed warn) → supersede prior release
    → plan math → calloff explosion. Returns the release report."""
    schedule = db.get(Schedule, schedule_id)
    if schedule is None:
        raise _error("NOT_FOUND", "Schedule not found", "वेळापत्रक सापडले नाही", 404,
                     {"schedule_id": schedule_id})
    if schedule.status != "draft":
        raise _error("SCHEDULE_NOT_DRAFT",
                     f"Only draft schedules can be released (status={schedule.status}); "
                     f"use re-release to roll back",
                     "फक्त मसुदा वेळापत्रक प्रसिद्ध करता येते", 422,
                     {"status": schedule.status})

    schedule.sanity = sanity_checks(db, schedule)
    checks = schedule.sanity["checks"]
    hards = [c for c in checks if c["severity"] == "hard"]
    if hards:
        db.commit()  # persist the sanity verdict even on refusal
        first = hards[0]
        raise _error(first["code"], first["message_en"], first["message_mr"], 422,
                     {"checks": hards})
    warns = [c for c in checks if c["severity"] == "warn"]
    if warns and not confirm_warnings:
        db.commit()
        raise _error("RELEASE_WARNINGS",
                     "Release has warnings — confirm to proceed",
                     "प्रसिद्धीसाठी चेतावण्या आहेत — पुष्टी करा", 422,
                     {"checks": warns})

    # Supersede the prior released version of this period + its active plans (§11.13).
    prior = _latest_released(db, schedule)
    if prior is not None:
        prior.status = "superseded"
        (db.query(LinePlan)
         .filter_by(schedule_id=prior.id, status="active")
         .update({"status": "superseded"}))

    report = _generate_plans(db, schedule)

    schedule.status = "released"
    schedule.released_by = user.id
    schedule.released_at = dt.datetime.now(dt.timezone.utc)
    record(db, user_id=user.id, entity="schedules", entity_id=schedule.id,
           action="status_change", before={"status": "draft"},
           after={"status": "released", "superseded_version":
                  prior.version if prior else None, **{k: report[k] for k in
                  ("plans_created", "calloffs_created")}})
    db.commit()
    return {"schedule_id": schedule.id, "version": schedule.version, **report}


def _generate_plans(db: Session, schedule: Schedule) -> dict:
    """PLACEHOLDER plan math (module docstring; Domain_QA Q1). Runs inside the
    caller's transaction — commits belong to release()."""
    unmapped: list[dict] = []
    no_vendor: list[dict] = []

    # 1. split math + line mapping, aggregated per (line, material, date)
    planned: dict[tuple[int, int, dt.date], Decimal] = {}
    for ln in db.query(ScheduleLine).filter_by(schedule_id=schedule.id):
        pct = _split_pct(db, ln.model_family, ln.bucket_date)
        if pct is None:  # unreachable after sanity hard-stop; belt and braces
            raise _error("SPLIT_MISSING", f"No split for {ln.model_family}",
                         "विभागणी सापडली नाही", 422, {"family": ln.model_family})
        yesh_qty = (ln.qty * pct / Decimal("100")).quantize(QTY)
        mapping = (db.query(LineMaterial)
                   .filter_by(material_id=ln.material_id)
                   .order_by(LineMaterial.line_id).first()) if ln.material_id else None
        if mapping is None:
            mat = db.get(Material, ln.material_id) if ln.material_id else None
            unmapped.append({"material_id": ln.material_id,
                             "sap_code": mat.sap_code if mat else None,
                             "model_family": ln.model_family,
                             "bucket_date": ln.bucket_date.isoformat(),
                             "qty": _q(ln.qty)})
            continue
        key = (mapping.line_id, ln.material_id, ln.bucket_date)
        planned[key] = planned.get(key, Decimal("0")) + yesh_qty

    # 2. line_plans with per-(date,line) revision sequence
    revisions: dict[tuple[dt.date, int], int] = {}
    for (line_id, material_id, plan_date), qty in sorted(
            planned.items(), key=lambda kv: (kv[0][2], kv[0][0], kv[0][1])):
        rkey = (plan_date, line_id)
        if rkey not in revisions:
            revisions[rkey] = (db.query(func.max(LinePlan.revision))
                               .filter_by(plan_date=plan_date, line_id=line_id)
                               .scalar() or 0) + 1
        db.add(LinePlan(plan_date=plan_date, line_id=line_id, material_id=material_id,
                        planned_qty=qty, schedule_id=schedule.id,
                        revision=revisions[rkey], status="active"))

    # 3. BOM explosion → vendor calloffs, aggregated per (vendor, component, date)
    calloffs: dict[tuple[int, int, dt.date], Decimal] = {}
    for (line_id, material_id, plan_date), qty in planned.items():
        bom = (db.query(Bom).filter_by(parent_material_id=material_id, is_active=True)
               .order_by(Bom.id).first())
        if bom is None:
            continue  # no BOM → nothing to call off (parent may be bought-out)
        for bl in db.query(BomLine).filter_by(bom_id=bom.id):
            if bl.is_scrap_credit:
                continue
            po = (db.query(PurchaseOrder)
                  .filter_by(material_id=bl.component_material_id, status="open")
                  .order_by(PurchaseOrder.id.desc()).first())
            if po is None:
                comp = db.get(Material, bl.component_material_id)
                entry = {"material_id": bl.component_material_id,
                         "sap_code": comp.sap_code if comp else None,
                         "calloff_date": plan_date.isoformat(),
                         "qty": _q(bl.qty_per * qty)}
                if entry not in no_vendor:
                    no_vendor.append(entry)
                continue
            ckey = (po.vendor_id, bl.component_material_id, plan_date)
            calloffs[ckey] = calloffs.get(ckey, Decimal("0")) + \
                (bl.qty_per * qty).quantize(QTY)
    for (vendor_id, component_id, calloff_date), qty in sorted(
            calloffs.items(), key=lambda kv: (kv[0][2], kv[0][0], kv[0][1])):
        db.add(VendorCalloff(vendor_id=vendor_id, material_id=component_id,
                             calloff_date=calloff_date, qty=qty,
                             schedule_id=schedule.id, status="released"))

    return {"plans_created": len(planned), "calloffs_created": len(calloffs),
            "unmapped": unmapped, "no_vendor": no_vendor}


def re_release(db: Session, user: CurrentUser, schedule_id: int) -> dict:
    """§11.13 rollback-by-re-release: clone an old version's lines as a NEW draft
    version, then release it (warnings auto-confirmed — the planner explicitly chose
    this rollback). Nothing is ever deleted; the bad release stays in history."""
    source = db.get(Schedule, schedule_id)
    if source is None:
        raise _error("NOT_FOUND", "Schedule not found", "वेळापत्रक सापडले नाही", 404,
                     {"schedule_id": schedule_id})
    if source.status not in ("released", "superseded"):
        raise _error("RE_RELEASE_SOURCE_INVALID",
                     "Only a released or superseded version can be re-released",
                     "फक्त प्रसिद्ध/अधिक्रमित आवृत्ती पुन्हा प्रसिद्ध करता येते", 422,
                     {"status": source.status})
    lines = [{"material_id": ln.material_id, "model_family": ln.model_family,
              "bucket_date": ln.bucket_date, "qty": ln.qty}
             for ln in db.query(ScheduleLine).filter_by(schedule_id=source.id)]
    clone = create_schedule(db, user, customer_id=source.customer_id,
                            period=source.period, lines=lines,
                            source_file_id=source.source_file_id)
    record(db, user_id=user.id, entity="schedules", entity_id=clone.id,
           action="create", before=None,
           after={"re_release_of": source.id, "source_version": source.version})
    report = release(db, user, clone.id, confirm_warnings=True)
    return {"cloned_from_version": source.version, **report}


# ---------------------------------------------------------------- plan views (P13)


def _plan_rows(db: Session, on_date: dt.date, line_id: int | None) -> list[dict]:
    """Active-revision rows for a date, with LIVE confirmed totals from the
    production module (wired at M3/M4 integration; lazy import avoids a cycle)."""
    from app.services.production import confirmed_totals
    q = (db.query(LinePlan, Material, Line)
         .join(Material, Material.id == LinePlan.material_id)
         .join(Line, Line.id == LinePlan.line_id)
         .filter(LinePlan.plan_date == on_date, LinePlan.status == "active"))
    if line_id is not None:
        q = q.filter(LinePlan.line_id == line_id)
    rows = []
    totals_cache: dict[int, dict] = {}
    for plan, mat, line in q.order_by(LinePlan.line_id, Material.sap_code):
        if line.id not in totals_cache:
            totals_cache[line.id] = confirmed_totals(db, line.id, on_date)
        t = totals_cache[line.id].get(mat.id) or {}
        confirmed_good = Decimal(str(t.get("good", 0)))
        confirmed_reject = Decimal(str(t.get("rejected", 0)))
        rows.append({
            "plan_id": plan.id, "plan_date": plan.plan_date, "line_id": line.id,
            "line_name": line.name, "material_id": mat.id, "sap_code": mat.sap_code,
            "description": mat.description, "revision": plan.revision,
            "planned_qty": plan.planned_qty,
            "confirmed_good": confirmed_good, "confirmed_reject": confirmed_reject,
            "remaining": plan.planned_qty - confirmed_good,
        })
    return rows


def line_plans(db: Session, on_date: dt.date, line_id: int | None = None) -> list[dict]:
    return _plan_rows(db, on_date, line_id)


def ppc_view(db: Session, on_date: dt.date) -> list[dict]:
    """All lines for the date, grouped per line — the PPC wall view."""
    by_line: dict[int, dict] = {}
    for row in _plan_rows(db, on_date, None):
        grp = by_line.setdefault(row["line_id"], {
            "line_id": row["line_id"], "line_name": row["line_name"], "plans": []})
        grp["plans"].append(row)
    return list(by_line.values())


def supervisor_view(db: Session, line_id: int, on_date: dt.date) -> list[dict]:
    """Parts on one line + the SAP production order the confirmation will resolve
    against (Domain_QA Q3: stable order per part/month)."""
    rows = _plan_rows(db, on_date, line_id)
    for row in rows:
        order = (db.query(ProductionOrder)
                 .filter_by(line_id=line_id, material_id=row["material_id"])
                 .order_by(ProductionOrder.id.desc()).first())
        row["production_order_id"] = order.id if order else None
        row["sap_order_no"] = order.sap_order_no if order else None
    return rows
