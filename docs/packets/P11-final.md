# Packet P11-final: REAL Bajaj schedule format — DONE (Cowork, 2026-06-12)
The sample arrived ('3Wh Production Plan - May 2026'); ADR-005's provisional layer is
superseded exactly as designed — only the ingest changed.

Delivered:
- importers/schedule_xlsx.py — parses the Monthly sheet (vehicle models × Bajaj lines D/E
  carried forward × 4 week buckets with '(d to d)' header dates); qty = 'Monthly Req in
  3WH plant', 4WH-plant rows skipped + reported; read_only streaming (the workbook carries
  a 65k-row tracking sheet — naive load took 25s, streaming 2.6s). parse_line_map() bonus:
  the workbook's material→line sheet = Yeshshree's REAL line names (Domain_QA Q5).
- normalize_family(): ordered substring rules + planner overrides via
  app_settings['model_family_map']; unmatched → raw name → SPLIT_MISSING sanity catches it.
- model_part_factors table + /config/part-factors CRUD — the vehicles→parts cascade
  (sample proves rear mudguard = 2/vehicle: 48,555 × 2 = 97,110). Release explodes
  family-level lines via factors; missing factor → unmapped report 'no_part_factor'.
- POST /schedules/upload-xlsx — file stored (files service), schedule created at
  vehicle level, response: families found, parse errors, line-map preview.
Tests: 5 golden/behavioral (incl. 100 vehicles × 2 × 74% = 148 plan math; same model on
both D and E lines — a real-file catch). 21/21 green with plans+config regression.
PILOT-SETUP TASK CREATED: planner must fill part-factors for the pilot parts before the
first real release (Domain_QA Q1 note). Frontend follow-up: schedule_screen gets an
upload-xlsx button (currently manual-entry only).
Checklist: tests-first ✓ · scope ✓ · invariants ✓ · self-review ✓
