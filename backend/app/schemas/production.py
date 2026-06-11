"""Production confirmation / hold / correction schemas (P29–P31). Decimal everywhere —
never float (CLAUDE.md invariant 9). Create models list ONLY what the API accepts
(order_id, status, posted_after_close, shift_context_id are server-resolved)."""
import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict


class _Read(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class ProcessLoss(BaseModel):
    """§4.7 process_loss JSON — per-stage loss quantities."""
    blanking: Decimal = Decimal("0")
    piercing: Decimal = Decimal("0")
    forming: Decimal = Decimal("0")


class ConfirmationCreate(BaseModel):
    """POST /confirmations body — also the frozen payload of a confirmation_hold
    (§11.11), so resolve_hold can re-validate it with this exact model."""
    client_ref: uuid.UUID
    line_id: int
    shift: Literal["A", "B"]
    material_id: int
    good_qty: Decimal
    rejected_qty: Decimal = Decimal("0")
    reject_reason_id: int | None = None  # required if rejected_qty > 0 (service-enforced)
    downtime_min: int = 0
    downtime_reason_id: int | None = None  # required if downtime_min > 0
    process_loss: ProcessLoss | None = None
    kind: Literal["interim", "shift_close"] = "interim"
    shift_date: date | None = None  # defaults to today (server date)


class ConfirmationRead(_Read):
    id: int
    order_id: int
    line_id: int
    shift: str
    material_id: int
    good_qty: Decimal
    rejected_qty: Decimal
    reject_reason_id: int | None
    downtime_min: int
    downtime_reason_id: int | None
    process_loss: dict | None
    kind: str
    status: str
    client_ref: uuid.UUID
    supervisor_id: int
    posted_at: datetime
    shift_context_id: int | None
    posted_after_close: bool
    # sap_outbox.status joined in (pending/batched/sent/acked/failed); None only if
    # the outbox row is missing (cannot happen for rows written by this service).
    sap_sync_status: str | None = None


class HoldRead(_Read):
    id: int
    line_id: int
    material_id: int
    shift_context_id: int
    payload: dict  # the full ConfirmationCreate body, frozen (§11.11)
    status: str
    resolved_order_id: int | None
    client_ref: uuid.UUID
    created_by: int
    created_at: datetime


class HoldResolve(BaseModel):
    """PPC supplies the SAP order; line/material default from the hold itself."""
    sap_order_no: str
    line_id: int | None = None
    material_id: int | None = None


class HoldResolveResult(BaseModel):
    hold: HoldRead
    confirmation: ConfirmationRead


class CorrectionCreate(BaseModel):
    delta_good: Decimal
    delta_reject: Decimal = Decimal("0")
    reason: str


class CorrectionRead(_Read):
    id: int
    confirmation_id: int
    delta_good: Decimal
    delta_reject: Decimal
    reason: str
    approval_id: int
    status: str
