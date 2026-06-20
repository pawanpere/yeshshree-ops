"""GR / QC / full-lot reject / debit notes + anomaly register (P20/P21).
Spec: Architecture §4.6, §5.3 write path, §11.7 tolerances, §11.9 full-lot reject.

The whole GR is ONE transaction (CLAUDE.md invariant 3): validate → anomaly rules →
goods_receipts row → stock_ledger / RGP / debit notes → sap_outbox (frozen payload)
→ soft anomalies + notifications → single db.commit() at the end.

Decisions (documented per packet brief):
- full_lot_reject debit amount = base_amount (multiplier 1): base is already the FULL
  invoice/expected qty x PO rate (§11.9 "full invoice qty basis"); the 5x punitive
  multiplier applies only to kind='shortage_5x'. Multiplier for shortage comes from
  app_settings['debit_note'].multiplier (default 5).
- hard-anomaly escalation (confirm_escalate=true): the hard hit is registered in the
  anomaly register (status open) and blocker notifications go to ALL active users with
  role in ('supervisor','management') — station is NOT filtered, the supervisor pool
  is small and management always wants hard escalations. Notification.kind=
  'anomaly_escalation', tier='blocker' (§11.14: hard-block escalations are blockers).
- rate source: the matched PO line's rate; falls back to material master price when
  the PO line carries no rate (real SAP exports sometimes blank it).
- §11.18 weighbridge_weight: goods_receipts has no such column yet — not captured
  here; arrives with its own migration packet.
"""
import datetime as dt
from decimal import Decimal

from sqlalchemy.orm import Session

from app.core.audit import record
from app.core.deps import CurrentUser, _error
from app.models.config_tables import AppSetting, MaterialGroupTolerance
from app.models.gate import GateEntry, ReturnGatePass
from app.models.identity import User
from app.models.inventory import DebitNote, GoodsReceipt, StockLedger
from app.models.master import Material, PurchaseOrder
from app.models.workflow import Anomaly, Notification
from app.services import anomaly_rules  # noqa: F401 — import registers gr_pre_post rules
from app.services.anomaly import (persist_soft, raise_hard, register_hard, run_rules,
                                  to_decimal)
from app.services.numbering import next_doc_no
from app.services.tx import enqueue_outbox, idempotent_replay

QTY = Decimal("0.001")    # NUMERIC(14,3)
MONEY = Decimal("0.01")   # NUMERIC(14,2)


def _debit_multiplier(db: Session) -> Decimal:
    row = db.get(AppSetting, "debit_note")
    if row and isinstance(row.value, dict) and "multiplier" in row.value:
        return to_decimal(row.value["multiplier"])
    return Decimal("5")


