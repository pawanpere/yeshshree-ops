"""REAL Bajaj schedule parser (supersedes the provisional CSV — ADR-005 expired
2026-06-12 when the sample landed: data/bajaj_schedule_sample_may2026.xlsx).

Workbook anatomy (from the real file, '3 Wh Production Plan'):
- 'Monthly' sheet = THE schedule. Header pair: row with 'Sr.No.'/'Model'/'Line' +
  the row below carrying Dom/Export/Total and week ranges '(2 to 9)'. Data rows:
  vehicle MODELS (not parts), Bajaj line letter (D/E) carried forward on blanks,
  'Total … Line' subtotal rows skipped, data ends at 'Grand Total'.
- qty for OUR plant = 'Monthly Req … 3W' column; rows where it's 0 are produced in
  Bajaj's 4WH plant → fall back to Net-vehicles total, else skipped (reported).
- Week columns hold qty per week; bucket_date = month + range start day. When all
  weeks are 0 but monthly_req > 0, one bucket on the 1st carries the month.
- A material→line sheet (header 'Material'|'Line') maps SAP codes to Yeshshree's
  REAL production lines (CRADEL, DASH BOARD, FRONT MUDGAURD…) — parsed as a bonus
  for admin review (Domain_QA Q5).

PERFORMANCE: workbooks ship with a 65k-row daily-tracking sheet; we open in
read_only streaming mode and materialize at most `_SCAN_ROWS` rows per sheet —
never the whole book.

Vehicle model → family normalization: ordered substring rules; planner overrides
via app_settings['model_family_map'] {substring: family} (checked first, insertion
order). Unmatched models keep their raw name — the release sanity check
(SPLIT_MISSING) then forces an explicit decision. Cascade vehicles→parts happens at
release via model_part_factors (services/plans.py), not here.
"""
import datetime as dt
import io
import re
from decimal import Decimal

from openpyxl import load_workbook

WEEK_RANGE = re.compile(r"\((\d{1,2})\s*to\s*(\d{1,2})\)")
_SCAN_ROWS = 250  # schedule + line-map sheets are well under this

# Family groupings DECODED FROM THE WORKBOOK'S OWN FORMULAS (Monthly sheet, right
# block, T-column =+Q… sums — 2026-06-12): LPG models roll into the Re CNG bucket;
# 2-stroke ('2S') models are their own family 'PG MF 2s'; MAX UG / Max Wider / RIKI /
# Maxima-C(cabin) are separate; EV is family-specific, not one bucket.
# All rules remain ordered (first match wins) and planner-overridable via
# app_settings['model_family_map'].
DEFAULT_FAMILY_RULES: list[tuple[tuple[str, ...], str]] = [
    # (ALL substrings must match, upper-cased) → family. Order = the workbook's truth:
    # Q-row sums per family decoded one by one (e.g. Re max UG = MAXIMA Z fuel rows;
    # 'Wider sc' in RE EV names means wider SCISSOR, not Maxima X Wide).
    (("2S",), "PG MF 2s"),                          # =Q13+Q16
    (("MAX UG", "EV"), "Re max UG EV GOGO"),
    (("MAX UG",), "Re max UG"),
    (("MAXIMA X WIDE", "WEGO"), "Max Wider EV"),    # =Q29
    (("MAXIMA X WIDE", "EV"), "Max Wider EV"),
    (("MAXIMA X WIDE",), "Max Wider"),              # =Q20+Q30+Q31 (all fuels)
    (("MAXIMA C",), "gc Cabin"),                    # =Q32..Q40
    (("MAXIMA Z", "EV"), "Re max UG EV GOGO"),      # =Q28
    (("MAXIMA Z",), "Re max UG"),                   # =Q21..Q26 (all fuels)
    (("RIKI",), "E RIKI"),                          # =Q41..Q43
    (("RE EV",), "EV GOGO"),                        # =Q17+Q18 (Wider-scissor WEGOs)
    (("WEGO",), "Re max UG EV GOGO"),               # =Q27 (WEGO P7009)
    (("EV",), "EV GOGO"),
    (("CNG",), "RE CNG"),
    (("LPG",), "RE CNG"),  # LPG models share the CNG family split (=Q7..Q11)
    (("DIESEL",), "RE Diesel"),
    (("DSL",), "RE Diesel"),
    (("PET",), "RE Petrol"),
]


def normalize_family(model: str, overrides: dict[str, str] | None = None) -> str:
    up = model.upper()
    for sub, family in (overrides or {}).items():
        if sub.upper() in up:
            return family
    for subs, family in DEFAULT_FAMILY_RULES:
        if all(s in up for s in subs):
            return family
    return model.strip()  # unmatched → raw; SPLIT_MISSING sanity will surface it


def _num(v) -> Decimal:
    if v is None or v == "":
        return Decimal("0")
    try:
        return Decimal(str(v))
    except Exception:
        return Decimal("0")


def _cell(rows: list[tuple], r: int, c: int):
    """1-based (r, c) access into materialized rows; None when out of range."""
    if r - 1 >= len(rows):
        return None
    row = rows[r - 1]
    if c - 1 >= len(row):
        return None
    return row[c - 1]


def _sheets(source: bytes | str, max_rows: int = _SCAN_ROWS):
    """Yield (sheet_name, rows) with rows materialized up to max_rows,
    using read_only streaming — the 65k-row tracking sheet stays unread."""
    wb = load_workbook(io.BytesIO(source) if isinstance(source, bytes) else source,
                       data_only=True, read_only=True)
    try:
        for name in wb.sheetnames:
            ws = wb[name]
            rows = []
            for i, row in enumerate(ws.iter_rows(max_row=max_rows, values_only=True)):
                rows.append(row)
                if i + 1 >= max_rows:
                    break
            yield name, rows
    finally:
        wb.close()


