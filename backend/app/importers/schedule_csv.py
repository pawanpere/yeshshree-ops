"""PROVISIONAL Bajaj schedule CSV parser (P11).

⚠⚠ FORMAT IS PROVISIONAL — Domain_QA.md Q1 is still ⛔: how Bajaj's schedule maps
to part numbers is UNKNOWN until the real sample file arrives ("Kartik: drop the
sample in the folder — this is the oldest open item"). This module defines a
PLACEHOLDER interchange format so the rest of M1 (versioning, diff, sanity,
release math) can be built and tested against a stable interface. When the real
sample lands, ONLY this parser is rewritten — it must keep returning the same
row-dict shape (the "interface" Domain_QA Q1 mandates so family-level vs
part-level slots in either way). Do NOT let downstream code grow knowledge of
this CSV layout.

Provisional format (one bucketed quantity per row):

    part_sap_code,model_family,bucket_date,qty
    1101030569,RE Petrol,2026-06-15,1000

- ``part_sap_code`` — SAP material code of the finished part (TEXT, required).
- ``model_family``  — Bajaj model family; must match a configured
  ``model_family_splits.family`` for release to succeed (required).
- ``bucket_date``   — ISO date YYYY-MM-DD (required).
- ``qty``           — decimal quantity, > 0 (required).

Error contract: row-level problems are COLLECTED, never raised — the planner
sees every bad row at once, not one per upload attempt. Returns ``(rows,
errors)`` where ``rows`` is a list of dicts ``{"sap_code", "model_family",
"bucket_date" (datetime.date), "qty" (Decimal)}`` and ``errors`` is a list of
``{"row": <1-based line no>, "code", "message"}``. A bad header is a single
fatal error with row 0 and no rows.
"""
import csv
import datetime as dt
import io
from decimal import Decimal, InvalidOperation

EXPECTED_HEADER = ["part_sap_code", "model_family", "bucket_date", "qty"]


def parse_schedule_csv(content: bytes | str) -> tuple[list[dict], list[dict]]:
    """Parse the provisional CSV. Never raises on bad rows — see module docstring."""
    if isinstance(content, bytes):
        # utf-8-sig: tolerate the BOM Excel loves to prepend.
        content = content.decode("utf-8-sig", errors="replace")
    reader = csv.reader(io.StringIO(content))
    rows: list[dict] = []
    errors: list[dict] = []

    header = next(reader, None)
    if header is None or [h.strip().lower() for h in header] != EXPECTED_HEADER:
        errors.append({"row": 0, "code": "BAD_HEADER",
                       "message": f"Expected header {','.join(EXPECTED_HEADER)!r}, "
                                  f"got {','.join(header or [])!r}"})
        return rows, errors

    for lineno, raw in enumerate(reader, start=2):
        if not raw or all(not c.strip() for c in raw):
            continue  # blank line — Excel trailing rows
        if len(raw) != len(EXPECTED_HEADER):
            errors.append({"row": lineno, "code": "BAD_COLUMNS",
                           "message": f"Expected {len(EXPECTED_HEADER)} columns, got {len(raw)}"})
            continue
        sap_code, family, date_s, qty_s = (c.strip() for c in raw)
        if not sap_code or not family:
            errors.append({"row": lineno, "code": "MISSING_FIELD",
                           "message": "part_sap_code and model_family are required"})
            continue
        try:
            bucket_date = dt.date.fromisoformat(date_s)
        except ValueError:
            errors.append({"row": lineno, "code": "BAD_DATE",
                           "message": f"bucket_date {date_s!r} is not an ISO date"})
            continue
        try:
            qty = Decimal(qty_s)
        except InvalidOperation:
            errors.append({"row": lineno, "code": "BAD_QTY",
                           "message": f"qty {qty_s!r} is not a number"})
            continue
        if qty <= 0:
            errors.append({"row": lineno, "code": "BAD_QTY",
                           "message": f"qty must be > 0, got {qty}"})
            continue
        rows.append({"sap_code": sap_code, "model_family": family,
                     "bucket_date": bucket_date, "qty": qty})
    return rows, errors
