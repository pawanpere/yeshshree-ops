"""Production confirmations + shift contexts + PPC hold queue + corrections
(P29/P30/P31). Spec: Architecture §4.7, §5.3, §11.10, §11.11; Domain_QA Q13–15
(phone confirmations replace the 3-hourly PC batch; SAP stays the source of truth —
every confirmation gets a frozen CONFIRMATION outbox row in the same transaction).

Decisions (documented per packet brief):
- PLAN PINNING (§11.10): the shift context is created on the FIRST confirmation (or
  hold) of (line, shift_date, shift), pinning plan_revision = max ACTIVE line_plans
  revision for (line, date) at that moment (0 when no plan exists). Plan validation
  reads rows at revision == pinned regardless of status — a mid-shift release marks
  them 'superseded' but the pinned revision still governs the open shift; fallback is
  the latest revision <= pinned (covers a pin taken between partial regenerations).
- EXCEED RULE: planned > 0 and cumulative(good+rejected, this context+material,
  incl. this post) > planned × (1 + plan_exceed_pct/100) → hard 422
  CONFIRMATION_EXCEEDS_PLAN. plan_exceed_pct comes from
  app_settings['anomaly_thresholds']['plan_exceed_pct'], default 20. planned == 0
  (no plan row) never blocks — unplanned work is honest work (Domain_QA Q14).
- ORDER RESOLUTION: latest production_orders row for (line, material). None → 409
  CONFIRMATION_NEEDS_ORDER, details explain the hold path (§11.11) — nothing posted.
- BACKFLUSH: PROD_IN at FG for good_qty + one PROD_CONSUME per non-scrap-credit BOM
  line of the material's active BOM (qty = -(qty_per × good), location RM). good == 0
  writes no stock rows (no zero-movements in the ledger).
- HOLD NOTIFICATION (§11.11): blocker to every active user with role='planning' OR
  station='ppc' — there is no dedicated PPC role in §4.1; planning owns the queue and
  station='ppc' covers the PPC wall device login.
- RESOLVE IDEMPOTENCY: the confirmation posted from a hold reuses the HOLD's
  client_ref (the original POST /confirmations 409'd, so its client_ref was never
  persisted; the hold body's client_ref is the surviving unique handle). Re-running
  resolve replays the same confirmation and re-flips the hold — self-healing.
- AUTO CLOSE (§11.10): shift end parsed from plan_calendar.shifts JSON
  {'A': 'HH:MM-HH:MM', ...} for the context's date; end <= start rolls to the next
  day. No calendar row / no window for the shift → context is skipped (cannot know
  the boundary). Notification goes to the supervisor of the FIRST confirmation in
  the context; a context with no confirmations (opened by a hold) falls back to all
  active 'supervisor' role users. Per-line shift_pattern override (Domain_QA Q6) is
  DEFERRED — the lines model has no such column yet; plant default only.
- CORRECTIONS (P31): approval required_roles=['management'] — simplest single-role
  sign-off; supervisors request, management decides (admin can use §11.2 override).
  Apply = signed ledger ADJUSTMENT rows (PROD_IN delta_good at FG + PROD_CONSUME
  deltas per BOM, ref_type='confirmation_corrections', created_by NULL — system-
  written), original confirmation status='corrected', correction 'applied'. Rejected
  delta touches no stock. NO new outbox row on apply: the SAP-side correction CSV
  spec doesn't exist yet (Domain_QA Q15 lists the confirmation spec as the pending
  SAP input) — flagged for the P40 batcher packet.
- MODEL MISMATCHES NOTED: confirmation_corrections has no CHECK on status (we use
  pending/applied/declined like issue_corrections); Line has no shift_pattern column
  (Q6 delta not yet modelled).
"""
import datetime as dt
import uuid
from decimal import Decimal

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.core.audit import record
from app.core.deps import CurrentUser, _error
from app.models.config_tables import AppSetting, PlanCalendar, ReasonCode
from app.models.identity import User
from app.models.inventory import StockLedger
from app.models.master import Bom, BomLine, Line, Material, ProductionOrder
from app.models.planning import LinePlan
from app.models.production import (ConfirmationCorrection, ConfirmationHold,
                                   ProductionConfirmation, ShiftContext)