def parse_monthly_plan(source: bytes | str, period: str,
                       family_overrides: dict[str, str] | None = None
                       ) -> tuple[list[dict], list[str]]:
    """source = xlsx bytes or path; period = 'YYYY-MM'.
    Returns (rows, errors). Row: {model, family, line_code, dom, export, total,
    monthly_req, qty, buckets: [{'bucket_date': date, 'qty': Decimal}]}."""
    errors: list[str] = []
    target: list[tuple] | None = None
    header_row = 0
    for _name, rows in _sheets(source):
        for r in range(1, min(8, len(rows)) + 1):
            a = str(_cell(rows, r, 1) or "").strip()
            b = str(_cell(rows, r, 2) or "").strip()
            if a.startswith("Sr") and b == "Model":
                target, header_row = rows, r
                break
        if target is not None:
            break
    if target is None:
        return [], ["No sheet with an 'Sr.No. | Model | Line' header found — "
                    "Bajaj layout changed? See importers/schedule_xlsx.py docstring."]
    rows_ = target

    year, month = int(period[:4]), int(period[5:7])
    sub = header_row + 1  # Dom/Export/Total + '(d to d)' ranges
    width = max(len(rows_[header_row - 1]), len(rows_[sub - 1]))

    # column discovery from the header pair
    cols: dict[str, int] = {}
    weeks: list[tuple[int, int]] = []  # (col, start_day)
    for c in range(1, width + 1):
        top = str(_cell(rows_, header_row, c) or "")
        below = str(_cell(rows_, sub, c) or "")
        if below.strip() == "Dom":
            cols["dom"] = c
        elif below.strip() == "Export":
            cols["export"] = c
        elif below.strip() == "Total" and "total" not in cols:
            cols["total"] = c
        m = WEEK_RANGE.search(below)
        if m and top.strip().lower().startswith("week"):
            weeks.append((c, int(m.group(1))))
        top_flat = top.replace("\n", " ").strip().lower()
        if top_flat.startswith("monthly req") and "monthly_req" not in cols:
            cols["monthly_req"] = c
        if top_flat.startswith("net vehicles") and "net_total" not in cols:
            cols["net_total"] = c
    if not weeks:
        errors.append("No 'Week N (d to d)' columns found — bucket dates unknown; "
                      "monthly totals land on the 1st.")
    if "monthly_req" not in cols:
        errors.append("No 'Monthly Req' column — using Total instead.")

    out: list[dict] = []
    line_code = None
    for r in range(sub + 1, len(rows_) + 1):
        model = _cell(rows_, r, 2)
        if model is None:
            continue
        model = str(model).strip()
        if model.lower().startswith("total"):
            continue  # 'Total D Line' subtotals
        if model.lower().startswith("grand total"):
            break  # end of schedule block; below is scratch
        raw_line = _cell(rows_, r, 3)
        if raw_line not in (None, ""):
            line_code = str(raw_line).strip()

        monthly_req = _num(_cell(rows_, r, cols["monthly_req"])) \
            if "monthly_req" in cols else Decimal("0")
        total = _num(_cell(rows_, r, cols.get("total", 6)))
        net_total = _num(_cell(rows_, r, cols["net_total"])) \
            if "net_total" in cols else Decimal("0")
        qty = monthly_req if monthly_req > 0 else net_total
        if qty <= 0:
            if total > 0:
                errors.append(f"row {r} '{model}': made outside the 3WH plant "
                              f"(monthly req 0, total {total}) — skipped")
            continue

        buckets: list[dict] = []
        for col, start_day in weeks:
            wqty = _num(_cell(rows_, r, col))
            if wqty > 0:
                try:
                    bucket = dt.date(year, month, start_day)
                except ValueError:
                    errors.append(f"row {r}: bad week start day {start_day}")
                    continue
                buckets.append({"bucket_date": bucket, "qty": wqty})
        if not buckets:  # monthly qty without weekly spread → one bucket on the 1st
            buckets = [{"bucket_date": dt.date(year, month, 1), "qty": qty}]

        out.append({
            "model": model,
            "family": normalize_family(model, family_overrides),
            "line_code": line_code,
            "dom": _num(_cell(rows_, r, cols["dom"])) if "dom" in cols else Decimal("0"),
            "export": _num(_cell(rows_, r, cols["export"])) if "export" in cols else Decimal("0"),
            "total": total,
            "monthly_req": monthly_req,
            "qty": qty,
            "buckets": buckets,
        })
    if not out:
        errors.append("Schedule block parsed empty — header found but no data rows.")
    return out, errors


def parse_line_map(source: bytes | str) -> list[dict]:
    """Material→line sheet (header 'Material'|'Line'): Yeshshree's REAL line names.
    The header can sit a few rows down (the sample's sheet dimension starts at A4),
    so scan the first 10 rows. Returned for admin review — applying it to
    lines/line_materials is a human call."""
    for _name, rows in _sheets(source):
        header = None
        for r in range(1, min(10, len(rows)) + 1):
            if str(_cell(rows, r, 1) or "").strip() == "Material" and \
                    str(_cell(rows, r, 2) or "").strip() == "Line":
                header = r
                break
        if header is None:
            continue
        out = []
        for r in range(header + 1, len(rows) + 1):
            mat, line = _cell(rows, r, 1), _cell(rows, r, 2)
            if mat is None or line is None:
                continue
            out.append({"sap_code": str(mat).strip(), "line": str(line).strip()})
        return out
    return []
