# Gate Receiving — LIVE DEMO

Scan an invoice → OCR reads the PO → matches a (dummy) open-PO → material is pinned →
quality guy enters qty + QC → **GRN Excel** is generated. That's the whole demo.

> **DEMO data.** The open-PO list is dummy (`dummy_po.py`) — it stands in for the real
> SAP open-PO feed (SFTP), which is a pending dependency. Say this plainly to the audience.

## 1. One-time setup

```
python3 -m pip install fastapi uvicorn openpyxl pillow pypdfium2 certifi
export GVISION_KEY="<your Google Cloud Vision API key>"
```

> 🔑 Rotate the Vision key that was shared in chat and restrict it to the Vision API.

## 2. Run

```
cd demo
export GVISION_KEY="..."
python3 -m uvicorn server:app --port 8000
```
Open **http://localhost:8000** on the demo screen (full-screen the browser).

## 3. Wire the scanner (the "live" bit)

Set the printer/scanner to **Scan-to-Folder** and point it at this folder:
```
demo/scans/
```
When the watchman scans, the file lands there, the app auto-ingests it, OCRs it, matches
the PO, and the receiving screen pops up on its own.

**No scan-to-folder?** Use the **Upload manually** button on the home screen, or drop any
PDF/JPG into `demo/scans/` by hand — same result.

## 4. What to show (the script)

1. Home screen: *"Waiting for a scan…"*
2. Watchman scans the invoice on the printer → screen flips to the receiving entry.
3. Point out: **PO auto-matched**, and the **material is pinned by the PO** — including the
   two look-alike materials it *ruled out* (the 0.02 mm / grade-code traps).
4. Quality guy types **received qty**, **batch/heat**, sets **Quality = OK / Pass**.
5. Click **Confirm & Generate GRN** → **Download GRN Excel** (movement type 101, SAP-ready).

## 5. Dummy printable invoices (print these, then scan)

Fully fictitious GST invoices in `demo/dummy_invoices/` — open each PDF, print, then scan.
Regenerate any time with `python3 make_invoice.py`.

| File | Vendor (dummy) | PO it matches | Material pinned |
|---|---|---|---|
| `dummy_invoices/4500100231.pdf` | Sentry Steel & Metals Pvt. Ltd. | `4500100231` | CRCA SHEET CH52 0.630×745×1285 |
| `dummy_invoices/4500100232.pdf` | Apex Metalloys LLP | `4500100232` | CR HSLA 2.00×250×2500 |
| `dummy_invoices/4500100233.pdf` | Shree Balaji Steel Centre | `4500100233` | CRCA EDD 1.00×470×680 |

All vendors / GSTINs / POs / materials are dummy data living in `dummy_po.py` (the
stand-in for the SAP open-PO feed). **Recommended hero: `4500100231.pdf`.**

## 6. ⚠ DRY RUN before the audience (do this first!)

Print → scan is lossy; verify OCR survives it:
1. Print `dummy_invoices/4500100231.pdf`, scan it on the real printer into `demo/scans/`.
2. Confirm the screen shows **PO matched · 4500100231**.
3. If OCR misreads the PO, the screen offers a **manual PO picker** — the demo never stalls.

## Files
- `server.py` — the web app (folder-watch + screens + GRN)
- `ocr.py` — render + Google Vision OCR + field extraction
- `dummy_po.py` — the stand-in open-PO data (edit to add POs/materials)
- `grn.py` — GRN Excel generator (SAP-ready columns)
- `scans/` — scanner drop folder · `grn_out/` — generated GRN sheets
