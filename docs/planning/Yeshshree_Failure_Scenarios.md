# Yeshshree Operations App — Failure Scenarios (Premortem)

Assume the app is built and live at plant 1117. These are the real-life situations where it gets stuck, blocks people, or silently goes wrong — walked through role by role, the way users would actually hit them. Legend: ✅ already handled by the current design · ⚠️ **GAP** — needs a design decision or build item (collected in §9).

---

## 1. Gate (security guard, shared device, ScanJet + gate PC)

| # | Scenario | What the guard experiences | Handling |
|---|---|---|---|
| 1 | **Internet down at the gate, trucks queuing.** Monsoon, fiber cut, router dead. Drivers won't wait; supervisor pressure to let trucks in. | App spins; nothing matches; queue grows | ⚠️ **GAP** — retry queue covers *submits*, but PO-match needs the server. Fix: an offline "minimal gate entry" (vehicle no + photos + invoice photo, queued locally) + the paper register continues; a **backfill screen** to complete entries once online. Trucks must never wait for the app. |
| 2 | **ScanJet jams / gate PC off / Windows updated overnight and the agent didn't restart.** Guard scans, nothing appears in the app, no error anywhere. | Confusion — "the app is broken" | ⚠️ **GAP** — agent must send a **heartbeat**; app shows a "scanner offline since 09:12" banner at gate + admin notification. Fallback path (phone camera QR / manual) is one tap away. |
| 3 | **Same invoice scanned twice** (guard re-scans because the first seemed to do nothing). | Two pending entries for one truck | ✅ file sha256 dedupe + duplicate invoice_no+vendor warning. |
| 4 | **One invoice, two trucks** (mill splits a consignment across vehicles / second lot comes next day). | Second scan rejected as "duplicate invoice" | ⚠️ **GAP** — duplicate-invoice check must allow a deliberate "part consignment 2 of N" continuation instead of hard-refusing. |
| 5 | **One truck, five invoices** (vendor clubs deliveries). | Guard scans 5 docs for 1 vehicle | ✅ multiple gate entries may share a vehicle no. UI should make "same truck" fast (copy vehicle/driver from last entry). |
| 6 | **Material arrives on a delivery challan, invoice comes next week** (very common for job-work returns). | No invoice number to enter; entry form blocks | ⚠️ **GAP** — gate entry needs a `doc_type` (invoice / challan / returnable gate pass) and the GR→billing linkage must tolerate invoice-later. |
| 7 | **Customer return** — Bajaj sends rejected assemblies back. Inward, but no vendor, no PO. | Doesn't fit any form | ⚠️ **GAP** — "other inward" category (customer return / repair / consumable) so the gate is never the place where reality fails to fit the form. |
| 8 | **Guard shift change mid-entry.** | New guard, locked session | ✅ PIN quick-switch on the station device. |
| 9 | **Wrong PO auto-matched** (two open POs, same material, same vendor). | QC later sees wrong expected qty | ✅ PO re-link allowed any time before GR posts (unmatched-folder mechanics reused). |

## 2. QC / Goods receipt

| # | Scenario | Experience | Handling |
|---|---|---|---|
| 10 | **QC person absent/busy; truck unloaded, GR pending for hours.** | Gate did its job; receipt sits in queue; vendor's driver wants his signed copy | ⚠️ **GAP** — escalation timer: GR pending > 30 min (the app-map target) → notify store head; > 2 h → management. Without this the "30-min GR" promise is a poster, not a system. |
| 11 | **Steel arrives by weight, PO in KG, invoice shows both weight and sheet count; weighbridge says 28,090 kg vs invoice 28,172 kg.** | 0.3% diff — is that a shortage? | ⚠️ **GAP** — per-material-group **tolerance config** (e.g. ±0.5% steel weight). Within tolerance = accept clean; outside = shortage flow. Otherwise every steel GR soft-flags and people learn to ignore flags. |
| 12 | **Anomaly hard-block fires on a legitimate entry** (genuine part-delivery of 100 against PO 1,000) and the supervisor who must approve the escalation is in a meeting. | QC stuck, truck waiting | ⚠️ **GAP** — escalation must have a timeout chain (supervisor → store head → plant head) and any of them can release. A hard-block with an unresponsive approver = plant blocked. |
| 13 | **Entire lot fails QC; truck should go back loaded.** | Where's the "reject whole lot, return on same vehicle" button? | ⚠️ **GAP** — full-lot rejection path: GR with accepted_qty 0, return gate-pass generated, nothing touches stock, debit/return note drafted. |
| 14 | **Two different materials on one invoice line confusion** (vendor invoice lists 2 items, PO match locked to 1). | Qty mismatch chaos | ✅ gate entry per PO line item; the QR's ItemCnt warns when invoice has more lines than entries created. |

