"""P29/P30/P31 acceptance: interim confirmation with plan-revision pinning + backflush
+ CONFIRMATION outbox, reject-reason enforcement, >120%-of-pinned-plan hard block
(mid-shift plan cut doesn't block honest work), no-order 409 → PPC hold → resolve,
manual + auto shift close with late-post flag, correction via approval handler,
idempotent replay."""
import datetime as dt
import uuid
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.models.config_tables import AppSetting, PlanCalendar, ReasonCode
from app.models.identity import User
from app.models.inventory import StockLedger
from app.models.master import Bom, BomLine, Customer, Line, Material, ProductionOrder
from app.models.planning import LinePlan, Schedule
from app.models.production import (ConfirmationCorrection, ConfirmationHold,
                                   ProductionConfirmation, ShiftContext)
from app.models.system import SapOutbox
from app.models.workflow import Approval, Notification
from app.services import production as svc
from app.services.approval_handlers import APPLY
import app.core.db as db_mod

SHIFT_DATE = dt.date(2026, 6, 11)
QTY_PER = Decimal("2.509")  # KG of CRCA per mudguard (real BOM scale)
PLANNED = Decimal("300.000")  # rev 1 plan; 20% allowance → hard limit 360


@pytest.fixture()
def seeded(db):
    sup = User(username="sup1", password_hash=hash_password("s"), full_name="S",
               role="supervisor", language="mr")
    planner = User(username="ppc1", password_hash=hash_password("p"), full_name="P",
                   role="planning", station="ppc", language="en")
    db.add_all([
        User(username="admin", password_hash=hash_password("a"), full_name="A",
             role="admin", language="en"),
        sup, planner,
        User(username="boss", password_hash=hash_password("b"), full_name="B",
             role="management", language="en"),
    ])
    line = Line(name="Press Line 1")
    fert = Material(sap_code="2101010101", description="MUDGUARD ASSY CT100",
                    mat_type="FERT", uom="EA", price=Decimal("180.00"))
    fert2 = Material(sap_code="2101020202", description="MUDGUARD ASSY PLATINA",
                     mat_type="FERT", uom="EA", price=Decimal("190.00"))
    comp = Material(sap_code="1101030569", description="CRCA SHEET D TG04",
                    mat_type="ROH", mat_group="1103", uom="KG",
                    price=Decimal("63.00"))
    scrap = Material(sap_code="9101000001", description="MS SCRAP",
                     mat_type="ZSCP", uom="KG", price=Decimal("28.00"))
    customer = Customer(sap_code="C-BAJAJ", name="Bajaj Auto")
    db.add_all([line, fert, fert2, comp, scrap, customer])
    db.flush()
    bom = Bom(parent_material_id=fert.id, is_active=True)
    db.add(bom)
    db.flush()
    db.add_all([
        BomLine(bom_id=bom.id, component_material_id=comp.id, item_no=10,
                qty_per=QTY_PER, uom="KG"),
        BomLine(bom_id=bom.id, component_material_id=scrap.id, item_no=20,
                qty_per=Decimal("0.350"), uom="KG", is_scrap_credit=True),
    ])
    order = ProductionOrder(sap_order_no="000100012345", line_id=line.id,
                            material_id=fert.id, status="open")
    schedule = Schedule(customer_id=customer.id, period="2026-06", version=1,
                        status="released", diff={}, created_by=1)
    db.add_all([order, schedule])
    db.flush()
    db.add_all([
        LinePlan(plan_date=SHIFT_DATE, line_id=line.id, material_id=fert.id,
                 planned_qty=PLANNED, schedule_id=schedule.id, revision=1,
                 status="active"),
        PlanCalendar(cal_date=SHIFT_DATE, is_working=True,
                     shifts={"A": "06:00-14:30", "B": "14:30-23:00"}),
        ReasonCode(kind="reject", code="RJ-DENT", label_en="Dent",
                   label_mr="पोचा", sort=1),
        ReasonCode(kind="downtime", code="DT-DIE", label_en="Die change",
                   label_mr="डाय बदल", sort=1),
        AppSetting(key="anomaly_thresholds", value={"plan_exceed_pct": 20}),
    ])
    db.commit()
    return {"line": line, "fert": fert, "fert2": fert2, "comp": comp,
            "scrap": scrap, "order": order, "schedule": schedule,
            "sup": sup, "planner": planner}


