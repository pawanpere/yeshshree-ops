# ADR-005: Provisional schedule format + plan math
Date: 2026-06-12 · Status: accepted, EXPIRES when the real Bajaj sample arrives
Decision: schedule ingest = CSV (part_sap_code, model_family, bucket_date, qty) + manual
JSON entry; plan math = family split % → line plans (material→line via line_materials,
lowest line_id when multi-mapped) → BOM explode → vendor call-offs (vendor of latest open
PO per component).
Why: stage 1 was blocked on Bajaj's real file (Domain_QA Q1); building behind a parser
interface let M1–M5 proceed. ONLY importers/schedule_csv.py (and possibly the split
application) change when the sample lands — line plans, pinning, dashboards are insulated.
