"""P20/P21 acceptance: GR with §11.7 tolerances, shortage→5x debit, hard/soft anomaly
rules, confirm-escalate path, §11.9 full-lot reject (RGP, zero stock), idempotent
replay, anomaly register list+resolve."""
import uuid
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.models.config_tables import MaterialGroupTolerance
from app.models.gate import GateEntry, ReturnGatePass
from app.models.identity import User
from app.models.inventory import DebitNote, GoodsReceipt, StockLedger
from app.models.master import Material, PurchaseOrder, Vendor
from app.models.system import SapOutbox
from app.models.workflow import Anomaly, Notification
import app.core.db as db_mod

EXPECTED = Decimal("28172.000")  # KG, matches the real CRCA steel scale
RATE = Decimal("63.00")          # PO rate (deliberately != material price 60)


def _entry(db, vendor, material, po, **over):
    n = uuid.uuid4().hex[:8]
    base = dict(doc_no=f"G-{n}", vendor_id=vendor.id, invoice_no=f"INV-{n}",
                po_id=po.id, material_id=material.id, qty_expected=EXPECTED,
                vehicle_no="MH12AB1234", driver_name="Ramu", match_status="matched",
                status="open", client_ref=uuid.uuid4(), created_by=1)
    base.update(over)
    e = GateEntry(**base)
    db.add(e)
    db.commit()
    return e


@pytest.fixture()
def seeded(db):
    db.add_all([
        User(username="admin", password_hash=hash_password("a"), full_name="A",
             role="admin", language="en"),
        User(username="qc1", password_hash=hash_password("q"), full_name="Q",
             role="plant_ops", station="qc", language="mr"),
        User(username="sup1", password_hash=hash_password("s"), full_name="S",
             role="supervisor", station="store", language="mr"),
        User(username="boss", password_hash=hash_password("b"), full_name="B",
             role="management", language="en"),
    ])
    vendor = Vendor(sap_code="V-100", name="Tata Steel BSL")
    material = Material(sap_code="1101030569", description="CRCA SHEET D TG04",
                        mat_type="ROH", mat_group="1103", uom="KG",
                        price=Decimal("60.00"))
    db.add_all([vendor, material])
    db.flush()
    db.add(MaterialGroupTolerance(mat_group="1103", uom="KG",
                                  pct_tolerance=Decimal("0.50")))
    po = PurchaseOrder(sap_po_no="4500001234", item_no=10, vendor_id=vendor.id,
                       material_id=material.id, ordered_qty=EXPECTED,
                       open_qty=EXPECTED, rate=RATE, uom="KG", status="open")
    db.add(po)
    db.commit()
    entry = _entry(db, vendor, material, po)
    return {"vendor": vendor, "material": material, "po": po, "entry": entry}


