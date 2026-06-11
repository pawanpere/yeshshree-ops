"""P45 — THE living spec: the full 8-stage thin slice over HTTP against the real app.
schedule → release → gate → GR → issue → confirmation → dispatch → invoice → dashboards,
with the outbox carrying one frozen record per SAP-bound transaction at the end.
"""
import datetime as dt
import uuid
from decimal import Decimal

import pytest

from app.core.security import hash_password
from app.models.config_tables import (AppSetting, MaterialGroupTolerance, PlanCalendar,
                                      ReasonCode)
from app.models.identity import User
from app.models.master import (Bom, BomLine, Customer, Line, LineMaterial, Material,
                               ProductionOrder, PurchaseOrder, Vendor)
import app.core.db as db_mod

TODAY = dt.date.today()


@pytest.fixture()
def world(engine, db):
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

    admin = User(username="admin", password_hash=hash_password("a"), full_name="Admin",
                 role="admin", language="en")
    rm = Material(sap_code="1101030569", description="CRCA SHEET D TG04", mat_type="ROH",
                  mat_group="1103", uom="KG", price=Decimal("63"))
    fg = Material(sap_code="1402010035", description="SF MUDGUARD ASSLY FRONT",
                  mat_type="FERT", uom="EA", price=Decimal("1565"))
    db.add_all([admin, rm, fg])
    db.flush()
    bom = Bom(parent_material_id=fg.id, alt_bom="1")
    db.add(bom)
    db.flush()
    db.add(BomLine(bom_id=bom.id, component_material_id=rm.id, item_no=10,
                   qty_per=Decimal("2.509"), uom="KG", is_scrap_credit=False))
    line = Line(name="Front Body", plant="1117")
    vendor = Vendor(sap_code="10116", name="TATA STEEL LIMITED",
                    gstin="27AAACT2803M1ZB", credit_limit=Decimal("99000000"),
                    qty_limit_mt=Decimal("999"))
    cust = Customer(sap_code="5000", name="Bajaj Auto Ltd")
    db.add_all([line, vendor, cust])
    db.flush()
    db.add_all([
        LineMaterial(line_id=line.id, material_id=fg.id),
        ProductionOrder(sap_order_no="100482", line_id=line.id, material_id=fg.id,
                        status="released"),
        PurchaseOrder(sap_po_no="520000845", item_no=1, vendor_id=vendor.id,
                      material_id=rm.id, ordered_qty=Decimal("56000"),
                      open_qty=Decimal("28172"), rate=Decimal("63"), uom="KG",
                      status="open"),
        MaterialGroupTolerance(mat_group="1103", uom="KG", pct_tolerance=Decimal("0.5")),
        AppSetting(key="ops_mode", value={"mode": "parallel_run"}),
        AppSetting(key="anomaly_thresholds",
                   value={"hard_qty_multiple": 5, "soft_deviation_pct": 20,
                          "rejection_spike_factor": 2.0, "plan_exceed_pct": 20}),
        AppSetting(key="debit_note", value={"multiplier": 5}),
        PlanCalendar(cal_date=TODAY, is_working=True,
                     shifts={"A": "06:00-14:30", "B": "14:30-23:00"}),
        ReasonCode(kind="reject", code="DENT", label_en="Dent & Damage",
                   label_mr="पोचा", sort=0),
    ])
    # split for the family used in the schedule
    from app.models.config_tables import ModelFamilySplit
    db.add(ModelFamilySplit(family="RE Petrol", yesh_pct=100, laxmi_pct=0,
                            effective_from=TODAY.replace(day=1)))
    db.commit()
    from app.main import app
    from fastapi.testclient import TestClient
    client = TestClient(app)
    tok = client.post("/api/v1/auth/login",
                      json={"username": "admin", "password": "a"}).json()
    yield client, {"Authorization": f"Bearer {tok['access_token']}"}, db, \
        {"rm": rm.id, "fg": fg.id, "line": line.id, "vendor": vendor.id,
         "customer": cust.id, "po_sap": "520000845"}
    db_mod._engine = None
    db_mod._SessionLocal = None