## 3. Store — stock & issue

| # | Scenario | Experience | Handling |
|---|---|---|---|
| 15 | **App stock ≠ physical stock during the parallel run.** Someone did a SAP-only or paper-only movement (they will, daily, for weeks). App says 0.4 MT, rack has 3 MT. | Issue blocked for "insufficient stock" — store keeper loses faith in the app on day 3 | ⚠️ **GAP — the most important policy decision in this doc.** During parallel run: **negative/insufficient stock warns but never blocks**, and a periodic SAP-stock import reconciles the ledger (ADJUST movements, fully audited). Hard-blocking on stock comes only after the app becomes system of record. |
| 16 | **Credit waiver needed at 7 PM; Materials Head on a flight, CFO's phone off.** Vendor truck waiting for RM; vendor's line will stop overnight. | Issue blocked; store keeper helpless; phone calls fly | ⚠️ **GAP** — three layers: **delegate approvers** (configurable), **SLA escalation** (pending > 2 h → remind, > 4 h → escalate to MD), and an **emergency override** (plant head can release with mandatory reason; auto-creates a post-facto approval + flags it on the management overview). Controls that can't bend under real pressure get bypassed *outside* the system — that's worse. |
| 17 | **Issued the wrong material physically, app says otherwise** (or right material, wrong qty typed). | Stock drifts from day one | ⚠️ **GAP** — issue correction flow (same pattern as confirmation corrections: reversal + reissue via approval, never silent edit). |
| 18 | **Vendor at qty limit but it's month-end pull and everyone knows the schedule doubles next week.** | Legit business blocked by stale limit | ✅ waiver flow exists; plus the credit re-baseline approval is designed for exactly this. SLA fix in #16 makes it usable. |

## 4. Production supervisor

| # | Scenario | Experience | Handling |
|---|---|---|---|
| 19 | **Supervisor forgets to close the shift; B-shift starts.** | B's posts land on A's open context; daily numbers wrong | ⚠️ **GAP** — auto-close at shift boundary (from `plan_calendar`), late posts allowed but flagged "posted after close" and attributed by login, not by open session. |
| 20 | **Plan revised downward at 11 AM while the line already produced more than the new plan.** Confirmation now exceeds 120% of remaining → hard-block on honest work. | "The app refuses my real production" | ⚠️ **GAP** — plan revisions apply to **future shifts only**; the validation always checks against the plan version active when the shift started. |
| 21 | **Part shows "needs order"** (no production order resolved) — supervisor can't confirm at all. | Output happening, no way to record it | ⚠️ **GAP** — a "can't confirm" queue visible to PPC with one-tap escalation; PPC resolves the order mapping; confirmations were never lost, just held. |
| 22 | **Supervisor's phone dead at shift end.** | Can't close shift | ✅ login from any station device or colleague's phone (PIN/password) — accounts are not device-locked. |
| 23 | **Rejected pieces get reworked overnight and become good.** | Yesterday's reject count now overstates scrap | ⚠️ **GAP** (accepted for MVP) — no rework flow in v1; corrections flow is the stopgap. Listed for phase 2; yield report footnotes "rework not modelled". |
| 24 | **Wifi dead spot at the press line.** | Posts fail at submit | ✅ client retry queue + idempotency keys — supervisor taps submit, walks on; it syncs when signal returns. History screen shows pending/posted per entry. |

## 5. Vendor (BYOD)

| # | Scenario | Experience | Handling |
|---|---|---|---|
| 25 | **Vendor changed phone number / forgot PIN / OTP not arriving.** | Locked out, calls the planner | ⚠️ **GAP** — admin reset screen (re-issue OTP, change phone) — small build item, big support burden if missing. |
| 26 | **Vendor disputes what they saw: "the schedule never showed 550."** | He-said-she-said | ✅ schedule versions are immutable + notification log + audit trail — show exactly what was visible when. |
| 27 | **Vendor's truck arrives before Purchase created the PO** (verbal urgent order — happens weekly). | Gate: unmatched ✅, QC counts ✅ — then GR can't post for days because there's no PO | ⚠️ **GAP** — unmatched-entry aging alarm (> 24 h → Purchase + planner notified daily) so material doesn't sit unbookable and unpaid-for. |

## 6. Planning

