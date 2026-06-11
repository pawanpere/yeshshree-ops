"""Generic escalation timers engine (P26; Architecture §11.8).

Predicates are plain Python in a registry (code); thresholds + notify chains are
config rows (`escalation_rules`). The worker calls `escalation_scan` every 5 min;
tests call the same pure function with a fake `now` — identical code path.

Mismatch noted vs the brief: predicates yield (ref_type, ref_id, since) 3-tuples,
not 2-tuples — the chain-stage check needs the breach start time (`since`) to decide
whether `threshold_min + after_min` has elapsed; deriving it again per stage would
duplicate every query. `since` is the row's created_at / last_heartbeat_at.

Chain semantics: stage N (1-based index into notify_chain) fires when
`now >= since + threshold_min + after_min`. UQ(rule_code, ref_id, stage) makes
rescans idempotent — existing events (open OR resolved) are skipped.

Role sentinel: 'approvers' in a chain for ref_type='approvals' expands to the
approval's required_roles INCLUDING active delegates (§11.2 "remind approvers
+ delegates"); other role names notify all active holders of that role.

Seed roles decision (org → role mapping): store head ≈ supervisor, plant head/MD ≈
management, purchase/planner ≈ planning, gate-agent health → admin (§11.4).
"""
import datetime as dt
from typing import Callable, Iterable

from sqlalchemy.orm import Session

from app.models.gate import GateEntry
from app.models.system import StationStatus
from app.models.workflow import Anomaly, Approval, EscalationEvent, EscalationRule
from app.services.approvals import approval_recipients
from app.services.notifications import create_notification, notify_roles


def _now(now: dt.datetime | None) -> dt.datetime:
    return now if now is not None else dt.datetime.now(dt.timezone.utc)


def _cutoff(now: dt.datetime, minutes: int) -> dt.datetime:
    return now - dt.timedelta(minutes=minutes)


# --- predicate registry: rule_code → (db, rule, now) → iter[(ref_type, ref_id, since)] ---

def _gr_pending(db: Session, rule: EscalationRule, now: dt.datetime) -> Iterable[tuple]:
    rows = (db.query(GateEntry.id, GateEntry.created_at)
            .filter(GateEntry.status == "open",
                    GateEntry.match_status == "matched",
                    GateEntry.created_at <= _cutoff(now, rule.threshold_min))
            .all())
    return [("gate_entries", rid, since) for rid, since in rows]


def _unmatched_gate(db: Session, rule: EscalationRule, now: dt.datetime) -> Iterable[tuple]:
    rows = (db.query(GateEntry.id, GateEntry.created_at)
            .filter(GateEntry.status == "open",
                    GateEntry.match_status == "unmatched",
                    GateEntry.created_at <= _cutoff(now, rule.threshold_min))
            .all())
    return [("gate_entries", rid, since) for rid, since in rows]


def _approval_pending(db: Session, rule: EscalationRule, now: dt.datetime) -> Iterable[tuple]:
    rows = (db.query(Approval.id, Approval.created_at)
            .filter(Approval.status == "pending",
                    Approval.created_at <= _cutoff(now, rule.threshold_min))
            .all())
    return [("approvals", rid, since) for rid, since in rows]


def _gate_agent_stale(db: Session, rule: EscalationRule, now: dt.datetime) -> Iterable[tuple]:
    rows = (db.query(StationStatus.id, StationStatus.last_heartbeat_at)
            .filter(StationStatus.kind == "gate_agent",
                    StationStatus.last_heartbeat_at.is_not(None),
                    StationStatus.last_heartbeat_at <= _cutoff(now, rule.threshold_min))
            .all())
    return [("station_status", rid, since) for rid, since in rows]


def _hard_block_unanswered(db: Session, rule: EscalationRule, now: dt.datetime) -> Iterable[tuple]:
    rows = (db.query(Anomaly.id, Anomaly.created_at)
            .filter(Anomaly.severity == "hard",
                    Anomaly.status == "open",
                    Anomaly.created_at <= _cutoff(now, rule.threshold_min))
            .all())
    return [("anomalies", rid, since) for rid, since in rows]


PREDICATES: dict[str, Callable[[Session, EscalationRule, dt.datetime], Iterable[tuple]]] = {
    "gr_pending_30m": _gr_pending,
    "unmatched_gate_24h": _unmatched_gate,
    "approval_pending_2h": _approval_pending,
    "approval_pending_4h": _approval_pending,
    "gate_agent_stale_15m": _gate_agent_stale,
    "hard_block_unanswered_30m": _hard_block_unanswered,
}