from app.models.system import SapOutbox
from app.services.anomaly import to_decimal
from app.services.approval_handlers import on_approve, on_reject
from app.services.approvals import create_approval
from app.services.notifications import create_notification, notify_roles
from app.services.tx import enqueue_outbox, idempotent_replay

QTY = Decimal("0.001")  # NUMERIC(14,3)
CORRECTION_ROLES = ["management"]  # decision: single-role sign-off (module docstring)
DEFAULT_PLAN_EXCEED_PCT = Decimal("20")


def _now(now: dt.datetime | None = None) -> dt.datetime:
    return now if now is not None else dt.datetime.now(dt.timezone.utc)


def _plan_exceed_pct(db: Session) -> Decimal:
    row = db.get(AppSetting, "anomaly_thresholds")
    if row and isinstance(row.value, dict) and "plan_exceed_pct" in row.value:
        return to_decimal(row.value["plan_exceed_pct"])
    return DEFAULT_PLAN_EXCEED_PCT


# ---------------------------------------------------------------- shift context


def _get_or_open_shift_context(db: Session, line_id: int, shift: str,
                               shift_date: dt.date,
                               now: dt.datetime | None = None) -> ShiftContext:
    """§11.10: first confirmation (or hold) of the shift opens the context, pinning
    the line_plans revision active at that moment. Joins the caller's transaction —
    no commit here (a refused first post must not leave a pinned context behind)."""
    ctx = (db.query(ShiftContext)
           .filter_by(line_id=line_id, shift_date=shift_date, shift=shift)
           .one_or_none())
    if ctx is not None:
        return ctx
    pinned = (db.query(func.max(LinePlan.revision))
              .filter_by(line_id=line_id, plan_date=shift_date, status="active")
              .scalar()) or 0
    ctx = ShiftContext(line_id=line_id, shift_date=shift_date, shift=shift,
                       plan_revision=pinned, opened_at=_now(now))
    db.add(ctx)
    db.flush()
    return ctx


def _pinned_planned_qty(db: Session, ctx: ShiftContext, material_id: int) -> Decimal:
    """Σ planned_qty for the material AT THE PINNED REVISION (status ignored —
    superseded-but-pinned rows still govern this shift, §11.10). Fallback: the
    latest revision <= pinned when no row exists at exactly the pinned revision."""
    if ctx.plan_revision <= 0:
        return Decimal("0")
    base = db.query(LinePlan).filter_by(line_id=ctx.line_id,
                                        plan_date=ctx.shift_date,
                                        material_id=material_id)
    rows = base.filter(LinePlan.revision == ctx.plan_revision).all()
    if not rows:
        best = (base.filter(LinePlan.revision <= ctx.plan_revision)
                .with_entities(func.max(LinePlan.revision)).scalar())
        if best is None:
            return Decimal("0")
        rows = base.filter(LinePlan.revision == best).all()
    return sum((to_decimal(r.planned_qty) for r in rows), Decimal("0"))


# ---------------------------------------------------------------- confirmations


def _validate_reason(db: Session, reason_id: int | None, kind: str,
                     qty_label: str) -> ReasonCode | None:
    code_required = {"reject": "REJECT_REASON_REQUIRED",
                     "downtime": "DOWNTIME_REASON_REQUIRED"}[kind]
    code_invalid = {"reject": "REJECT_REASON_INVALID",
                    "downtime": "DOWNTIME_REASON_INVALID"}[kind]
    if reason_id is None:
        raise _error(code_required,
                     f"A {kind} reason is required when {qty_label} > 0",
                     "कारण आवश्यक आहे" if kind == "reject"
                     else "डाउनटाइम कारण आवश्यक आहे", 422, {"kind": kind})
    reason = db.get(ReasonCode, reason_id)
    if reason is None or reason.kind != kind or not reason.is_active:
        raise _error(code_invalid,
                     f"Reason {reason_id} is not an active {kind} reason code",
                     "दिलेले कारण वैध नाही", 422,
                     {"reason_id": reason_id, "expected_kind": kind})
    return reason


