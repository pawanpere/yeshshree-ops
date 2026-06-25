# Live OCR → ui2 frontend (demo)

Connects this folder's Google-Vision OCR to the **ui2** gate flow in
`yeshshree-ops-2`, so the polished app drives a real "scan → read PO → pin
material → QC → GRN" demo. The original standalone HTML demo (`server.py`) is
untouched; this adds a JSON+CORS service (`api.py`) the Flutter app calls.

```
 scanned invoice ─▶ demo/api.py (Google Vision OCR + dummy-PO match + GRN xlsx)
                         ▲  JSON, CORS, :8900
                         │
        yeshshree-ops-2 ui2 app  ── gate role ─▶ "Scan invoice — live OCR"
        (Flutter web, UI2_MODE)
```

## 1. Start the OCR service (this folder)

```
cd demo
export GVISION_KEY="<your Google Cloud Vision API key>"   # real OCR; omit for sample-only
python3 -m uvicorn api:app --port 8900
# (no local Python deps? one-shot via uv:)
# uv run --with fastapi --with uvicorn --with openpyxl --with pillow \
#        --with pypdfium2 --with certifi uvicorn api:app --port 8900
```

- **With `GVISION_KEY`** → real Vision OCR on whatever is scanned/uploaded.
- **Without it** → the service still runs; the three bundled sample invoices
  (named by PO) match by file name so the whole UI flow is demoable. The app
  shows a `SAMPLE ONLY` badge in this mode.

## 2. Start the ui2 app (../../yeshshree-ops-2/app)

```
cd ../../yeshshree-ops-2/app
flutter run -d chrome --no-web-resources-cdn --dart-define=UI2_MODE=true
# OCR service on a different host/port? add:
#   --dart-define=OCR_URL=http://127.0.0.1:8900
```

Open the gate role (login, or the dev deep-link `?role=gate`) → tap
**“Scan invoice — live OCR”**.

## 3. Demo flow

1. The screen waits for a scan. Either scan an invoice into `demo/scans/`
   (ScanJet scan-to-folder) **or** tap one of the **sample invoice** buttons.
2. OCR reads the PO → it auto-matches a dummy open PO → **material is pinned**
   (with the look-alikes it ruled out) next to the scanned page.
3. Enter received / accepted / rejected qty, batch/heat, QC pass-fail.
4. **Confirm & Generate GRN** → **Download GRN Excel** (movement type 101).

If OCR can't read the PO, the screen offers a manual PO picker — it never stalls.

## Endpoints (`api.py`)

| Method | Path | Purpose |
|---|---|---|
| GET  | `/ocr/health` | `{ok, has_key, pos}` |
| GET  | `/ocr/pos` | dummy open-PO list (manual pick) |
| GET  | `/ocr/latest?after=<id>` | newest decoded scan (folder-watch poll) |
| POST | `/ocr/ingest-sample` `{po_no}` | OCR a bundled sample invoice |
| POST | `/ocr/grn` `{po_no, qtys, qc…}` | generate the GRN Excel |
| GET  | `/ocr/grn/{grn_no}.xlsx` | download it |

> DEMO data: the open-PO list is `dummy_po.py` (stand-in for the SAP open-PO
> feed). Say so to the audience.
