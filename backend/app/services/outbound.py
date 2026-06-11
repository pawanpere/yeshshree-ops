"""Outbound: dispatch → SAP-recorded sales invoice → confirm (P34).
Spec: Architecture §4.7 (dispatches/sales_invoices), §5.5 (invoice_dispatch_mismatch),
§11.1 (parallel-run stock policy), Domain_QA Q2 (SAP creates the invoice incl.
IRN/e-way — the app RECORDS and CONFIRMS it, never generates), invariants 2/3/4/11.

Decisions (documented per packet brief):
- Doc numbers: §4.7 says dispatches are DN-…, but doc_sequences doc_type 'DN' is
  ALREADY used by debit_notes (P20). Dispatches deliberately SHARE that sequence —
  one 'DN' counter means a dispatch and a debit note can never carry the same DN-
  number; numbers interleave across the two tables (cosmetic, uniqueness wins).
- Stock check (§11.1): FG balance is checked PER MATERIAL with line qtys aggregated
  first (two lines of the same material must not each pass against the same stock).
  parallel_run → post anyway + soft anomaly `stock_insufficient_warned` per material;
  authoritative → 422 STOCK_INSUFFICIENT before anything is written.
- total_pcs is Integer in the model while line qty is NUMERIC(14,3): total_pcs is
  stored as int(Σqty) — dispatches count pieces; fractional FG qty would be a master-
  data smell, not something this packet invents a column for.
- sales_invoices has NO created_by/created_at columns (§4.7 model verbatim): the
  recording user is captured by audit_log (middleware + record()) only.
- record_invoice: invoice data comes from SAP (Domain_QA Q2) → NO stock effect and
  NO outbox row at record time; the INVOICE outbox row is written by confirm_sale
  (the confirmation is OUR event; the invoice itself is SAP's).
- Match check: Σqty per material on the invoice vs Σqty per material on the dispatch;
  any differing material (including one-side-only) → match_status='mismatch', which
  REQUIRES mismatch_reason and registers soft anomaly `invoice_dispatch_mismatch`
  (observed/expected per material, §5.5). Mismatched invoices still record — the
  paper truth wins; the anomaly register carries the investigation.
- confirm_sale is idempotent: confirming an already-confirmed invoice returns it
  unchanged (retry-safe without a client_ref — there is nothing new to write).
- No 'commercial' role exists in §4.1 — invoice record/confirm guards are
  plant_ops/admin (see api/outbound.py).
"""
import datetime as dt
from decimal import Decimal

from sqlalchemy.orm import Session

from app.core.audit import record
from app.core.deps import CurrentUser, _error
from app.models.inventory import StockLedger
from app.models.master import Customer, Material
from app.models.outbound import Dispatch, DispatchLine, SalesInvoice, SalesInvoiceLine
from app.models.workflow import Anomaly
from app.services import inventory
from app.services.anomaly import to_decimal
from app.services.numbering import next_doc_no
from app.services.tx import enqueue_outbox, idempotent_replay

QTY = Decimal("0.001")    # NUMERIC(14,3)
MONEY = Decimal("0.01")   # NUMERIC(14,2)


def _load_materials(db: Session, lines) -> dict[int, Material]:
    """Resolve every line's material or 404 — before any write."""
    materials: dict[int, Material] = {}
    for ln in lines:
        if ln.material_id not in materials:
            m = db.get(Material, ln.material_id)
            if m is None:
                raise _error("NOT_FOUND", "Material not found", "सामग्री सापडली नाही",
                             404, {"material_id": ln.material_id})
            materials[ln.material_id] = m
    return materials


def _validated_qtys(lines, code: str) -> list[Decimal]:
    qtys = [to_decimal(ln.qty).quantize(QTY) for ln in lines]
    if not qtys:
        raise _error(code, "At least one line is required",
                     "किमान एक ओळ आवश्यक आहे", 422, {})
    for q in qtys:
        if q <= 0:
            raise _error(code, "Line quantity must be greater than zero",
                         "ओळीचे प्रमाण शून्यापेक्षा जास्त असावे", 422, {"qty": str(q)})
    return qtys


def _per_material(pairs) -> dict[int, Decimal]:
    agg: dict[int, Decimal] = {}
    for material_id, qty in pairs:
        agg[material_id] = (agg.get(material_id, Decimal("0")) + qty).quantize(QTY)
    return agg


def dispatch_lines(db: Session, dispatch_id: int) -> list[DispatchLine]:
    return (db.query(DispatchLine).filter_by(dispatch_id=dispatch_id)
            .order_by(DispatchLine.id).all())


def invoice_lines(db: Session, invoice_id: int) -> list[SalesInvoiceLine]:
    return (db.query(SalesInvoiceLine).filter_by(invoice_id=invoice_id)
            .order_by(SalesInvoiceLine.id).all())


