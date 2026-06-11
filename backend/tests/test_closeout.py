"""Items 8–10 closeout: weighbridge fields, per-line shifts, escalation resolution
call-sites, photo sweep, enriched healthz."""
import datetime as dt
import uuid
from decimal import Decimal

import pytest

from app.core.security import hash_password
from app.models.config_tables import PlanCalendar
from app.models.gate import GateEntry
from app.models.identity import User
from app.models.master import Line
from app.models.production import ShiftContext
from app.models.workflow import EscalationEvent, Notification
from app.services.production import shift_auto_close_job
from app.services.sweeps import photos_pending_sweep

TODAY = dt.date.today()


@pytest.fixture()
def admin(db):
    u = User(username="admin", password_hash=hash_password("a"), full_name="A",
             role="admin", language="en")
    db.add(u)
    db.commit()
    return u


def _entry(db, admin, **kw):
    e = GateEntry(doc_no=f"G-{uuid.uuid4().hex[:6]}", vehicle_no="MH12", driver_name="D",
                  match_status="unmatched", status="open", client_ref=uuid.uuid4(),
                  created_by=admin.id, **kw)
    db.add(e)
    db.commit()
    return e


def test_line_shift_pattern_overrides_calendar(db, admin):
    """Domain_QA Q6: line-specific shifts govern auto-close, not the plant default."""
    db.add(PlanCalendar(cal_date=TODAY, is_working=True,
                        shifts={"A": "06:00-23:30"}))  # plant default: A ends 23:30
    line = Line(name="Floor Top", plant="1117",
                shift_pattern={"A": "06:00-12:00"})  # this line's A ends at noon
    db.add(line)
    db.flush()
    db.add(ShiftContext(line_id=line.id, shift_date=TODAY, shift="A",
                        plan_revision=1, opened_at=dt.datetime.now(dt.timezone.utc)))
    db.commit()
    fake_now = dt.datetime.combine(TODAY, dt.time(13, 0))  # 13:00 — past line end,
    closed = shift_auto_close_job(db, now=fake_now)        # before plant default end
    assert closed == 1
    ctx = db.query(ShiftContext).one()
    assert ctx.close_kind == "auto"


def test_photos_pending_sweep_notifies_once(db, admin):
    old = _entry(db, admin, photos_pending=True)
    db.query(GateEntry).filter_by(id=old.id).update(
        {"created_at": dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=30)})
    _entry(db, admin, photos_pending=True)  # fresh — under 24h, not swept
    db.commit()
    assert photos_pending_sweep(db) == 1
    assert db.query(Notification).filter_by(kind="photos_pending").count() == 1
    assert photos_pending_sweep(db) == 0  # idempotent — no double notification


def test_resolve_events_wired_into_gate_match(db, admin):
    from app.models.master import Material, PurchaseOrder, Vendor
    from app.core.deps import CurrentUser
    from app.services.gate import link_po
    v = Vendor(sap_code="V1", name="V")
    m = Material(sap_code="M1", description="d", mat_type="ROH", uom="KG")
    db.add_all([v, m])
    db.flush()
    po = PurchaseOrder(sap_po_no="P1", item_no=1, vendor_id=v.id, material_id=m.id,
                       ordered_qty=Decimal("10"), open_qty=Decimal("10"),
                       rate=Decimal("5"), uom="KG", status="open")
    entry = _entry(db, admin, vendor_id=v.id)
    db.add_all([po,
                EscalationEvent(rule_code="unmatched_gate_24h", ref_type="gate_entries",
                                ref_id=entry.id, stage=1, notified_roles=["planning"])])
    db.commit()
    user = CurrentUser(id=admin.id, username="admin", role="admin", station=None,
                       vendor_id=None, device_key=None)
    link_po(db, user, entry.id, po.id)
    ev = db.query(EscalationEvent).one()
    assert ev.resolved_at is not None  # matching closed the chain


def test_healthz_enriched(engine, db):
    import app.core.db as db_mod
    from sqlalchemy.orm import sessionmaker
    db_mod._engine = engine
    db_mod._SessionLocal = sessionmaker(bind=engine)
    from fastapi.testclient import TestClient
    from app.main import app
    r = TestClient(app).get("/api/v1/system/healthz").json()
    assert {"status", "db", "storage", "outbox"} <= set(r)
    assert r["outbox"] == {"pending": 0, "batched": 0, "failed": 0}
    db_mod._engine = None
    db_mod._SessionLocal = None


def test_weighbridge_fields_roundtrip(db, admin):
    """GR stores weighbridge evidence when provided (schema + model wiring)."""
    from app.models.inventory import GoodsReceipt
    gr = GoodsReceipt(doc_no="GR-T1", gate_entry_id=_entry(db, admin).id,
                      material_id=None, expected_qty=Decimal("100"),
                      received_qty=Decimal("99"), accepted_qty=Decimal("99"),
                      rejected_qty=Decimal("0"), qc_result="pass",
                      shortage_qty=Decimal("0"),
                      weighbridge_weight=Decimal("28090.000"),
                      client_ref=uuid.uuid4(), posted_by=admin.id)
    # material_id is NOT NULL — supply one
    from app.models.master import Material
    m = Material(sap_code="MX", description="d", mat_type="ROH", uom="KG")
    db.add(m)
    db.flush()
    gr.material_id = m.id
    db.add(gr)
    db.commit()
    assert db.query(GoodsReceipt).one().weighbridge_weight == Decimal("28090.000")