def post_confirmation(db: Session, user: CurrentUser, body) -> ProductionConfirmation:
    """§5.3 uniform write path, ONE commit: validate → plan rule → confirmation row
    → backflush stock → frozen CONFIRMATION outbox → audit → commit."""
    existing = idempotent_replay(db, ProductionConfirmation, body.client_ref)
    if existing:
        return existing

    now = _now()
    shift_date = body.shift_date or now.date()
    line = db.get(Line, body.line_id)
    if line is None:
        raise _error("NOT_FOUND", "Line not found", "लाईन सापडली नाही", 404,
                     {"line_id": body.line_id})
    material = db.get(Material, body.material_id)
    if material is None:
        raise _error("NOT_FOUND", "Material not found", "सामग्री सापडली नाही", 404,
                     {"material_id": body.material_id})

    good = to_decimal(body.good_qty).quantize(QTY)
    rejected = to_decimal(body.rejected_qty or 0).quantize(QTY)
    if good < 0 or rejected < 0 or body.downtime_min < 0:
        raise _error("CONFIRMATION_QTY_INVALID",
                     "Quantities and downtime must not be negative",
                     "प्रमाण आणि डाउनटाइम ऋण असू शकत नाही", 422,
                     {"good_qty": str(good), "rejected_qty": str(rejected),
                      "downtime_min": body.downtime_min})

    reject_reason = (_validate_reason(db, body.reject_reason_id, "reject",
                                      "rejected_qty") if rejected > 0 else None)
    downtime_reason = (_validate_reason(db, body.downtime_reason_id, "downtime",
                                        "downtime_min") if body.downtime_min > 0
                       else None)

    # Order resolution (Domain_QA Q3: stable order per part/month).
    order = (db.query(ProductionOrder)
             .filter_by(line_id=body.line_id, material_id=body.material_id)
             .order_by(ProductionOrder.id.desc()).first())
    if order is None:
        raise _error(
            "CONFIRMATION_NEEDS_ORDER",
            "No SAP production order for this line + material — hold the "
            "confirmation for PPC instead",
            "या लाईन + सामग्रीसाठी SAP उत्पादन ऑर्डर नाही — PPC साठी होल्ड करा",
            409,
            {"line_id": body.line_id, "material_id": body.material_id,
             "hold_endpoint": "POST /api/v1/confirmations/hold",
             "hint": "Submit the SAME body to the hold endpoint; nothing is lost — "
                     "PPC resolves the order and the confirmation posts from the "
                     "held payload (§11.11)."})

    ctx = _get_or_open_shift_context(db, body.line_id, body.shift, shift_date, now)

    # Plan validation against the PINNED revision (§11.10).
    planned = _pinned_planned_qty(db, ctx, body.material_id)
    if planned > 0:
        prior = (db.query(
                     func.coalesce(func.sum(ProductionConfirmation.good_qty), 0),
                     func.coalesce(func.sum(ProductionConfirmation.rejected_qty), 0))
                 .filter_by(shift_context_id=ctx.id, material_id=body.material_id)
                 .one())
        cumulative = to_decimal(prior[0]) + to_decimal(prior[1]) + good + rejected
        pct = _plan_exceed_pct(db)
        limit = (planned * (Decimal("1") + pct / Decimal("100"))).quantize(QTY)
        if cumulative > limit:
            raise _error(
                "CONFIRMATION_EXCEEDS_PLAN",
                f"Cumulative {cumulative} exceeds {limit} "
                f"({planned} planned at pinned revision {ctx.plan_revision} "
                f"+ {pct}% allowance)",
                "एकूण प्रमाण पिन केलेल्या नियोजनाच्या मर्यादेबाहेर आहे", 422,
                {"planned": str(planned), "pinned_revision": ctx.plan_revision,
                 "cumulative": str(cumulative), "limit": str(limit),
                 "plan_exceed_pct": str(pct)})

    process_loss = (body.process_loss.model_dump(mode="json")
                    if body.process_loss is not None else None)
    conf = ProductionConfirmation(
        order_id=order.id, line_id=body.line_id, shift=body.shift,
        material_id=body.material_id, good_qty=good, rejected_qty=rejected,
        reject_reason_id=body.reject_reason_id, downtime_min=body.downtime_min,
        downtime_reason_id=body.downtime_reason_id, process_loss=process_loss,
        kind=body.kind, status="posted", client_ref=body.client_ref,
        supervisor_id=user.id, posted_at=now, shift_context_id=ctx.id,
        posted_after_close=ctx.closed_at is not None)  # late post: allowed, flagged
    db.add(conf)
    db.flush()

    # Backflush (invariant 2: stock changes only via stock_ledger).
    if good > 0:
        db.add(StockLedger(material_id=material.id, location="FG",
                           movement="PROD_IN", qty=good, uom=material.uom,
                           ref_type="production_confirmations", ref_id=conf.id,
                           created_by=user.id))
        bom = (db.query(Bom).filter_by(parent_material_id=material.id,
                                       is_active=True).order_by(Bom.id).first())
        if bom is not None:
            for bl in db.query(BomLine).filter_by(bom_id=bom.id).order_by(BomLine.item_no):
                if bl.is_scrap_credit:
                    continue  # scrap-credit lines never consume (§4.2)
                db.add(StockLedger(
                    material_id=bl.component_material_id, location="RM",
                    movement="PROD_CONSUME",
                    qty=-(to_decimal(bl.qty_per) * good).quantize(QTY), uom=bl.uom,
                    ref_type="production_confirmations", ref_id=conf.id,
                    created_by=user.id))

    # Frozen AFRU-style payload (Domain_QA Q15: outbox postback is core MVP).
    enqueue_outbox(db, "CONFIRMATION", conf.id, payload={
        "sap_order_no": order.sap_order_no,
        "material_sap_code": material.sap_code,
        "shift": body.shift,
        "shift_date": shift_date.isoformat(),
        "good_qty": str(good),
        "rejected_qty": str(rejected),
        "reject_reason_code": reject_reason.code if reject_reason else None,
        "downtime_min": body.downtime_min,
        "downtime_reason_code": downtime_reason.code if downtime_reason else None,
        "process_loss": process_loss,
        "kind": body.kind,
        "posted_at": now.isoformat(),
    })

    if body.kind == "shift_close" and ctx.closed_at is None:
        ctx.closed_at = now
        ctx.close_kind = "manual"

    record(db, user_id=user.id, entity="production_confirmations",
           entity_id=conf.id, action="create", before=None,
           after={"order_id": order.id, "line_id": body.line_id,
                  "shift": body.shift, "shift_date": shift_date.isoformat(),
                  "good_qty": str(good), "rejected_qty": str(rejected),
                  "kind": body.kind, "shift_context_id": ctx.id,
                  "pinned_revision": ctx.plan_revision,
                  "posted_after_close": conf.posted_after_close})
    db.commit()  # invariant 3: everything above or nothing
    db.refresh(conf)
    return conf


