"""User + station-device admin router (Phase 5). Admin-only. NO delete routes
(deactivate via is_active). HTTP concerns only — logic in services/identity.py."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, require
from app.models.identity import StationDevice, User
from app.schemas import identity as s
from app.services.identity import (create_device, create_user, update_device,
                                    update_user)

router = APIRouter(prefix="/api/v1/master", tags=["identity"])

admin_guard = require("admin")


# --- users ---
@router.get("/users", response_model=list[s.UserRead])
def list_users(q: str | None = Query(None, description="search username/name"),
               role: str | None = Query(None),
               active_only: bool = True, limit: int = 200, offset: int = 0,
               db: Session = Depends(get_db),
               _: CurrentUser = Depends(admin_guard)):
    query = db.query(User)
    if active_only:
        query = query.filter_by(is_active=True)
    if role:
        query = query.filter_by(role=role)
    if q:
        like = f"%{q}%"
        query = query.filter(User.username.ilike(like) | User.full_name.ilike(like))
    return query.order_by(User.username).limit(limit).offset(offset).all()


@router.post("/users", response_model=s.UserRead, status_code=201)
def create_user_endpoint(body: s.UserCreate, db: Session = Depends(get_db),
                         user: CurrentUser = Depends(admin_guard)):
    return create_user(db, user, body)


@router.patch("/users/{user_id}", response_model=s.UserRead)
def update_user_endpoint(user_id: int, body: s.UserUpdate,
                         db: Session = Depends(get_db),
                         user: CurrentUser = Depends(admin_guard)):
    return update_user(db, user, user_id, body.model_dump(exclude_unset=True))


# --- station devices ---
@router.get("/station-devices", response_model=list[s.StationDeviceRead])
def list_devices(station: str | None = Query(None), active_only: bool = True,
                 limit: int = 200, offset: int = 0,
                 db: Session = Depends(get_db),
                 _: CurrentUser = Depends(admin_guard)):
    query = db.query(StationDevice)
    if active_only:
        query = query.filter_by(is_active=True)
    if station:
        query = query.filter_by(station=station)
    return query.order_by(StationDevice.device_key).limit(limit).offset(offset).all()


@router.post("/station-devices", response_model=s.StationDeviceRead, status_code=201)
def create_device_endpoint(body: s.StationDeviceCreate, db: Session = Depends(get_db),
                           user: CurrentUser = Depends(admin_guard)):
    return create_device(db, user, body)


@router.patch("/station-devices/{device_id}", response_model=s.StationDeviceRead)
def update_device_endpoint(device_id: int, body: s.StationDeviceUpdate,
                           db: Session = Depends(get_db),
                           user: CurrentUser = Depends(admin_guard)):
    return update_device(db, user, device_id, body.model_dump(exclude_unset=True))
