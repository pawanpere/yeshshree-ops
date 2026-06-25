"""Live demo server — run: GVISION_KEY=... python -m uvicorn server:app --port 8000
Flow:  scanner drops PDF in scans/  (or you upload)  ->  OCR  ->  match PO  ->
quality screen (qty + QC)  ->  GRN .xlsx in grn_out/.   DEMO data only."""
import io
import os
import time
import threading
import traceback
from datetime import date

from fastapi import FastAPI, UploadFile, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse, Response, FileResponse

import ocr
import dummy_po
import grn

SCANS = os.environ.get("SCANS_DIR") or os.path.join(os.path.dirname(__file__), "scans")
GRN_OUT = os.path.join(os.path.dirname(__file__), "grn_out")
os.makedirs(SCANS, exist_ok=True)
os.makedirs(GRN_OUT, exist_ok=True)

app = FastAPI()
ENTRIES: list[dict] = []          # in-memory; newest last
_processed: set[str] = set()
_attempts: dict[str, int] = {}
_lock = threading.Lock()
_MAGICS = (b"%PDF-", b"\xff\xd8\xff", b"\x89PNG\r\n")   # PDF / JPEG / PNG headers


def _process(name: str, content: bytes) -> dict:
    """bytes -> entry dict (OCR + PO match). Never raises out — errors become an entry."""
    entry = {"id": len(ENTRIES) + 1, "name": name, "opened": False,
             "po": None, "fields": {}, "error": None, "grn_path": None, "grn_no": None}
    try:
        jpeg = ocr.render_to_jpeg_bytes(content)
        entry["jpeg"] = jpeg
        text = ocr.vision_ocr(jpeg)
        entry["fields"] = ocr.extract_fields(text)
        entry["po"] = dummy_po.match(entry["fields"]["po_candidates"], text)
    except Exception as exc:
        entry["error"] = str(exc)
        entry["jpeg"] = entry.get("jpeg", b"")
        traceback.print_exc()
    with _lock:
        ENTRIES.append(entry)
    return entry


def _watch():
    """Poll scans/ for new, fully-written files and ingest them."""
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
                if sz == 0 or sizes.get(fn) != sz:   # empty or still growing — wait
                    sizes[fn] = sz
                    continue
                with open(path, "rb") as f:
                    content = f.read()
                if not content.startswith(_MAGICS):  # not a complete PDF/image yet
                    n = _attempts.get(fn, 0) + 1
                    _attempts[fn] = n
                    if n < 6:                        # give the scanner time to finish
                        continue
                _processed.add(fn)                   # commit once: complete, or gave up
                _process(fn, content)
        except Exception:
            traceback.print_exc()
        time.sleep(1.5)


@app.on_event("startup")
def _start():
    threading.Thread(target=_watch, daemon=True).start()


# ---------- rendering helpers ----------
def _page(body: str, refresh: bool = False) -> str:
    head = '<meta http-equiv="refresh" content="2">' if refresh else ""
    return f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">{head}
