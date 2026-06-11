"""Gate entry logic (P16+P18). Spec: Architecture §4.5 + §11.3/11.5/11.6, §5.7.

Write path per CLAUDE.md invariants 3/4/7: idempotent_replay → validate →
domain row (+doc_no under doc_sequences lock) → field-level audit → commit.
NO outbox here — gate entries never post to SAP; the GR does (P20).
Vendor scoping N/A: every route is internal-roles-only (vendor role gets 403
in the router guard)."""
import datetime as dt

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.audit import record
from app.core.deps import CurrentUser, _error
from app.models.gate import GateEntry
from app.models.master import PurchaseOrder
from app.schemas import gate as s
from app.services import numbering
from app.services.master import get_or_404
from app.services.tx import idempotent_replay


# --- internals -------------------------------------------------------------

def _validate_doc_type(doc_type: str, inward_category: str | None,
                       vendor_id: int | None, invoice_no: str | None) -> None:
    if doc_type == "invoice" and not (invoice_no and vendor_id):
        raise _error("GATE_INVOICE_REQUIRED",
                     "Invoice entries need an invoice number and a vendor",
                     "इनव्हॉइस नोंदीसाठी इनव्हॉइस क्रमांक आणि पुरवठादार आवश्यक आहेत",
                     422, {"doc_type": doc_type})
    if doc_type == "other_inward" and not inward_category:
        raise _error("GATE_CATEGORY_REQUIRED",
                     "Other-inward entries need an inward category",
                     "इतर आवक नोंदीसाठी आवक प्रकार निवडणे आवश्यक आहे",
                     422, {"doc_type": doc_type})


def _check_duplicate_invoice(db: Session, *, doc_type: str, vendor_id: int | None,
                             invoice_no: str | None, consignment_no: int) -> None:
    """§11.6: same vendor+invoice+consignment → structured 409 offering explicit
    continuation; the client re-posts with consignment_no=N to continue."""
    if doc_type != "invoice" or not (vendor_id and invoice_no):
        return
    existing = (db.query(GateEntry)
                .filter_by(doc_type="invoice", vendor_id=vendor_id,
                           invoice_no=invoice_no, consignment_no=consignment_no)
                .first())
    if existing is None:
        return
    max_no = (db.query(func.max(GateEntry.consignment_no))
              .filter_by(doc_type="invoice", vendor_id=vendor_id, invoice_no=invoice_no)
              .scalar())
    raise _error("DUPLICATE_INVOICE",
                 "This invoice is already entered — continue as the next consignment?",
                 "हे इनव्हॉइस आधीच नोंदवले आहे — पुढील खेप (कन्साइनमेंट) म्हणून सुरू ठेवायचे?",
                 409, {"existing_doc_no": existing.doc_no,
                       "existing_id": existing.id,
                       "next_consignment_no": int(max_no or 1) + 1})


def _resolve_po_match(db: Session, *, po_id: int | None, vendor_id: int | None,
                      material_id: int | None, qty_expected) -> dict:
    """PO match (P18). Explicit po_id wins; else auto-match when EXACTLY ONE open
    PO line exists for vendor+material; else unmatched. A match LOCKS material
    and qty from the PO line."""
    if po_id is not None:
        po = get_or_404(db, PurchaseOrder, po_id, "purchase order")
        if vendor_id is not None and po.vendor_id != vendor_id:
            raise _error("PO_VENDOR_MISMATCH",
                         "This PO does not belong to the selected vendor",
                         "हा PO निवडलेल्या पुरवठादाराचा नाही", 422,
                         {"po_id": po_id, "po_vendor_id": po.vendor_id,
                          "vendor_id": vendor_id})
        return {"po_id": po.id, "material_id": po.material_id,
                "qty_expected": qty_expected if qty_expected is not None else po.open_qty,
                "match_status": "matched"}
    if vendor_id is not None and material_id is not None:
        candidates = (db.query(PurchaseOrder)
                      .filter_by(vendor_id=vendor_id, material_id=material_id,
                                 status="open")
                      .all())
        if len(candidates) == 1:
            po = candidates[0]
            return {"po_id": po.id, "material_id": po.material_id,
                    "qty_expected": qty_expected if qty_expected is not None else po.open_qty,
                    "match_status": "matched"}
    return {"po_id": None, "material_id": material_id,
            "qty_expected": qty_expected, "match_status": "unmatched"}


def _get_open_entry(db: Session, entry_id: int) -> GateEntry:
    entry = get_or_404(db, GateEntry, entry_id, "gate entry")
    if entry.status != "open":
        raise _error("GATE_NOT_OPEN", "This gate entry is no longer open",
                     "ही गेट नोंद आता खुली नाही", 422,
                     {"id": entry.id, "status": entry.status})
    return entry


# --- create (P16) ----------------------------------------------------------

