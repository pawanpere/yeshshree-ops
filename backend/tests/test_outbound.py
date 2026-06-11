"""P34 acceptance: dispatch (DN-, FG DISPATCH_OUT ledger, outbox DISPATCH), §11.1
parallel-run warn vs authoritative block, SAP invoice recording + dispatch match
(ok / mismatch+reason / mismatch anomaly), confirm-sale (outbox INVOICE, dispatch
invoiced), not-open dispatch rejection, idempotent replay on dispatch + invoice."""
import uuid
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.models.config_tables import AppSetting
from app.models.identity import User
from app.models.inventory import StockLedger
from app.models.master import Customer, Material
from app.models.outbound import Dispatch, DispatchLine, SalesInvoice, SalesInvoiceLine
from app.models.system import SapOutbox
from app.models.workflow import Anomaly
import app.core.db as db_mod

FG1_STOCK = Decimal("1500")
FG2_STOCK = Decimal("1200")


def _seed_fg(db, material_id, qty, uom="EA"):
    """FG stock arrives only via the ledger (invariant 2) — PROD_IN seed rows."""
    db.add(StockLedger(material_id=material_id, location="FG", movement="PROD_IN",
                       qty=Decimal(str(qty)), uom=uom, vendor_id=None,
                       ref_type="seed", ref_id=0, created_by=None))


@pytest.fixture()
def seeded(db):
    db.add_all([
        User(username="admin", password_hash=hash_password("a"), full_name="A",
             role="admin", language="en"),
        User(username="store1", password_hash=hash_password("s"), full_name="S",
             role="plant_ops", station="store", language="mr"),
    ])
    bajaj = Customer(sap_code="5000", name="Bajaj Auto Ltd", gstin="27AAACB2902H1ZN")
    fg1 = Material(sap_code="2201050001", description="BRACKET COMP FRAME KTM",
                   mat_type="FERT", uom="EA", price=Decimal("118.50"))
    fg2 = Material(sap_code="2201050002", description="GUARD CHAIN PULSAR",
                   mat_type="FERT", uom="EA", price=Decimal("96.00"))
    db.add_all([bajaj, fg1, fg2])
    db.flush()
    _seed_fg(db, fg1.id, FG1_STOCK)
    _seed_fg(db, fg2.id, FG2_STOCK)
    db.add_all([
        AppSetting(key="ops_mode", value={"mode": "parallel_run"}),
        AppSetting(key="anomaly_thresholds",
                   value={"hard_qty_multiple": 5, "soft_deviation_pct": 20,
                          "rejection_spike_factor": 2.0}),
    ])
    db.commit()
    return {"bajaj": bajaj, "fg1": fg1, "fg2": fg2}


