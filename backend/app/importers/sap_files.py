"""Parsers for SAP 'unconverted list' exports (UTF-16 LE, tab-separated, .xls extension).

Header-driven: each parser locates the real header line and maps column names → indexes,
so minor column reordering in future SAP exports doesn't silently corrupt data.
Pure functions — no DB access here (seed.py owns writes). Spec: Plan §1 decision 4;
golden-file tests in tests/test_importers.py run against the real files in data/.
"""
from decimal import Decimal, InvalidOperation
from pathlib import Path


def _read_lines(path: str | Path) -> list[str]:
    return Path(path).read_text(encoding="utf-16").splitlines()


def _find_header(lines: list[str], must_contain: list[str]) -> tuple[int, dict[str, list[int]]]:
    """Return (line_index, name → [indexes]) for the first line containing all markers.
    Duplicate column names (SAP loves them) map to a list of indexes, in order."""
    for i, line in enumerate(lines):
        if all(m in line for m in must_contain):
            cols: dict[str, list[int]] = {}
            for idx, name in enumerate(line.split("\t")):
                name = name.strip()
                if name:
                    cols.setdefault(name, []).append(idx)
            return i, cols
    raise ValueError(f"Header with {must_contain} not found — SAP export format changed?")


def _num(raw: str) -> Decimal | None:
    raw = raw.strip().replace(",", "")
    if not raw:
        return None
    try:
        return Decimal(raw)
    except InvalidOperation:
        return None


def _cell(fields: list[str], cols: dict[str, list[int]], name: str, occurrence: int = 0) -> str:
    idxs = cols.get(name, [])
    if occurrence >= len(idxs) or idxs[occurrence] >= len(fields):
        return ""
    return fields[idxs[occurrence]].strip()


def parse_materials(path: str | Path) -> list[dict]:
    """1117 material code list.xls → material master rows (plant 1117 only)."""
    lines = _read_lines(path)
    h, cols = _find_header(lines, ["Material", "Plnt", "MTyp"])
    out = []
    for line in lines[h + 1 :]:
        if not line.startswith("\t"):
            continue
        f = line.split("\t")
        code = _cell(f, cols, "Material")
        if not code.isdigit():
            continue
        out.append({
            "sap_code": code,
            "description": _cell(f, cols, "Material Description"),
            "mat_type": _cell(f, cols, "MTyp"),
            "mat_group": _cell(f, cols, "Matl Group"),
            "uom": _cell(f, cols, "BUn"),
            "price": _num(_cell(f, cols, "Price")),
            "abc": _cell(f, cols, "ABC") or None,
        })
    return out


def parse_bom(path: str | Path) -> list[dict]:
    """1117 bill of material.xls → one row per BOM component line.
    'BOM' column is the Bajaj part no (e.g. 00005901); 'Material' is the parent SAP code.
    Negative quantities are scrap credits (is_scrap_credit)."""
    lines = _read_lines(path)
    h, cols = _find_header(lines, ["BOMcat", "AltBOM", "Component"])
    out = []
    for line in lines[h + 1 :]:
        if not line.startswith("\t"):
            continue
        f = line.split("\t")
        if _cell(f, cols, "BOMcat") != "M":
            continue
        qty = _num(_cell(f, cols, "Quantity"))
        if qty is None:
            continue
        out.append({
            "bom_no": _cell(f, cols, "BOM"),
            "alt_bom": _cell(f, cols, "AltBOM"),
            "parent_code": _cell(f, cols, "Material"),
            "parent_desc": _cell(f, cols, "Material Description", 0),
            "component_code": _cell(f, cols, "Component"),
            "component_desc": _cell(f, cols, "Material Description", 1),
            "qty_per": qty,
            "uom": _cell(f, cols, "Un"),
            "item_no": int(_cell(f, cols, "Item") or 0),
            "is_scrap_credit": qty < 0,
        })
    return out


def parse_grn_report(path: str | Path) -> list[dict]:
    """1117 purchase report.xls (GRN history) → receipt rows. Source for: real vendor
    codes/names, real PO numbers, PO rates, materials supplied per vendor."""
    lines = _read_lines(path)
    h, cols = _find_header(lines, ["GRN No", "Vendor Name", "PO No"])
    out = []
    for line in lines[h + 1 :]:
        if not line.startswith("\t"):
            continue
        f = line.split("\t")
        grn = _cell(f, cols, "GRN No")
        if not grn.isdigit():
            continue
        out.append({
            "grn_no": grn,
            "grn_date": _cell(f, cols, "GRN Date"),
            "vendor_code": _cell(f, cols, "Vendor"),
            "vendor_name": _cell(f, cols, "Vendor Name"),
            "invoice_no": _cell(f, cols, "Ref.No."),
            "po_no": _cell(f, cols, "PO No"),
            "material_code": _cell(f, cols, "Material No"),
            "material_desc": _cell(f, cols, "Material Description"),
            "uom": _cell(f, cols, "UoM"),
            "received_qty": _num(_cell(f, cols, "Rec-Qty")),
            "short_qty": _num(_cell(f, cols, "Short-Qty")),
            "accepted_qty": _num(_cell(f, cols, "Accpt-Qty")),
            "rejected_qty": _num(_cell(f, cols, "Rej-Qty")),
            "po_rate": _num(_cell(f, cols, "PO-Rate")),
        })
    return out
