"""Vendor-portal read logic (Phase 6). INVARIANT 5: the vendor scope comes from the
authenticated principal's JWT vendor_id (resolved here in the service), NEVER from a
client-supplied id. Every query filters by that vendor_id, so a vendor can only ever
read their own orders / call-offs / exposure / debit notes / consignment stock."""
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import CurrentUser, _error
from app.models.inventory import DebitNote, StockLedger
from app.models.master import Material, PurchaseOrder, Vendor
from app.models.planning import VendorCalloff
from app.services import issuing


def _vendor_id(user: CurrentUser) -> int:
    """The caller's vendor scope, from the JWT. A vendor account with no linked
    vendor cannot read anything — fail loudly rather than leak another vendor's data."""
    if user.vendor_id is None:
        raise _error("VENDOR_NOT_LINKED",
                     "This account is not linked to a vendor",
                     "हे खाते कोणत्याही विक्रेत्याशी जोडलेले नाही", 409)
    return user.vendor_id


def my_purchase_orders(db: Session, user: CurrentUser) -> list[dict]:
    vid = _vendor_id(user)
    rows = (db.query(PurchaseOrder, Material.description)
            .join(Material, Material.id == PurchaseOrder.material_id)
            .filter(PurchaseOrder.vendor_id == vid)
            .order_by(PurchaseOrder.status, PurchaseOrder.sap_po_no,
                      PurchaseOrder.item_no).all())
    return [{"id": po.id, "sap_po_no": po.sap_po_no, "item_no": po.item_no,
             "material_id": po.material_id, "material": desc,
             "ordered_qty": po.ordered_qty, "open_qty": po.open_qty,
             "rate": po.rate, "uom": po.uom, "due_date": po.due_date,
             "status": po.status} for po, desc in rows]


def my_calloffs(db: Session, user: CurrentUser) -> list[dict]:
    vid = _vendor_id(user)
    rows = (db.query(VendorCalloff, Material.description)
            .join(Material, Material.id == VendorCalloff.material_id)
            .filter(VendorCalloff.vendor_id == vid)
            .order_by(VendorCalloff.calloff_date.desc()).all())
    return [{"id": c.id, "material_id": c.material_id, "material": desc,
             "calloff_date": c.calloff_date, "qty": c.qty, "status": c.status}
            for c, desc in rows]


def my_exposure(db: Session, user: CurrentUser) -> dict:
    vid = _vendor_id(user)
    exp = issuing.vendor_exposure(db, vid)
    vendor = db.get(Vendor, vid)
    return {"vendor_id": vid, "credit_exposure": exp["credit_exposure"],
            "qty_mt": exp["qty_mt"],
            "credit_limit": vendor.credit_limit if vendor else None,
            "qty_limit_mt": vendor.qty_limit_mt if vendor else None}


def my_debit_notes(db: Session, user: CurrentUser) -> list[dict]:
    vid = _vendor_id(user)
    rows = (db.query(DebitNote).filter(DebitNote.vendor_id == vid)
            .order_by(DebitNote.id.desc()).all())
    return [{"id": d.id, "doc_no": d.doc_no, "kind": d.kind,
             "base_amount": d.base_amount, "amount": d.amount, "status": d.status}
            for d in rows]


def my_stock(db: Session, user: CurrentUser) -> list[dict]:
    """Our material currently held AT this vendor (consignment / job-work)."""
    vid = _vendor_id(user)
    rows = (db.query(StockLedger.material_id, Material.description, Material.uom,
                     func.coalesce(func.sum(StockLedger.qty), 0))
            .join(Material, Material.id == StockLedger.material_id)
            .filter(StockLedger.location == "AT_VENDOR",
                    StockLedger.vendor_id == vid)
            .group_by(StockLedger.material_id, Material.description, Material.uom)
            .having(func.coalesce(func.sum(StockLedger.qty), 0) != 0)
            .order_by(Material.description).all())
    return [{"material_id": mid, "material": desc, "qty": qty, "uom": uom}
            for mid, desc, uom, qty in rows]