def create_entry(db: Session, user: CurrentUser, body: s.GateEntryCreate) -> GateEntry:
    existing = idempotent_replay(db, GateEntry, body.client_ref)
    if existing:
        return existing
    _validate_doc_type(body.doc_type, body.inward_category, body.vendor_id, body.invoice_no)
    _check_duplicate_invoice(db, doc_type=body.doc_type, vendor_id=body.vendor_id,
                             invoice_no=body.invoice_no, consignment_no=body.consignment_no)
    match = _resolve_po_match(db, po_id=body.po_id, vendor_id=body.vendor_id,
                              material_id=body.material_id, qty_expected=body.qty_expected)
    entry = GateEntry(
        doc_no=numbering.next_doc_no(db, "G"),
        vendor_id=body.vendor_id,
        invoice_no=body.invoice_no,
        invoice_date=body.invoice_date,
        invoice_value=body.invoice_value,
        irn=body.irn,
        vehicle_no=body.vehicle_no,
        driver_name=body.driver_name,
        doc_type=body.doc_type,
        inward_category=body.inward_category,
        consignment_no=body.consignment_no,
        consignment_total=body.consignment_total,
        status="open",
        client_ref=body.client_ref,
        created_by=user.id,
        **match,
    )
    db.add(entry)
    db.flush()
    record(db, user_id=user.id, entity="gate_entries", entity_id=entry.id,
           action="create", before=None,
           after={"doc_no": entry.doc_no, "match_status": entry.match_status,
                  "doc_type": entry.doc_type, "consignment_no": entry.consignment_no})
    db.commit()  # gate-pass payload; NO outbox — SAP learns of inward via the GR
    db.refresh(entry)
    return entry


# --- backfill (§11.3) ------------------------------------------------------

def create_backfill(db: Session, user: CurrentUser, body: s.GateBackfillCreate) -> GateEntry:
    existing = idempotent_replay(db, GateEntry, body.client_ref)
    if existing:
        return existing
    entry = GateEntry(
        doc_no=numbering.next_doc_no(db, "G"),
        vehicle_no=body.vehicle_no,
        driver_name=body.driver_name,
        vendor_name_text=body.vendor_name_text,
        entry_mode="backfill",
        backfill_status="pending_completion",
        match_status="unmatched",
        status="open",
        client_ref=body.client_ref,
        created_by=user.id,
    )
    if body.entered_at is not None:
        entry.created_at = body.entered_at  # actual gate time, not sync time
    db.add(entry)
    db.flush()
    record(db, user_id=user.id, entity="gate_entries", entity_id=entry.id,
           action="create", before=None,
           after={"doc_no": entry.doc_no, "entry_mode": "backfill"})
    db.commit()
    db.refresh(entry)
    return entry


def complete_backfill(db: Session, user: CurrentUser, entry_id: int,
                      body: s.GateBackfillComplete) -> GateEntry:
    entry = _get_open_entry(db, entry_id)
    if entry.entry_mode != "backfill" or entry.backfill_status != "pending_completion":
        raise _error("BACKFILL_NOT_PENDING",
                     "This entry is not awaiting backfill completion",
                     "ही नोंद बॅकफिल पूर्णतेच्या प्रतीक्षेत नाही", 422,
                     {"id": entry.id, "entry_mode": entry.entry_mode,
                      "backfill_status": entry.backfill_status})
    _validate_doc_type(body.doc_type, body.inward_category, body.vendor_id, body.invoice_no)
    _check_duplicate_invoice(db, doc_type=body.doc_type, vendor_id=body.vendor_id,
                             invoice_no=body.invoice_no, consignment_no=body.consignment_no)
    match = _resolve_po_match(db, po_id=body.po_id, vendor_id=body.vendor_id,
                              material_id=body.material_id, qty_expected=body.qty_expected)
    before = {"backfill_status": entry.backfill_status, "vendor_id": entry.vendor_id,
              "invoice_no": entry.invoice_no, "po_id": entry.po_id,
              "match_status": entry.match_status}
    entry.vendor_id = body.vendor_id
    entry.invoice_no = body.invoice_no
    entry.invoice_date = body.invoice_date
    entry.invoice_value = body.invoice_value
    entry.irn = body.irn
    entry.doc_type = body.doc_type
    entry.inward_category = body.inward_category
    entry.consignment_no = body.consignment_no
    entry.consignment_total = body.consignment_total
    entry.po_id = match["po_id"]
    entry.material_id = match["material_id"]
    entry.qty_expected = match["qty_expected"]
    entry.match_status = match["match_status"]
    entry.backfill_status = "completed"
    record(db, user_id=user.id, entity="gate_entries", entity_id=entry.id,
           action="status_change", before=before,
           after={"backfill_status": "completed", "vendor_id": entry.vendor_id,
                  "invoice_no": entry.invoice_no, "po_id": entry.po_id,
                  "match_status": entry.match_status})
    db.commit()
    db.refresh(entry)
    return entry


# --- invoice-later (§11.5) ---------------------------------------------------

