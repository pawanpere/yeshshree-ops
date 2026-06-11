"""P24/P27 acceptance: inhouse issue, vendor double-entry + exposure, credit/qty limit
breach → waiver_pending (approval + NO stock), waiver apply via the handler registry,
issue correction reversal+repost, idempotent replay."""
import uuid
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.models.identity import User
from app.models.inventory import Issue, IssueCorrection, StockLedger
from app.models.master import Material, Vendor
from app.models.system import SapOutbox
from app.models.workflow import Anomaly, Approval, Notification
from app.services.approval_handlers import APPLY, REJECT
import app.core.db as db_mod

CREDIT_LIMIT = Decimal("1400000.00")
QTY_LIMIT_MT = Decimal("10.000")
STEEL_PRICE = Decimal("63.00")


def _seed_ledger(db, material_id, qty, *, location="RM", vendor_id=None, uom="KG"):
    db.add(StockLedger(material_id=material_id, location=location, movement="GR_IN",
                       qty=Decimal(str(qty)), uom=uom, vendor_id=vendor_id,
                       ref_type="seed", ref_id=0, created_by=None))


@pytest.fixture()
def seeded(db):
    db.add_all([
        User(username="admin", password_hash=hash_password("a"), full_name="A",
             role="admin", language="en"),
        User(username="store1", password_hash=hash_password("s"), full_name="S",
             role="plant_ops", station="store", language="mr"),
        User(username="sup1", password_hash=hash_password("u"), full_name="U",
             role="supervisor", station="store", language="mr"),
        User(username="boss", password_hash=hash_password("b"), full_name="B",
             role="management", language="en"),
    ])
    vendor = Vendor(sap_code="V-200", name="Sai Pressings",
                    credit_limit=CREDIT_LIMIT, qty_limit_mt=QTY_LIMIT_MT)
    steel = Material(sap_code="1101030569", description="CRCA SHEET D TG04",
                     mat_type="ROH", mat_group="1103", uom="KG", price=STEEL_PRICE)
    pricey = Material(sap_code="1101099999", description="SPECIAL ALLOY SHEET",
                      mat_type="ROH", mat_group="1103", uom="KG",
                      price=Decimal("700.00"))
    db.add_all([vendor, steel, pricey])
    db.flush()
    _seed_ledger(db, steel.id, "30000")   # GR_IN 30000 KG per packet brief
    _seed_ledger(db, pricey.id, "5000")
    db.commit()
    return {"vendor": vendor, "steel": steel, "pricey": pricey}


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


def _issue_rows(db, issue_id):
    return (db.query(StockLedger).filter_by(ref_type="issues", ref_id=issue_id)
            .order_by(StockLedger.id).all())


def test_inhouse_issue_posted_single_row_outbox(client, db, seeded):
    """(6) inhouse: posted, ONE ISSUE_OUT row (no AT_VENDOR leg), outbox ISSUE."""
    store = _token(client, "store1", "s")
    r = _post_issue(client, store, seeded["steel"].id, "1000")
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["doc_no"].startswith("ISS-")
    assert data["status"] == "posted"
    assert data["stock_warning"] is False
    assert Decimal(str(data["value"])) == Decimal("63000.00")
    rows = _issue_rows(db, data["id"])
    assert len(rows) == 1
    assert (rows[0].movement, rows[0].location, rows[0].qty) == \
        ("ISSUE_OUT", "RM", Decimal("-1000"))
    ob = db.query(SapOutbox).filter_by(record_type="ISSUE").one()
    assert ob.status == "pending"
    assert ob.payload["doc_no"] == data["doc_no"]
    assert ob.payload["qty"] == "1000.000"
    assert db.query(Anomaly).count() == 0


