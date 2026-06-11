"""Approvals + delegations + notifications schemas (P25/P26/P38).
Read models use from_attributes; create models list ONLY what the API accepts."""
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict


class _Read(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --- approvals ---
class ApprovalRead(_Read):
    id: int
    approval_type: str
    ref_type: str
    ref_id: int
    payload: dict
    required_roles: list[str]
    status: str
    created_by: int
    created_at: datetime
    decided_at: datetime | None
    overridden_by: int | None
    override_reason: str | None


class DecideRequest(BaseModel):
    decision: Literal["approve", "decline", "hold"]
    note: str | None = None


class OverrideRequest(BaseModel):
    reason: str  # mandatory; blank → 422 OVERRIDE_REASON_REQUIRED (§11.2)


# --- delegations (§11.2) ---
class DelegationCreate(BaseModel):
    principal_user_id: int
    delegate_user_id: int
    approval_type: str | None = None  # NULL = all types
    valid_from: date
    valid_to: date


class DelegationRead(_Read):
    id: int
    principal_user_id: int
    delegate_user_id: int
    approval_type: str | None
    valid_from: date
    valid_to: date
    created_by: int
    is_active: bool


class DelegationUpdate(BaseModel):
    is_active: bool  # only False is accepted — deactivate, never delete


# --- notifications (§11.14) ---
class NotificationRead(_Read):
    id: int
    user_id: int
    title: str
    body: str | None
    kind: str
    ref_type: str | None
    ref_id: int | None
    read_at: datetime | None
    created_at: datetime
    tier: str
    acted_at: datetime | None
    next_repeat_at: datetime | None
    digest_of: dict | None
