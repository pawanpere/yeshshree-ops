"""Notification helpers + tier mechanics (P38; Architecture §11.14).

- `create_notification` is the ONE primitive every service uses (no commit — it joins
  the caller's transaction, invariant 3). Blockers get `next_repeat_at = now + 15 min`
  at creation so the `blocker_repeat` worker can pick them up without extra state.
- `digest_bundle` (worker, hourly): collapses a user's unread tier='digest' rows into
  one summary notification carrying source ids in `digest_of`; sources are marked read
  so a re-run never double-bundles. Decision: groups of ONE are left alone — a digest
  of a single item is noise, the row already stands on its own.
- `blocker_repeat` (worker, 15 min): unacted blockers past `next_repeat_at` are
  re-notified via a DUPLICATE row whose backoff doubles (15 → 30 → 60 …). The original
  row's `next_repeat_at` is cleared — the newest duplicate carries the repeat chain.
  Backoff is derived as (next_repeat_at − created_at), so no extra column is needed.
- Acting (`mark_acted`) stops the whole chain: every unacted blocker of that user on
  the same ref gets `acted_at`, repeats end.
All functions accept a fake `now` so worker AND tests share the exact code path.
"""
import datetime as dt

from sqlalchemy.orm import Session

from app.core.deps import CurrentUser, _error
from app.models.identity import User
from app.models.workflow import Notification

INITIAL_REPEAT_MIN = 15
DIGEST_SUMMARY_KIND = "digest_summary"


def _now(now: dt.datetime | None) -> dt.datetime:
    return now if now is not None else dt.datetime.now(dt.timezone.utc)


def create_notification(db: Session, *, user_id: int, kind: str, title: str,
                        body: str | None = None, tier: str = "digest",
                        ref_type: str | None = None, ref_id: int | None = None,
                        digest_of: dict | None = None,
                        now: dt.datetime | None = None) -> Notification:
    """No commit — runs inside the caller's transaction (CLAUDE.md invariant 3)."""
    now = _now(now)
    n = Notification(
        user_id=user_id, kind=kind, title=title, body=body, tier=tier,
        ref_type=ref_type, ref_id=ref_id, created_at=now,
        next_repeat_at=(now + dt.timedelta(minutes=INITIAL_REPEAT_MIN)
                        if tier == "blocker" else None),
    )
    if digest_of is not None:
        n.digest_of = digest_of
    db.add(n)
    return n


def notify_roles(db: Session, roles, *, kind: str, title: str, body: str | None = None,
                 tier: str = "blocker", ref_type: str | None = None,
                 ref_id: int | None = None,
                 now: dt.datetime | None = None) -> list[Notification]:
    """One notification per ACTIVE user holding any of `roles`. No commit."""
    users = (db.query(User)
             .filter(User.is_active.is_(True), User.role.in_(list(roles)))
             .all())
    return [create_notification(db, user_id=u.id, kind=kind, title=title, body=body,
                                tier=tier, ref_type=ref_type, ref_id=ref_id, now=now)
            for u in users]


# --- inbox endpoints (commit-owning, called from api/notifications.py) ---

def list_notifications(db: Session, user: CurrentUser,
                       unread: bool | None = None) -> list[Notification]:
    q = db.query(Notification).filter(Notification.user_id == user.id)
    if unread is True:
        q = q.filter(Notification.read_at.is_(None))
    elif unread is False:
        q = q.filter(Notification.read_at.is_not(None))
    return q.order_by(Notification.id.desc()).limit(200).all()


def _own_or_404(db: Session, user: CurrentUser, notification_id: int) -> Notification:
    n = db.get(Notification, notification_id)
    if n is None or n.user_id != user.id:  # never leak another user's inbox
        raise _error("NOT_FOUND", "Notification not found", "सूचना सापडली नाही", 404,
                     {"notification_id": notification_id})
    return n


def mark_read(db: Session, user: CurrentUser, notification_id: int) -> Notification:
    n = _own_or_404(db, user, notification_id)
    if n.read_at is None:
        n.read_at = dt.datetime.now(dt.timezone.utc)
        db.commit()
        db.refresh(n)
    return n


def mark_acted(db: Session, user: CurrentUser, notification_id: int) -> Notification:
    """§11.14: acting sets acted_at → blocker repeats stop, for the WHOLE chain
    (every unacted notification of this user on the same ref)."""
    n = _own_or_404(db, user, notification_id)
    now = dt.datetime.now(dt.timezone.utc)
    chain = [n]
    if n.ref_type is not None and n.ref_id is not None:
        chain = (db.query(Notification)
                 .filter(Notification.user_id == user.id,
                         Notification.ref_type == n.ref_type,
                         Notification.ref_id == n.ref_id,
                         Notification.acted_at.is_(None))
                 .all()) or [n]
    for row in chain:
        if row.acted_at is None:
            row.acted_at = now
        row.next_repeat_at = None
        if row.read_at is None:
            row.read_at = now
    db.commit()
    db.refresh(n)
    return n


# --- worker jobs (also called by tests with fake `now`) ---

def digest_bundle(db: Session, now: dt.datetime | None = None) -> int:
    """Collapse each user's unread digest rows (≥2) into ONE summary. Returns the
    number of summary notifications created."""
    now = _now(now)
    rows = (db.query(Notification)
            .filter(Notification.tier == "digest",
                    Notification.read_at.is_(None),
                    Notification.kind != DIGEST_SUMMARY_KIND)
            .order_by(Notification.id)
            .all())
    by_user: dict[int, list[Notification]] = {}
    for r in rows:
        by_user.setdefault(r.user_id, []).append(r)
    created = 0
    for user_id, items in by_user.items():
        if len(items) < 2:
            continue  # a digest of one is noise — leave the row as-is
        ids = [i.id for i in items]
        titles = "; ".join(i.title for i in items[:5])
        create_notification(db, user_id=user_id, kind=DIGEST_SUMMARY_KIND,
                            title=f"{len(ids)} updates",
                            body=titles, tier="digest",
                            digest_of={"ids": ids}, now=now)
        for i in items:
            i.read_at = now  # consumed by the summary — never re-bundled
        created += 1
    db.commit()
    return created


def blocker_repeat(db: Session, now: dt.datetime | None = None) -> int:
    """Re-notify unacted blockers past next_repeat_at; backoff doubles each repeat.
    Returns the number of repeats fired."""
    now = _now(now)
    due = (db.query(Notification)
           .filter(Notification.tier == "blocker",
                   Notification.acted_at.is_(None),
                   Notification.next_repeat_at.is_not(None),
                   Notification.next_repeat_at <= now)
           .all())
    for n in due:
        interval = n.next_repeat_at - n.created_at
        if interval.total_seconds() <= 0:
            interval = dt.timedelta(minutes=INITIAL_REPEAT_MIN)
        dup = create_notification(db, user_id=n.user_id, kind=n.kind, title=n.title,
                                  body=n.body, tier="blocker",
                                  ref_type=n.ref_type, ref_id=n.ref_id, now=now)
        dup.next_repeat_at = now + (interval * 2)  # doubled backoff
        n.next_repeat_at = None  # the newest duplicate carries the chain
    db.commit()
    return len(due)
