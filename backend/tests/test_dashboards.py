"""P32+P35 acceptance: dashboard aggregates (achievement, yield, sales, overview)
+ ETag/304 polling contract. READ-ONLY endpoints — the seed below is the entire
world; every asserted number is hand-computable from it.

Seed: 1 line, 2 priced materials (1565 / 980), plans 300+280 (+1 superseded
decoy), shift A confirmations (good 215, rej 6 DENT, downtime 40 DIE_CHANGE),
shift B (good 100), confirmed invoice today (50x1565 + 30x980), 1 open
dispatch, 1 hard + 1 soft open anomaly, 1 pending approval + 1 pending
override_review, 1 unmatched gate entry, outbox pending+failed, 1 open hold."""
import datetime as dt
import uuid
from decimal import Decimal

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker

import app.core.db as db_mod
from app.core.security import hash_password
from app.models.config_tables import ReasonCode
from app.models.gate import GateEntry
from app.models.identity import User
from app.models.master import Customer, Line, Material, ProductionOrder
from app.models.outbound import Dispatch, SalesInvoice, SalesInvoiceLine
from app.models.planning import LinePlan, Schedule
from app.models.production import (ConfirmationHold, ProductionConfirmation,
                                   ShiftContext)
from app.models.system import SapOutbox
from app.models.workflow import Anomaly, Approval

TODAY = dt.date.today()
MONTH = TODAY.strftime("%Y-%m")
NOW = dt.datetime.now(dt.timezone.utc)


