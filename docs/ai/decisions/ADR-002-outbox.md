# ADR-002: Transactional outbox for guaranteed SAP postback (no message queue)
Date: 2026-06-10 · Status: accepted
Decision: sap_outbox row written in the SAME transaction as every domain write; worker batches → CSV → SFTP (tmp+rename, seq numbers, checksum) → at-least-once + SAP-side dedupe on record id.
Why: delivery guarantee == DB durability; backlog is queryable SQL; a queue adds a second stateful system with worse visibility.
