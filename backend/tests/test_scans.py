"""P17/P19 acceptance: golden decode of the 3 REAL scanned invoices in data/
(TATA = QR+PDF417, JSW = QR+Code128, POSHS = no barcodes), the scan ingest
endpoint (dedupe-first), phone decode-qr, and the heartbeat upsert (§11.4)."""
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.models.gate import File as FileRow, GateScan
from app.models.identity import User
from app.models.master import Material, PurchaseOrder, Vendor
from app.models.system import StationStatus
from app.services import scan_decode
import app.core.db as db_mod

DATA = Path(__file__).resolve().parents[2] / "data"
TATA_PDF = DATA / "doc00857220260527165933.pdf"
JSW_PDF = DATA / "doc00857520260527170203.pdf"
POSHS_PDF = DATA / "doc00857920260527170430.pdf"

pytestmark = pytest.mark.skipif(
    not TATA_PDF.exists(),
    reason="golden scan files not present (see data/README.md)",
)


# --- pure decode (services/scan_decode.py, no DB) ---

def test_tata_decode_golden():
    res = scan_decode.decode_document(TATA_PDF.read_bytes(), "application/pdf")
    assert res.decode_status == "decoded"
    assert res.pdf417_payload and "PO:520000845" in res.pdf417_payload
    s = res.suggestions
    assert s["po_no"] == "520000845"
    assert s["vehicle_no"] == "MH12MV9997"
    assert s["invoice_no"] == "3131079408"
    assert s["vendor_gstin"] == "27AAACT2803M1ZB"
    assert s["invoice_value"] == 369366.15
    assert s["invoice_date"] == "2026-05-24"
    assert s["weight"] == 28172.00
    assert s.get("irn") and len(s["irn"]) == 64
    assert s["hsn"] == "72092720"


def test_jsw_decode_golden():
    res = scan_decode.decode_document(JSW_PDF.read_bytes(), "application/pdf")
    assert res.decode_status == "decoded"
    assert res.qr_payload["DocNo"] == "26S32700002680"
    assert res.qr_payload["SellerGstin"] == "27AAACJ4323N1ZG"
    assert res.suggestions["invoice_no"] == "26S32700002680"
    assert res.suggestions["invoice_value"] == 791212.14
    # the Code128 (delivery number) is kept raw, not invented into suggestions
    assert {"format": "Code128", "text": "8150428185"} in res.raw_barcodes


def test_poshs_no_barcodes_graceful():
    res = scan_decode.decode_document(POSHS_PDF.read_bytes(), "application/pdf")
    assert res.decode_status == "none"
    assert res.qr_payload is None and res.pdf417_payload is None
    assert res.suggestions == {}


# --- API (client fixture pattern from test_master_config.py) ---

