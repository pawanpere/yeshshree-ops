"""P23 acceptance: balance math from mixed movements, parallel-run warn-don't-block
(ADR-003 / §11.1), authoritative hard block, SAP stock reconcile via ADJUST rows
(idempotent on re-run), days-of-cover honesty (None without history)."""
import uuid
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.models.config_tables import AppSetting
from app.models.identity import User
from app.models.inventory import Issue, StockLedger
from app.models.master import Material, Vendor
from app.models.system import AuditLog, ImportJob
from app.models.workflow import Anomaly
from app.services import inventory as inv
import app.core.db as db_mod


def _seed_ledger(db, material_id, location, qty, *, vendor_id=None, uom="KG",
                 movement="GR_IN"):
    db.add(StockLedger(material_id=material_id, location=location, movement=movement,
                       qty=Decimal(str(qty)), uom=uom, vendor_id=vendor_id,
                       ref_type="seed", ref_id=0, created_by=None))


@pytest.fixture()
def seeded(db):
    db.add_all([
        User(username="admin", password_hash=hash_password("a"), full_name="A",
             role="admin", language="en"),
        User(username="store1", password_hash=hash_password("s"), full_name="S",
             role="plant_ops", station="store", language="mr"),
    ])
    material = Material(sap_code="1101030569", description="CRCA SHEET D TG04",
                        mat_type="ROH", mat_group="1103", uom="KG",
                        price=Decimal("63.00"))
    vendor = Vendor(sap_code="V-100", name="Sai Pressings")
    db.add_all([material, vendor])
    db.commit()
    return {"material": material, "vendor": vendor}


