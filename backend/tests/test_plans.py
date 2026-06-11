"""P11–P13 acceptance: schedule versioning + diff, §11.13 sanity/release/re-release,
placeholder plan math (Domain_QA Q1), BOM→vendor calloffs, plan read views.

Seed: Bajaj customer · RE Petrol split 74/26 eff 2026-06-01 · FERT parent with BOM
(component 2.509 KG + a scrap-credit line that must be skipped) · line + mapping ·
production order · open PO for the component (gives the calloff its vendor)."""
import datetime as dt
from decimal import Decimal

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker

import app.core.db as db_mod
from app.core.security import hash_password
from app.models.config_tables import ModelFamilySplit
from app.models.identity import User
from app.models.master import (Bom, BomLine, Customer, Line, LineMaterial, Material,
                               ProductionOrder, PurchaseOrder, Vendor)
from app.models.planning import LinePlan, Schedule, ScheduleLine, VendorCalloff

TODAY = dt.date.today()
PERIOD = TODAY.strftime("%Y-%m")           # current month → no PERIOD_MISMATCH warn
BUCKET = TODAY.isoformat()
FERT = "91101999001"   # mapped finished part
FERT2 = "91101999002"  # finished part with NO line mapping (test 8)
RM = "1101030569"      # BOM component with an open PO


