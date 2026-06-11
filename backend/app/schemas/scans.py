"""Scan-pipeline + station-status schemas (P17/P19). Spec: §5.7 + §11.4."""
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class _Read(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class ScanRead(_Read):
    id: int
    file_id: int
    source: str
    decode_status: str
    qr_payload: dict | None
    pdf417_payload: str | None
    hsn_check: str
    status: str
    gate_entry_id: int | None
    created_at: datetime


class ScanUploadResponse(BaseModel):
    """POST /gate-entries/scans result. `duplicate=true` = these exact bytes were
    already scanned (Failure Scenarios #3) — the EXISTING scan is returned."""
    scan: ScanRead
    duplicate: bool
    suggestions: dict
    suggested_vendor_id: int | None
    suggested_po_id: int | None


class PendingScan(BaseModel):
    scan: ScanRead
    suggestions: dict


class DecodeQrRequest(BaseModel):
    payload: str  # raw QR text from the phone camera (JWS 'eyJ…')


class DecodeQrResponse(BaseModel):
    decode_status: str  # 'decoded' | 'none'
    suggestions: dict


class HeartbeatRequest(BaseModel):
    device_key: str
    agent_version: str
    watch_folder_ok: bool
    last_scan_at: datetime | None = None


class StationStatusRead(_Read):
    id: int
    device_key: str
    kind: str
    last_heartbeat_at: datetime | None
    agent_version: str | None
    detail: dict | None
    stale_seconds: int | None = None  # computed; None = never heartbeated