@pytest.fixture()
def client(engine, db, seeded):
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False,
                                        expire_on_commit=False)
    from app.main import app
    from app.api.outbound import router as outbound_router
    # Packet scope cannot touch main.py — mount the router here (idempotent).
    if not any(getattr(r, "path", None) == "/api/v1/dispatches" for r in app.routes):
        app.include_router(outbound_router)
    yield TestClient(app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def _token(client, username, password):
    r = client.post("/api/v1/auth/login", json={"username": username, "password": password})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _post_dispatch(client, headers, seeded, lines=None, **over):
    body = {"customer_id": seeded["bajaj"].id, "vehicle_no": "MH14GH7777",
            "lines": lines or [{"material_id": seeded["fg1"].id, "qty": "500"},
                               {"material_id": seeded["fg2"].id, "qty": "300"}],
            "client_ref": str(uuid.uuid4())}
    body.update(over)
    return client.post("/api/v1/dispatches", json=body, headers=headers)


def _post_invoice(client, headers, dispatch_id, lines, **over):
    body = {"invoice_no": "9152206841", "invoice_date": "2026-06-11",
            "dispatch_id": dispatch_id, "irn": "f3a1" + "0" * 60,
            "eway_bill_no": "171009876543", "total_value": "88050.00",
            "lines": lines, "client_ref": str(uuid.uuid4())}
    body.update(over)
    return client.post("/api/v1/invoices", json=body, headers=headers)


def _fg_balance(db, material_id):
    from app.services.inventory import balance_qty
    return balance_qty(db, material_id, "FG")


def _set_mode(db, mode):
    row = db.get(AppSetting, "ops_mode")
    row.value = {"mode": mode}
    db.commit()


def test_dispatch_happy_path(client, db, seeded):
    """(1) DN- doc, two negative DISPATCH_OUT FG rows, balances reduced,
    outbox DISPATCH with sap codes, total_pcs = Σqty."""
    store = _token(client, "store1", "s")
    r = _post_dispatch(client, store, seeded)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["doc_no"].startswith("DN-")
    assert data["status"] == "open"
    assert data["total_pcs"] == 800
    assert data["stock_warning"] is False
    assert len(data["lines"]) == 2
    led = (db.query(StockLedger)
           .filter_by(ref_type="dispatches", ref_id=data["id"])
           .order_by(StockLedger.id).all())
    assert [(l.movement, l.location, l.qty) for l in led] == [
        ("DISPATCH_OUT", "FG", Decimal("-500")),
        ("DISPATCH_OUT", "FG", Decimal("-300"))]
    assert _fg_balance(db, seeded["fg1"].id) == Decimal("1000")
    assert _fg_balance(db, seeded["fg2"].id) == Decimal("900")
    ob = db.query(SapOutbox).filter_by(record_type="DISPATCH").one()
    assert ob.status == "pending"
    assert ob.payload["doc_no"] == data["doc_no"]
    assert ob.payload["customer_sap_code"] == "5000"
    assert ob.payload["total_pcs"] == 800
    assert [l["material_sap_code"] for l in ob.payload["lines"]] == \
        ["2201050001", "2201050002"]
    assert ob.payload["lines"][0]["qty"] == "500.000"


def test_dispatch_beyond_fg_warns_then_blocks(client, db, seeded):
    """(2) §11.1: parallel_run posts + soft stock_insufficient_warned + warn flag;
    authoritative → 422 STOCK_INSUFFICIENT, nothing written."""
    store = _token(client, "store1", "s")
    over = [{"material_id": seeded["fg1"].id, "qty": "2000"}]  # > 1500 FG
    r = _post_dispatch(client, store, seeded, lines=over)
    assert r.status_code == 200, r.text
    assert r.json()["stock_warning"] is True
    a = db.query(Anomaly).filter_by(rule_code="stock_insufficient_warned").one()
    assert (a.severity, a.status) == ("soft", "open")
    assert (a.ref_type, a.ref_id) == ("dispatches", r.json()["id"])
    assert a.observed["requested"] == "2000.000"
    assert a.message_mr  # bilingual
    # posted anyway: FG goes negative (parallel run never blocks — invariant 11)
    assert _fg_balance(db, seeded["fg1"].id) == Decimal("-500")

    _set_mode(db, "authoritative")
    before = db.query(Dispatch).count()
    r2 = _post_dispatch(client, store, seeded,
                        lines=[{"material_id": seeded["fg2"].id, "qty": "5000"}])
    assert r2.status_code == 422
    detail = r2.json()["detail"]
    assert detail["code"] == "STOCK_INSUFFICIENT"
    assert detail["message_mr"]
    assert db.query(Dispatch).count() == before
    assert _fg_balance(db, seeded["fg2"].id) == FG2_STOCK


def test_invoice_equal_qtys_match_ok_pending(client, db, seeded):
    """(3) Σqty per material equal → match ok, status pending, NO stock effect,
    NO outbox INVOICE yet (that belongs to confirm)."""
    store = _token(client, "store1", "s")
    d = _post_dispatch(client, store, seeded).json()
    ledger_before = db.query(StockLedger).count()
    r = _post_invoice(client, store, d["id"],
                      [{"material_id": seeded["fg1"].id, "qty": "500", "value": "59250.00"},
                       {"material_id": seeded["fg2"].id, "qty": "300", "value": "28800.00"}])
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["match_status"] == "ok"
    assert data["status"] == "pending"
    assert data["confirmed_by"] is None
    assert len(data["lines"]) == 2
    assert db.query(StockLedger).count() == ledger_before  # no stock effect
    assert db.query(SapOutbox).filter_by(record_type="INVOICE").count() == 0


def test_invoice_mismatch_requires_reason_then_records(client, db, seeded):
    """(4) differing qty w/o reason → 422; with reason → recorded mismatch + soft
    anomaly invoice_dispatch_mismatch with per-material observed/expected."""
    store = _token(client, "store1", "s")
    d = _post_dispatch(client, store, seeded).json()
    lines = [{"material_id": seeded["fg1"].id, "qty": "480", "value": "56880.00"},
             {"material_id": seeded["fg2"].id, "qty": "300", "value": "28800.00"}]
    r = _post_invoice(client, store, d["id"], lines)
    assert r.status_code == 422
    detail = r.json()["detail"]
    assert detail["code"] == "INVOICE_MISMATCH_REASON_REQUIRED"
    assert detail["message_mr"]
    assert detail["details"]["observed"] == {"2201050001": "480.000"}
    assert detail["details"]["expected"] == {"2201050001": "500.000"}
    assert db.query(SalesInvoice).count() == 0

    r2 = _post_invoice(client, store, d["id"], lines,
                       mismatch_reason="20 pcs line rejection at Bajaj gate")
    assert r2.status_code == 200, r2.text
    assert r2.json()["match_status"] == "mismatch"
    assert r2.json()["status"] == "pending"
    a = db.query(Anomaly).filter_by(rule_code="invoice_dispatch_mismatch").one()
    assert (a.severity, a.status) == ("soft", "open")
    assert (a.ref_type, a.ref_id) == ("sales_invoices", r2.json()["id"])
    assert a.observed == {"2201050001": "480.000"}
    assert a.expected["2201050001"] == "500.000"
    assert a.expected["mismatch_reason"] == "20 pcs line rejection at Bajaj gate"


def test_confirm_sale_freezes_outbox_and_invoices_dispatch(client, db, seeded):
    """(5) confirm → invoice confirmed (by/at set), dispatch invoiced, outbox
    INVOICE with the frozen payload that feeds the live sales report."""
    store = _token(client, "store1", "s")
    d = _post_dispatch(client, store, seeded).json()
    inv = _post_invoice(client, store, d["id"],
                        [{"material_id": seeded["fg1"].id, "qty": "500", "value": "59250.00"},
                         {"material_id": seeded["fg2"].id, "qty": "300", "value": "28800.00"}]).json()
    r = client.post(f"/api/v1/invoices/{inv['id']}/confirm", headers=store)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["status"] == "confirmed"
    assert data["confirmed_by"] is not None
    assert data["confirmed_at"] is not None
    assert db.get(Dispatch, d["id"]).status == "invoiced"
    ob = db.query(SapOutbox).filter_by(record_type="INVOICE").one()
    assert ob.status == "pending"
    assert ob.payload == {
        "invoice_no": "9152206841",
        "invoice_date": "2026-06-11",
        "dispatch_doc_no": d["doc_no"],
        "lines": [{"material_sap_code": "2201050001", "qty": "500.000",
                   "value": "59250.00"},
                  {"material_sap_code": "2201050002", "qty": "300.000",
                   "value": "28800.00"}],
        "total_value": "88050.00",
        "irn": "f3a1" + "0" * 60,
        "eway_bill_no": "171009876543",
    }
    # confirm retry is idempotent — no second outbox row, same confirmed_at
    r2 = client.post(f"/api/v1/invoices/{inv['id']}/confirm", headers=store)
    assert r2.status_code == 200
    assert r2.json()["confirmed_at"] == data["confirmed_at"]
    assert db.query(SapOutbox).filter_by(record_type="INVOICE").count() == 1


def test_invoice_against_invoiced_dispatch_rejected(client, db, seeded):
    """(6) dispatch already invoiced → 422 INVOICE_DISPATCH_NOT_OPEN."""
    store = _token(client, "store1", "s")
    d = _post_dispatch(client, store, seeded).json()
    lines = [{"material_id": seeded["fg1"].id, "qty": "500", "value": "59250.00"},
             {"material_id": seeded["fg2"].id, "qty": "300", "value": "28800.00"}]
    inv = _post_invoice(client, store, d["id"], lines).json()
    client.post(f"/api/v1/invoices/{inv['id']}/confirm", headers=store)
    r = _post_invoice(client, store, d["id"], lines, invoice_no="9152206842")
    assert r.status_code == 422
    detail = r.json()["detail"]
    assert detail["code"] == "INVOICE_DISPATCH_NOT_OPEN"
    assert detail["details"]["status"] == "invoiced"
    assert detail["message_mr"]


def test_idempotent_replay_dispatch_and_invoice(client, db, seeded):
    """(7) same client_ref retried → original result, no duplicate rows/ledger/outbox."""
    store = _token(client, "store1", "s")
    ref = str(uuid.uuid4())
    r1 = _post_dispatch(client, store, seeded, client_ref=ref)
    r2 = _post_dispatch(client, store, seeded, client_ref=ref)
    assert r1.status_code == r2.status_code == 200
    assert r1.json()["doc_no"] == r2.json()["doc_no"]
    assert db.query(Dispatch).count() == 1
    assert db.query(DispatchLine).count() == 2
    assert db.query(StockLedger).filter_by(movement="DISPATCH_OUT").count() == 2
    assert db.query(SapOutbox).filter_by(record_type="DISPATCH").count() == 1

    d_id = r1.json()["id"]
    iref = str(uuid.uuid4())
    lines = [{"material_id": seeded["fg1"].id, "qty": "500", "value": "59250.00"},
             {"material_id": seeded["fg2"].id, "qty": "300", "value": "28800.00"}]
    i1 = _post_invoice(client, store, d_id, lines, client_ref=iref)
    i2 = _post_invoice(client, store, d_id, lines, client_ref=iref)
    assert i1.status_code == i2.status_code == 200
    assert i1.json()["id"] == i2.json()["id"]
    assert db.query(SalesInvoice).count() == 1
    assert db.query(SalesInvoiceLine).count() == 2