def post_goods_receipt(db: Session, user: CurrentUser, body) -> GoodsReceipt:
    # Invariant 4: retried request returns the original result.
    existing = idempotent_replay(db, GoodsReceipt, body.client_ref)
    if existing:
        return existing

    entry = db.get(GateEntry, body.gate_entry_id)
    if entry is None:
        raise _error("NOT_FOUND", "Gate entry not found", "गेट एंट्री सापडली नाही", 404,
                     {"gate_entry_id": body.gate_entry_id})
    if entry.status != "open" or entry.match_status != "matched":
        raise _error("GR_ENTRY_NOT_READY",
                     "Gate entry is not ready for GR (must be open and PO-matched)",
                     "गेट एंट्री GR साठी तयार नाही (खुली आणि PO-जुळलेली हवी)", 422,
                     {"status": entry.status, "match_status": entry.match_status})
    if entry.entry_mode == "backfill" and entry.backfill_status != "completed":
        raise _error("GR_BACKFILL_PENDING",
                     "Gate entry backfill is incomplete — complete it before GR",
                     "गेट एंट्री बॅकफिल अपूर्ण आहे — GR आधी ती पूर्ण करा", 422,
                     {"backfill_status": entry.backfill_status})
    material = db.get(Material, entry.material_id) if entry.material_id else None
    if material is None:
        raise _error("GR_ENTRY_NOT_READY", "Gate entry has no material linked",
                     "गेट एंट्रीला सामग्री जोडलेली नाही", 422, {"gate_entry_id": entry.id})

    received = to_decimal(body.received_qty).quantize(QTY)
    rejected = to_decimal(body.rejected_qty).quantize(QTY)
    if received <= 0 or rejected < 0 or rejected > received:
        raise _error("GR_QTY_INVALID",
                     "Quantities are invalid (received > 0, 0 <= rejected <= received)",
                     "प्रमाण अवैध आहे (प्राप्त > 0, 0 <= नाकारलेले <= प्राप्त)", 422,
                     {"received_qty": str(received), "rejected_qty": str(rejected)})

    po = db.get(PurchaseOrder, entry.po_id) if entry.po_id else None
    expected = to_decimal(entry.qty_expected or 0).quantize(QTY)

    # §11.7: material-group tolerance is consulted BEFORE shortage/anomaly logic.
    tol = (db.query(MaterialGroupTolerance)
           .filter_by(mat_group=material.mat_group, uom=material.uom, is_active=True)
           .one_or_none())
    within_tolerance = bool(
        tol is not None and expected > 0
        and abs(received - expected) / expected * 100 <= to_decimal(tol.pct_tolerance))

    # §5.3 step 2: anomaly rules. Hard + no operator confirmation → 422, nothing written.
    results = run_rules(db, "gr_pre_post", expected=expected, received=received,
                        within_tolerance=within_tolerance)
    hard = [r for r in results if r.severity == "hard"]
    if hard and not body.confirm_escalate:
        raise_hard(results)

    full_lot_reject = body.qc_result == "fail"
    if full_lot_reject:
        # §11.9: fail = the WHOLE lot is rejected; accepted treated as 0.
        accepted, rejected, shortage = Decimal("0"), received, Decimal("0")
    else:
        accepted = received - rejected
        shortage = Decimal("0") if within_tolerance else max(expected - received, Decimal("0"))
    accepted, rejected, shortage = (q.quantize(QTY) for q in (accepted, rejected, shortage))

    now = dt.datetime.now(dt.timezone.utc)
    gr = GoodsReceipt(doc_no=next_doc_no(db, "GR"), gate_entry_id=entry.id,
                      po_id=entry.po_id, material_id=material.id,
                      expected_qty=expected, received_qty=received,
                      accepted_qty=accepted, rejected_qty=rejected,
                      qc_result=body.qc_result, qc_remarks=body.qc_remarks,
                      shortage_qty=shortage,
                      weighbridge_weight=body.weighbridge_weight,
                      weighbridge_slip_photo_id=body.weighbridge_slip_photo_id,
                      status="posted",
                      client_ref=body.client_ref, posted_by=user.id, posted_at=now)
    db.add(gr)
    db.flush()

    # GR resolves any open gate-entry escalation events (gr_pending_30m / unmatched_24h)
    from app.services.escalations import resolve_events
    resolve_events(db, "gate_entries", entry.id)

    if hard:  # confirm_escalate=True: register + blocker-notify, then proceed (§5.5)
        for h in hard:
            register_hard(db, h, ref_type="goods_receipts", ref_id=gr.id)
        _notify_escalation(db, gr, hard[0])

    rate = to_decimal(po.rate) if po is not None and po.rate is not None \
        else to_decimal(material.price or 0)
    vendor_id = entry.vendor_id or (po.vendor_id if po else None)

    if full_lot_reject:
        # §11.9: NO stock_ledger rows; return gate pass + full-basis debit, same txn.
        db.add(ReturnGatePass(doc_no=next_doc_no(db, "RGP"), goods_receipt_id=gr.id,
                              gate_entry_id=entry.id, vehicle_no=entry.vehicle_no,
                              reason=body.qc_remarks or "Full lot rejected at QC",
                              status="issued", created_by=user.id))
        if vendor_id is not None:
            base = (expected * rate).quantize(MONEY)
            db.add(DebitNote(doc_no=next_doc_no(db, "DN"), goods_receipt_id=gr.id,
                             vendor_id=vendor_id, kind="full_lot_reject",
                             base_amount=base, multiplier=Decimal("1"),
                             amount=base, status="draft"))
    else:
        if accepted > 0:  # invariant 2: stock changes ONLY via stock_ledger
            # Route inbound stock by category: a purchased component goes to the COMP
            # store, raw material to RM (§4.6). Outbound/consumption routing for
            # components is a deferred follow-up (this phase covers inbound only).
            db.add(StockLedger(material_id=material.id,
                               location=material.stock_location, movement="GR_IN",
                               qty=accepted, uom=material.uom, vendor_id=vendor_id,
                               ref_type="goods_receipts", ref_id=gr.id,
                               created_by=user.id))
        if shortage > 0 and vendor_id is not None:
            multiplier = _debit_multiplier(db)
            base = (shortage * rate).quantize(MONEY)
            db.add(DebitNote(doc_no=next_doc_no(db, "DN"), goods_receipt_id=gr.id,
                             vendor_id=vendor_id, kind="shortage_5x",
                             base_amount=base, multiplier=multiplier,
                             amount=(base * multiplier).quantize(MONEY), status="draft"))

    persist_soft(db, results, ref_type="goods_receipts", ref_id=gr.id)

    enqueue_outbox(db, "GR", gr.id, payload={
        "doc_no": gr.doc_no,
        "gate_doc_no": entry.doc_no,
        "sap_po_no": po.sap_po_no if po else None,
        "material_sap_code": material.sap_code,
        "expected_qty": str(expected),
        "received_qty": str(received),
        "accepted_qty": str(accepted),
        "rejected_qty": str(rejected),
        "shortage_qty": str(shortage),
        "qc_result": body.qc_result,
        "posted_at": now.isoformat(),
    })

    entry.status = "gr_done"
    record(db, user_id=user.id, entity="goods_receipts", entity_id=gr.id,
           action="create", before=None,
           after={"doc_no": gr.doc_no, "gate_doc_no": entry.doc_no,
                  "received_qty": str(received), "accepted_qty": str(accepted),
                  "rejected_qty": str(rejected), "shortage_qty": str(shortage),
                  "qc_result": body.qc_result,
                  "escalated": bool(hard)})
    db.commit()  # invariant 3: everything above or nothing
    db.refresh(gr)
    return gr


