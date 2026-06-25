"""JSON + CORS OCR service for the ui2 Flutter frontend.

This is a thin JSON API around the SAME building blocks the standalone HTML demo
uses (`ocr.py` Google Vision OCR, `dummy_po.py` open-PO match, `grn.py` GRN Excel).
It exists so the polished ui2 gate flow (yeshshree-ops-2) can drive live OCR while
`server.py` (the self-contained HTML demo) stays exactly as it was.

Run:
    cd demo
    export GVISION_KEY="<your Google Cloud Vision API key>"
    python3 -m uvicorn api:app --port 8900

Endpoints (all JSON, CORS-open for localhost so the Flutter web build can call it):
    GET  /ocr/health                 -> {ok, has_key, pos}
    GET  /ocr/pos                    -> [ {po_no, vendor_name, material_*, uom, open_qty}, ... ]
    GET  /ocr/latest?after=<id>      -> {latest_id, entry|null}   (folder-watch poll)
    POST /ocr/ingest-sample {po_no}  -> {entry}  (OCR a bundled dummy invoice — no scanner needed)
    POST /ocr/grn {po_no, qtys, qc}  -> {grn_no, download_url}
    GET  /ocr/grn/{grn_no}.xlsx      -> the generated GRN sheet

Without GVISION_KEY the folder-watch path reports an error per scan, but
/ocr/ingest-sample still works by falling back to a filename match (the bundled
invoices are named by PO) so the UI flow can be demoed before the key is wired.
"""
import os
import ssl
import time
import threading
import traceback
import urllib.error
from datetime import date

from fastapi import FastAPI, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse

import ocr
import dummy_po
import grn

HERE = os.path.dirname(__file__)
SCANS = os.environ.get("SCANS_DIR") or os.path.join(HERE, "scans")
SAMPLES = os.path.join(HERE, "dummy_invoices")
GRN_OUT = os.path.join(HERE, "grn_out")
os.makedirs(SCANS, exist_ok=True)
os.makedirs(GRN_OUT, exist_ok=True)

app = FastAPI(title="Yeshshree OCR demo API")
# CORS: a demo service, so allow any origin (the Flutter web build runs on an
# arbitrary localhost port). No credentials are used (the OCR service is
# tokenless), so allow_origins=["*"] is safe here.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

ENTRIES: list[dict] = []          # decoded scans, newest last
_processed: set[str] = set()
_attempts: dict[str, int] = {}
_lock = threading.Lock()
_MAGICS = (b"%PDF-", b"\xff\xd8\xff", b"\x89PNG\r\n")   # PDF / JPEG / PNG headers


def _has_key() -> bool:
    return bool(os.environ.get("GVISION_KEY"))


def _vision_with_retry(jpeg: bytes, attempts: int = 3) -> str:
    """Call Google Vision, retrying transient transport errors (e.g. an SSL
    connection reset / EOF) with a fresh connection each time. A scanned page
    must never fail the demo over a one-off network hiccup."""
    last: Exception | None = None
    for i in range(attempts):
        try:
            return ocr.vision_ocr(jpeg, timeout=25)
        except (urllib.error.URLError, ssl.SSLError, OSError) as exc:
            last = exc
            time.sleep(0.8 * (i + 1))
    raise last if last else RuntimeError("Vision OCR failed")


def _process(name: str, content: bytes, hint_po: str | None = None) -> dict:
    """bytes -> decoded entry. Real Google Vision OCR when GVISION_KEY is set;
    otherwise (sample ingest only) fall back to the filename/hint PO so the UI
    can still be demoed. Never raises out — failures become an entry with .error."""
    entry = {
        "id": len(ENTRIES) + 1, "name": name, "opened": False,
        "po": None, "fields": {}, "error": None, "ocr_mode": None,
        "grn_no": None,
    }
    try:
        # Rendering the first page to an image is local (pdfium/pillow) and needs
        # no key — so the scanned page can be shown even in the no-key fallback.
        jpeg = ocr.render_to_jpeg_bytes(content)
        entry["image_b64"] = _b64(jpeg)
        if _has_key():
            text = _vision_with_retry(jpeg)
            f = ocr.extract_fields(text)
            entry["fields"] = {k: f.get(k) for k in ("po_candidates", "vendor_gstin", "invoice_no")}
            entry["po"] = dummy_po.match(f["po_candidates"], text)
            entry["ocr_mode"] = "vision"
        else:
            # No key: can't read the page. For a sample ingest we know which PO the
            # file is (named by PO), so resolve it and flag the skipped OCR plainly.
            entry["fields"] = {"po_candidates": [hint_po] if hint_po else [],
                               "vendor_gstin": None, "invoice_no": None}
            entry["po"] = dummy_po.DUMMY_POS.get(hint_po) if hint_po else None
            entry["ocr_mode"] = "skipped_no_key"
            if entry["po"] is None:
                entry["error"] = "GVISION_KEY not set — export your Google Vision API key"
    except Exception as exc:               # noqa: BLE001 — any failure becomes an entry
        entry["error"] = str(exc)
        entry.setdefault("image_b64", "")
        traceback.print_exc()
    with _lock:
        ENTRIES.append(entry)
    return entry