@pytest.fixture()
def client(engine, db):
    db_mod._engine = engine
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False,
                                        expire_on_commit=False)
    db.add_all([
        User(username="planner", password_hash=hash_password("p"), full_name="P",
             role="planning", language="en"),
        User(username="sup1", password_hash=hash_password("s"), full_name="S",
             role="supervisor", language="mr"),
    ])
    customer = Customer(sap_code="BAJ001", name="Bajaj Auto")
    split = ModelFamilySplit(family="RE Petrol", yesh_pct=74, laxmi_pct=26,
                             effective_from=dt.date(2026, 6, 1))
    fert = Material(sap_code=FERT, description="MUDGUARD ASSY RE", mat_type="FERT",
                    uom="EA")
    fert2 = Material(sap_code=FERT2, description="MUDGUARD ASSY RE LH",
                     mat_type="FERT", uom="EA")
    rm = Material(sap_code=RM, description="CRCA SHEET D TG04", mat_type="ROH",
                  mat_group="1103", uom="KG")
    line = Line(name="Front Body")
    vendor = Vendor(sap_code="V100", name="Vendor One")
    db.add_all([customer, split, fert, fert2, rm, line, vendor])
    db.flush()
    bom = Bom(parent_material_id=fert.id)
    db.add(bom)
    db.flush()
    db.add_all([
        BomLine(bom_id=bom.id, component_material_id=rm.id, item_no=10,
                qty_per=Decimal("2.509"), uom="KG"),
        BomLine(bom_id=bom.id, component_material_id=rm.id, item_no=20,
                qty_per=Decimal("0.400"), uom="KG", is_scrap_credit=True),
        LineMaterial(line_id=line.id, material_id=fert.id),
        ProductionOrder(sap_order_no="100001", line_id=line.id, material_id=fert.id,
                        status="released"),
        PurchaseOrder(sap_po_no="450001", item_no=10, vendor_id=vendor.id,
                      material_id=rm.id, ordered_qty=Decimal("10000"),
                      open_qty=Decimal("8000"), uom="KG", status="open"),
    ])
    db.commit()

    from app.api.auth import router as auth_router
    from app.api.plans import router as plans_router
    test_app = FastAPI()
    test_app.include_router(auth_router)
    test_app.include_router(plans_router)
    yield TestClient(test_app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def _token(client, username="planner", password="p"):
    r = client.post("/api/v1/auth/login", json={"username": username,
                                                "password": password})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _customer_id(db):
    return db.query(Customer).filter_by(sap_code="BAJ001").one().id


def _mk(client, headers, db, *, qty="1000", sap=FERT, period=PERIOD, bucket=BUCKET,
        family="RE Petrol", extra_lines=()):
    lines = [{"sap_code": sap, "model_family": family, "bucket_date": bucket,
              "qty": qty}, *extra_lines]
    r = client.post("/api/v1/schedules", headers=headers,
                    json={"customer_id": _customer_id(db), "period": period,
                          "lines": lines})
    assert r.status_code == 201, r.text
    return r.json()


def _release(client, headers, sid, confirm=False):
    return client.post(f"/api/v1/schedules/{sid}/release", headers=headers,
                       json={"confirm_warnings": confirm})


# 1 — manual create stores lines; v1 diff is empty (no released baseline)
def test_create_v1_manual_lines_and_empty_diff(client, db):
    h = _token(client)
    sched = _mk(client, h, db)
    assert sched["version"] == 1 and sched["status"] == "draft"
    rows = db.query(ScheduleLine).filter_by(schedule_id=sched["id"]).all()
    assert len(rows) == 1
    assert rows[0].qty == Decimal("1000") and rows[0].model_family == "RE Petrol"
    diff = client.get(f"/api/v1/schedules/{sched['id']}/diff", headers=h).json()["diff"]
    assert diff["vs_version"] is None and diff["entries"] == []


# 2 — CSV upload becomes v2; diff vs v1 appears only because v1 was RELEASED
def test_upload_csv_v2_diff_vs_released_v1(client, db):
    h = _token(client)
    v1 = _mk(client, h, db, qty="1000")
    assert _release(client, h, v1["id"]).status_code == 200
    csv_body = f"part_sap_code,model_family,bucket_date,qty\n{FERT},RE Petrol,{BUCKET},1200\nBAD-CODE-ROW\n"
    r = client.post("/api/v1/schedules/upload", headers=h,
                    data={"customer_id": str(_customer_id(db)), "period": PERIOD},
                    files={"file": ("sched.csv", csv_body.encode(), "text/csv")})
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["schedule"]["version"] == 2 and body["rows_ok"] == 1
    assert body["row_errors"][0]["code"] == "BAD_COLUMNS"  # collected, not raised
    diff = body["schedule"] and client.get(
        f"/api/v1/schedules/{body['schedule']['id']}/diff", headers=h).json()["diff"]
    assert diff["vs_version"] == 1
    (entry,) = diff["entries"]
    assert entry["old"] == "1000.000" and entry["new"] == "1200.000"
    assert entry["delta"] == "200.000"
    assert diff["totals"]["delta"] == "200.000"


# 3 — sanity: missing split = hard 422; period mismatch = warn needing confirmation
def test_sanity_split_missing_hard_and_period_warn(client, db):
    h = _token(client)
    bad = _mk(client, h, db, family="RE Diesel")  # no split configured
    r = _release(client, h, bad["id"])
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "SPLIT_MISSING"
    assert "RE Diesel" in r.json()["detail"]["message_en"]

    nxt = (TODAY.replace(day=1) + dt.timedelta(days=32)).replace(day=1)
    future = _mk(client, h, db, period=nxt.strftime("%Y-%m"),
                 bucket=nxt.replace(day=15).isoformat())
    r2 = _release(client, h, future["id"])
    assert r2.status_code == 422
    assert r2.json()["detail"]["code"] == "RELEASE_WARNINGS"
    assert {c["code"] for c in r2.json()["detail"]["details"]["checks"]} == \
        {"PERIOD_MISMATCH"}
    assert _release(client, h, future["id"], confirm=True).status_code == 200


# 4 — release math: 1000 × 74% = 740 plan; calloff 740 × 2.509 to the PO's vendor
def test_release_plan_math_and_calloff(client, db):
    h = _token(client)
    v1 = _mk(client, h, db, qty="1000")
    r = _release(client, h, v1["id"])
    assert r.status_code == 200, r.text
    report = r.json()
    assert report["plans_created"] == 1 and report["calloffs_created"] == 1
    assert report["unmapped"] == [] and report["no_vendor"] == []
    plan = db.query(LinePlan).filter_by(schedule_id=v1["id"]).one()
    assert plan.planned_qty == Decimal("740.000")
    assert plan.revision == 1 and plan.status == "active"
    assert plan.plan_date == dt.date.fromisoformat(BUCKET)
    co = db.query(VendorCalloff).filter_by(schedule_id=v1["id"]).one()  # scrap line skipped
    assert co.qty == Decimal("1856.660")  # 740 × 2.509
    assert co.vendor_id == db.query(Vendor).filter_by(sap_code="V100").one().id
    assert co.calloff_date == dt.date.fromisoformat(BUCKET)
    assert co.status == "released"


# 5 — releasing v2 supersedes v1's schedule + plans; new revision is active
def test_release_v2_supersedes_v1_plans(client, db):
    h = _token(client)
    v1 = _mk(client, h, db, qty="1000")
    _release(client, h, v1["id"])
    v2 = _mk(client, h, db, qty="1200")
    assert _release(client, h, v2["id"]).status_code == 200
    db.expire_all()
    assert db.get(Schedule, v1["id"]).status == "superseded"
    old = db.query(LinePlan).filter_by(schedule_id=v1["id"]).one()
    new = db.query(LinePlan).filter_by(schedule_id=v2["id"]).one()
    assert old.status == "superseded" and old.revision == 1
    assert new.status == "active" and new.revision == 2
    assert new.planned_qty == Decimal("888.000")  # 1200 × 74%


# 6 — §11.13 rollback: re-release v1 = NEW released version with v1 qty; nothing deleted
def test_re_release_clones_as_new_version(client, db):
    h = _token(client)
    v1 = _mk(client, h, db, qty="1000")
    _release(client, h, v1["id"])
    v2 = _mk(client, h, db, qty="1200")
    _release(client, h, v2["id"])
    r = client.post(f"/api/v1/schedules/{v1['id']}/re-release", headers=h)
    assert r.status_code == 200, r.text
    report = r.json()
    assert report["version"] == 3 and report["cloned_from_version"] == 1
    db.expire_all()
    v3 = db.get(Schedule, report["schedule_id"])
    assert v3.status == "released"
    assert db.get(Schedule, v2["id"]).status == "superseded"
    new_plan = db.query(LinePlan).filter_by(schedule_id=v3.id).one()
    assert new_plan.planned_qty == Decimal("740.000")  # v1 quantities
    assert new_plan.revision == 3 and new_plan.status == "active"
    # nothing deleted: all 3 schedule versions, lines, and plan revisions remain
    assert db.query(Schedule).count() == 3
    assert db.query(ScheduleLine).count() == 3
    assert db.query(LinePlan).count() == 3


# 7 — supervisor view: frozen planned/confirmed/remaining shape + production order id
def test_supervisor_view_shape(client, db):
    h = _token(client)
    v1 = _mk(client, h, db, qty="1000")
    _release(client, h, v1["id"])
    line_id = db.query(Line).one().id
    sup = _token(client, "sup1", "s")  # internal read role
    r = client.get("/api/v1/plans/supervisor-view",
                   params={"line_id": line_id, "date": BUCKET}, headers=sup)
    assert r.status_code == 200
    (row,) = r.json()
    assert row["sap_code"] == FERT and row["line_name"] == "Front Body"
    assert Decimal(row["planned_qty"]) == Decimal("740.000")
    assert Decimal(row["confirmed_good"]) == 0  # placeholder until production packet
    assert Decimal(row["confirmed_reject"]) == 0
    assert Decimal(row["remaining"]) == Decimal("740.000")
    order = db.query(ProductionOrder).one()
    assert row["production_order_id"] == order.id
    assert row["sap_order_no"] == "100001"
    # ppc + line-plans views share the row shape
    ppc = client.get("/api/v1/plans/ppc-view", params={"date": BUCKET}, headers=sup)
    assert ppc.json()[0]["line_id"] == line_id
    assert ppc.json()[0]["plans"][0]["plan_id"] == row["plan_id"]
    lp = client.get("/api/v1/plans/line-plans",
                    params={"date": BUCKET, "line_id": line_id}, headers=sup)
    assert Decimal(lp.json()[0]["planned_qty"]) == Decimal("740.000")


# 8 — a material with no line mapping lands in the release report, not in plans
def test_unmapped_material_reported_not_planned(client, db):
    h = _token(client)
    sched = _mk(client, h, db, qty="1000", extra_lines=[
        {"sap_code": FERT2, "model_family": "RE Petrol", "bucket_date": BUCKET,
         "qty": "500"}])
    r = _release(client, h, sched["id"])
    assert r.status_code == 200, r.text
    report = r.json()
    assert report["plans_created"] == 1
    (miss,) = report["unmapped"]
    assert miss["sap_code"] == FERT2 and miss["qty"] == "500.000"
    fert2_id = db.query(Material).filter_by(sap_code=FERT2).one().id
    assert db.query(LinePlan).filter_by(material_id=fert2_id).count() == 0