def create_dispatch(db: Session, user: CurrentUser, body) -> Dispatch:
    # Invariant 4: retried request returns the original result.
    existing = idempotent_replay(db, Dispatch, body.client_ref)
    if existing:
        return existing

    customer = db.get(Customer, body.customer_id)
    if customer is None:
        raise _error("NOT_FOUND", "Customer not found", "ग्राहक सापडला नाही", 404,
                     {"customer_id": body.customer_id})
    qtys = _validated_qtys(body.lines, "DISPATCH_LINES_INVALID")
    materials = _load_materials(db, body.lines)

    # §11.1 FG stock policy, aggregated per material (see module docstring).
    warned: list[dict] = []
    for material_id, qty in _per_material(
            zip((ln.material_id for ln in body.lines), qtys)).items():
        chk = inventory.check_stock(db, material_id, qty, "FG")
        if chk["blocking"]:
            raise _error("STOCK_INSUFFICIENT",
                         "Insufficient finished-goods stock for this dispatch",
                         "या डिस्पॅचसाठी पुरेसा तयार माल साठा नाही", 422,
                         {"material_id": material_id, "balance": str(chk["balance"]),
                          "requested": str(qty)})
        if not chk["sufficient"]:
            warned.append({"material_id": material_id,
                           "sap_code": materials[material_id].sap_code,
                           "balance": str(chk["balance"]), "requested": str(qty)})

    total_pcs = int(sum(qtys))  # Integer column vs NUMERIC lines — documented above
    dispatch = Dispatch(doc_no=next_doc_no(db, "DN"), customer_id=customer.id,
                        vehicle_no=body.vehicle_no, total_pcs=total_pcs,
                        status="open", client_ref=body.client_ref, created_by=user.id)
    db.add(dispatch)
    db.flush()

    payload_lines = []
    for ln, qty in zip(body.lines, qtys):
        material = materials[ln.material_id]
        db.add(DispatchLine(dispatch_id=dispatch.id, material_id=material.id, qty=qty))
        # Invariant 2: stock leaves FG only via the ledger — negative DISPATCH_OUT.
        db.add(StockLedger(material_id=material.id, location="FG",
                           movement="DISPATCH_OUT", qty=-qty, uom=material.uom,
                           vendor_id=None, ref_type="dispatches", ref_id=dispatch.id,
                           created_by=user.id))
        payload_lines.append({"material_sap_code": material.sap_code,
                              "qty": str(qty), "uom": material.uom})

    for w in warned:
        # invariant 11 / ADR-003: posted anyway in parallel_run, registered soft.
        db.add(Anomaly(rule_code="stock_insufficient_warned", severity="soft",
                       ref_type="dispatches", ref_id=dispatch.id,
                       observed={"material_sap_code": w["sap_code"],
                                 "balance": w["balance"], "requested": w["requested"]},
                       expected={"balance_at_least": w["requested"]},
                       message_en="Dispatch posted with insufficient FG app stock "
                                  "(parallel run — warn only)",
                       message_mr="अपुऱ्या FG अ‍ॅप साठ्यासह डिस्पॅच पोस्ट केला "
                                  "(समांतर रन — फक्त इशारा)",
                       status="open"))

    enqueue_outbox(db, "DISPATCH", dispatch.id, payload={
        "doc_no": dispatch.doc_no,
        "customer_sap_code": customer.sap_code,
        "vehicle_no": dispatch.vehicle_no,
        "total_pcs": dispatch.total_pcs,
        "lines": payload_lines,
    })
    record(db, user_id=user.id, entity="dispatches", entity_id=dispatch.id,
           action="create", before=None,
           after={"doc_no": dispatch.doc_no, "customer_id": customer.id,
                  "vehicle_no": dispatch.vehicle_no, "total_pcs": total_pcs,
                  "status": "open", "lines": payload_lines,
                  "stock_warned_materials": [w["sap_code"] for w in warned]})
    db.commit()  # invariant 3: everything above or nothing
    db.refresh(dispatch)
    return dispatch


