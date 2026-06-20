"""Phase 4: material stock category (rm/component/fg), COMP stock routing on GR, and
the job_work_return inward category. A purchased component GRs to the COMP store; raw
material still GRs to RM (back-compatible)."""
import uuid
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app.core.security import hash_password
from app.models.config_tables import MaterialGroupTolerance
from app.models.gate import GateEntry
from app.models.identity import User
from app.models.inventory import StockLedger
from app.models.master import Material, PurchaseOrder, Vendor
import app.core.db as db_mod


# ---- model-level: the stock_location property + the new CHECK constraints ----

def test_stock_location_property():
    comp = Material(sap_code="C1", description="Fastener M8", mat_type="HAWA",
                    uom="EA", category="component")
    rm = Material(sap_code="R1", description="CR coil", mat_type="ROH",
                  uom="KG", category="rm")
    fg = Material(sap_code="F1", description="Front fork", mat_type="FERT",
                  uom="EA", category="fg")
    assert comp.stock_location == "COMP"
    assert rm.stock_location == "RM"
    assert fg.stock_location == "RM"  # fg is never GR'd inbound; never routes to COMP


def test_category_check_rejects_unknown(db):
    db.add(Material(sap_code="X1", description="bad", mat_type="ROH", uom="EA",
                    category="widget"))
    with pytest.raises(IntegrityError):
        db.commit()


def _gate_entry(**over):
    base = dict(doc_no=f"G-{uuid.uuid4().hex[:8]}", vehicle_no="MH12AB1",
                driver_name="R", doc_type="challan", match_status="unmatched",
                status="open", client_ref=uuid.uuid4(), created_by=1)
    base.update(over)
    return GateEntry(**base)


def test_inward_category_accepts_job_work_return(db):
    db.add(_gate_entry(inward_category="job_work_return"))
    db.commit()  # must not raise
    assert db.query(GateEntry).filter_by(
        inward_category="job_work_return").count() == 1


def test_inward_category_rejects_unknown(db):
    db.add(_gate_entry(inward_category="nope"))
    with pytest.raises(IntegrityError):
        db.commit()


def test_inward_category_schema_accepts_job_work_return():
    # The API request type must accept it too, not just the DB CHECK.
    from pydantic import TypeAdapter

    from app.schemas.gate import InwardCategory
    adapter = TypeAdapter(InwardCategory)
    assert adapter.validate_python("job_work_return") == "job_work_return"
    with pytest.raises(Exception):
        adapter.validate_python("not_a_category")


# ---- service-level: GR routes a component to COMP, raw material to RM ----

EXPECTED = Decimal("500.000")


@pytest.fixture()
def world(db):
    db.add(User(username="qc1", password_hash=hash_password("q"), full_name="Q",
                role="plant_ops", station="qc", language="en"))
    vendor = Vendor(sap_code="V-9", name="Sandhar")
    component = Material(sap_code="FAST-M8", description="Fasteners M8",
                         mat_type="HAWA", mat_group="9999", uom="EA",
                         category="component", price=Decimal("12.00"))
    rm = Material(sap_code="CR-25", description="CR coil 2.5", mat_type="ROH",
                  mat_group="9999", uom="KG", category="rm", price=Decimal("60.00"))
    db.add_all([vendor, component, rm])
    db.flush()
    db.add(MaterialGroupTolerance(mat_group="9999", uom="EA",
                                  pct_tolerance=Decimal("0.50")))
    pos, entries = {}, {}
    for key, mat in {"component": component, "rm": rm}.items():
        po = PurchaseOrder(sap_po_no=f"PO-{key}", item_no=10, vendor_id=vendor.id,
                           material_id=mat.id, ordered_qty=EXPECTED, open_qty=EXPECTED,
                           rate=Decimal("12.00"), uom=mat.uom, status="open")
        db.add(po)
        db.flush()
        pos[key] = po
        e = GateEntry(doc_no=f"G-{key}", vendor_id=vendor.id, invoice_no=f"INV-{key}",
                      po_id=po.id, material_id=mat.id, qty_expected=EXPECTED,
                      vehicle_no="MH12AB1", driver_name="R", match_status="matched",
                      status="open", client_ref=uuid.uuid4(), created_by=1)
        db.add(e)
        entries[key] = e
    db.commit()
    return {"component_entry": entries["component"], "rm_entry": entries["rm"]}


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


def _qc(client):
    r = client.post("/api/v1/auth/login", json={"username": "qc1", "password": "q"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _post_gr(client, headers, entry_id):
    return client.post("/api/v1/goods-receipts", headers=headers, json={
        "gate_entry_id": entry_id, "received_qty": str(EXPECTED),
        "qc_result": "pass", "client_ref": str(uuid.uuid4())})


def test_component_gr_posts_to_comp(client, db, world):
    r = _post_gr(client, _qc(client), world["component_entry"].id)
    assert r.status_code == 200, r.text
    led = db.query(StockLedger).filter_by(
        ref_id=r.json()["id"], movement="GR_IN").one()
    assert led.location == "COMP"
    assert led.qty == EXPECTED


def test_raw_material_gr_posts_to_rm(client, db, world):
    r = _post_gr(client, _qc(client), world["rm_entry"].id)
    assert r.status_code == 200, r.text
    led = db.query(StockLedger).filter_by(
        ref_id=r.json()["id"], movement="GR_IN").one()
    assert led.location == "RM"


def test_issue_of_a_component_is_refused(client, db, world):
    """Outbound component routing is a later phase; issuing a component must be
    refused (not silently posted to RM, which parallel_run would not block)."""
    comp = db.query(Material).filter_by(sap_code="FAST-M8").one()
    r = client.post("/api/v1/issues", headers=_qc(client), json={
        "destination": "inhouse", "material_id": comp.id, "qty": "1",
        "client_ref": str(uuid.uuid4())})
    assert r.status_code == 422, r.text
    assert r.json()["detail"]["code"] == "ISSUE_COMPONENT_UNSUPPORTED"