# ---------------------------------------------------------------- hold queue (§11.11)


def _notify_ppc(db: Session, *, title: str, body: str, ref_id: int) -> None:
    """Blocker to PPC = role 'planning' OR station 'ppc' (module docstring)."""
    users = (db.query(User)
             .filter(User.is_active.is_(True),
                     or_(User.role == "planning", User.station == "ppc")).all())
    for u in users:
        create_notification(db, user_id=u.id, kind="confirmation_hold",
                            tier="blocker", title=title, body=body,
                            ref_type="confirmation_holds", ref_id=ref_id)


def hold_confirmation(db: Session, user: CurrentUser, body) -> ConfirmationHold:
    """§11.11: store the FULL confirmation body — nothing lost, nothing posted."""
    existing = idempotent_replay(db, ConfirmationHold, body.client_ref)
    if existing:
        return existing
    now = _now()
    shift_date = body.shift_date or now.date()
    material = db.get(Material, body.material_id)
    if material is None or db.get(Line, body.line_id) is None:
        raise _error("NOT_FOUND", "Line or material not found",
                     "लाईन किंवा सामग्री सापडली नाही", 404,
                     {"line_id": body.line_id, "material_id": body.material_id})
    ctx = _get_or_open_shift_context(db, body.line_id, body.shift, shift_date, now)
    hold = ConfirmationHold(line_id=body.line_id, material_id=body.material_id,
                            shift_context_id=ctx.id,
                            payload=body.model_dump(mode="json"),  # Decimal → str
                            status="open", client_ref=body.client_ref,
                            created_by=user.id)
    db.add(hold)
    db.flush()
    _notify_ppc(db, title=f"Confirmation held — no order for {material.sap_code}",
                body=f"Line {body.line_id}, shift {body.shift}: supply the SAP "
                     f"order to post it / SAP ऑर्डर द्या म्हणजे पोस्ट होईल",
                ref_id=hold.id)
    record(db, user_id=user.id, entity="confirmation_holds", entity_id=hold.id,
           action="create", before=None,
           after={"line_id": body.line_id, "material_id": body.material_id,
                  "shift_context_id": ctx.id, "good_qty": str(body.good_qty)})
    db.commit()
    db.refresh(hold)
    return hold