def _notify_stage(db: Session, rule: EscalationRule, stage_no: int, roles: list,
                  ref_type: str, ref_id: int, now: dt.datetime) -> list[str]:
    """Blocker notifications for one chain stage; returns the CONCRETE roles notified
    ('approvers' sentinel expanded). Joins the caller's transaction."""
    concrete: list[str] = []
    title = f"Escalation {rule.rule_code} (stage {stage_no})"
    body = f"{ref_type} #{ref_id} breached {rule.threshold_min} min"
    for role in roles:
        if role == "approvers" and ref_type == "approvals":
            approval = db.get(Approval, ref_id)
            if approval is None:
                continue
            concrete.extend(r for r in approval.required_roles if r not in concrete)
            for u in approval_recipients(db, list(approval.required_roles),
                                         approval.approval_type, now=now):
                create_notification(db, user_id=u.id, kind="escalation", tier="blocker",
                                    title=title, body=body,
                                    ref_type=ref_type, ref_id=ref_id, now=now)
        else:
            if role not in concrete:
                concrete.append(role)
            notify_roles(db, [role], kind="escalation", tier="blocker", title=title,
                         body=body, ref_type=ref_type, ref_id=ref_id, now=now)
    return concrete


def escalation_scan(db: Session, now: dt.datetime | None = None) -> int:
    """One pass over every active rule with a known predicate. Idempotent: the
    UQ(rule_code, ref_id, stage) is respected by skipping existing events.
    Returns the number of stages fired. Worker job AND test entry point."""
    now = _now(now)
    fired = 0
    rules = db.query(EscalationRule).filter(EscalationRule.is_active.is_(True)).all()
    for rule in rules:
        predicate = PREDICATES.get(rule.rule_code)
        if predicate is None:
            continue  # config row without code yet — never crash the scan
        chain = rule.notify_chain or []
        for ref_type, ref_id, since in predicate(db, rule, now):
            for stage_no, stage in enumerate(chain, start=1):
                due_at = since + dt.timedelta(
                    minutes=rule.threshold_min + int(stage.get("after_min", 0)))
                if now < due_at:
                    continue
                exists = (db.query(EscalationEvent)
                          .filter_by(rule_code=rule.rule_code, ref_id=ref_id,
                                     stage=stage_no).one_or_none())
                if exists is not None:
                    continue  # UQ(rule_code, ref_id, stage) — already fired
                notified = _notify_stage(db, rule, stage_no, list(stage.get("roles", [])),
                                         ref_type, ref_id, now)
                db.add(EscalationEvent(rule_code=rule.rule_code, ref_type=ref_type,
                                       ref_id=ref_id, stage=stage_no,
                                       notified_roles=notified, created_at=now))
                fired += 1
    db.commit()
    return fired


def resolve_events(db: Session, ref_type: str, ref_id: int,
                   now: dt.datetime | None = None) -> int:
    """Close open events when the underlying thing completes (GR posted, approval
    decided, entry matched…). NO commit — call sites run inside their own
    transaction; they arrive in later packets."""
    now = _now(now)
    rows = (db.query(EscalationEvent)
            .filter(EscalationEvent.ref_type == ref_type,
                    EscalationEvent.ref_id == ref_id,
                    EscalationEvent.resolved_at.is_(None))
            .all())
    for row in rows:
        row.resolved_at = now
    return len(rows)


DEFAULT_RULES: list[dict] = [
    # gate entry open >30 min → store head (supervisor); >2 h total → management
    dict(rule_code="gr_pending_30m", ref_type="gate_entries", threshold_min=30,
         notify_chain=[{"after_min": 0, "roles": ["supervisor"]},
                       {"after_min": 90, "roles": ["management"]}], repeat_min=None),
    # unmatched gate entry >24 h → purchase/planner + store head, repeats daily
    dict(rule_code="unmatched_gate_24h", ref_type="gate_entries", threshold_min=1440,
         notify_chain=[{"after_min": 0, "roles": ["planning", "supervisor"]}],
         repeat_min=1440),
    # pending approval >2 h → remind approvers+delegates; >4 h → escalate management
    dict(rule_code="approval_pending_2h", ref_type="approvals", threshold_min=120,
         notify_chain=[{"after_min": 0, "roles": ["approvers"]}], repeat_min=None),
    dict(rule_code="approval_pending_4h", ref_type="approvals", threshold_min=240,
         notify_chain=[{"after_min": 0, "roles": ["management"]}], repeat_min=None),
    # gate-agent heartbeat stale >15 min → admin (§11.4)
    dict(rule_code="gate_agent_stale_15m", ref_type="station_status", threshold_min=15,
         notify_chain=[{"after_min": 0, "roles": ["admin"]}], repeat_min=None),
    # open hard anomaly >30 min → supervisor; +30 min → management
    dict(rule_code="hard_block_unanswered_30m", ref_type="anomalies", threshold_min=30,
         notify_chain=[{"after_min": 0, "roles": ["supervisor"]},
                       {"after_min": 30, "roles": ["management"]}], repeat_min=None),
]


def seed_default_escalation_rules(db: Session) -> list[EscalationRule]:
    """Idempotent get-or-create by rule_code (§11.8 seed rules)."""
    out = []
    for spec in DEFAULT_RULES:
        row = (db.query(EscalationRule)
               .filter_by(rule_code=spec["rule_code"]).one_or_none())
        if row is None:
            row = EscalationRule(**spec, is_active=True)
            db.add(row)
        out.append(row)
    db.commit()
    return out