def _b64(data: bytes) -> str:
    import base64
    return base64.b64encode(data).decode()


def _public(e: dict | None) -> dict | None:
    """Entry shape the frontend reads (no raw bytes)."""
    if e is None:
        return None
    return {
        "id": e["id"],
        "name": e["name"],
        "matched": e["po"] is not None,
        "po": e["po"],                 # full dummy-PO dict: material_code/desc, grade, lookalikes…
        "fields": e["fields"],         # po_candidates, vendor_gstin, invoice_no
        "error": e["error"],
        "ocr_mode": e["ocr_mode"],
        "image_b64": e.get("image_b64", ""),
    }


def _watch() -> None:
    """Poll scans/ for new, fully-written files and OCR them (the live ScanJet
    scan-to-folder path). Identical settle logic to server.py."""
    sizes: dict[str, int] = {}
    while True:
        try:
            for fn in sorted(os.listdir(SCANS)):
                if fn in _processed or fn.startswith("."):
                    continue
                path = os.path.join(SCANS, fn)
                if not os.path.isfile(path):
                    continue
                sz = os.path.getsize(path)
                if sz == 0 or sizes.get(fn) != sz:    # empty or still growing — wait
                    sizes[fn] = sz
                    continue
                with open(path, "rb") as f:
                    content = f.read()
                if not content.startswith(_MAGICS):   # not a complete PDF/image yet
                    n = _attempts.get(fn, 0) + 1
                    _attempts[fn] = n
                    if n < 6:
                        continue
                _processed.add(fn)
                _process(fn, content)
        except Exception:                              # noqa: BLE001
            traceback.print_exc()
        time.sleep(1.5)


@app.on_event("startup")
def _start() -> None:
    threading.Thread(target=_watch, daemon=True).start()


# ----------------------------------------------------------------- routes ---
@app.get("/ocr/health")
def health() -> dict:
    return {"ok": True, "has_key": _has_key(), "pos": len(dummy_po.DUMMY_POS),
            "scans_dir": SCANS}


@app.get("/ocr/pos")
def pos() -> list[dict]:
    return [
        {"po_no": k, "line": v["line"], "vendor_name": v["vendor_name"],
         "material_code": v["material_code"], "material_desc": v["material_desc"],
         "grade": v["grade"], "uom": v["uom"], "open_qty": v["open_qty"]}
        for k, v in dummy_po.DUMMY_POS.items()
    ]


@app.get("/ocr/latest")
def latest(after: int = 0) -> dict:
    """Newest decoded scan with id > `after` (the folder-watch poll). The frontend
    passes the last id it has seen; gets back the next one or null."""
    with _lock:
        newest = ENTRIES[-1] if ENTRIES else None
        latest_id = newest["id"] if newest else 0
        fresh = newest if (newest and newest["id"] > after) else None
    return {"latest_id": latest_id, "entry": _public(fresh)}


@app.post("/ocr/ingest-sample")
def ingest_sample(po_no: str = Body(..., embed=True)) -> dict:
    """OCR one of the bundled dummy invoices (named by PO) — lets the demo run
    with no physical scanner. Real Vision OCR when the key is set."""
    path = os.path.join(SAMPLES, f"{po_no}.pdf")
    if not os.path.isfile(path):
        return JSONResponse({"error": f"no sample invoice for {po_no}"}, status_code=404)
    with open(path, "rb") as f:
        content = f.read()
    e = _process(f"sample-{po_no}.pdf", content, hint_po=po_no)
    return {"entry": _public(e)}


@app.post("/ocr/grn")
def make_grn(body: dict = Body(...)) -> dict:
    """Generate the SAP-ready GRN Excel (movement type 101) for a matched PO."""
    po_no = str(body.get("po_no") or "")
    po = dummy_po.DUMMY_POS.get(po_no)
    if po is None:
        return JSONResponse({"error": f"unknown PO {po_no}"}, status_code=400)
    with _lock:
        grn_no = f"GR-2026-{len(ENTRIES) + 1:04d}"
    path = os.path.join(GRN_OUT, f"{grn_no}.xlsx")
    grn.generate_grn(
        path, grn_no=grn_no, posting_date=date.today().isoformat(), po=po,
        received_qty=str(body.get("received_qty", po["open_qty"])),
        accepted_qty=str(body.get("accepted_qty", po["open_qty"])),
        rejected_qty=str(body.get("rejected_qty", "0.000")),
        qc_result=str(body.get("qc_result", "pass")),
        batch_no=str(body.get("batch_no", "")),
        invoice_no=body.get("invoice_no"),
        remarks=str(body.get("remarks", "")),
    )
    return {"grn_no": grn_no, "download_url": f"/ocr/grn/{grn_no}.xlsx"}


@app.get("/ocr/grn/{grn_no}.xlsx", response_model=None)
def download_grn(grn_no: str):
    path = os.path.join(GRN_OUT, f"{grn_no}.xlsx")
    if not os.path.isfile(path):
        return JSONResponse({"error": "not found"}, status_code=404)
    return FileResponse(
        path, filename=f"{grn_no}.xlsx",
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