def resolve_hold(db: Session, user: CurrentUser, hold_id: int,
                 order_body) -> tuple[ConfirmationHold, ProductionConfirmation]:
    """PPC supplies the SAP order → ProductionOrder created if missing → the REAL
    confirmation posts from the frozen payload under the HOLD's client_ref (module
    docstring) → hold resolved. post_confirmation owns the single commit."""
    from app.schemas.production import ConfirmationCreate  # local: layering hygiene

    hold = db.get(ConfirmationHold, hold_id)
    if hold is None:
        raise _error("NOT_FOUND", "Hold not found", "होल्ड सापडला नाही", 404,
                     {"hold_id": hold_id})
    if hold.status != "open":
        raise _error("HOLD_NOT_OPEN", f"Hold is already {hold.status}",
                     "होल्ड आधीच निकाली निघाला आहे", 409,
                     {"hold_id": hold_id, "status": hold.status})

    order = (db.query(ProductionOrder)
             .filter_by(sap_order_no=order_body.sap_order_no).one_or_none())
    if order is None:
        order = ProductionOrder(sap_order_no=order_body.sap_order_no,
                                line_id=order_body.line_id or hold.line_id,
                                material_id=order_body.material_id or hold.material_id,
                                status="open")
        db.add(order)
        db.flush()

    hold.status = "resolved"
    hold.resolved_order_id = order.id
    record(db, user_id=user.id, entity="confirmation_holds", entity_id=hold.id,
           action="status_change", before={"status": "open"},
           after={"status": "resolved", "resolved_order_id": order.id,
                  "sap_order_no": order.sap_order_no})

    # payload carries the hold's client_ref — the posted confirmation reuses it.
    conf_body = ConfirmationCreate.model_validate(hold.payload)
    conf = post_confirmation(db, user, conf_body)  # commits hold flip + order too
    db.commit()  # replay early-return path leaves the flip pending — flush it
    db.refresh(hold)
    return hold, conf