@pytest.fixture()
def client(engine, db, seeded):
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False,
                                        expire_on_commit=False)
    from app.main import app
    from app.api.production import router as production_router
    # Packet scope cannot touch main.py — mount the router here (idempotent).
    if not any(getattr(r, "path", None) == "/api/v1/confirmations"
               for r in app.routes):
        app.include_router(production_router)
    yield TestClient(app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def _token(client, username, password):
    r = client.post("/api/v1/auth/login", json={"username": username,
                                                "password": password})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _body(seeded, good, **over):
    body = {"client_ref": str(uuid.uuid4()), "line_id": seeded["line"].id,
            "shift": "A", "material_id": seeded["fert"].id,
            "good_qty": str(good), "shift_date": SHIFT_DATE.isoformat()}
    body.update(over)
    return body


def _post(client, headers, seeded, good, **over):
    return client.post("/api/v1/confirmations", json=_body(seeded, good, **over),
                       headers=headers)


# --- (1) interim post: pinned context, backflush, outbox, history ---

def test_interim_post_pins_revision_backflush_outbox_history(client, db, seeded):
    sup = _token(client, "sup1", "s")
    r = _post(client, sup, seeded, "40")
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["kind"] == "interim"
    assert data["status"] == "posted"
    assert data["posted_after_close"] is False
    assert data["order_id"] == seeded["order"].id

    ctx = db.query(ShiftContext).one()
    assert (ctx.line_id, ctx.shift, ctx.shift_date) == \
        (seeded["line"].id, "A", SHIFT_DATE)
    assert ctx.plan_revision == 1  # pinned at first confirmation (§11.10)
    assert ctx.closed_at is None
    assert data["shift_context_id"] == ctx.id

    rows = db.query(StockLedger).order_by(StockLedger.id).all()
    assert len(rows) == 2  # scrap-credit BOM line writes nothing
    fg, rm = rows
    assert (fg.movement, fg.location, fg.material_id, fg.qty) == \
        ("PROD_IN", "FG", seeded["fert"].id, Decimal("40"))
    assert (rm.movement, rm.location, rm.material_id) == \
        ("PROD_CONSUME", "RM", seeded["comp"].id)
    assert rm.qty == Decimal("-100.360")  # -(2.509 × 40)

    ob = db.query(SapOutbox).filter_by(record_type="CONFIRMATION").one()
    assert ob.status == "pending"
    assert ob.record_id == data["id"]
    assert ob.payload["sap_order_no"] == "000100012345"
    assert ob.payload["material_sap_code"] == seeded["fert"].sap_code
    assert ob.payload["good_qty"] == "40.000"

    h = client.get("/api/v1/confirmations",
                   params={"line_id": seeded["line"].id,
                           "date": SHIFT_DATE.isoformat()}, headers=sup)
    assert h.status_code == 200, h.text
    hist = h.json()
    assert len(hist) == 1
    assert hist[0]["sap_sync_status"] == "pending"

    totals = svc.confirmed_totals(db, seeded["line"].id, SHIFT_DATE)
    assert totals[seeded["fert"].id] == {"good": Decimal("40"),
                                         "rejected": Decimal("0")}


# --- (2) reject qty requires an active reject reason ---

def test_reject_without_reason_422(client, db, seeded):
    sup = _token(client, "sup1", "s")
    r = _post(client, sup, seeded, "10", rejected_qty="5")
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "REJECT_REASON_REQUIRED"
    assert r.json()["detail"]["message_mr"]  # bilingual envelope
    # a downtime code is NOT a reject reason
    dt_reason = db.query(ReasonCode).filter_by(kind="downtime").one()
    r = _post(client, sup, seeded, "10", rejected_qty="5",
              reject_reason_id=dt_reason.id)
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "REJECT_REASON_INVALID"
    assert db.query(ProductionConfirmation).count() == 0
    assert db.query(StockLedger).count() == 0


# --- (3) >120% of PINNED plan blocks; mid-shift plan cut doesn't ---

def test_exceeds_pinned_plan_and_revision_pinning(client, db, seeded):
    sup = _token(client, "sup1", "s")
    reject = db.query(ReasonCode).filter_by(kind="reject").one()
    assert _post(client, sup, seeded, "345", rejected_qty="5",
                 reject_reason_id=reject.id).status_code == 200  # 350 ≤ 360

    r = _post(client, sup, seeded, "20")  # cumulative 370 > 300 × 1.2
    assert r.status_code == 422
    detail = r.json()["detail"]
    assert detail["code"] == "CONFIRMATION_EXCEEDS_PLAN"
    assert detail["details"]["pinned_revision"] == 1
    assert detail["details"]["planned"] == "300.000"
    assert detail["details"]["limit"] == "360.000"

    # Plan revised DOWN mid-shift (rev 2 = 100) AFTER the context pinned rev 1.
    db.query(LinePlan).filter_by(plan_date=SHIFT_DATE, status="active") \
        .update({"status": "superseded"})
    db.add(LinePlan(plan_date=SHIFT_DATE, line_id=seeded["line"].id,
                    material_id=seeded["fert"].id, planned_qty=Decimal("100"),
                    schedule_id=seeded["schedule"].id, revision=2, status="active"))
    db.commit()

    # Would breach rev 2 (355 > 120) but fits the PINNED rev 1 (355 ≤ 360) → posts.
    r = _post(client, sup, seeded, "5")
    assert r.status_code == 200, r.text
    assert db.query(ShiftContext).one().plan_revision == 1  # pin never moves


# --- (4) no order → 409 + hold + PPC notification; resolve posts for real ---

def test_no_order_409_hold_and_resolve(client, db, seeded):
    sup = _token(client, "sup1", "s")
    body = _body(seeded, "25", material_id=seeded["fert2"].id)
    r = client.post("/api/v1/confirmations", json=body, headers=sup)
    assert r.status_code == 409
    detail = r.json()["detail"]
    assert detail["code"] == "CONFIRMATION_NEEDS_ORDER"
    assert "hold" in detail["details"]["hold_endpoint"]
    assert db.query(ProductionConfirmation).count() == 0

    r = client.post("/api/v1/confirmations/hold", json=body, headers=sup)
    assert r.status_code == 200, r.text
    hold_id = r.json()["id"]
    hold = db.get(ConfirmationHold, hold_id)
    assert hold.status == "open"
    assert hold.payload["good_qty"] == "25"
    note = db.query(Notification).filter_by(kind="confirmation_hold").one()
    assert note.user_id == seeded["planner"].id  # role planning / station ppc
    assert note.tier == "blocker"

    holds = client.get("/api/v1/confirmations/holds?status=open", headers=sup)
    assert [h["id"] for h in holds.json()] == [hold_id]

    ppc = _token(client, "ppc1", "p")
    r = client.post(f"/api/v1/confirmations/holds/{hold_id}/resolve",
                    json={"sap_order_no": "000100099999"}, headers=ppc)
    assert r.status_code == 200, r.text
    out = r.json()
    assert out["hold"]["status"] == "resolved"
    order = db.query(ProductionOrder).filter_by(sap_order_no="000100099999").one()
    assert (order.line_id, order.material_id) == \
        (seeded["line"].id, seeded["fert2"].id)
    assert out["hold"]["resolved_order_id"] == order.id
    conf = db.query(ProductionConfirmation).one()
    # posted under the HOLD's client_ref (documented idempotency handle)
    assert conf.client_ref == hold.client_ref
    assert conf.good_qty == Decimal("25")
    assert conf.order_id == order.id
    fg = db.query(StockLedger).one()  # fert2 has no BOM → FG row only
    assert (fg.movement, fg.location, fg.qty) == ("PROD_IN", "FG", Decimal("25"))

    again = client.post(f"/api/v1/confirmations/holds/{hold_id}/resolve",
                        json={"sap_order_no": "000100099999"}, headers=ppc)
    assert again.status_code == 409
    assert again.json()["detail"]["code"] == "HOLD_NOT_OPEN"


# --- (5) manual shift close; late post flagged ---

def test_shift_close_then_late_post_flagged(client, db, seeded):
    sup = _token(client, "sup1", "s")
    r = _post(client, sup, seeded, "30", kind="shift_close")
    assert r.status_code == 200, r.text
    ctx = db.query(ShiftContext).one()
    assert ctx.closed_at is not None
    assert ctx.close_kind == "manual"

    r = _post(client, sup, seeded, "5")  # late post: accepted, flagged (§11.10)
    assert r.status_code == 200, r.text
    assert r.json()["posted_after_close"] is True


# --- (6) auto close from plan_calendar boundary ---

def test_shift_auto_close_job(client, db, seeded):
    sup = _token(client, "sup1", "s")
    assert _post(client, sup, seeded, "10").status_code == 200
    ctx = db.query(ShiftContext).one()
    assert ctx.closed_at is None

    before_end = dt.datetime(2026, 6, 11, 14, 0, tzinfo=dt.timezone.utc)
    assert svc.shift_auto_close_job(db, now=before_end) == 0

    past_end = dt.datetime(2026, 6, 11, 15, 0, tzinfo=dt.timezone.utc)  # > 14:30
    assert svc.shift_auto_close_job(db, now=past_end) == 1
    db.refresh(ctx)
    assert ctx.closed_at is not None
    assert ctx.close_kind == "auto"
    note = db.query(Notification).filter_by(kind="shift_auto_closed").one()
    assert note.user_id == seeded["sup"].id  # first confirmation's supervisor
    assert note.ref_id == ctx.id
    assert svc.shift_auto_close_job(db, now=past_end) == 0  # nothing left open


# --- (7) correction approved via the handler registry ---

def test_correction_apply_adjusts_ledger_and_status(client, db, seeded):
    sup = _token(client, "sup1", "s")
    conf_id = _post(client, sup, seeded, "40").json()["id"]

    r = client.post(f"/api/v1/confirmations/{conf_id}/correction",
                    json={"delta_good": "5", "delta_reject": "2",
                          "reason": "tally slip recount"}, headers=sup)
    assert r.status_code == 200, r.text
    corr = db.get(ConfirmationCorrection, r.json()["id"])
    assert corr.status == "pending"
    approval = db.get(Approval, corr.approval_id)
    assert approval.approval_type == "confirmation_correction"
    assert list(approval.required_roles) == ["management"]
    assert db.query(StockLedger).count() == 2  # nothing applied yet

    APPLY["confirmation_correction"](db, approval)  # engine calls this on approve
    db.commit()

    adj = (db.query(StockLedger)
           .filter_by(ref_type="confirmation_corrections", ref_id=corr.id)
           .order_by(StockLedger.id).all())
    assert len(adj) == 2
    assert (adj[0].movement, adj[0].location, adj[0].qty) == \
        ("PROD_IN", "FG", Decimal("5"))
    assert (adj[1].movement, adj[1].location, adj[1].qty) == \
        ("PROD_CONSUME", "RM", Decimal("-12.545"))  # -(2.509 × 5)
    db.refresh(corr)
    assert corr.status == "applied"
    assert db.get(ProductionConfirmation, conf_id).status == "corrected"
    # re-applying is a no-op (idempotent handler)
    APPLY["confirmation_correction"](db, approval)
    db.commit()
    assert db.query(StockLedger).filter_by(
        ref_type="confirmation_corrections").count() == 2

    totals = svc.confirmed_totals(db, seeded["line"].id, SHIFT_DATE)
    assert totals[seeded["fert"].id] == {"good": Decimal("45"),
                                         "rejected": Decimal("2")}


# --- (8) idempotent replay ---

def test_idempotent_replay_same_client_ref(client, db, seeded):
    sup = _token(client, "sup1", "s")
    body = _body(seeded, "40")
    r1 = client.post("/api/v1/confirmations", json=body, headers=sup)
    r2 = client.post("/api/v1/confirmations", json=body, headers=sup)
    assert r1.status_code == r2.status_code == 200
    assert r1.json()["id"] == r2.json()["id"]
    assert db.query(ProductionConfirmation).count() == 1
    assert db.query(StockLedger).count() == 2  # no duplicate backflush
    assert db.query(SapOutbox).filter_by(record_type="CONFIRMATION").count() == 1