@pytest.fixture()
def client(engine, db, tmp_path, monkeypatch):
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    from app.services import files
    monkeypatch.setattr(files, "_LOCAL_DIR", tmp_path / "filestore")
    db.add_all([
        User(username="admin", password_hash=hash_password("a"), full_name="A",
             role="admin", language="en"),
        User(username="gate1", password_hash=hash_password("g"), full_name="G",
             role="plant_ops", station="gate", language="mr"),
        User(username="v1", password_hash=hash_password("v"), full_name="V",
             role="vendor", language="en"),
    ])
    vendor = Vendor(sap_code="10307", name="TATA STEEL LIMITED",
                    gstin="27AAACT2803M1ZB")
    mat = Material(sap_code="1101030569", description="CRCA SHEET D TG04",
                   mat_type="ROH", mat_group="1103", uom="KG")
    db.add_all([vendor, mat])
    db.flush()
    db.add(PurchaseOrder(sap_po_no="520000845", item_no=1, vendor_id=vendor.id,
                         material_id=mat.id, ordered_qty=50000, open_qty=30000,
                         rate=51, uom="KG", status="open"))
    db.commit()
    from app.main import app
    # P17 scope creates the routers but does NOT touch main.py — register here.
    from app.api.scans import scans_router, system_router
    paths = {getattr(r, "path", None) for r in app.routes}
    if "/api/v1/gate-entries/scans" not in paths:
        app.include_router(scans_router)
        app.include_router(system_router)
    yield TestClient(app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def _token(client, username, password):
    r = client.post("/api/v1/auth/login", json={"username": username, "password": password})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _upload(client, headers, path: Path):
    with path.open("rb") as fh:
        return client.post("/api/v1/gate-entries/scans", headers=headers,
                           files={"file": (path.name, fh, "application/pdf")})


def test_upload_tata_scan_resolves_vendor_and_po(client, db):
    gate = _token(client, "gate1", "g")
    r = _upload(client, gate, TATA_PDF)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["duplicate"] is False
    assert body["scan"]["decode_status"] == "decoded"
    assert body["scan"]["status"] == "pending"
    assert body["scan"]["hsn_check"] == "n/a"  # mat_group is not an HSN (see api/scans.py)
    assert body["suggestions"]["po_no"] == "520000845"
    assert body["suggested_vendor_id"] == db.query(Vendor).filter_by(
        gstin="27AAACT2803M1ZB").one().id
    assert body["suggested_po_id"] == db.query(PurchaseOrder).filter_by(
        sap_po_no="520000845").one().id
    # appears in the pending list with suggestions
    pending = client.get("/api/v1/gate-entries/scans/pending", headers=gate).json()
    assert [p["scan"]["id"] for p in pending] == [body["scan"]["id"]]
    assert pending[0]["suggestions"]["vehicle_no"] == "MH12MV9997"
    # vendor role must not reach the scan pipeline
    vendor = _token(client, "v1", "v")
    assert client.get("/api/v1/gate-entries/scans/pending", headers=vendor).status_code == 403


def test_duplicate_upload_returns_existing_scan(client, db):
    gate = _token(client, "gate1", "g")
    first = _upload(client, gate, TATA_PDF).json()
    files_before = db.query(FileRow).filter_by(kind="scan").count()
    scans_before = db.query(GateScan).count()
    second = _upload(client, gate, TATA_PDF).json()
    assert second["duplicate"] is True
    assert second["scan"]["id"] == first["scan"]["id"]
    assert db.query(FileRow).filter_by(kind="scan").count() == files_before
    assert db.query(GateScan).count() == scans_before


def test_discard_scan(client):
    gate = _token(client, "gate1", "g")
    scan_id = _upload(client, gate, POSHS_PDF).json()["scan"]["id"]
    r = client.post(f"/api/v1/gate-entries/scans/{scan_id}/discard", headers=gate)
    assert r.status_code == 200 and r.json()["status"] == "discarded"
    assert client.get("/api/v1/gate-entries/scans/pending", headers=gate).json() == []


def test_decode_qr_phone_fallback(client):
    """Phone camera sends the RAW JWS text — extract it from the real TATA pdf."""
    res = scan_decode.decode_document(TATA_PDF.read_bytes(), "application/pdf")
    jws = next(b["text"] for b in res.raw_barcodes if b["format"] == "QRCode")
    gate = _token(client, "gate1", "g")
    r = client.post("/api/v1/gate-entries/decode-qr", headers=gate,
                    json={"payload": jws})
    assert r.status_code == 200
    body = r.json()
    assert body["decode_status"] == "decoded"
    assert body["suggestions"]["vendor_gstin"] == "27AAACT2803M1ZB"
    assert body["suggestions"]["invoice_no"] == "3131079408"
    assert body["suggestions"]["invoice_value"] == 369366.15
    # garbage payload → none, not 500
    bad = client.post("/api/v1/gate-entries/decode-qr", headers=gate,
                      json={"payload": "not-a-jws"})
    assert bad.json() == {"decode_status": "none", "suggestions": {}}


def test_heartbeat_upserts_single_row(client, db):
    gate = _token(client, "gate1", "g")
    body = {"device_key": "gate-scanjet-1", "agent_version": "1.0.0",
            "watch_folder_ok": True}
    assert client.post("/api/v1/system/agent-heartbeat", headers=gate,
                       json=body).status_code == 200
    first = db.query(StationStatus).one()
    t1 = first.last_heartbeat_at
    time.sleep(0.05)
    db.expire_all()
    assert client.post("/api/v1/system/agent-heartbeat", headers=gate,
                       json={**body, "agent_version": "1.0.1",
                             "last_scan_at": "2026-06-11T10:00:00Z"}).status_code == 200
    rows = db.query(StationStatus).all()
    assert len(rows) == 1  # upsert, not insert
    assert rows[0].kind == "gate_agent"
    assert rows[0].agent_version == "1.0.1"
    assert rows[0].last_heartbeat_at > t1
    assert rows[0].detail["watch_folder_ok"] is True
    status = client.get("/api/v1/system/station-status", headers=gate).json()
    assert len(status) == 1
    assert status[0]["device_key"] == "gate-scanjet-1"
    assert 0 <= status[0]["stale_seconds"] < 60