# ---------------------------------------------------------------- totals + history


def confirmed_totals(db: Session, line_id: int, shift_date: dt.date,
                     material_id: int | None = None) -> dict[int, dict[str, Decimal]]:
    """{material_id: {good, rejected}} for a line+date — dashboards/plans wiring
    (replaces the P13 placeholder zeros). Applied correction deltas included so the
    totals match the ledger, not the original keying mistake."""
    q = (db.query(ProductionConfirmation.material_id,
                  func.coalesce(func.sum(ProductionConfirmation.good_qty), 0),
                  func.coalesce(func.sum(ProductionConfirmation.rejected_qty), 0))
         .join(ShiftContext,
               ShiftContext.id == ProductionConfirmation.shift_context_id)
         .filter(ProductionConfirmation.line_id == line_id,
                 ShiftContext.shift_date == shift_date)
         .group_by(ProductionConfirmation.material_id))
    if material_id is not None:
        q = q.filter(ProductionConfirmation.material_id == material_id)
    out: dict[int, dict[str, Decimal]] = {
        mid: {"good": to_decimal(g), "rejected": to_decimal(r)}
        for mid, g, r in q.all()}

    cq = (db.query(ProductionConfirmation.material_id,
                   func.coalesce(func.sum(ConfirmationCorrection.delta_good), 0),
                   func.coalesce(func.sum(ConfirmationCorrection.delta_reject), 0))
          .join(ProductionConfirmation,
                ProductionConfirmation.id == ConfirmationCorrection.confirmation_id)
          .join(ShiftContext,
                ShiftContext.id == ProductionConfirmation.shift_context_id)
          .filter(ProductionConfirmation.line_id == line_id,
                  ShiftContext.shift_date == shift_date,
                  ConfirmationCorrection.status == "applied")
          .group_by(ProductionConfirmation.material_id))
    if material_id is not None:
        cq = cq.filter(ProductionConfirmation.material_id == material_id)
    for mid, dg, dr in cq.all():
        slot = out.setdefault(mid, {"good": Decimal("0"), "rejected": Decimal("0")})
        slot["good"] += to_decimal(dg)
        slot["rejected"] += to_decimal(dr)
    return out


def history(db: Session, line_id: int | None = None,
            on_date: dt.date | None = None,
            limit: int = 200, offset: int = 0) -> list[tuple]:
    """(confirmation, sap_outbox.status) rows — the router maps outbox status to
    sap_sync_status (pending/batched/sent/acked/failed)."""
    q = (db.query(ProductionConfirmation, SapOutbox.status)
         .outerjoin(SapOutbox,
                    (SapOutbox.record_type == "CONFIRMATION")
                    & (SapOutbox.record_id == ProductionConfirmation.id)))
    if line_id is not None:
        q = q.filter(ProductionConfirmation.line_id == line_id)
    if on_date is not None:
        q = (q.join(ShiftContext,
                    ShiftContext.id == ProductionConfirmation.shift_context_id)
             .filter(ShiftContext.shift_date == on_date))
    return (q.order_by(ProductionConfirmation.id.desc())
            .limit(limit).offset(offset).all())


# ---------------------------------------------------------------- auto close (§11.10)


def _shift_end(shifts: dict | None, shift: str, shift_date: dt.date,
               tz: dt.tzinfo | None) -> dt.datetime | None:
    """'HH:MM-HH:MM' window for the shift; end <= start rolls past midnight.
    Missing calendar/window → None (boundary unknown, context skipped)."""
    window = (shifts or {}).get(shift)
    if not window or "-" not in str(window):
        return None
    start_s, end_s = str(window).split("-", 1)
    try:
        start_t = dt.time.fromisoformat(start_s.strip())
        end_t = dt.time.fromisoformat(end_s.strip())
    except ValueError:
        return None
    end = dt.datetime.combine(shift_date, end_t, tzinfo=tz)
    if end_t <= start_t:  # night shift crossing midnight
        end += dt.timedelta(days=1)
    return end


