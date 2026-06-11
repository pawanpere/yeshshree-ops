"""Scan ingest + station status routers (P17/P19). Spec: §5.7 + §11.4 + §6.

Two routers (wired in main.py by the packet that owns it — NOT here):
- /api/v1/gate-entries: scans upload (agent), pending list, discard, decode-qr (phone)
- /api/v1/system: agent-heartbeat (upsert), station-status (gate screen poll)

Dedupe-first contract: identical bytes scanned twice (guard re-feeds the ScanJet
"because nothing happened") return the EXISTING scan with duplicate=true — never
a second decode/file/pipeline run (Failure Scenarios #3, services/files.py)."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, UploadFile
from sqlalchemy.orm import Session

from app.core.audit import record
from app.core.db import get_db
from app.core.deps import CurrentUser, require
from app.models.gate import GateScan
from app.models.master import PurchaseOrder, Vendor
from app.models.system import StationStatus
from app.schemas.scans import (DecodeQrRequest, DecodeQrResponse, HeartbeatRequest,
                               PendingScan, ScanRead, ScanUploadResponse,
                               StationStatusRead)
from app.services import files, scan_decode
from app.services.master import get_or_404

scans_router = APIRouter(prefix="/api/v1/gate-entries", tags=["scans"])
system_router = APIRouter(prefix="/api/v1/system", tags=["system"])

guard = require("plant_ops", "admin")


def _lookup_vendor_and_po(db: Session, suggestions: dict) -> tuple[int | None, int | None]:
    """Suggestion → master-data resolution. GSTIN match is exact; PO match is the
    first OPEN line of the suggested SAP PO number (item-level pick is the guard's)."""
    vendor_id = None
    gstin = suggestions.get("vendor_gstin")
    if gstin:
        vendor = db.query(Vendor).filter_by(gstin=gstin, is_active=True).first()
        vendor_id = vendor.id if vendor else None
    po_id = None
    po_no = suggestions.get("po_no")
    if po_no:
        po = (db.query(PurchaseOrder).filter_by(sap_po_no=po_no, status="open")
              .order_by(PurchaseOrder.item_no).first())
        po_id = po.id if po else None
    return vendor_id, po_id


def _response(db: Session, scan: GateScan, *, duplicate: bool) -> ScanUploadResponse:
    suggestions = (scan.qr_payload or {}).get("suggestions", {})
    vendor_id, po_id = _lookup_vendor_and_po(db, suggestions)
    return ScanUploadResponse(scan=ScanRead.model_validate(scan), duplicate=duplicate,
                              suggestions=suggestions, suggested_vendor_id=vendor_id,
                              suggested_po_id=po_id)


@scans_router.post("/scans", response_model=ScanUploadResponse)
async def upload_scan(file: UploadFile, db: Session = Depends(get_db),
                      user: CurrentUser = Depends(guard)) -> ScanUploadResponse:
    """gate-agent (or manual upload) → store → decode → suggestion lookup.
    Source is 'agent' for this multipart path; phones use /decode-qr (no file)."""
    content = await file.read()
    existing = files.find_duplicate_scan(db, content)
    if existing is not None:
        scan = (db.query(GateScan).filter_by(file_id=existing.id)
                .order_by(GateScan.id).first())
        if scan is not None:  # same bytes → same scan, no second pipeline run
            return _response(db, scan, duplicate=True)
    file_row = files.save_file(db, content=content, filename=file.filename or "scan",
                               kind="scan", mime=file.content_type, uploaded_by=user.id)
    result = scan_decode.decode_document(content, file.content_type)
    # hsn_check: materials.mat_group is a SAP material group (e.g. '1103'), NOT an
    # HSN chapter — there is no honest automatic comparison against MainHsnCode
    # without a configured mat_group↔HSN mapping. MVP records 'n/a'.
    # TODO(§11.18): wire material_group↔HSN mapping table, then 'ok'/'mismatch'.
    scan = GateScan(
        file_id=file_row.id,
        source="agent",
        decode_status=result.decode_status,
        qr_payload={"einvoice": result.qr_payload, "suggestions": result.suggestions,
                    "barcodes": result.raw_barcodes},
        pdf417_payload=result.pdf417_payload,
        hsn_check="n/a",
        status="pending",
        gate_entry_id=None,
    )
    db.add(scan)
    db.flush()
    record(db, user_id=user.id, entity="gate_scans", entity_id=scan.id, action="create",
           before=None, after={"decode_status": result.decode_status,
                               "file_id": file_row.id})
    db.commit()
    db.refresh(scan)
    return _response(db, scan, duplicate=False)


@scans_router.get("/scans/pending", response_model=list[PendingScan])
def pending_scans(db: Session = Depends(get_db),
                  _: CurrentUser = Depends(guard)) -> list[PendingScan]:
    rows = (db.query(GateScan).filter_by(status="pending")
            .order_by(GateScan.created_at, GateScan.id).all())
    return [PendingScan(scan=ScanRead.model_validate(r),
                        suggestions=(r.qr_payload or {}).get("suggestions", {}))
            for r in rows]


@scans_router.post("/scans/{scan_id}/discard", response_model=ScanRead)
def discard_scan(scan_id: int, db: Session = Depends(get_db),
                 user: CurrentUser = Depends(guard)) -> GateScan:
    """Wrong feed / blank page / test scan. File stays archived; row is auditable."""
    scan = get_or_404(db, GateScan, scan_id, "scan")
    if scan.status != "discarded":
        record(db, user_id=user.id, entity="gate_scans", entity_id=scan.id,
               action="status_change", before={"status": scan.status},
               after={"status": "discarded"})
        scan.status = "discarded"
        db.commit()
    return scan


@scans_router.post("/decode-qr", response_model=DecodeQrResponse)
def decode_qr(body: DecodeQrRequest, _: CurrentUser = Depends(guard)) -> DecodeQrResponse:
    """Phone-camera fallback (§11.4 scanner-offline banner): the app sends the RAW
    QR text it scanned; we parse the same e-invoice JWS. Nothing is stored."""
    qr = scan_decode.parse_einvoice_qr(body.payload)
    return DecodeQrResponse(decode_status="decoded" if qr else "none",
                            suggestions=scan_decode.build_suggestions(qr, None))


@system_router.post("/agent-heartbeat", response_model=StationStatusRead)
def agent_heartbeat(body: HeartbeatRequest, db: Session = Depends(get_db),
                    _: CurrentUser = Depends(guard)) -> StationStatus:
    """Upsert by device_key (§11.4). Detail keeps the agent's self-reported state;
    staleness is computed at read time, never stored."""
    row = db.query(StationStatus).filter_by(device_key=body.device_key).one_or_none()
    detail = {"watch_folder_ok": body.watch_folder_ok,
              "last_scan_at": body.last_scan_at.isoformat() if body.last_scan_at else None}
    if row is None:
        row = StationStatus(device_key=body.device_key, kind="gate_agent")
        db.add(row)
        db.flush()
    row.last_heartbeat_at = datetime.now(timezone.utc)
    row.agent_version = body.agent_version
    row.detail = detail
    # a live heartbeat closes any open gate_agent_stale escalation chain
    from app.services.escalations import resolve_events
    resolve_events(db, "station_status", row.id)
    db.commit()
    db.refresh(row)
    return row


@system_router.get("/station-status", response_model=list[StationStatusRead])
def station_status(db: Session = Depends(get_db),
                   _: CurrentUser = Depends(guard)) -> list[StationStatusRead]:
    """Gate screen polls this; stale > 5 min → 'scanner offline' banner (§11.4)."""
    now = datetime.now(timezone.utc)
    out = []
    for row in db.query(StationStatus).order_by(StationStatus.device_key).all():
        item = StationStatusRead.model_validate(row)
        if row.last_heartbeat_at is not None:
            hb = row.last_heartbeat_at
            if hb.tzinfo is None:  # SQLite returns naive UTC
                hb = hb.replace(tzinfo=timezone.utc)
            item.stale_seconds = max(0, int((now - hb).total_seconds()))
        out.append(item)
    return out
