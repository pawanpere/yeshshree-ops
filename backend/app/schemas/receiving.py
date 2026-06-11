"""Receiving (GR) + anomaly-register schemas (P20/P21). Decimal everywhere — never
float (CLAUDE.md invariant 9). Read models use from_attributes; create models list
ONLY the fields the API accepts. §11.18: GR NEVER prefills received qty — there is
deliberately no endpoint/schema that returns a suggested received_qty."""
import uuid
from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict


class _Read(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --- goods receipts ---
class GoodsReceiptCreate(BaseModel):
    gate_entry_id: int
    received_qty: Decimal  # 100% physical count at QC (§11.18) — operator-typed
    rejected_qty: Decimal = Decimal("0")
    qc_result: Literal["pass", "fail"]  # 'fail' = full-lot reject (§11.9)
    qc_remarks: str | None = None
    confirm_escalate: bool = False  # operator confirms a hard anomaly → escalate path
    client_ref: uuid.UUID


class GoodsReceiptRead(_Read):
    id: int
    doc_no: str
    gate_entry_id: int
    po_id: int | None
    material_id: int
    expected_qty: Decimal
    received_qty: Decimal
    accepted_qty: Decimal
    rejected_qty: Decimal
    qc_result: str
    qc_remarks: str | None
    shortage_qty: Decimal
    status: str
    posted_by: int
    posted_at: datetime


# --- anomaly register ---
class AnomalyRead(_Read):
    id: int
    rule_code: str
    severity: str
    ref_type: str
    ref_id: int
    observed: dict | None
    expected: dict | None
    message_en: str
    message_mr: str
    status: str
    resolved_by: int | None
    resolved_at: datetime | None
    created_at: datetime


class AnomalyResolve(BaseModel):
    note: str  # stored in the audit diff (anomalies table has no note column)