def test_vendor_sale_within_limits_double_entry_exposure(client, db, seeded):
    """(7) vendor_sale: RM negative + AT_VENDOR positive (double-entry, §5.5a);
    exposure endpoint reflects the issued value."""
    store, admin = _token(client, "store1", "s"), _token(client, "admin", "a")
    v = seeded["vendor"]
    r = _post_issue(client, store, seeded["steel"].id, "5000",
                    destination="vendor_sale", vendor_id=v.id)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["status"] == "posted"
    assert data["limit_check"]["limits"]["breaches"] == []
    rows = _issue_rows(db, data["id"])
    assert [(x.location, x.qty) for x in rows] == \
        [("RM", Decimal("-5000")), ("AT_VENDOR", Decimal("5000"))]
    assert all(x.vendor_id == v.id for x in rows)
    exp = client.get(f"/api/v1/vendors/{v.id}/exposure", headers=admin).json()
    assert Decimal(str(exp["credit_exposure"])) == Decimal("315000.00")  # 5000×63
    assert Decimal(str(exp["qty_mt"])) == Decimal("5.000")
    assert Decimal(str(exp["credit_limit"])) == CREDIT_LIMIT


def test_credit_limit_breach_blocks_with_waiver(client, db, seeded):
    """(8) 2100 KG × ₹700 = 1,470,000 > 1,400,000 → waiver_pending: approval row,
    blocker notification to management, NO stock movement, NO outbox."""
    store = _token(client, "store1", "s")
    r = _post_issue(client, store, seeded["pricey"].id, "2100",
                    destination="vendor_sale", vendor_id=seeded["vendor"].id)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["status"] == "waiver_pending"
    limits = data["limit_check"]["limits"]
    assert limits["breaches"] == ["credit_limit"]
    assert limits["exposure_after"] == "1470000.00"
    assert limits["credit_limit"] == "1400000.00"
    approval = db.query(Approval).filter_by(approval_type="credit_waiver").one()
    assert approval.status == "pending"
    assert (approval.ref_type, approval.ref_id) == ("issues", data["id"])
    assert list(approval.required_roles) == ["management"]
    assert approval.payload["limits"]["breaches"] == ["credit_limit"]
    assert _issue_rows(db, data["id"]) == []        # no stock while blocked
    assert db.query(SapOutbox).count() == 0          # no outbox while blocked
    note = db.query(Notification).filter_by(kind="credit_waiver").one()
    assert note.tier == "blocker"
    assert db.get(User, note.user_id).role == "management"


def test_waiver_approve_handler_posts_issue(client, db, seeded):
    """(9) engine contract: flip status + call APPLY['credit_waiver'] → posted issue,
    double-entry ledger, outbox ISSUE (same _post_movements as the direct path)."""
    store = _token(client, "store1", "s")
    r = _post_issue(client, store, seeded["pricey"].id, "2100",
                    destination="vendor_sale", vendor_id=seeded["vendor"].id)
    issue_id = r.json()["id"]
    approval = db.query(Approval).filter_by(approval_type="credit_waiver").one()
    approval.status = "approved"
    APPLY["credit_waiver"](db, approval)
    db.commit()
    issue = db.get(Issue, issue_id)
    assert issue.status == "posted"
    assert issue.approval_id == approval.id
    rows = _issue_rows(db, issue_id)
    assert [(x.location, x.qty) for x in rows] == \
        [("RM", Decimal("-2100")), ("AT_VENDOR", Decimal("2100"))]
    ob = db.query(SapOutbox).filter_by(record_type="ISSUE", record_id=issue_id).one()
    assert ob.payload["doc_no"] == issue.doc_no
    # re-applying is a no-op (handler is idempotent)
    APPLY["credit_waiver"](db, approval)
    db.commit()
    assert len(_issue_rows(db, issue_id)) == 2


def test_waiver_reject_cancels_and_notifies_creator(client, db, seeded):
    store = _token(client, "store1", "s")
    r = _post_issue(client, store, seeded["pricey"].id, "2100",
                    destination="vendor_sale", vendor_id=seeded["vendor"].id)
    issue_id = r.json()["id"]
    approval = db.query(Approval).filter_by(approval_type="credit_waiver").one()
    approval.status = "declined"
    REJECT["credit_waiver"](db, approval)
    db.commit()
    issue = db.get(Issue, issue_id)
    assert issue.status == "cancelled"
    assert _issue_rows(db, issue_id) == []
    note = db.query(Notification).filter_by(kind="credit_waiver_declined").one()
    assert note.user_id == issue.created_by