@pytest.fixture()
def client(engine, db, seeded):
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False,
                                        expire_on_commit=False)
    from app.main import app
    from app.api.inventory import router as inventory_router
    # Packet scope cannot touch main.py — mount the router here (idempotent).
    if not any(getattr(r, "path", None) == "/api/v1/stock/balances"
               for r in app.routes):
        app.include_router(inventory_router)
    yield TestClient(app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def _token(client, username, password):
    r = client.post("/api/v1/auth/login", json={"username": username, "password": password})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _post_issue(client, headers, material_id, qty, **over):
    body = {"destination": "inhouse", "material_id": material_id, "qty": str(qty),
            "client_ref": str(uuid.uuid4())}
    body.update(over)
    return client.post("/api/v1/issues", json=body, headers=headers)


def test_balances_math_mixed_movements(client, db, seeded):
    """(1) SUM(qty) grouped by material × location, + vendor for AT_VENDOR (§4.6)."""
    m, v = seeded["material"].id, seeded["vendor"].id
    _seed_ledger(db, m, "RM", "100")
    _seed_ledger(db, m, "RM", "-30", movement="ISSUE_OUT")
    _seed_ledger(db, m, "RM", "5", movement="ADJUST")
    _seed_ledger(db, m, "WIP", "7", movement="PROD_IN")
    _seed_ledger(db, m, "AT_VENDOR", "10", vendor_id=v, movement="ISSUE_OUT")
    db.commit()
    admin = _token(client, "admin", "a")
    rows = client.get("/api/v1/stock/balances", headers=admin).json()
    by_key = {(r["material_id"], r["location"], r["vendor_id"]): Decimal(str(r["qty"]))
              for r in rows}
    assert by_key[(m, "RM", None)] == Decimal("75")
    assert by_key[(m, "WIP", None)] == Decimal("7")
    assert by_key[(m, "AT_VENDOR", v)] == Decimal("10")
    # filters
    rm = client.get(f"/api/v1/stock/balances?material_id={m}&location=RM",
                    headers=admin).json()
    assert len(rm) == 1 and Decimal(str(rm[0]["qty"])) == Decimal("75")
    av = client.get(f"/api/v1/stock/balances?vendor_id={v}", headers=admin).json()
    assert len(av) == 1 and av[0]["location"] == "AT_VENDOR"


def test_parallel_run_insufficient_posts_with_warning(client, db, seeded):
    """(2) invariant 11 / ADR-003: insufficient stock NEVER blocks in parallel_run —
    posts anyway, response carries the warning, soft anomaly registered."""
    store = _token(client, "store1", "s")
    r = _post_issue(client, store, seeded["material"].id, "50")
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["status"] == "posted"
    assert data["stock_warning"] is True
    assert data["limit_check"]["stock"]["warned"] is True
    anomaly = db.query(Anomaly).filter_by(rule_code="stock_insufficient_warned").one()
    assert anomaly.severity == "soft"
    assert (anomaly.ref_type, anomaly.ref_id) == ("issues", data["id"])
    assert anomaly.message_mr  # bilingual
    led = db.query(StockLedger).filter_by(ref_type="issues", ref_id=data["id"]).one()
    assert led.qty == Decimal("-50")  # posted anyway


def test_authoritative_insufficient_blocks_422(client, db, seeded):
    """(3) same shortfall in authoritative mode → 422 STOCK_INSUFFICIENT envelope."""
    db.add(AppSetting(key="ops_mode", value={"mode": "authoritative"}))
    db.commit()
    store = _token(client, "store1", "s")
    r = _post_issue(client, store, seeded["material"].id, "50")
    assert r.status_code == 422
    detail = r.json()["detail"]
    assert detail["code"] == "STOCK_INSUFFICIENT"
    assert detail["message_mr"]  # bilingual envelope
    assert detail["details"]["balance"] == "0.000"
    assert db.query(Issue).count() == 0
    assert db.query(StockLedger).count() == 0
    assert db.query(Anomaly).count() == 0


def test_reconcile_adjusts_drift_then_idempotent(client, db, seeded):
    """(4) §11.1: snapshot 500 vs ledger 460 → ONE ADJUST +40 (audited); the same
    snapshot again → zero adjustments (delta 0 by construction)."""
    m = seeded["material"]
    _seed_ledger(db, m.id, "RM", "460")
    db.commit()
    admin = _token(client, "admin", "a")
    snapshot = f"Material\tQty\tUoM\n{m.sap_code}\t500\tKG\n".encode()
    r = client.post("/api/v1/imports/sap-stock", headers=admin,
                    files={"file": ("stock.txt", snapshot, "text/tab-separated-values")})
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["adjustments"] == 1
    assert data["rows_total"] == data["rows_ok"] == 1
    adj = db.query(StockLedger).filter_by(movement="ADJUST").one()
    assert adj.qty == Decimal("40")
    assert (adj.ref_type, adj.ref_id) == ("import_job", data["import_job_id"])
    job = db.get(ImportJob, data["import_job_id"])
    assert (job.kind, job.status) == ("sap_stock", "completed")
    audit = db.query(AuditLog).filter_by(entity="stock_ledger", entity_id=adj.id).one()
    assert audit.after["delta"] == "40.000"
    # rerun the SAME snapshot → no drift left, no new ADJUST
    r2 = client.post("/api/v1/imports/sap-stock", headers=admin,
                     files={"file": ("stock.txt", snapshot, "text/tab-separated-values")})
    assert r2.status_code == 200
    assert r2.json()["adjustments"] == 0
    assert db.query(StockLedger).filter_by(movement="ADJUST").count() == 1
    assert inv.balance_qty(db, m.id, "RM") == Decimal("500")


def test_days_of_cover_none_without_history(client, db, seeded):
    """(5) no consumption history → None, never a fake number; with history → math."""
    m = seeded["material"]
    admin = _token(client, "admin", "a")
    r = client.get(f"/api/v1/stock/days-of-cover/{m.id}", headers=admin)
    assert r.status_code == 200
    assert r.json()["days_of_cover"] is None
    # 300 in, 60 consumed over the window → avg 2/day, balance 240 → 120 days
    _seed_ledger(db, m.id, "RM", "300")
    _seed_ledger(db, m.id, "RM", "-60", movement="ISSUE_OUT")
    db.commit()
    r2 = client.get(f"/api/v1/stock/days-of-cover/{m.id}", headers=admin)
    assert Decimal(str(r2.json()["days_of_cover"])) == Decimal("120.0")