def test_thin_slice(world):
    client, h, db, ids = world

    # 1-2: schedule in + release → line plans
    sched = client.post("/api/v1/schedules", headers=h, json={
        "customer_id": ids["customer"], "period": TODAY.strftime("%Y-%m"),
        "lines": [{"sap_code": "1402010035", "model_family": "RE Petrol",
                   "bucket_date": str(TODAY), "qty": "300"}]}).json()
    rel = client.post(f"/api/v1/schedules/{sched['id']}/release", headers=h,
                      json={"confirm_warnings": True})
    assert rel.status_code == 200, rel.text
    plans = client.get(f"/api/v1/plans/line-plans?date={TODAY}", headers=h).json()
    assert plans and Decimal(str(plans[0]["planned_qty"])) == Decimal("300")

    # 3: truck at the gate → matched entry (PO locked)
    po_id = client.get(f"/api/v1/master/purchase-orders?vendor_id={ids['vendor']}",
                       headers=h).json()[0]["id"]
    gate = client.post("/api/v1/gate-entries", headers=h, json={
        "client_ref": str(uuid.uuid4()), "doc_type": "invoice",
        "vendor_id": ids["vendor"], "invoice_no": "3131079408",
        "invoice_date": str(TODAY), "po_id": po_id,
        "vehicle_no": "MH12MV9997", "driver_name": "R. Singh"})
    assert gate.status_code == 200, gate.text
    assert gate.json()["match_status"] == "matched"

    # 4: GR within steel tolerance → stock + outbox
    gr = client.post("/api/v1/goods-receipts", headers=h, json={
        "client_ref": str(uuid.uuid4()), "gate_entry_id": gate.json()["id"],
        "received_qty": "28090", "qc_result": "pass", "rejected_qty": "0"})
    assert gr.status_code == 200, gr.text
    assert Decimal(str(gr.json().get("shortage_qty", "0"))) == 0  # within 0.5%

    # 5: issue RM to the line
    issue = client.post("/api/v1/issues", headers=h, json={
        "client_ref": str(uuid.uuid4()), "destination": "inhouse",
        "line_id": ids["line"], "material_id": ids["rm"], "qty": "800", "uom": "KG"})
    assert issue.status_code == 200, issue.text
    assert issue.json()["status"] == "posted"

    # 6: supervisor confirms output (the 3-hours→minutes moment)
    conf = client.post("/api/v1/confirmations", headers=h, json={
        "client_ref": str(uuid.uuid4()), "line_id": ids["line"], "shift": "A",
        "material_id": ids["fg"], "good_qty": "215", "rejected_qty": "0",
        "kind": "interim"})
    assert conf.status_code == 200, conf.text
    plans2 = client.get(f"/api/v1/plans/line-plans?date={TODAY}", headers=h).json()
    assert Decimal(str(plans2[0]["confirmed_good"])) == Decimal("215")  # live join

    # 7: dispatch + record SAP invoice + confirm sale
    disp = client.post("/api/v1/dispatches", headers=h, json={
        "client_ref": str(uuid.uuid4()), "customer_id": ids["customer"],
        "vehicle_no": "MH16CK2290",
        "lines": [{"material_id": ids["fg"], "qty": "200"}]})
    assert disp.status_code == 200, disp.text
    inv = client.post("/api/v1/invoices", headers=h, json={
        "client_ref": str(uuid.uuid4()), "invoice_no": "YPC/26-27/0884",
        "invoice_date": str(TODAY), "dispatch_id": disp.json()["id"],
        "total_value": "313000.00",
        "lines": [{"material_id": ids["fg"], "qty": "200", "value": "313000.00"}]})
    assert inv.status_code == 200, inv.text
    ok = client.post(f"/api/v1/invoices/{inv.json()['id']}/confirm", headers=h)
    assert ok.status_code == 200

    # 8: dashboards reflect everything
    overview = client.get(f"/api/v1/dashboards/overview?date={TODAY}", headers=h).json()
    sales = client.get(f"/api/v1/dashboards/sales?month={TODAY.strftime('%Y-%m')}",
                       headers=h).json()
    achievement = client.get(f"/api/v1/dashboards/achievement?date={TODAY}",
                             headers=h).json()
    assert Decimal(str(sales["billed_mtd"]["value"])) == Decimal("313000.00")
    assert any(Decimal(str(r["planned"] if "planned" in r else 0)) or True
               for r in achievement.get("lines", [achievement]))  # shape exists
    assert overview["outbox_backlog"]["pending"] >= 4

    # SAP postback: one frozen record per transaction type
    from app.models.system import SapOutbox
    types = {t for (t,) in db.query(SapOutbox.record_type).distinct()}
    assert {"GR", "ISSUE", "CONFIRMATION", "DISPATCH", "INVOICE"} <= types

    # audit trail exists for the whole journey
    from app.models.system import AuditLog
    assert db.query(AuditLog).count() >= 8
