"""P25/P26 acceptance: create→blocker notifications, co-approval per role, decline→
REJECT handler, delegate decides on-behalf (window enforced), emergency override
(reason mandatory, APPLY runs, post-facto override_review), inbox by role+delegation."""
import datetime as dt

import pytest
from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.models.identity import User
from app.models.workflow import (Approval, ApprovalDecision, ApprovalDelegation,
                                 Notification)
from app.services import approval_handlers
from app.services import approvals as svc
import app.core.db as db_mod

TODAY = dt.datetime.now(dt.timezone.utc).date()
DAY = dt.timedelta(days=1)


@pytest.fixture()
def users(db):
    rows = {
        "admin": User(username="admin", password_hash=hash_password("a"),
                      full_name="A", role="admin", language="en"),
        "boss": User(username="boss", password_hash=hash_password("b"),
                     full_name="B", role="management", language="en"),
        "plan1": User(username="plan1", password_hash=hash_password("p"),
                      full_name="P", role="planning", language="en"),
        "sup1": User(username="sup1", password_hash=hash_password("s"),
                     full_name="S", role="supervisor", language="mr"),
        "ops1": User(username="ops1", password_hash=hash_password("o"),
                     full_name="O", role="plant_ops", station="store", language="mr"),
    }
    db.add_all(rows.values())
    db.commit()
    return rows


@pytest.fixture()
def client(engine, db, users):
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False,
                                        expire_on_commit=False)
    from app.main import app
    from app.api.approvals import router as approvals_router
    from app.api.notifications import router as notifications_router
    # P25 scope cannot touch main.py — mount routers here (idempotent across tests).
    if not any(getattr(r, "path", None) == "/api/v1/approvals/inbox" for r in app.routes):
        app.include_router(approvals_router)
    if not any(getattr(r, "path", None) == "/api/v1/notifications" for r in app.routes):
        app.include_router(notifications_router)
    yield TestClient(app)
    db_mod._engine = None
    db_mod._SessionLocal = None


@pytest.fixture()
def handlers():
    """Snapshot/restore the APPLY/REJECT registries — tests register their own."""
    apply_before, reject_before = dict(approval_handlers.APPLY), dict(approval_handlers.REJECT)
    yield approval_handlers
    approval_handlers.APPLY.clear()
    approval_handlers.APPLY.update(apply_before)
    approval_handlers.REJECT.clear()
    approval_handlers.REJECT.update(reject_before)


def _token(client, username, password):
    r = client.post("/api/v1/auth/login", json={"username": username, "password": password})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _approval(db, users, approval_type="debit_note", roles=("management",), ref_id=101):
    ap = svc.create_approval(db, approval_type=approval_type, ref_type="debit_notes",
                             ref_id=ref_id, payload={"amount": "8851.50"},
                             required_roles=list(roles),
                             created_by=users["admin"].id)
    db.commit()
    return ap


def _delegate(db, users, principal, delegate, frm=TODAY - DAY, to=TODAY + DAY,
              approval_type=None, is_active=True):
    d = ApprovalDelegation(principal_user_id=users[principal].id,
                           delegate_user_id=users[delegate].id,
                           approval_type=approval_type, valid_from=frm, valid_to=to,
                           created_by=users[principal].id, is_active=is_active)
    db.add(d)
    db.commit()
    return d


def test_create_sends_blockers_to_role_holders_and_delegates(db, users):
    _delegate(db, users, "boss", "ops1")  # active delegation: management → ops1
    ap = _approval(db, users, roles=("management",))
    notes = db.query(Notification).filter_by(kind="approval_request").all()
    assert {n.user_id for n in notes} == {users["boss"].id, users["ops1"].id}
    assert {n.tier for n in notes} == {"blocker"}
    assert {(n.ref_type, n.ref_id) for n in notes} == {("approvals", ap.id)}
    assert all(n.next_repeat_at is not None for n in notes)  # repeat chain armed


def test_co_approval_completes_only_when_every_role_approved(db, users, client, handlers):
    applied = []
    handlers.on_approve("debit_note")(lambda d, ap: applied.append(ap.id))
    ap = _approval(db, users, roles=("management", "planning"))
    boss, plan = _token(client, "boss", "b"), _token(client, "plan1", "p")
    r1 = client.post(f"/api/v1/approvals/{ap.id}/decide", headers=boss,
                     json={"decision": "approve", "note": "ok"})
    assert r1.status_code == 200 and r1.json()["status"] == "pending"
    assert applied == []  # planning has not approved yet
    r2 = client.post(f"/api/v1/approvals/{ap.id}/decide", headers=plan,
                     json={"decision": "approve"})
    assert r2.status_code == 200 and r2.json()["status"] == "approved"
    assert r2.json()["decided_at"] is not None
    assert applied == [ap.id]  # APPLY handler ran exactly once
    # terminal approval refuses further decisions
    r3 = client.post(f"/api/v1/approvals/{ap.id}/decide", headers=boss,
                     json={"decision": "approve"})
    assert r3.status_code == 409
    assert r3.json()["detail"]["code"] == "APPROVAL_ALREADY_DECIDED"


