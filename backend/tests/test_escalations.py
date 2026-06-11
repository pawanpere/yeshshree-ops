"""P26/P38 acceptance with a fixture clock: staged escalation timers (UQ-idempotent
rescans), approval reminder + resolve_events, gate-agent staleness, digest bundling,
blocker repeat with doubled backoff. All times naive-UTC for SQLite determinism."""
import datetime as dt
import uuid

import pytest

from app.core.security import hash_password
from app.models.gate import GateEntry
from app.models.identity import User
from app.models.system import StationStatus
from app.models.workflow import Approval, EscalationEvent, Notification
from app.services.escalations import (escalation_scan, resolve_events,
                                      seed_default_escalation_rules)
from app.services.notifications import blocker_repeat, create_notification, digest_bundle

T0 = dt.datetime(2026, 6, 11, 8, 0, 0)  # fixture clock origin


def m(minutes: int) -> dt.datetime:
    return T0 + dt.timedelta(minutes=minutes)


@pytest.fixture()
def users(db):
    rows = {
        "admin": User(username="admin", password_hash=hash_password("a"),
                      full_name="A", role="admin", language="en"),
        "boss": User(username="boss", password_hash=hash_password("b"),
                     full_name="B", role="management", language="en"),
        "sup1": User(username="sup1", password_hash=hash_password("s"),
                     full_name="S", role="supervisor", language="mr"),
        "plan1": User(username="plan1", password_hash=hash_password("p"),
                      full_name="P", role="planning", language="en"),
    }
    db.add_all(rows.values())
    db.commit()
    return rows


def _gate_entry(db, users, created_at=T0, **over):
    n = uuid.uuid4().hex[:8]
    base = dict(doc_no=f"G-{n}", vehicle_no="MH12AB1234", driver_name="Ramu",
                match_status="matched", status="open", client_ref=uuid.uuid4(),
                created_by=users["admin"].id, created_at=created_at)
    base.update(over)
    e = GateEntry(**base)
    db.add(e)
    db.commit()
    return e


def test_gr_pending_stages_fire_once_each(db, users):
    seed_default_escalation_rules(db)
    seed_default_escalation_rules(db)  # idempotent get-or-create
    entry = _gate_entry(db, users)

    assert escalation_scan(db, now=m(29)) == 0  # not yet in breach
    assert escalation_scan(db, now=m(31)) == 1  # stage 1 (threshold 30 + after 0)
    ev1 = db.query(EscalationEvent).one()
    assert (ev1.rule_code, ev1.stage, ev1.ref_type, ev1.ref_id) == \
        ("gr_pending_30m", 1, "gate_entries", entry.id)
    assert ev1.notified_roles == ["supervisor"]
    notes = db.query(Notification).filter_by(kind="escalation").all()
    assert [n.user_id for n in notes] == [users["sup1"].id]
    assert notes[0].tier == "blocker"

    assert escalation_scan(db, now=m(35)) == 0  # rescan: UQ respected, no duplicate
    assert escalation_scan(db, now=m(121)) == 1  # stage 2 (30 + after 90 = 120)
    ev2 = db.query(EscalationEvent).filter_by(stage=2).one()
    assert ev2.notified_roles == ["management"]
    boss_notes = db.query(Notification).filter_by(kind="escalation",
                                                  user_id=users["boss"].id).all()
    assert len(boss_notes) == 1
    assert escalation_scan(db, now=m(125)) == 0  # never duplicates either stage
    assert db.query(EscalationEvent).count() == 2


def test_approval_pending_fires_and_resolve_closes(db, users):
    seed_default_escalation_rules(db)
    ap = Approval(approval_type="debit_note", ref_type="debit_notes", ref_id=7,
                  payload={}, required_roles=["management"], status="pending",
                  created_by=users["admin"].id, created_at=T0)
    db.add(ap)
    db.commit()

    assert escalation_scan(db, now=m(121)) == 1  # approval_pending_2h, not yet 4h
    ev = db.query(EscalationEvent).one()
    assert (ev.rule_code, ev.stage) == ("approval_pending_2h", 1)
    assert ev.notified_roles == ["management"]  # 'approvers' sentinel expanded
    note = db.query(Notification).filter_by(kind="escalation").one()
    assert (note.user_id, note.tier) == (users["boss"].id, "blocker")
    assert (note.ref_type, note.ref_id) == ("approvals", ap.id)

    assert resolve_events(db, "approvals", ap.id, now=m(130)) == 1
    db.commit()
    db.refresh(ev)
    assert ev.resolved_at is not None
    assert escalation_scan(db, now=m(135)) == 0  # resolved event still blocks re-fire


def test_gate_agent_stale_fires_on_old_heartbeat(db, users):
    seed_default_escalation_rules(db)
    st = StationStatus(device_key="GATE-PC-01", kind="gate_agent",
                       last_heartbeat_at=T0, agent_version="1.0.0")
    db.add(st)
    db.commit()
    assert escalation_scan(db, now=m(10)) == 0  # heartbeat only 10 min old
    assert escalation_scan(db, now=m(20)) == 1  # >15 min stale
    ev = db.query(EscalationEvent).one()
    assert (ev.rule_code, ev.ref_type, ev.ref_id) == \
        ("gate_agent_stale_15m", "station_status", st.id)
    note = db.query(Notification).filter_by(kind="escalation").one()
    assert note.user_id == users["admin"].id


def test_digest_bundle_collapses_into_one_summary(db, users):
    uid = users["sup1"].id
    for i in range(3):
        create_notification(db, user_id=uid, kind="plan_change", tier="digest",
                            title=f"Plan changed #{i}", now=m(i))
    db.commit()
    assert digest_bundle(db, now=m(60)) == 1
    summary = db.query(Notification).filter_by(kind="digest_summary").one()
    assert summary.user_id == uid
    assert summary.title == "3 updates"
    sources = db.query(Notification).filter_by(kind="plan_change").all()
    assert summary.digest_of == {"ids": [n.id for n in sources]}
    assert all(n.read_at is not None for n in sources)  # consumed by the summary
    assert digest_bundle(db, now=m(120)) == 0  # nothing left to bundle


def test_blocker_repeat_doubles_backoff(db, users):
    uid = users["boss"].id
    n = create_notification(db, user_id=uid, kind="approval_request", tier="blocker",
                            title="Approval needed", ref_type="approvals", ref_id=9,
                            now=T0)
    db.commit()
    assert n.next_repeat_at == m(15)  # initial backoff armed at creation

    assert blocker_repeat(db, now=m(10)) == 0  # not due yet
    assert blocker_repeat(db, now=m(16)) == 1  # past next_repeat_at → re-notify
    rows = (db.query(Notification).filter_by(user_id=uid, kind="approval_request")
            .order_by(Notification.id).all())
    assert len(rows) == 2
    original, dup = rows
    assert original.next_repeat_at is None  # chain moved to the duplicate
    assert dup.next_repeat_at == m(16) + dt.timedelta(minutes=30)  # 15 → 30 doubled
    assert dup.tier == "blocker" and dup.ref_id == 9

    assert blocker_repeat(db, now=m(17)) == 0  # duplicate not due yet
    assert blocker_repeat(db, now=m(47)) == 1  # 30-min backoff elapses → fires again
    newest = (db.query(Notification).filter_by(user_id=uid, kind="approval_request")
              .order_by(Notification.id.desc()).first())
    assert newest.next_repeat_at == m(47) + dt.timedelta(minutes=60)  # 30 → 60