def test_qty_limit_breach_also_blocks(client, db, seeded):
    """(10) 11,000 KG = 11 MT > 10 MT limit (value ₹693,000 is fine) → still blocked."""
    store = _token(client, "store1", "s")
    r = _post_issue(client, store, seeded["steel"].id, "11000",
                    destination="vendor_sale", vendor_id=seeded["vendor"].id)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["status"] == "waiver_pending"
    limits = data["limit_check"]["limits"]
    assert limits["breaches"] == ["qty_limit_mt"]
    assert limits["qty_mt_after"] == "11.000"
    assert _issue_rows(db, data["id"]) == []


def test_correction_approved_reverses_and_reposts(client, db, seeded):
    """(11) §11.12: reversal rows negate the originals (ref_type='issue_correction'),
    a NEW posted issue carries corrected values, original → corrected."""
    store = _token(client, "store1", "s")
    orig = _post_issue(client, store, seeded["steel"].id, "1000").json()
    rc = client.post(f"/api/v1/issues/{orig['id']}/correction", headers=store,
                     json={"corrected": {"qty": "800"}, "reason": "typed 1000 for 800"})
    assert rc.status_code == 200, rc.text
    corr_id = rc.json()["id"]
    assert rc.json()["status"] == "pending"
    approval = db.query(Approval).filter_by(approval_type="issue_correction").one()
    assert set(approval.required_roles) == {"supervisor", "admin"}  # store head + fallback
    assert approval.payload["corrected"] == {"qty": "800"}
    assert db.get(Issue, orig["id"]).status == "posted"  # nothing applied yet
    approval.status = "approved"
    APPLY["issue_correction"](db, approval)
    db.commit()
    reversal = db.query(StockLedger).filter_by(ref_type="issue_correction",
                                               ref_id=corr_id).one()
    assert (reversal.qty, reversal.location, reversal.movement) == \
        (Decimal("1000"), "RM", "ISSUE_OUT")  # negated original
    assert db.get(Issue, orig["id"]).status == "corrected"
    assert db.get(IssueCorrection, corr_id).status == "applied"
    replacement = (db.query(Issue).filter(Issue.id != orig["id"])
                   .filter_by(status="posted").one())
    assert replacement.qty == Decimal("800")
    assert replacement.value == Decimal("50400.00")  # 800 × 63
    assert replacement.limit_check["corrected_from"] == orig["id"]
    new_rows = _issue_rows(db, replacement.id)
    assert [(x.location, x.qty) for x in new_rows] == [("RM", Decimal("-800"))]
    # outbox: original ISSUE + replacement ISSUE (frozen payloads)
    obs = db.query(SapOutbox).filter_by(record_type="ISSUE").all()
    assert {o.record_id for o in obs} == {orig["id"], replacement.id}
    # net stock effect: 30000 − 1000 + 1000 − 800 = 29200
    from app.services.inventory import balance_qty
    assert balance_qty(db, seeded["steel"].id, "RM") == Decimal("29200")


def test_idempotent_replay_same_client_ref(client, db, seeded):
    """(12) invariant 4: retried client_ref → original result, no duplicates."""
    store = _token(client, "store1", "s")
    ref = str(uuid.uuid4())
    r1 = _post_issue(client, store, seeded["steel"].id, "1000", client_ref=ref)
    r2 = _post_issue(client, store, seeded["steel"].id, "1000", client_ref=ref)
    assert r1.status_code == r2.status_code == 200
    assert r1.json()["doc_no"] == r2.json()["doc_no"]
    assert db.query(Issue).count() == 1
    assert db.query(StockLedger).filter_by(ref_type="issues").count() == 1
    assert db.query(SapOutbox).count() == 1