def test_decline_runs_reject_handler(db, users, client, handlers):
    rejected = []
    handlers.on_reject("credit_waiver")(lambda d, ap: rejected.append(ap.id))
    ap = _approval(db, users, approval_type="credit_waiver", roles=("management",))
    boss = _token(client, "boss", "b")
    r = client.post(f"/api/v1/approvals/{ap.id}/decide", headers=boss,
                    json={"decision": "decline", "note": "no budget"})
    assert r.status_code == 200 and r.json()["status"] == "declined"
    assert rejected == [ap.id]


def test_delegate_decides_on_behalf_window_respected(db, users, client):
    _delegate(db, users, "boss", "ops1")  # valid NOW
    ap = _approval(db, users, roles=("management",))
    ops = _token(client, "ops1", "o")
    r = client.post(f"/api/v1/approvals/{ap.id}/decide", headers=ops,
                    json={"decision": "approve"})
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "approved"  # delegate counted for management
    dec = db.query(ApprovalDecision).filter_by(approval_id=ap.id).one()
    assert dec.user_id == users["ops1"].id
    assert dec.on_behalf_of_user_id == users["boss"].id

    # expired delegation → 403-equivalent error, decision refused
    _delegate(db, users, "plan1", "ops1", frm=TODAY - 10 * DAY, to=TODAY - DAY)
    ap2 = _approval(db, users, roles=("planning",), ref_id=102)
    r2 = client.post(f"/api/v1/approvals/{ap2.id}/decide", headers=ops,
                     json={"decision": "approve"})
    assert r2.status_code == 403
    assert r2.json()["detail"]["code"] == "NOT_AN_APPROVER"
    assert r2.json()["detail"]["message_mr"]  # bilingual envelope
    db.expire_all()
    assert db.get(Approval, ap2.id).status == "pending"


def test_override_reason_required_apply_runs_review_created(db, users, client, handlers):
    applied = []
    handlers.on_approve("debit_note")(lambda d, ap: applied.append(ap.id))
    ap = _approval(db, users, roles=("management", "planning"))
    sup, boss = _token(client, "sup1", "s"), _token(client, "boss", "b")
    # role guard: supervisor cannot override
    assert client.post(f"/api/v1/approvals/{ap.id}/override", headers=sup,
                       json={"reason": "truck waiting"}).status_code == 403
    # mandatory reason
    r = client.post(f"/api/v1/approvals/{ap.id}/override", headers=boss,
                    json={"reason": "   "})
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "OVERRIDE_REASON_REQUIRED"
    assert applied == []
    # the real override
    r2 = client.post(f"/api/v1/approvals/{ap.id}/override", headers=boss,
                     json={"reason": "truck blocking the gate, MD on phone"})
    assert r2.status_code == 200, r2.text
    body = r2.json()
    assert body["status"] == "overridden"
    assert body["overridden_by"] == users["boss"].id
    assert body["override_reason"].startswith("truck blocking")
    assert applied == [ap.id]  # APPLY ran despite no approvals
    review = db.query(Approval).filter_by(approval_type="override_review").one()
    assert review.status == "pending"
    assert review.payload["original_approval_id"] == ap.id
    assert sorted(review.required_roles) == ["management", "planning"]
    # post-facto review notifies the original roles as blockers
    notes = db.query(Notification).filter_by(kind="approval_request",
                                             ref_id=review.id).all()
    assert {n.user_id for n in notes} == {users["boss"].id, users["plan1"].id}


def test_inbox_filters_by_role_and_delegation(db, users, client):
    ap = _approval(db, users, roles=("planning",))
    plan, sup = _token(client, "plan1", "p"), _token(client, "sup1", "s")
    assert [a["id"] for a in client.get("/api/v1/approvals/inbox", headers=plan).json()] == [ap.id]
    assert client.get("/api/v1/approvals/inbox", headers=sup).json() == []
    # delegation via API: plan1 delegates to sup1 → appears in sup1's inbox
    r = client.post("/api/v1/approvals/delegations", headers=plan, json={
        "principal_user_id": users["plan1"].id, "delegate_user_id": users["sup1"].id,
        "valid_from": str(TODAY), "valid_to": str(TODAY + DAY)})
    assert r.status_code == 201, r.text
    deleg_id = r.json()["id"]
    assert [a["id"] for a in client.get("/api/v1/approvals/inbox", headers=sup).json()] == [ap.id]
    # only the principal (or admin) may delegate someone else's authority
    bad = client.post("/api/v1/approvals/delegations", headers=sup, json={
        "principal_user_id": users["plan1"].id, "delegate_user_id": users["sup1"].id,
        "valid_from": str(TODAY), "valid_to": str(TODAY + DAY)})
    assert bad.status_code == 403
    assert bad.json()["detail"]["code"] == "DELEGATION_NOT_PRINCIPAL"
    # PATCH-deactivate (no http DELETE) drops it from the delegate's inbox
    off = client.patch(f"/api/v1/approvals/delegations/{deleg_id}", headers=plan,
                       json={"is_active": False})
    assert off.status_code == 200 and off.json()["is_active"] is False
    assert client.get("/api/v1/approvals/inbox", headers=sup).json() == []
    # hold keeps the approval in the inbox
    client.post(f"/api/v1/approvals/{ap.id}/decide", headers=plan,
                json={"decision": "hold", "note": "need the invoice scan"})
    rows = client.get("/api/v1/approvals/inbox", headers=plan).json()
    assert [a["status"] for a in rows] == ["hold"]