def shift_auto_close_job(db: Session, now: dt.datetime | None = None) -> int:
    """Worker job (§11.10): close open contexts whose shift end has passed
    (close_kind='auto') + notify the supervisor. Fake `now` for worker AND tests —
    the boundary is compared in `now`'s own timezone (naive now → naive boundary)."""
    now = _now(now)
    closed = 0
    open_ctxs = (db.query(ShiftContext)
                 .filter(ShiftContext.closed_at.is_(None))
                 .order_by(ShiftContext.id).all())
    for ctx in open_ctxs:
        cal = db.get(PlanCalendar, ctx.shift_date)
        end = _shift_end(cal.shifts if cal else None, ctx.shift, ctx.shift_date,
                         now.tzinfo)
        if end is None or now < end:
            continue
        ctx.closed_at = now
        ctx.close_kind = "auto"
        first = (db.query(ProductionConfirmation)
                 .filter_by(shift_context_id=ctx.id)
                 .order_by(ProductionConfirmation.id).first())
        title = (f"Shift {ctx.shift} on line {ctx.line_id} auto-closed "
                 f"({ctx.shift_date.isoformat()})")
        body = ("Posts after close are accepted but flagged / "
                "बंद झाल्यानंतरच्या नोंदी स्वीकारल्या जातात पण फ्लॅग होतात")
        if first is not None:  # the supervisor who ran the shift
            create_notification(db, user_id=first.supervisor_id,
                                kind="shift_auto_closed", title=title, body=body,
                                ref_type="shift_contexts", ref_id=ctx.id, now=now)
        else:  # context opened by a hold only — fall back to the supervisor role
            notify_roles(db, ["supervisor"], kind="shift_auto_closed", title=title,
                         body=body, tier="digest", ref_type="shift_contexts",
                         ref_id=ctx.id, now=now)
        record(db, user_id=None, entity="shift_contexts", entity_id=ctx.id,
               action="status_change", before={"closed_at": None},
               after={"closed_at": now.isoformat(), "close_kind": "auto"})
        closed += 1
    if closed:
        db.commit()
    return closed


# ---------------------------------------------------------------- corrections (P31)


def request_correction(db: Session, user: CurrentUser, confirmation_id: int,
                       delta_good: Decimal, delta_reject: Decimal,
                       reason: str) -> ConfirmationCorrection:
    conf = db.get(ProductionConfirmation, confirmation_id)
    if conf is None:
        raise _error("NOT_FOUND", "Confirmation not found",
                     "कन्फर्मेशन सापडले नाही", 404,
                     {"confirmation_id": confirmation_id})
    if conf.status != "posted":
        raise _error("CONFIRMATION_NOT_CORRECTABLE",
                     "Only posted confirmations can be corrected",
                     "फक्त पोस्ट केलेली कन्फर्मेशनच दुरुस्त करता येतात", 422,
                     {"status": conf.status})
    delta_good = to_decimal(delta_good).quantize(QTY)
    delta_reject = to_decimal(delta_reject).quantize(QTY)
    if delta_good == 0 and delta_reject == 0:
        raise _error("CORRECTION_EMPTY", "Nothing to correct",
                     "दुरुस्त करण्यासारखे काही नाही", 422, {})
    if (conf.good_qty + delta_good < 0) or (conf.rejected_qty + delta_reject < 0):
        raise _error("CORRECTION_NEGATIVE",
                     "Correction would make a quantity negative",
                     "दुरुस्तीने प्रमाण ऋण होईल", 422,
                     {"good_qty": str(conf.good_qty), "delta_good": str(delta_good),
                      "rejected_qty": str(conf.rejected_qty),
                      "delta_reject": str(delta_reject)})
    if not (reason or "").strip():
        raise _error("CORRECTION_REASON_REQUIRED", "Correction needs a reason",
                     "दुरुस्तीसाठी कारण आवश्यक आहे", 422, {})

    approval = create_approval(  # engine primitive — joins this transaction (§5.6)
        db, approval_type="confirmation_correction",
        ref_type="production_confirmations", ref_id=conf.id,
        payload={"delta_good": str(delta_good), "delta_reject": str(delta_reject),
                 "reason": reason},
        required_roles=list(CORRECTION_ROLES), created_by=user.id)
    corr = ConfirmationCorrection(confirmation_id=conf.id, delta_good=delta_good,
                                  delta_reject=delta_reject, reason=reason,
                                  approval_id=approval.id, status="pending")
    db.add(corr)
    db.flush()
    record(db, user_id=user.id, entity="confirmation_corrections",
           entity_id=corr.id, action="create", before=None,
           after={"confirmation_id": conf.id, "delta_good": str(delta_good),
                  "delta_reject": str(delta_reject), "reason": reason,
                  "approval_id": approval.id})
    db.commit()
    db.refresh(corr)
    return corr


