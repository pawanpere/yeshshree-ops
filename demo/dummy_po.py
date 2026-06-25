"""DUMMY open-PO data for the demo — fully fictitious vendors / POs / materials.
Stands in for the SAP open-PO feed. The PO is the SOURCE OF TRUTH for the material:
once the PO matches, material/grade/dimensions are PINNED from here. `lookalikes`
are near-twin materials the PO rules out. Each PO also carries an `invoice` block
used to generate its matching printable dummy invoice (make_invoice.py)."""

DUMMY_POS = {
    "4500100231": {
        "po_no": "4500100231", "line": "10",
        "vendor_name": "Sentry Steel & Metals Pvt. Ltd.", "vendor_gstin": "27AABCS1234K1Z9",
        "vendor_addr": "Plot D-22, MIDC Industrial Area, Waluj, Chh. Sambhajinagar 431136",
        "material_code": "1101050167",
        "material_desc": "CRCA SHEET CH52 0.630 X 745 X 1285 MM",
        "grade": "CH52", "thickness_mm": 0.630, "width_mm": 745, "length_mm": 1285,
        "uom": "TO", "open_qty": "5.000", "rate": "68500.00",
        "plant": "1117", "storage_loc": "RM01",
        "lookalikes": [
            "1101030236  CRCA SHEET D 0.77 X 745 X 1285  (thinner / grade D)",
            "1101050058  CRCA SHEET BHS180 0.80 X 745 X 1285  (thicker / BHS grade)",
        ],
        "invoice": {"no": "STM/26-27/0418", "date": "18/06/2026", "vehicle": "MH20FG4521",
                    "eway": "381204559871", "qty": "4.620", "hsn": "72092720",
                    "batch": "HT-26A0418", "transporter": "Sai Roadlines"},
    },
    "4500100232": {
        "po_no": "4500100232", "line": "10",
        "vendor_name": "Apex Metalloys LLP", "vendor_gstin": "27AAFCA5678M1Z3",
        "vendor_addr": "Gat No. 142, Ranjangaon MIDC, Pune 412220",
        "material_code": "1101140020",
        "material_desc": "CR HSLA SHEET 2.00 X 250 X 2500 MM",
        "grade": "HSLA", "thickness_mm": 2.00, "width_mm": 250, "length_mm": 2500,
        "uom": "MT", "open_qty": "3.500", "rate": "67000.00",
        "plant": "1117", "storage_loc": "RM01",
        "lookalikes": [
            "1101140021  CR HSLA 2.00 X 250 X 2440  (shorter length)",
            "1101040097  CRCA EDD 1.00 X 470 X 680  (different grade/size)",
        ],
        "invoice": {"no": "AML-2627-1156", "date": "17/06/2026", "vehicle": "MH12LK8830",
                    "eway": "381204560042", "qty": "3.180", "hsn": "72112340",
                    "batch": "AML-Q26-1156", "transporter": "Bharat Logistics"},
    },
    "4500100233": {
        "po_no": "4500100233", "line": "20",
        "vendor_name": "Shree Balaji Steel Centre", "vendor_gstin": "27AAKFS9012P1Z7",
        "vendor_addr": "B-9, Chakan MIDC Phase II, Pune 410501",
        "material_code": "1101040097",
        "material_desc": "CRCA SHEET EDD 1.00 X 470 X 680 MM",
        "grade": "EDD", "thickness_mm": 1.00, "width_mm": 470, "length_mm": 680,
        "uom": "TO", "open_qty": "2.800", "rate": "66200.00",
        "plant": "1117", "storage_loc": "RM01",
        "lookalikes": [
            "1101030569  CRCA SHEET D TG04 1.00 X 470 X 680  (grade D TG04, same size)",
            "1101200002  CRCA GAIF 1.0 X 470 X 680  (coated, same size)",
        ],
        "invoice": {"no": "SBSC/0926", "date": "16/06/2026", "vehicle": "MH14DE2207",
                    "eway": "381204558310", "qty": "2.640", "hsn": "72091790",
                    "batch": "SB-2609", "transporter": "Maxx Carriers"},
    },
}


def _close(a: str, b: str) -> bool:
    """True if a and b differ by at most one char (length-equal) — tolerates a
    single OCR digit slip so a near-miss still resolves."""
    if a == b:
        return True
    if len(a) != len(b):
        return False
    return sum(x != y for x, y in zip(a, b)) <= 1


def match(po_candidates: list[str], raw_text: str | None = None) -> dict | None:
    """Best dummy-PO match. 1) explicit OCR'd PO candidates (exact, then 1-char off).
    2) fallback: scan the whole OCR text for any digit run that matches a known PO —
    so the demo resolves even if the 'PO No' label wasn't parsed."""
    cands = list(po_candidates or [])
    for c in cands:                                   # exact
        if c in DUMMY_POS:
            return DUMMY_POS[c]
    if raw_text:                                      # any known PO anywhere in the text
        import re
        runs = re.findall(r"\d{8,12}", raw_text.replace(" ", ""))
        for r in runs:
            if r in DUMMY_POS:
                return DUMMY_POS[r]
        cands += runs
    for c in cands:                                   # fuzzy (1-char off)
        for po_no, rec in DUMMY_POS.items():
            if _close(c, po_no):
                return rec
    return None


# backwards-compatible alias
def match_po(po_candidates: list[str]) -> dict | None:
    return match(po_candidates)