def record_invoice(db: Session, user: CurrentUser, body) -> SalesInvoice:
    """RECORD the SAP-created invoice (Domain_QA Q2) and match it to its dispatch.
    No stock effect, no outbox here — see module docstring."""
    existing = idempotent_replay(db, SalesInvoice, body.client_ref)
    if existing:
        return existing

    dispatch = db.get(Dispatch, body.dispatch_id)
    if dispatch is None:
        raise _error("NOT_FOUND", "Dispatch not found", "डिस्पॅच सापडला नाही", 404,
                     {"dispatch_id": body.dispatch_id})
    if dispatch.status != "open":
        raise _error("INVOICE_DISPATCH_NOT_OPEN",
                     "Invoice can only be recorded against an open dispatch",
                     "फक्त खुल्या डिस्पॅचवरच इनव्हॉइस नोंदवता येते", 422,
                     {"dispatch_id": dispatch.id, "status": dispatch.status})
    qtys = _validated_qtys(body.lines, "INVOICE_LINES_INVALID")
    materials = _load_materials(db, body.lines)

    # §4.7 match check: Σqty per material, invoice vs dispatch.
    inv_qty = _per_material(zip((ln.material_id for ln in body.lines), qtys))
    dsp_qty = _per_material((dl.material_id, to_decimal(dl.qty).quantize(QTY))
                            for dl in dispatch_lines(db, dispatch.id))
    observed, expected = {}, {}
    for material_id in sorted(set(inv_qty) | set(dsp_qty)):
        i, d = inv_qty.get(material_id, Decimal("0")), dsp_qty.get(material_id, Decimal("0"))
        if i != d:
            material = materials.get(material_id) or db.get(Material, material_id)
            key = material.sap_code if material else str(material_id)
            observed[key] = str(i)   # what the SAP invoice says
            expected[key] = str(d)   # what we dispatched
    match_status = "mismatch" if observed else "ok"
    if match_status == "mismatch" and not body.mismatch_reason:
        raise _error("INVOICE_MISMATCH_REASON_REQUIRED",
                     "Invoice quantities differ from the dispatch — a reason is required",
                     "इनव्हॉइसचे प्रमाण डिस्पॅचशी जुळत नाही — कारण आवश्यक आहे", 422,
                     {"observed": observed, "expected": expected})

    invoice = SalesInvoice(invoice_no=body.invoice_no, invoice_date=body.invoice_date,
                           dispatch_id=dispatch.id, irn=body.irn,
                           eway_bill_no=body.eway_bill_no,
                           total_value=to_decimal(body.total_value).quantize(MONEY),
                           match_status=match_status, status="pending",
                           client_ref=body.client_ref)
    db.add(invoice)
    db.flush()
    for ln, qty in zip(body.lines, qtys):
        db.add(SalesInvoiceLine(invoice_id=invoice.id, material_id=ln.material_id,
                                qty=qty, value=to_decimal(ln.value).quantize(MONEY)))
    if match_status == "mismatch":
        db.add(Anomaly(rule_code="invoice_dispatch_mismatch", severity="soft",
                       ref_type="sales_invoices", ref_id=invoice.id,
                       observed=observed,
                       expected=expected | {"mismatch_reason": body.mismatch_reason},
                       message_en="Invoice quantities differ from dispatch "
                                  f"{dispatch.doc_no}",
                       message_mr=f"इनव्हॉइसचे प्रमाण डिस्पॅच {dispatch.doc_no} "
                                  "शी जुळत नाही",
                       status="open"))
    record(db, user_id=user.id, entity="sales_invoices", entity_id=invoice.id,
           action="create", before=None,
           after={"invoice_no": invoice.invoice_no,
                  "invoice_date": str(invoice.invoice_date),
                  "dispatch_doc_no": dispatch.doc_no,
                  "total_value": str(invoice.total_value),
                  "match_status": match_status, "status": "pending",
                  "mismatch_reason": body.mismatch_reason})
    db.commit()
    db.refresh(invoice)
    return invoice


def confirm_sale(db: Session, user: CurrentUser, invoice_id: int) -> SalesInvoice:
    """Confirm the recorded invoice — THIS event feeds the live sales report and
    is what we tell SAP about (outbox INVOICE)."""
    invoice = db.get(SalesInvoice, invoice_id)
    if invoice is None:
        raise _error("NOT_FOUND", "Invoice not found", "इनव्हॉइस सापडले नाही", 404,
                     {"invoice_id": invoice_id})
    if invoice.status == "confirmed":
        return invoice  # idempotent retry — nothing new to write
    dispatch = db.get(Dispatch, invoice.dispatch_id)

    invoice.status = "confirmed"
    invoice.confirmed_by = user.id
    invoice.confirmed_at = dt.datetime.now(dt.timezone.utc)
    dispatch.status = "invoiced"

    lines = []
    for ln in invoice_lines(db, invoice.id):
        material = db.get(Material, ln.material_id)
        lines.append({"material_sap_code": material.sap_code if material else None,
                      "qty": str(ln.qty), "value": str(ln.value)})
    enqueue_outbox(db, "INVOICE", invoice.id, payload={
        "invoice_no": invoice.invoice_no,
        "invoice_date": str(invoice.invoice_date),
        "dispatch_doc_no": dispatch.doc_no,
        "lines": lines,
        "total_value": str(invoice.total_value),
        "irn": invoice.irn,
        "eway_bill_no": invoice.eway_bill_no,
    })
    record(db, user_id=user.id, entity="sales_invoices", entity_id=invoice.id,
           action="status_change",
           before={"status": "pending", "dispatch_status": "open"},
           after={"status": "confirmed", "dispatch_status": "invoiced",
                  "confirmed_by": user.id,
                  "confirmed_at": invoice.confirmed_at.isoformat()})
    db.commit()
    db.refresh(invoice)
    return invoice