| # | Scenario | Experience | Handling |
|---|---|---|---|
| 28 | **Bajaj changes their Excel layout** (new column, renamed sheet) — parser fails on the 1st of the month. | Stage 1 of everything is stuck | ✅ by decision: manual schedule-entry form is the permanent escape hatch; import errors show row-level reasons. |
| 29 | **New model family in the schedule, no split % configured.** | Release blocked | ✅ deliberate hard-stop (the app map's amber "Set now" rows) — but add: the block names the owner and one-taps to the config row. |
| 30 | **Planner releases a wrong schedule** (uploaded May file in June). | Wrong plans everywhere, lines confused | ⚠️ **GAP** — release shows a sanity banner (period vs today, totals vs last version ±50% warning) and **release rollback** = re-release previous version as new revision (never delete). |

## 7. Management

| # | Scenario | Experience | Handling |
|---|---|---|---|
| 31 | **Approval notification flood** — every waiver, debit, config edit pings the CFO; by week 2 he ignores all of them, including the one that blocks a truck. | Notification blindness | ⚠️ **GAP** — two notification tiers: "blocking someone right now" (loud, repeated) vs "FYI digest" (bundled hourly/daily). Default everything to digest except blockers. |
| 32 | **Dashboard disagrees with SAP report in the Monday meeting.** | Trust collapse — the actual death scenario for the pilot | ✅ designed for: daily reconciliation export + every dashboard number drills to its source rows (audit trail). Discrepancy is explainable in minutes, with named entries. |

## 8. System-wide

| # | Scenario | Experience | Handling |
|---|---|---|---|
| 33 | **Cloud/server outage** — whole app down 2 hours. | Everyone falls back to paper | ✅ pilot is a parallel run — plant never stops. Add a status banner + admin SMS-less alert (email). Backfill screens (#1) absorb the gap afterwards. |
| 34 | **SFTP postback failing for 4 days** (SAP side changed the password, nobody told us). | Invisible — until SAP misses data | ✅ outbox: nothing lost, backlog alert at threshold, `failed` rows page the admin. Honest status on `/healthz`. |
| 35 | **New SAP material/vendor codes appear mid-week** (new part started) — transactions can't reference them. | Gate/GR pick-lists miss the item | ⚠️ **GAP** — admin "add material/vendor now" screen (marked `source=manual`, reconciled by next SAP import) — don't make the plant wait for a file. |
| 36 | **Shared device clock wrong** (someone changed the date) → JWTs rejected, "login expired" confusion. | Random auth failures on one device | ⚠️ **GAP** — server returns its time on auth errors; app detects skew and says "device clock is wrong" instead of "login failed". |
| 37 | **Photo upload fails (R2 hiccup / 2G moment)** — does the gate entry fail too? | Guard blocked by a photo | ⚠️ **GAP** — photos must be **non-blocking**: entry posts, photos retry in background, entry flagged "photos pending". |
| 38 | **Old APK after a breaking API change.** | Weird errors on some phones only | ⚠️ **GAP** — version handshake on launch; below minimum → force-update screen with the APK link. |
| 39 | **Double-tap submit on a laggy network.** | Would duplicate a GR/confirmation | ✅ `client_ref` idempotency — the second tap returns the first result. |
| 40 | **Marathi user hits an error only defined in English.** | Reads nothing useful | ✅ error envelope carries `message_mr`; CI check that every error code has both languages. |

---

## 9. Design changes this premortem forces (the actual to-do)

Collected gaps, deduplicated, in build order: (1) **parallel-run stock policy: warn-don't-block + SAP stock reconcile import** [#15 — policy, M3]; (2) **approval SLA + delegates + emergency override with post-facto approval** [#12, #16 — M3]; (3) **offline gate fallback + backfill screen** [#1 — M2]; (4) **gate-agent heartbeat + station status banner** [#2 — M2]; (5) **doc_type on gate entry (challan/return) + "other inward" category** [#6, #7 — M2]; (6) **part-consignment continuation on duplicate invoice** [#4 — M2]; (7) **tolerance config per material group** [#11 — M2]; (8) **escalation timers: GR>30min, unmatched>24h, hard-block unanswered, approval>2h** [#10, #12, #27 — M3]; (9) **full-lot rejection + return gate pass** [#13 — M2]; (10) **auto shift close + late-post flag; plan revisions future-shifts-only** [#19, #20 — M4]; (11) **"can't confirm" PPC queue** [#21 — M4]; (12) **issue corrections** [#17 — M3]; (13) **release sanity checks + rollback-by-re-release** [#30 — M1]; (14) **notification tiers (blocker vs digest)** [#31 — M6]; (15) **admin manual master-data add, vendor credential reset, photos non-blocking, version handshake, clock-skew message** [#25, #35–38 — M0/M7].

Accepted as out-of-MVP, documented: rework flow (#23), customer-return full lifecycle (#7 gets a stub category only).

**The two principles underneath all of this:** a truck, a shift, or a vendor must never physically wait on the app (paper/parallel always wins, backfill later); and every hard control needs a human override with audit, because controls that can't bend under real pressure get bypassed outside the system entirely.