@on_approve("confirmation_correction")
def _apply_confirmation_correction(db: Session, approval) -> None:
    """Runs INSIDE the approvals engine's transaction — no commit. Idempotent:
    re-applying a decided approval is a no-op (correction already left 'pending')."""
    corr = (db.query(ConfirmationCorrection)
            .filter_by(approval_id=approval.id).one_or_none())
    if corr is None or corr.status != "pending":
        return
    conf = db.get(ProductionConfirmation, corr.confirmation_id)
    material = db.get(Material, conf.material_id)
    delta_good = to_decimal(corr.delta_good)

    if delta_good != 0:
        # Signed adjustment rows mirror the original backflush (created_by NULL —
        # system-written; the human actor lives on the approval + audit_log, §4.6).
        db.add(StockLedger(material_id=conf.material_id, location="FG",
                           movement="PROD_IN", qty=delta_good, uom=material.uom,
                           ref_type="confirmation_corrections", ref_id=corr.id,
                           created_by=None))
        bom = (db.query(Bom).filter_by(parent_material_id=conf.material_id,
                                       is_active=True).order_by(Bom.id).first())
        if bom is not None:
            for bl in db.query(BomLine).filter_by(bom_id=bom.id).order_by(BomLine.item_no):
                if bl.is_scrap_credit:
                    continue
                db.add(StockLedger(
                    material_id=bl.component_material_id, location="RM",
                    movement="PROD_CONSUME",
                    qty=-(to_decimal(bl.qty_per) * delta_good).quantize(QTY),
                    uom=bl.uom, ref_type="confirmation_corrections",
                    ref_id=corr.id, created_by=None))
    # delta_reject changes the keyed split only — no stock movement.

    conf.status = "corrected"  # invariant 6: new rows reference the original
    corr.status = "applied"
    record(db, user_id=None, entity="production_confirmations", entity_id=conf.id,
           action="status_change", before={"status": "posted"},
           after={"status": "corrected", "correction_id": corr.id,
                  "delta_good": str(corr.delta_good),
                  "delta_reject": str(corr.delta_reject)})


@on_reject("confirmation_correction")
def _reject_confirmation_correction(db: Session, approval) -> None:
    corr = (db.query(ConfirmationCorrection)
            .filter_by(approval_id=approval.id).one_or_none())
    if corr is None or corr.status != "pending":
        return
    corr.status = "declined"
    create_notification(db, user_id=approval.created_by,
                        kind="confirmation_correction_declined", tier="digest",
                        title="Confirmation correction declined",
                        body="The correction request was declined / "
                             "दुरुस्तीची विनंती नाकारली गेली",
                        ref_type="confirmation_corrections", ref_id=corr.id)
    record(db, user_id=None, entity="confirmation_corrections", entity_id=corr.id,
           action="status_change", before={"status": "pending"},
           after={"status": "declined"})
