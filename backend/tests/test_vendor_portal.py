"""Phase 6: vendor portal. INVARIANT 5 — a vendor reads ONLY their own data, scoped
in the service from the JWT vendor_id (no client-supplied id to tamper with)."""
from decimal import Decimal
import uuid

import pytest
from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.models.identity import User
from app.models.inventory import DebitNote, StockLedger
from app.models.master import Material, PurchaseOrder, Vendor
import app.core.db as db_mod


@pytest.fixture()
def world(db):
    v1 = Vendor(sap_code="V001", name="Sandhar Steel",
                credit_limit=Decimal("1000000.00"), qty_limit_mt=Decimal("500"))
    v2 = Vendor(sap_code="V002", name="Bharat Forge",
                credit_limit=Decimal("2000000.00"), qty_limit_mt=Decimal("800"))
    db.add_all([v1, v2])
    db.flush()
    db.add_all([
        User(username="v1user", password_hash=hash_password("p1"), full_name="V1",
             role="vendor", vendor_id=v1.id, language="en"),
        User(username="v2user", password_hash=hash_password("p2"), full_name="V2",
             role="vendor", vendor_id=v2.id, language="en"),
        User(username="orphan", password_hash=hash_password("po"), full_name="O",
             role="vendor", language="en"),  # vendor account, NO vendor_id linked
        User(username="admin", password_hash=hash_password("a"), full_name="A",
             role="admin", language="en"),
    ])
    mat = Material(sap_code="CR-25", description="CR coil 2.5mm", mat_type="ROH",
                   uom="KG", category="rm", price=Decimal("60.00"))
    db.add(mat)
    db.flush()
    db.add_all([
        PurchaseOrder(sap_po_no="PO-V1", item_no=10, vendor_id=v1.id,
                      material_id=mat.id, ordered_qty=Decimal("1000"),
                      open_qty=Decimal("400"), rate=Decimal("60"), uom="KG",
                      status="open"),
        PurchaseOrder(sap_po_no="PO-V2", item_no=10, vendor_id=v2.id,
                      material_id=mat.id, ordered_qty=Decimal("2000"),
                      open_qty=Decimal("0"), rate=Decimal("60"), uom="KG",
                      status="open"),
    ])
    # 5000 KG of our material sits AT vendor 1 (exposure = 5000 × 60 = 300000).
    db.add(StockLedger(material_id=mat.id, location="AT_VENDOR", movement="ISSUE_OUT",
                       qty=Decimal("5000"), uom="KG", vendor_id=v1.id,
                       ref_type="issues", ref_id=1))
    db.add(DebitNote(doc_no="DN-1", goods_receipt_id=1, vendor_id=v1.id,
                     kind="shortage_5x", base_amount=Decimal("1000"),
                     multiplier=Decimal("5"), amount=Decimal("5000"), status="draft"))
    db.commit()
    return {"v1": v1, "v2": v2, "mat": mat}


@pytest.fixture()
def client(engine, db, world):
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False,
                                        expire_on_commit=False)
    from app.main import app
    yield TestClient(app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def _login(client, u, p):
    r = client.post("/api/v1/auth/login", json={"username": u, "password": p})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_vendor_sees_only_their_own_purchase_orders(client):
    v1 = _login(client, "v1user", "p1")
    rows = client.get("/api/v1/vendor/purchase-orders", headers=v1).json()
    pos = {r["sap_po_no"] for r in rows}
    assert pos == {"PO-V1"}  # NOT PO-V2

    v2 = _login(client, "v2user", "p2")
    rows2 = client.get("/api/v1/vendor/purchase-orders", headers=v2).json()
    assert {r["sap_po_no"] for r in rows2} == {"PO-V2"}


def test_vendor_exposure_is_scoped(client):
    v1 = _login(client, "v1user", "p1")
    exp1 = client.get("/api/v1/vendor/exposure", headers=v1).json()
    assert Decimal(str(exp1["credit_exposure"])) == Decimal("300000.00")
    assert Decimal(str(exp1["credit_limit"])) == Decimal("1000000.00")

    v2 = _login(client, "v2user", "p2")
    exp2 = client.get("/api/v1/vendor/exposure", headers=v2).json()
    assert Decimal(str(exp2["credit_exposure"])) == Decimal("0.00")


def test_vendor_stock_and_debit_notes_scoped(client):
    v1 = _login(client, "v1user", "p1")
    stock = client.get("/api/v1/vendor/stock", headers=v1).json()
    assert len(stock) == 1 and Decimal(str(stock[0]["qty"])) == Decimal("5000")
    dns = client.get("/api/v1/vendor/debit-notes", headers=v1).json()
    assert [d["doc_no"] for d in dns] == ["DN-1"]

    v2 = _login(client, "v2user", "p2")
    assert client.get("/api/v1/vendor/stock", headers=v2).json() == []
    assert client.get("/api/v1/vendor/debit-notes", headers=v2).json() == []


def test_vendor_with_no_linked_vendor_is_refused(client):
    orphan = _login(client, "orphan", "po")
    r = client.get("/api/v1/vendor/purchase-orders", headers=orphan)
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "VENDOR_NOT_LINKED"


def test_non_vendor_role_is_forbidden(client):
    admin = _login(client, "admin", "a")
    assert client.get("/api/v1/vendor/purchase-orders", headers=admin).status_code == 403
    assert client.get("/api/v1/vendor/exposure", headers=admin).status_code == 403
