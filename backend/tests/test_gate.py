"""P16+P18 acceptance: gate entry create (doc_type, consignment continuation),
PO match (explicit, auto, ambiguous), duplicate-invoice 409 continuation,
invoice-later for challans, backfill + completion, unmatched folder,
link-PO / re-link, mark-consumable, role guards, idempotent replay."""
import uuid
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.models.gate import GateEntry
from app.models.identity import User
from app.models.master import Material, PurchaseOrder, Vendor
from app.models.system import AuditLog
import app.core.db as db_mod


@pytest.fixture()
def client(engine, db):
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    db.add_all([
        User(username="admin", password_hash=hash_password("a"), full_name="A",
             role="admin", language="en"),
        User(username="gate1", password_hash=hash_password("g"), full_name="G",
             role="plant_ops", station="gate", language="mr"),
        User(username="v1", password_hash=hash_password("v"), full_name="V",
             role="vendor", language="en"),
    ])
    db.add_all([
        Vendor(sap_code="V-100", name="Tata Steel"),
        Material(sap_code="1101030569", description="CRCA SHEET D TG04",
                 mat_type="ROH", mat_group="1103", uom="KG"),
        Material(sap_code="1101030570", description="HR SHEET 2MM",
                 mat_type="ROH", mat_group="1103", uom="KG"),
    ])
    db.commit()
    vendor = db.query(Vendor).filter_by(sap_code="V-100").one()
    mat1 = db.query(Material).filter_by(sap_code="1101030569").one()
    mat2 = db.query(Material).filter_by(sap_code="1101030570").one()
    db.add_all([
        # exactly ONE open PO line for vendor+mat1 → auto-match target
        PurchaseOrder(sap_po_no="4500000001", item_no=10, vendor_id=vendor.id,
                      material_id=mat1.id, ordered_qty=Decimal("5000.000"),
                      open_qty=Decimal("1250.500"), uom="KG", status="open"),
        # TWO open PO lines for vendor+mat2 → ambiguous, must stay unmatched
        PurchaseOrder(sap_po_no="4500000002", item_no=10, vendor_id=vendor.id,
                      material_id=mat2.id, ordered_qty=Decimal("3000.000"),
                      open_qty=Decimal("3000.000"), uom="KG", status="open"),
        PurchaseOrder(sap_po_no="4500000003", item_no=10, vendor_id=vendor.id,
                      material_id=mat2.id, ordered_qty=Decimal("2000.000"),
                      open_qty=Decimal("800.000"), uom="KG", status="open"),
    ])
    db.commit()
    from app.main import app
    from app.api.gate import router as gate_router
    if not any(getattr(r, "path", "") == "/api/v1/gate-entries/unmatched"
               for r in app.routes):
        app.include_router(gate_router)  # main.py is outside this packet's scope
    yield TestClient(app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def _token(client, username, password):
    r = client.post("/api/v1/auth/login", json={"username": username, "password": password})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _ids(db):
    vendor = db.query(Vendor).filter_by(sap_code="V-100").one()
    mat1 = db.query(Material).filter_by(sap_code="1101030569").one()
    mat2 = db.query(Material).filter_by(sap_code="1101030570").one()
    po1 = db.query(PurchaseOrder).filter_by(sap_po_no="4500000001").one()
    po2 = db.query(PurchaseOrder).filter_by(sap_po_no="4500000002").one()
    po3 = db.query(PurchaseOrder).filter_by(sap_po_no="4500000003").one()
    return vendor, mat1, mat2, po1, po2, po3


def _entry(vendor_id, invoice_no="INV-001", **extra):
    body = {"client_ref": str(uuid.uuid4()), "vendor_id": vendor_id,
            "invoice_no": invoice_no, "vehicle_no": "MH12AB1234",
            "driver_name": "Ramesh"}
    body.update(extra)
    return body


# 1 — explicit po_id: matched, material+qty locked from the PO, doc_no G-NNNNN
def test_create_with_po_id_matches_and_locks_qty(client, db):
    gate = _token(client, "gate1", "g")
    vendor, mat1, _, po1, _, _ = _ids(db)
    r = client.post("/api/v1/gate-entries", headers=gate,
                    json=_entry(vendor.id, po_id=po1.id))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["match_status"] == "matched"
    assert body["po_id"] == po1.id
    assert body["material_id"] == mat1.id
    assert Decimal(body["qty_expected"]) == Decimal("1250.500")  # locked from PO open qty
    assert body["doc_no"] == "G-00001"
    assert body["status"] == "open"


# 2 — exactly one open PO for vendor+material → auto-match
def test_auto_match_single_open_po(client, db):
    gate = _token(client, "gate1", "g")
    vendor, mat1, _, po1, _, _ = _ids(db)
    r = client.post("/api/v1/gate-entries", headers=gate,
                    json=_entry(vendor.id, material_id=mat1.id))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["match_status"] == "matched"
    assert body["po_id"] == po1.id
    assert Decimal(body["qty_expected"]) == Decimal("1250.500")


# 3 — two open POs for the same vendor+material → ambiguous → unmatched
def test_ambiguous_pos_stay_unmatched(client, db):
    gate = _token(client, "gate1", "g")
    vendor, _, mat2, _, _, _ = _ids(db)
    r = client.post("/api/v1/gate-entries", headers=gate,
                    json=_entry(vendor.id, material_id=mat2.id))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["match_status"] == "unmatched"
    assert body["po_id"] is None
    # shows up in the unmatched folder
    folder = client.get("/api/v1/gate-entries/unmatched", headers=gate).json()
    assert any(e["id"] == body["id"] for e in folder)


# 4 — duplicate vendor+invoice_no → 409 with continuation hint; consignment 2 succeeds
def test_duplicate_invoice_409_then_consignment_continuation(client, db):
    gate = _token(client, "gate1", "g")
    vendor, _, _, po1, _, _ = _ids(db)
    first = client.post("/api/v1/gate-entries", headers=gate,
                        json=_entry(vendor.id, invoice_no="INV-777", po_id=po1.id))
    assert first.status_code == 200
    dup = client.post("/api/v1/gate-entries", headers=gate,
                      json=_entry(vendor.id, invoice_no="INV-777", po_id=po1.id))
    assert dup.status_code == 409
    detail = dup.json()["detail"]
    assert detail["code"] == "DUPLICATE_INVOICE"
    assert detail["message_mr"]
    assert detail["details"]["existing_doc_no"] == first.json()["doc_no"]
    assert detail["details"]["next_consignment_no"] == 2
    cont = client.post("/api/v1/gate-entries", headers=gate,
                       json=_entry(vendor.id, invoice_no="INV-777", po_id=po1.id,
                                   consignment_no=2, consignment_total=2))
    assert cont.status_code == 200, cont.text
    assert cont.json()["consignment_no"] == 2
    assert cont.json()["consignment_total"] == 2


# 5 — challan posts without invoice_no; attach-invoice fills it later (§11.5)
def test_challan_then_attach_invoice(client, db):
    gate = _token(client, "gate1", "g")
    vendor, _, _, po1, _, _ = _ids(db)
    r = client.post("/api/v1/gate-entries", headers=gate,
                    json=_entry(vendor.id, invoice_no=None, doc_type="challan",
                                po_id=po1.id))
    assert r.status_code == 200, r.text
    eid = r.json()["id"]
    assert r.json()["invoice_no"] is None
    a = client.post(f"/api/v1/gate-entries/{eid}/attach-invoice", headers=gate,
                    json={"invoice_no": "INV-LATE-9", "invoice_date": "2026-06-10",
                          "invoice_value": "154000.00"})
    assert a.status_code == 200, a.text
    assert a.json()["invoice_no"] == "INV-LATE-9"
    assert Decimal(a.json()["invoice_value"]) == Decimal("154000.00")
    # attach on a non-challan entry is rejected
    inv = client.post("/api/v1/gate-entries", headers=gate,
                      json=_entry(vendor.id, invoice_no="INV-REAL", po_id=po1.id))
    bad = client.post(f"/api/v1/gate-entries/{inv.json()['id']}/attach-invoice",
                      headers=gate, json={"invoice_no": "X"})
    assert bad.status_code == 422
    assert bad.json()["detail"]["code"] == "ATTACH_NOT_CHALLAN"


# 6 — offline backfill then completion (§11.3)
def test_backfill_then_complete(client, db):
    gate = _token(client, "gate1", "g")
    vendor, _, _, po1, _, _ = _ids(db)
    r = client.post("/api/v1/gate-entries/backfill", headers=gate,
                    json={"client_ref": str(uuid.uuid4()), "vehicle_no": "MH14XY9999",
                          "driver_name": "Suresh", "vendor_name_text": "Tata (paper reg.)"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["entry_mode"] == "backfill"
    assert body["backfill_status"] == "pending_completion"
    assert body["match_status"] == "unmatched"
    assert body["vendor_id"] is None and body["invoice_no"] is None
    eid = body["id"]
    # pending backfills surface in the unmatched folder
    folder = client.get("/api/v1/gate-entries/unmatched", headers=gate).json()
    assert any(e["id"] == eid for e in folder)
    c = client.post(f"/api/v1/gate-entries/{eid}/complete-backfill", headers=gate,
                    json={"vendor_id": vendor.id, "invoice_no": "INV-BF-1",
                          "invoice_date": "2026-06-09", "po_id": po1.id})
    assert c.status_code == 200, c.text
    done = c.json()
    assert done["backfill_status"] == "completed"
    assert done["match_status"] == "matched"
    assert done["po_id"] == po1.id
    assert done["material_id"] is not None
    assert Decimal(done["qty_expected"]) == Decimal("1250.500")


# 7 — link-po on an unmatched entry, then RE-link to a different PO while open
def test_link_po_and_relink(client, db):
    gate = _token(client, "gate1", "g")
    vendor, _, mat2, _, po2, po3 = _ids(db)
    r = client.post("/api/v1/gate-entries", headers=gate,
                    json=_entry(vendor.id, invoice_no="INV-LNK", material_id=mat2.id))
    eid = r.json()["id"]
    assert r.json()["match_status"] == "unmatched"
    l1 = client.post(f"/api/v1/gate-entries/{eid}/link-po", headers=gate,
                     json={"po_id": po2.id})
    assert l1.status_code == 200, l1.text
    assert l1.json()["match_status"] == "matched"
    assert l1.json()["po_id"] == po2.id
    assert Decimal(l1.json()["qty_expected"]) == Decimal("3000.000")
    # wrong match — re-link to the other PO while still open
    l2 = client.post(f"/api/v1/gate-entries/{eid}/link-po", headers=gate,
                     json={"po_id": po3.id})
    assert l2.status_code == 200, l2.text
    assert l2.json()["po_id"] == po3.id
    assert Decimal(l2.json()["qty_expected"]) == Decimal("800.000")
    # audit carries before/after po_id for the re-link
    # (action vocabulary is fixed by audit_log CHECK: link-po audits as 'update')
    rows = (db.query(AuditLog).filter_by(entity="gate_entries", entity_id=eid,
                                         action="update").all())
    assert any(row.before and row.before.get("po_id") == po2.id
               and row.after.get("po_id") == po3.id for row in rows)
    # no longer in unmatched folder
    folder = client.get("/api/v1/gate-entries/unmatched", headers=gate).json()
    assert not any(e["id"] == eid for e in folder)


# 8 — mark-consumable
def test_mark_consumable(client, db):
    gate = _token(client, "gate1", "g")
    vendor, _, mat2, _, _, _ = _ids(db)
    r = client.post("/api/v1/gate-entries", headers=gate,
                    json=_entry(vendor.id, invoice_no="INV-CONS", material_id=mat2.id))
    eid = r.json()["id"]
    m = client.post(f"/api/v1/gate-entries/{eid}/mark-consumable", headers=gate)
    assert m.status_code == 200, m.text
    assert m.json()["match_status"] == "consumable"
    rows = db.query(AuditLog).filter_by(entity="gate_entries", entity_id=eid,
                                        action="status_change").all()
    assert any(row.before.get("match_status") == "unmatched"
               and row.after.get("match_status") == "consumable" for row in rows)


# 9 — vendor role is locked out (internal-only endpoints)
def test_vendor_role_forbidden(client, db):
    vendor_hdr = _token(client, "v1", "v")
    vendor, _, _, _, _, _ = _ids(db)
    assert client.get("/api/v1/gate-entries", headers=vendor_hdr).status_code == 403
    assert client.get("/api/v1/gate-entries/unmatched",
                      headers=vendor_hdr).status_code == 403
    r = client.post("/api/v1/gate-entries", headers=vendor_hdr, json=_entry(vendor.id))
    assert r.status_code == 403


# 10 — idempotent replay: same client_ref twice → same doc_no, no second row
def test_idempotent_replay(client, db):
    gate = _token(client, "gate1", "g")
    vendor, _, _, po1, _, _ = _ids(db)
    body = _entry(vendor.id, invoice_no="INV-IDEM", po_id=po1.id)
    r1 = client.post("/api/v1/gate-entries", headers=gate, json=body)
    r2 = client.post("/api/v1/gate-entries", headers=gate, json=body)
    assert r1.status_code == 200 and r2.status_code == 200
    assert r1.json()["doc_no"] == r2.json()["doc_no"]
    assert (db.query(GateEntry)
            .filter_by(client_ref=uuid.UUID(body["client_ref"])).count()) == 1


# extra guard rails the spec calls out
def test_invoice_requires_invoice_no_and_vendor(client, db):
    gate = _token(client, "gate1", "g")
    vendor, _, _, _, _, _ = _ids(db)
    r = client.post("/api/v1/gate-entries", headers=gate,
                    json=_entry(vendor.id, invoice_no=None))
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "GATE_INVOICE_REQUIRED"
    r2 = client.post("/api/v1/gate-entries", headers=gate,
                     json=_entry(None, invoice_no="INV-NOVEND"))
    assert r2.status_code == 422
    assert r2.json()["detail"]["code"] == "GATE_INVOICE_REQUIRED"


def test_other_inward_requires_category(client, db):
    gate = _token(client, "gate1", "g")
    r = client.post("/api/v1/gate-entries", headers=_token(client, "gate1", "g"),
                    json={"client_ref": str(uuid.uuid4()), "doc_type": "other_inward",
                          "vehicle_no": "MH12ZZ0001", "driver_name": "Ganesh"})
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "GATE_CATEGORY_REQUIRED"
    ok = client.post("/api/v1/gate-entries", headers=gate,
                     json={"client_ref": str(uuid.uuid4()), "doc_type": "other_inward",
                           "inward_category": "customer_return",
                           "vehicle_no": "MH12ZZ0002", "driver_name": "Ganesh"})
    assert ok.status_code == 200, ok.text
    assert ok.json()["match_status"] == "unmatched"


def test_link_po_blocked_when_not_open(client, db):
    gate = _token(client, "gate1", "g")
    vendor, _, _, po1, po2, _ = _ids(db)
    r = client.post("/api/v1/gate-entries", headers=gate,
                    json=_entry(vendor.id, invoice_no="INV-CLOSED", po_id=po1.id))
    eid = r.json()["id"]
    db.query(GateEntry).filter_by(id=eid).update({"status": "gr_done"})
    db.commit()
    l = client.post(f"/api/v1/gate-entries/{eid}/link-po", headers=gate,
                    json={"po_id": po2.id})
    assert l.status_code == 422
    assert l.json()["detail"]["code"] == "GATE_NOT_OPEN"


def test_unmatched_folder_oldest_first_and_list_filters(client, db):
    gate = _token(client, "gate1", "g")
    vendor, _, mat2, _, _, _ = _ids(db)
    a = client.post("/api/v1/gate-entries", headers=gate,
                    json=_entry(vendor.id, invoice_no="INV-A", material_id=mat2.id))
    b = client.post("/api/v1/gate-entries", headers=gate,
                    json=_entry(vendor.id, invoice_no="INV-B", material_id=mat2.id))
    folder = client.get("/api/v1/gate-entries/unmatched", headers=gate).json()
    ids = [e["id"] for e in folder]
    assert ids.index(a.json()["id"]) < ids.index(b.json()["id"])  # oldest first
    lst = client.get("/api/v1/gate-entries", headers=gate,
                     params={"match_status": "unmatched", "status": "open"}).json()
    assert {a.json()["id"], b.json()["id"]} <= {e["id"] for e in lst}
    one = client.get(f"/api/v1/gate-entries/{a.json()['id']}", headers=gate)
    assert one.status_code == 200 and one.json()["invoice_no"] == "INV-A"
