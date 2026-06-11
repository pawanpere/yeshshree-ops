"""Housekeeping sweep jobs (§11.15), run by the worker. Each is idempotent —
already-notified refs are skipped via a notification-existence check."""
import datetime as dt

from sqlalchemy.orm import Session

from app.models.gate import GateEntry
from app.models.identity import User
from app.models.workflow import Notification
from app.services.notifications import create_notification


def photos_pending_sweep(db: Session, now: dt.datetime | None = None) -> int:
    """Gate entries whose photos never arrived within 24 h → notify admins once."""
    now = now or dt.datetime.now(dt.timezone.utc)
    cutoff = now - dt.timedelta(hours=24)
    stale = (db.query(GateEntry)
             .filter(GateEntry.photos_pending.is_(True),
                     GateEntry.created_at < cutoff).all())
    admins = db.query(User).filter_by(role="admin", is_active=True).all()
    fired = 0
    for entry in stale:
        already = (db.query(Notification)
                   .filter_by(kind="photos_pending", ref_type="gate_entries",
                              ref_id=entry.id).count())
        if already:
            continue
        for admin in admins:
            create_notification(
                db, user_id=admin.id, kind="photos_pending", tier="digest",
                title=f"Photos still missing on {entry.doc_no}",
                body=f"Gate entry {entry.doc_no} ({entry.vehicle_no}) has had photos "
                     f"pending for over 24h — check the device's upload queue.",
                ref_type="gate_entries", ref_id=entry.id)
        fired += 1
    db.commit()
    return fired