<title>Yeshshree · Gate Receiving (DEMO)</title>
<style>
*{{box-sizing:border-box}} body{{margin:0;font-family:-apple-system,Segoe UI,Roboto,sans-serif;
background:#0f1720;color:#e6edf3}}
.bar{{background:#1F4E78;padding:14px 22px;display:flex;align-items:center;gap:14px}}
.bar h1{{font-size:18px;margin:0;font-weight:700}}
.demo{{background:#B00000;color:#fff;font-size:11px;font-weight:700;padding:3px 9px;border-radius:4px}}
.wrap{{max-width:1100px;margin:26px auto;padding:0 18px}}
.card{{background:#16212e;border:1px solid #243446;border-radius:12px;padding:22px;margin-bottom:18px}}
.muted{{color:#8aa0b4}} .big{{font-size:26px;font-weight:700}}
.grid{{display:grid;grid-template-columns:1fr 1fr;gap:22px}}
img.scan{{width:100%;border-radius:8px;border:1px solid #243446;background:#fff}}
table{{width:100%;border-collapse:collapse;font-size:14px}} td,th{{padding:7px 9px;text-align:left}}
th{{color:#8aa0b4;font-weight:600;width:42%}}
.pill{{display:inline-block;background:#0d3d2b;color:#43d39e;padding:3px 10px;border-radius:20px;font-size:12px;font-weight:700}}
.pill.warn{{background:#3d2f0d;color:#e6b800}}
input,select{{width:100%;padding:10px;border-radius:7px;border:1px solid #2b3f54;background:#0f1720;color:#e6edf3;font-size:15px}}
label{{display:block;margin:12px 0 5px;font-size:13px;color:#8aa0b4}}
.btn{{display:inline-block;background:#2563eb;color:#fff;border:0;padding:13px 22px;border-radius:8px;
font-size:16px;font-weight:700;cursor:pointer;text-decoration:none}}
.btn.green{{background:#16a34a}} .lk{{color:#7ab7ff}}
.ruled{{color:#8aa0b4;font-size:13px;border-left:3px solid #B00000;padding-left:10px;margin:5px 0}}
@media (max-width:760px){{.grid{{grid-template-columns:1fr}} .bar h1{{font-size:15px}}
.wrap{{margin:14px auto}} .big{{font-size:22px}} .bar .muted{{display:none}}}}
</style></head><body>
<div class="bar"><h1>Yeshshree Press Comps · Gate Receiving</h1><span class="demo">DEMO</span>
<span class="muted" style="margin-left:auto;font-size:13px">Plant 1117 · live OCR + PO match</span></div>
<div class="wrap">{body}</div></body></html>"""


def _esc(v) -> str:
    return "" if v is None else str(v)


# ---------- routes ----------
@app.get("/", response_class=HTMLResponse)
def home():
    with _lock:
        latest = ENTRIES[-1] if ENTRIES else None
    if latest and not latest["opened"]:
        # auto-jump to the freshly scanned entry
        return _page(f'<div class="card"><div class="big">✓ New scan received</div>'
                     f'<p class="muted">Opening receiving screen…</p>'
                     f'<a class="btn" href="/entry/{latest["id"]}">Open ▶</a></div>'
                     f'<script>setTimeout(function(){{location.href="/entry/{latest["id"]}"}},700)</script>')
    body = ['<div class="card" style="text-align:center;padding:48px">'
            '<div class="big">📠 Waiting for a scan…</div>'
            '<p class="muted">Scan an invoice on the printer — it drops into the watch folder and appears here.</p>'
            '<form action="/upload" method="post" enctype="multipart/form-data" style="margin-top:18px">'
            '<input type="file" name="file" accept="application/pdf,image/*" style="max-width:340px;display:inline-block">'
            '<button class="btn" type="submit" style="margin-left:8px">Upload manually</button></form></div>']
    if ENTRIES:
        rows = "".join(
            f'<tr><td>#{e["id"]}</td><td>{_esc(e["name"])}</td>'
            f'<td>{"<span class=pill>matched "+e["po"]["po_no"]+"</span>" if e["po"] else "<span class=pill warn>no match</span>"}</td>'
            f'<td><a class="lk" href="/entry/{e["id"]}">open</a></td></tr>'
            for e in reversed(ENTRIES))
        body.append(f'<div class="card"><b>Scans</b><table>{rows}</table></div>')
    return _page("".join(body), refresh=True)


@app.post("/upload")
async def upload(file: UploadFile):
    e = _process(file.filename or "upload.pdf", await file.read())
    return RedirectResponse(f"/entry/{e['id']}", status_code=303)


@app.get("/entry/{eid}/image")
def image(eid: int):
    e = next((x for x in ENTRIES if x["id"] == eid), None)
    return Response(e["jpeg"], media_type="image/jpeg") if e and e.get("jpeg") else Response(status_code=404)


@app.get("/entry/{eid}", response_class=HTMLResponse)
def entry(eid: int):
    e = next((x for x in ENTRIES if x["id"] == eid), None)
    if not e:
        return _page('<div class="card">Not found. <a class="lk" href="/">back</a></div>')
    e["opened"] = True
    if e["grn_no"]:
        return RedirectResponse(f"/entry/{eid}/done", status_code=303)
    f = e["fields"]
    left = f'<img class="scan" src="/entry/{eid}/image">'
    if e["error"]:
        right = (f'<div class="card"><div class="big">⚠ OCR error</div>'
                 f'<p class="ruled">{_esc(e["error"])}</p>'
                 f'<a class="lk" href="/">back</a></div>')
        return _page(f'<div class="grid"><div>{left}</div><div>{right}</div></div>')
    po = e["po"]
    if not po:
        opts = "".join(f'<option value="{k}">{k} — {v["vendor_name"]} — {v["material_desc"]}</option>'
                       for k, v in dummy_po.DUMMY_POS.items())
        right = (f'<div class="big">No PO auto-matched</div>'
                 f'<p class="muted">OCR read PO candidates {f.get("po_candidates") or "—"}, '
                 f'GSTIN {_esc(f.get("vendor_gstin"))}. Pick the PO manually:</p>'
                 f'<form action="/entry/{eid}/setpo" method="post"><select name="po_no">{opts}</select>'
                 f'<div style="margin-top:14px"><button class="btn" type="submit">Use this PO ▶</button></div></form>')
        return _page(f'<div class="grid"><div>{left}</div><div class="card">{right}</div></div>')
    lookalikes = "".join(f'<div class="ruled">ruled out · {_esc(x)}</div>' for x in po["lookalikes"])
    right = f"""<div class="card">
      <span class="pill">PO matched · {po['po_no']} / line {po['line']}</span>
      <table>
        <tr><th>Vendor</th><td>{po['vendor_name']}</td></tr>
        <tr><th>OCR'd from invoice</th><td>GSTIN {_esc(f.get('vendor_gstin'))} · Inv {_esc(f.get('invoice_no'))}</td></tr>
        <tr><th>Material (pinned by PO)</th><td><b>{po['material_code']}</b><br>{po['material_desc']}</td></tr>
        <tr><th>Grade / size</th><td>{po['grade']} · {po['thickness_mm']} × {po['width_mm']} × {po['length_mm']} mm</td></tr>
      </table>{lookalikes}
    </div>
    <form class="card" action="/entry/{eid}/confirm" method="post">
      <b>Quality &amp; Quantity check</b>
      <label>Received quantity ({po['uom']})</label>
      <input name="received_qty" value="{po['open_qty']}">
      <label>Accepted quantity ({po['uom']})</label>
      <input name="accepted_qty" value="{po['open_qty']}">
      <label>Rejected quantity ({po['uom']})</label>
      <input name="rejected_qty" value="0.000">
      <label>Batch / Heat no.</label>
      <input name="batch_no" placeholder="e.g. CP22526R27">
      <label>Quality result</label>
      <select name="qc_result"><option value="pass">OK — Pass</option><option value="fail">Reject — Fail</option></select>
      <label>Remarks</label><input name="remarks" placeholder="optional">
      <div style="margin-top:18px"><button class="btn green" type="submit">✓ Confirm &amp; Generate GRN</button></div>
    </form>"""
    return _page(f'<div class="grid"><div>{left}</div><div>{right}</div></div>')


@app.post("/entry/{eid}/setpo")
def setpo(eid: int, po_no: str = Form(...)):
    e = next((x for x in ENTRIES if x["id"] == eid), None)
    if e and po_no in dummy_po.DUMMY_POS:
        e["po"] = dummy_po.DUMMY_POS[po_no]
    return RedirectResponse(f"/entry/{eid}", status_code=303)


@app.post("/entry/{eid}/confirm")
def confirm(eid: int, received_qty: str = Form(...), accepted_qty: str = Form(...),
            rejected_qty: str = Form("0.000"), batch_no: str = Form(""),
            qc_result: str = Form("pass"), remarks: str = Form("")):
    e = next((x for x in ENTRIES if x["id"] == eid), None)
    if not e or not e["po"]:
        return RedirectResponse("/", status_code=303)
    grn_no = f"GR-2026-{eid:04d}"
    path = os.path.join(GRN_OUT, f"{grn_no}.xlsx")
    grn.generate_grn(path, grn_no=grn_no, posting_date=date.today().isoformat(), po=e["po"],
                     received_qty=received_qty, accepted_qty=accepted_qty, rejected_qty=rejected_qty,
                     qc_result=qc_result, batch_no=batch_no, invoice_no=e["fields"].get("invoice_no"),
                     remarks=remarks)
    e["grn_no"], e["grn_path"] = grn_no, path
    e["grn_view"] = dict(received_qty=received_qty, accepted_qty=accepted_qty,
                         rejected_qty=rejected_qty, batch_no=batch_no, qc_result=qc_result)
    return RedirectResponse(f"/entry/{eid}/done", status_code=303)


@app.get("/entry/{eid}/done", response_class=HTMLResponse)
def done(eid: int):
    e = next((x for x in ENTRIES if x["id"] == eid), None)
    if not e or not e["grn_no"]:
        return RedirectResponse("/", status_code=303)
    po, v = e["po"], e["grn_view"]
    rows = "".join(f'<tr><th>{k}</th><td>{_esc(val)}</td></tr>' for k, val in [
        ("GRN No.", e["grn_no"]), ("PO / line", f'{po["po_no"]} / {po["line"]}'),
        ("Movement type", "101 (GR)"), ("Material", f'{po["material_code"]} — {po["material_desc"]}'),
        ("Plant / Sloc", f'{po["plant"]} / {po["storage_loc"]}'), ("UOM", po["uom"]),
        ("Received", v["received_qty"]), ("Accepted", v["accepted_qty"]), ("Rejected", v["rejected_qty"]),
        ("Batch / Heat", v["batch_no"] or "-"), ("QC", v["qc_result"].upper())])
    body = f"""<div class="card"><div class="big">✓ GRN generated — {e['grn_no']}</div>
      <p class="muted">SAP-ready goods-receipt sheet (movement type 101).</p>
      <table>{rows}</table>
      <div style="margin-top:18px">
        <a class="btn green" href="/entry/{eid}/grn.xlsx">⬇ Download GRN Excel</a>
        <a class="btn" style="background:#374151" href="/">Next scan</a></div></div>"""
    return _page(body)


@app.get("/entry/{eid}/grn.xlsx")
def download(eid: int):
    e = next((x for x in ENTRIES if x["id"] == eid), None)
    if not e or not e.get("grn_path"):
        return Response(status_code=404)
    return FileResponse(e["grn_path"], filename=os.path.basename(e["grn_path"]),
                        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
