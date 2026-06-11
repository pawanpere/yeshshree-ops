"""Notifications inbox router (P38; §11.14). HTTP concerns ONLY — tier mechanics
live in services/notifications.py (CLAUDE.md). NOTE: register in app/main.py with
`app.include_router(notifications_router)` — wiring main.py is outside this packet's
file list (tests mount it themselves)."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, require
from app.schemas import workflow as s
from app.services import notifications as svc

router = APIRouter(prefix="/api/v1/notifications", tags=["notifications"])

# Any authenticated user (vendors get notifications too) — rows are own-only in the
# service, so there is nothing to leak.
any_user = require()


@router.get("", response_model=list[s.NotificationRead])
def list_notifications(unread: bool | None = Query(None),
                       db: Session = Depends(get_db),
                       user: CurrentUser = Depends(any_user)):
    return svc.list_notifications(db, user, unread)


@router.post("/{notification_id}/read", response_model=s.NotificationRead)
def mark_read(notification_id: int, db: Session = Depends(get_db),
              user: CurrentUser = Depends(any_user)):
    return svc.mark_read(db, user, notification_id)


@router.post("/{notification_id}/act", response_model=s.NotificationRead)
def mark_acted(notification_id: int, db: Session = Depends(get_db),
               user: CurrentUser = Depends(any_user)):
    """Sets acted_at — stops blocker repeats for the whole chain on this ref."""
    return svc.mark_acted(db, user, notification_id)