def attach_invoice(db: Session, user: CurrentUser, entry_id: int,
                   body: s.GateAttachInvoice) -> GateEntry:
    entry = get_or_404(db, GateEntry, entry_id, "gate entry")
    if entry.doc_type != "challan":
        raise _error("ATTACH_NOT_CHALLAN",
                     "An invoice can be attached only to a challan entry",
                     "इनव्हॉइस फक्त चलन नोंदीलाच जोडता येते", 422,
                     {"id": entry.id, "doc_type": entry.doc_type})
    before = {"invoice_no": entry.invoice_no,
              "invoice_date": str(entry.invoice_date) if entry.invoice_date else None,
              "invoice_value": str(entry.invoice_value) if entry.invoice_value is not None else None,
              "irn": entry.irn}
    entry.invoice_no = body.invoice_no
    entry.invoice_date = body.invoice_date
    entry.invoice_value = body.invoice_value
    entry.irn = body.irn
    record(db, user_id=user.id, entity="gate_entries", entity_id=entry.id,
           action="update", before=before,
           after={"invoice_no": entry.invoice_no,
                  "invoice_date": str(entry.invoice_date) if entry.invoice_date else None,
                  "invoice_value": str(entry.invoice_value) if entry.invoice_value is not None else None,
                  "irn": entry.irn})
    db.commit()
    db.refresh(entry)
    return entry


# --- match maintenance (P18) -------------------------------------------------

def link_po(db: Session, user: CurrentUser, entry_id: int, po_id: int) -> GateEntry:
    """Link an unmatched entry to a PO, or RE-link a wrong match — only while open
    (after GR the receipt already references the PO; corrections go through P20)."""
    entry = _get_open_entry(db, entry_id)
    po = get_or_404(db, PurchaseOrder, po_id, "purchase order")
    if entry.vendor_id is not None and po.vendor_id != entry.vendor_id:
        raise _error("PO_VENDOR_MISMATCH",
                     "This PO does not belong to the entry's vendor",
                     "हा PO या नोंदीच्या पुरवठादाराचा नाही", 422,
                     {"po_id": po_id, "po_vendor_id": po.vendor_id,
                      "vendor_id": entry.vendor_id})
    before = {"po_id": entry.po_id, "material_id": entry.material_id,
              "qty_expected": str(entry.qty_expected) if entry.qty_expected is not None else None,
              "match_status": entry.match_status}
    entry.po_id = po.id
    entry.material_id = po.material_id  # locked from the PO line
    entry.qty_expected = po.open_qty
    entry.match_status = "matched"
    record(db, user_id=user.id, entity="gate_entries", entity_id=entry.id,
           action="update", before=before,  # audit_log.action CHECK has a fixed vocabulary
           after={"po_id": entry.po_id, "material_id": entry.material_id,
                  "qty_expected": str(entry.qty_expected),
                  "match_status": "matched"})
    from app.services.escalations import resolve_events
    resolve_events(db, "gate_entries", entry.id)  # closes unmatched_gate_24h chain
    db.commit()
    db.refresh(entry)
    return entry


def mark_consumable(db: Session, user: CurrentUser, entry_id: int) -> GateEntry:
    entry = _get_open_entry(db, entry_id)
    before = {"match_status": entry.match_status}
    entry.match_status = "consumable"
    record(db, user_id=user.id, entity="gate_entries", entity_id=entry.id,
           action="status_change", before=before,
           after={"match_status": "consumable"})
    from app.services.escalations import resolve_events
    resolve_events(db, "gate_entries", entry.id)  # closes unmatched_gate_24h chain
    db.commit()
    db.refresh(entry)
    return entry


# --- reads -------------------------------------------------------------------

def list_unmatched(db: Session, user: CurrentUser) -> list[GateEntry]:
    """The unmatched folder: open unmatched entries + pending backfills, oldest
    first (they age towards the >24h purchase alarm, §11.8 rule — P26 timer)."""
    return (db.query(GateEntry)
            .filter(GateEntry.status == "open")
            .filter((GateEntry.match_status == "unmatched")
                    | (GateEntry.backfill_status == "pending_completion"))
            .order_by(GateEntry.created_at.asc(), GateEntry.id.asc())
            .all())


def list_entries(db: Session, user: CurrentUser, *, status: str | None,
                 match_status: str | None, date: dt.date | None,
                 limit: int = 200, offset: int = 0) -> list[GateEntry]:
    q = db.query(GateEntry)
    if status:
        q = q.filter(GateEntry.status == status)
    if match_status:
        q = q.filter(GateEntry.match_status == match_status)
    if date:
        q = q.filter(func.date(GateEntry.created_at) == date.isoformat())
    return (q.order_by(GateEntry.created_at.desc(), GateEntry.id.desc())
            .limit(limit).offset(offset).all())


def get_entry(db: Session, user: CurrentUser, entry_id: int) -> GateEntry:
    return get_or_404(db, GateEntry, entry_id, "gate entry")
