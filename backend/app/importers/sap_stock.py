"""Parser for the SAP stock snapshot used by the §11.1 reconcile (P23).

FORMAT IS PROVISIONAL until the real SAP spec lands: we accept either the usual SAP
'unconverted list' encoding (UTF-16, tab-separated — same as sap_files.py) or a plain
UTF-8 CSV/TSV. Header-driven like sap_files.py: we locate the line carrying
'Material' + 'Qty' and map names → indexes, so column reordering can't silently
corrupt data. Optional 'Location'/'SLoc' column; absent → reconcile defaults to RM.
Pure function — no DB access here (services/inventory.py owns writes).
"""
from decimal import Decimal, InvalidOperation


def _decode(content: bytes) -> str:
    if content.startswith(b"\xff\xfe") or content.startswith(b"\xfe\xff"):
        return content.decode("utf-16")
    try:
        return content.decode("utf-8-sig")
    except UnicodeDecodeError:
        return content.decode("utf-16")


def _num(raw: str) -> Decimal | None:
    raw = raw.strip().replace(",", "")
    if not raw:
        return None
    try:
        return Decimal(raw)
    except InvalidOperation:
        return None


def parse_stock_snapshot(content: bytes) -> list[dict]:
    """→ [{sap_code, qty, uom, location?}] — qty is the SAP on-hand snapshot."""
    lines = _decode(content).splitlines()
    header_idx, cols, sep = None, {}, "\t"
    for i, line in enumerate(lines):
        if "Material" in line and "Qty" in line:
            sep = "\t" if "\t" in line else ","
            cols = {name.strip(): idx for idx, name in enumerate(line.split(sep))
                    if name.strip()}
            header_idx = i
            break
    if header_idx is None:
        raise ValueError("Header with ['Material', 'Qty'] not found — "
                         "stock snapshot format changed?")

    def cell(fields: list[str], name: str) -> str:
        idx = cols.get(name)
        if idx is None or idx >= len(fields):
            return ""
        return fields[idx].strip()

    out = []
    for line in lines[header_idx + 1:]:
        if not line.strip():
            continue
        f = line.split(sep)
        code = cell(f, "Material")
        qty = _num(cell(f, "Qty"))
        if not code or qty is None:
            continue  # separators / totals / footer noise
        row = {"sap_code": code, "qty": qty, "uom": cell(f, "UoM") or None}
        loc = cell(f, "Location") or cell(f, "SLoc")
        if loc:
            row["location"] = loc
        out.append(row)
    return out