@pytest.fixture()
def client(engine, db):
    db_mod._engine = engine
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False,
                                        expire_on_commit=False)
    mgmt = User(username="boss", password_hash=hash_password("b"), full_name="B",
                role="management", language="en")
    vend = User(username="v1", password_hash=hash_password("v"), full_name="V",
                role="vendor", language="en")
    customer = Customer(sap_code="BAJ001", name="Bajaj Auto")
    line = Line(name="Front Body")
    m1 = Material(sap_code="91101999001", description="MUDGUARD ASSY RE",
                  mat_type="FERT", uom="EA", price=Decimal("1565.00"))
    m2 = Material(sap_code="91101999002", description="MUDGUARD ASSY RE LH",
                  mat_type="FERT", uom="EA", price=Decimal("980.00"))
    dent = ReasonCode(kind="reject", code="DENT", label_en="Dent",
                      label_mr="पोचा", sort=1)
    die = ReasonCode(kind="downtime", code="DIE_CHANGE", label_en="Die change",
                     label_mr="डाय बदल", sort=1)
    db.add_all([mgmt, vend, customer, line, m1, m2, dent, die])
    db.flush()

    sched = Schedule(customer_id=customer.id, period=MONTH, version=1,
                     status="released", diff={}, created_by=mgmt.id)
    order = ProductionOrder(sap_order_no="100001", line_id=line.id,
                            material_id=m1.id, status="released")
    db.add_all([sched, order])
    db.flush()

    # plans: 300 + 280 active = 580; superseded decoy must NOT count
    db.add_all([
        LinePlan(plan_date=TODAY, line_id=line.id, material_id=m1.id,
                 planned_qty=Decimal("300"), schedule_id=sched.id, revision=1,
                 status="active"),
        LinePlan(plan_date=TODAY, line_id=line.id, material_id=m2.id,
                 planned_qty=Decimal("280"), schedule_id=sched.id, revision=1,
                 status="active"),
        LinePlan(plan_date=TODAY, line_id=line.id, material_id=m1.id,
                 planned_qty=Decimal("999"), schedule_id=sched.id, revision=0,
                 status="superseded"),
    ])

    ctx_a = ShiftContext(line_id=line.id, shift_date=TODAY, shift="A",
                         plan_revision=1, opened_at=NOW)
    ctx_b = ShiftContext(line_id=line.id, shift_date=TODAY, shift="B",
                         plan_revision=1, opened_at=NOW)
    db.add_all([ctx_a, ctx_b])
    db.flush()
    db.add_all([
        ProductionConfirmation(
            order_id=order.id, line_id=line.id, shift="A", material_id=m1.id,
            good_qty=Decimal("215"), rejected_qty=Decimal("6"),
            reject_reason_id=dent.id, downtime_min=40, downtime_reason_id=die.id,
            kind="interim", status="posted", client_ref=uuid.uuid4(),
            supervisor_id=mgmt.id, posted_at=NOW, shift_context_id=ctx_a.id),
        ProductionConfirmation(
            order_id=order.id, line_id=line.id, shift="B", material_id=m1.id,
            good_qty=Decimal("100"), rejected_qty=Decimal("0"),
            downtime_min=0, kind="shift_close", status="posted",
            client_ref=uuid.uuid4(), supervisor_id=mgmt.id, posted_at=NOW,
            shift_context_id=ctx_b.id),
    ])

    # outbound: 1 invoiced dispatch + confirmed invoice (2 lines), 1 OPEN dispatch
    d1 = Dispatch(doc_no="DN-0001", customer_id=customer.id, vehicle_no="MH12AB1234",
                  total_pcs=80, status="invoiced", client_ref=uuid.uuid4(),
                  created_by=mgmt.id)
    d2 = Dispatch(doc_no="DN-0002", customer_id=customer.id, vehicle_no="MH12CD5678",
                  total_pcs=40, status="open", client_ref=uuid.uuid4(),
                  created_by=mgmt.id)
    db.add_all([d1, d2])
    db.flush()
    inv = SalesInvoice(invoice_no="INV-7001", invoice_date=TODAY, dispatch_id=d1.id,
                       total_value=Decimal("107650.00"), match_status="ok",
                       status="confirmed", confirmed_by=mgmt.id, confirmed_at=NOW,
                       client_ref=uuid.uuid4())
    db.add(inv)
    db.flush()
    db.add_all([
        SalesInvoiceLine(invoice_id=inv.id, material_id=m1.id,
                         qty=Decimal("50"), value=Decimal("78250.00")),
        SalesInvoiceLine(invoice_id=inv.id, material_id=m2.id,
                         qty=Decimal("30"), value=Decimal("29400.00")),
    ])

    # workflow + gate + outbox + hold KPI rows
    db.add_all([
        Anomaly(rule_code="GR_QTY_MISMATCH", severity="hard", ref_type="gr",
                ref_id=1, message_en="hard one", message_mr="x", status="open"),
        Anomaly(rule_code="YIELD_DRIFT", severity="soft", ref_type="confirmation",
                ref_id=1, message_en="soft one", message_mr="x", status="open"),
        Approval(approval_type="credit_waiver", ref_type="issue", ref_id=1,
                 payload={}, required_roles=["management"], status="pending",
                 created_by=mgmt.id),
        Approval(approval_type="override_review", ref_type="approval", ref_id=1,
                 payload={}, required_roles=["management"], status="pending",
                 created_by=mgmt.id),
        GateEntry(doc_no="G-0001", invoice_no="VINV-1", vehicle_no="MH14XX9999",
                  driver_name="D", match_status="unmatched", status="open",
                  client_ref=uuid.uuid4(), created_by=mgmt.id),
        SapOutbox(record_type="GR", record_id=1, payload={}, status="pending"),
        SapOutbox(record_type="CONFIRMATION", record_id=1, payload={},
                  status="failed", last_error="boom"),
        ConfirmationHold(line_id=line.id, material_id=m1.id,
                         shift_context_id=ctx_a.id, payload={"good_qty": "10"},
                         status="open", client_ref=uuid.uuid4(),
                         created_by=mgmt.id),
    ])
    db.commit()

    from app.api.auth import router as auth_router
    from app.api.dashboards import router as dashboards_router
    test_app = FastAPI()
    test_app.include_router(auth_router)
    test_app.include_router(dashboards_router)
    yield TestClient(test_app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def _token(client, username="boss", password="b"):
    r = client.post("/api/v1/auth/login",
                    json={"username": username, "password": password})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


# 1 — achievement: planned counts only ACTIVE plans; shift split; top downtime
def test_achievement_math(client):
    h = _token(client)
    r = client.get(f"/api/v1/dashboards/achievement?date={TODAY}", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    t = body["totals"]
    assert Decimal(t["planned"]) == 580          # 300+280, decoy 999 excluded
    assert Decimal(t["confirmed_good"]) == 315   # 215+100
    assert Decimal(t["confirmed_rejected"]) == 6
    assert t["pct"] == "54.31"                   # 315/580
    [ln] = body["lines"]
    assert ln["line_name"] == "Front Body"
    assert Decimal(ln["shifts"]["A"]["good"]) == 215
    assert Decimal(ln["shifts"]["A"]["rejected"]) == 6
    assert Decimal(ln["shifts"]["B"]["good"]) == 100
    assert Decimal(ln["shifts"]["B"]["rejected"]) == 0
    assert ln["downtime_total_min"] == 40
    assert ln["top_downtime_reason"] == {"reason_code": "DIE_CHANGE",
                                         "label_en": "Die change", "minutes": 40}


# 2 — yield: per-shift yield, reason breakdown, price-proxy scrap value
def test_yield_math(client):
    h = _token(client)
    body = client.get(f"/api/v1/dashboards/yield?date={TODAY}", headers=h).json()
    assert body["overall"]["yield_pct"] == "98.13"      # 315/321
    assert body["overall"]["good"] and Decimal(body["overall"]["good"]) == 315
    by_shift = {row["shift"]: row for row in body["rows"]}
    assert Decimal(by_shift["A"]["good"]) == 215
    assert by_shift["A"]["yield_pct"] == "97.29"        # 215/221
    assert by_shift["B"]["yield_pct"] == "100.00"
    [reason] = body["reject_reasons"]
    assert reason["reason_code"] == "DENT" and reason["label_en"] == "Dent"
    assert Decimal(reason["qty"]) == 6
    # 6 rejected x material price 1565 (documented proxy, not BOM steel value)
    assert Decimal(body["imputed_scrap_value"]) == Decimal("9390.00")


# 3 — sales: confirmed invoices only; today == MTD (one invoice); open dispatch
def test_sales_today_mtd_and_backlog(client):
    h = _token(client)
    body = client.get(f"/api/v1/dashboards/sales?month={MONTH}", headers=h).json()
    assert Decimal(body["billed_today"]["pcs"]) == 80
    assert Decimal(body["billed_today"]["value"]) == Decimal("107650.00")
    assert Decimal(body["billed_mtd"]["pcs"]) == 80
    assert Decimal(body["billed_mtd"]["value"]) == Decimal("107650.00")
    rows = {m["sap_code"]: m for m in body["materials"]}
    assert Decimal(rows["91101999001"]["mtd_value"]) == Decimal("78250.00")
    assert Decimal(rows["91101999001"]["today_pcs"]) == 50
    assert Decimal(rows["91101999002"]["mtd_value"]) == Decimal("29400.00")
    assert body["awaiting_invoice"] == 1


# 4 — overview: every KPI exact; vendors are locked out (internal-only guard)
def test_overview_kpis_and_guard(client):
    h = _token(client)
    body = client.get(f"/api/v1/dashboards/overview?date={TODAY}", headers=h).json()
    assert body["achievement_pct"] == "54.31"
    assert Decimal(body["billed_today_value"]) == Decimal("107650.00")
    assert body["yield_pct"] == "98.13"
    assert body["open_anomalies"] == {"total": 2, "hard": 1}
    assert body["approvals_pending"] == 1          # override_review NOT counted here
    assert body["open_override_reviews"] == 1      # §11.2: never invisible
    assert body["unmatched_gate_entries"] == 1
    assert body["outbox_backlog"] == {"pending": 1, "failed": 1}
    assert body["holds_open"] == 1
    vendor = _token(client, "v1", "v")
    assert client.get("/api/v1/dashboards/overview",
                      headers=vendor).status_code == 403


# 5 — ETag polling contract: 200 + ETag, then If-None-Match -> empty 304
def test_etag_304_flow(client):
    h = _token(client)
    url = f"/api/v1/dashboards/achievement?date={TODAY}"
    r1 = client.get(url, headers=h)
    assert r1.status_code == 200
    etag = r1.headers["ETag"]
    assert etag
    r2 = client.get(url, headers={**h, "If-None-Match": etag})
    assert r2.status_code == 304
    assert r2.content == b""
    # a different/no token still revalidates correctly: stale tag -> full 200
    r3 = client.get(url, headers={**h, "If-None-Match": '"stale"'})
    assert r3.status_code == 200 and r3.headers["ETag"] == etag