@pytest.fixture()
def client(engine, db, seeded):
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False,
                                        expire_on_commit=False)
    from app.main import app
    from app.api.receiving import router as receiving_router
    # P20 scope cannot touch main.py — mount the router here (idempotent across tests).
    if not any(getattr(r, "path", None) == "/api/v1/goods-receipts" for r in app.routes):
        app.include_router(receiving_router)
    yield TestClient(app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def _token(client, username, password):
    r = client.post("/api/v1/auth/login", json={"username": username, "password": password})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _post_gr(client, headers, entry_id, received, **over):
    body = {"gate_entry_id": entry_id, "received_qty": str(received),
            "qc_result": "pass", "client_ref": str(uuid.uuid4())}
    body.update(over)
    return client.post("/api/v1/goods-receipts", json=body, headers=headers)


def test_within_tolerance_clean_accept(client, db, seeded):
    """82 KG short on 28172 = 0.29% < 0.5% tolerance → shortage 0, no flags (§11.7)."""
    qc = _token(client, "qc1", "q")
    r = _post_gr(client, qc, seeded["entry"].id, "28090")
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["doc_no"].startswith("GR-")
    assert Decimal(str(data["shortage_qty"])) == 0
    assert db.query(Anomaly).count() == 0
    assert db.query(DebitNote).count() == 0
    led = db.query(StockLedger).one()
    assert (led.movement, led.location) == ("GR_IN", "RM")
    assert led.qty == Decimal("28090")
    assert led.vendor_id == seeded["vendor"].id
    ob = db.query(SapOutbox).filter_by(record_type="GR").one()
    assert ob.status == "pending"
    assert ob.payload["doc_no"] == data["doc_no"]
    assert ob.payload["gate_doc_no"] == seeded["entry"].doc_no
    assert ob.payload["sap_po_no"] == "4500001234"
    assert ob.payload["shortage_qty"] == "0.000"
    db.refresh(seeded["entry"])
    assert seeded["entry"].status == "gr_done"


def test_shortage_beyond_tolerance_creates_5x_debit(client, db, seeded):
    """1172 KG short (4.2%) → shortage debit draft at 5x PO rate, not material price."""
    qc = _token(client, "qc1", "q")
    r = _post_gr(client, qc, seeded["entry"].id, "27000")
    assert r.status_code == 200, r.text
    shortage = EXPECTED - Decimal("27000")
    assert Decimal(str(r.json()["shortage_qty"])) == shortage
    dn = db.query(DebitNote).one()
    assert dn.kind == "shortage_5x"
    assert dn.status == "draft"
    assert dn.multiplier == Decimal("5")
    assert dn.base_amount == (shortage * RATE).quantize(Decimal("0.01"))
    assert dn.amount == (Decimal("5") * RATE * shortage).quantize(Decimal("0.01"))
    # 4.2% deviation < 20% soft threshold → no soft anomaly either
    assert db.query(Anomaly).count() == 0


def test_hard_anomaly_blocks(client, db, seeded):
    """2000 <= 28172/5 → gr_qty_vs_po hard → 422 ANOMALY_HARD, nothing written."""
    qc = _token(client, "qc1", "q")
    r = _post_gr(client, qc, seeded["entry"].id, "2000")
    assert r.status_code == 422
    detail = r.json()["detail"]
    assert detail["code"] == "ANOMALY_HARD"
    assert detail["details"]["rule_code"] == "gr_qty_vs_po"
    assert detail["message_mr"]  # bilingual envelope
    assert db.query(GoodsReceipt).count() == 0
    assert db.query(StockLedger).count() == 0
    db.refresh(seeded["entry"])
    assert seeded["entry"].status == "open"


def test_confirm_escalate_registers_hard_and_notifies(client, db, seeded):
    qc = _token(client, "qc1", "q")
    r = _post_gr(client, qc, seeded["entry"].id, "2000", confirm_escalate=True)
    assert r.status_code == 200, r.text
    gr_id = r.json()["id"]
    hard = db.query(Anomaly).filter_by(severity="hard").one()
    assert (hard.rule_code, hard.status) == ("gr_qty_vs_po", "open")
    assert (hard.ref_type, hard.ref_id) == ("goods_receipts", gr_id)
    notes = db.query(Notification).filter_by(kind="anomaly_escalation").all()
    assert len(notes) == 2  # sup1 (supervisor) + boss (management)
    assert {n.tier for n in notes} == {"blocker"}
    assert {n.ref_id for n in notes} == {gr_id}
    # 92.9% deviation also persists the soft flag alongside the registered hard
    assert db.query(Anomaly).filter_by(severity="soft",
                                       rule_code="gr_qty_deviation").count() == 1


def test_full_lot_reject_rgp_no_stock_debit_draft(client, db, seeded):
    """§11.9: qc fail → zero stock_ledger rows, RGP issued, full-basis debit draft."""
    qc = _token(client, "qc1", "q")
    r = _post_gr(client, qc, seeded["entry"].id, str(EXPECTED), qc_result="fail",
                 qc_remarks="Rust on full lot")
    assert r.status_code == 200, r.text
    data = r.json()
    assert Decimal(str(data["accepted_qty"])) == 0
    assert Decimal(str(data["rejected_qty"])) == EXPECTED
    assert db.query(StockLedger).count() == 0
    rgp = db.query(ReturnGatePass).one()
    assert rgp.doc_no.startswith("RGP-")
    assert rgp.goods_receipt_id == data["id"]
    assert rgp.reason == "Rust on full lot"
    assert rgp.status == "issued"
    dn = db.query(DebitNote).one()
    assert dn.kind == "full_lot_reject"
    assert dn.status == "draft"
    assert dn.multiplier == Decimal("1")
    assert dn.amount == dn.base_amount == (EXPECTED * RATE).quantize(Decimal("0.01"))


def test_partial_reject_ledger_gets_accepted_qty(client, db, seeded):
    qc = _token(client, "qc1", "q")
    r = _post_gr(client, qc, seeded["entry"].id, "28090", rejected_qty="100")
    assert r.status_code == 200, r.text
    assert Decimal(str(r.json()["accepted_qty"])) == Decimal("27990")
    led = db.query(StockLedger).one()
    assert led.qty == Decimal("27990")


def test_gr_on_unmatched_entry_rejected(client, db, seeded):
    unmatched = _entry(db, seeded["vendor"], seeded["material"], seeded["po"],
                       match_status="unmatched")
    qc = _token(client, "qc1", "q")
    r = _post_gr(client, qc, unmatched.id, "28090")
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "GR_ENTRY_NOT_READY"


def test_idempotent_replay_same_client_ref(client, db, seeded):
    qc = _token(client, "qc1", "q")
    ref = str(uuid.uuid4())
    r1 = _post_gr(client, qc, seeded["entry"].id, "28090", client_ref=ref)
    r2 = _post_gr(client, qc, seeded["entry"].id, "28090", client_ref=ref)
    assert r1.status_code == r2.status_code == 200
    assert r1.json()["doc_no"] == r2.json()["doc_no"]
    assert db.query(GoodsReceipt).count() == 1
    assert db.query(StockLedger).count() == 1  # no duplicate stock movement


def test_anomaly_register_lists_and_resolve(client, db, seeded):
    """22000 on 28172 = 21.9% deviation → soft flag; register lists it; resolve works."""
    qc = _token(client, "qc1", "q")
    r = _post_gr(client, qc, seeded["entry"].id, "22000")
    assert r.status_code == 200, r.text
    admin = _token(client, "admin", "a")
    rows = client.get("/api/v1/anomalies?severity=soft&status=open", headers=admin).json()
    assert len(rows) == 1
    assert rows[0]["rule_code"] == "gr_qty_deviation"
    assert rows[0]["message_mr"]
    rr = client.post(f"/api/v1/anomalies/{rows[0]['id']}/resolve", headers=admin,
                     json={"note": "vendor short-shipped, debit raised"})
    assert rr.status_code == 200
    assert rr.json()["status"] == "resolved"
    assert rr.json()["resolved_by"] is not None
    assert client.get("/api/v1/anomalies?status=open", headers=admin).json() == []
    assert len(client.get("/api/v1/anomalies?status=resolved", headers=admin).json()) == 1