def _notify_escalation(db: Session, gr: GoodsReceipt, result) -> None:
    targets = (db.query(User)
               .filter(User.is_active.is_(True), User.role.in_(("supervisor", "management")))
               .all())
    for u in targets:
        db.add(Notification(user_id=u.id, kind="anomaly_escalation", tier="blocker",
                            title=f"Hard anomaly escalated on {gr.doc_no} ({result.rule_code})",
                            body=f"{result.message_en} / {result.message_mr}",
                            ref_type="goods_receipts", ref_id=gr.id))


# --- anomaly register (P21) ---

def resolve_anomaly(db: Session, user: CurrentUser, anomaly_id: int, note: str) -> Anomaly:
    row = db.get(Anomaly, anomaly_id)
    if row is None:
        raise _error("NOT_FOUND", "Anomaly not found", "विसंगती सापडली नाही", 404,
                     {"anomaly_id": anomaly_id})
    if row.status == "resolved":
        return row  # resolving twice is a no-op, not an error
    before = {"status": row.status}
    row.status = "resolved"
    row.resolved_by = user.id
    row.resolved_at = dt.datetime.now(dt.timezone.utc)
    # `note` lives in the audit diff — anomalies has no note column (§4.8).
    record(db, user_id=user.id, entity="anomalies", entity_id=row.id,
           action="status_change", before=before,
           after={"status": "resolved", "note": note})
    # closes any open hard_block_unanswered escalation chain on this anomaly
    from app.services.escalations import resolve_events
    resolve_events(db, "anomalies", row.id)
    db.commit()
    db.refresh(row)
    return row
