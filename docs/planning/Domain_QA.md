# Domain Flow Q&A — Kartik, 2026-06-11

Answers that shape the build. Packets MUST quote this doc where relevant.
Status legend: ✅ settled · 🔶 placeholder until plant confirms · ⛔ blocked on input.

## Planning / schedule

| # | Question | Answer | Build consequence |
|---|---|---|---|
| 1 | How does Bajaj's schedule map to part numbers? | ⛔ Unknown — real sample file will show | Schedule parser (P11) stays blocked on the sample; mock format continues; cascade math written against an interface so family-level vs part-level slots in either way. **Kartik: drop the sample in the folder — this is the oldest open item.** |
| 3 | Do SAP production orders exist usably? | ✅ Stable order per part/month | Simple line+part→order mapping table, refreshed monthly. PPC hold queue (§11.11) stays as the safety net for gaps. |

## Money / documents

| # | Question | Answer | Build consequence |
|---|---|---|---|
| 2 | Where is the Bajaj invoice created? | ✅ SAP creates it (incl. IRN/e-way); app confirms only | M5 stays minimal: invoice header keyed/imported + qty-match check + confirm. No invoice generation, no GST API. |
| 4 | What does the ₹14 L vendor limit measure? | ✅ Value of our RM lying at the vendor | Architecture §5.5a confirmed as designed: exposure = Σ(AT_VENDOR qty × material price), BOM-relieved on part GRs. |
| 8 | Job-work challan vs sale-to-vendor split? | 🔶 Unsure | Keep destination CHECK(inhouse·vendor_sale·job_work); ask store team per vendor during pilot setup; document creation stays in SAP either way. |

## Plant floor

| # | Question | Answer | Build consequence |
|---|---|---|---|
| 5 | Are the 4 app-map lines real? | 🔶 Plant will confirm | Seeded 4 stay as placeholders; lines are admin-CRUD so renaming/adding is config, not code. |
| 6 | Shift pattern? | ✅ **Varies by line** | Design change: shifts become per-line — `plan_calendar.shifts` holds the plant default, lines get an optional `shift_pattern` override (implemented in P29/P30). Shift CHECK stays A·B until plant says otherwise. Auto-close fires per line. |
| 7 | Gate setup? | ✅ 1 gate, 15–50 trucks/day, weighbridge prints a slip | Real volume → gate UX speed matters (scan pipeline earns its keep). Add to gate/GR flow: `weighbridge_weight` field + weighbridge-slip photo (P16/P20). Steel tolerance checks use weighbridge weight vs invoice weight. |
| 11 | How is received qty established? | ✅ 100% count/weigh of everything | GR screen does **NOT** prefill received qty — prefill invites rubber-stamping. Fast numeric entry instead. (P20/P22.) |

## Pilot logistics

| # | Question | Answer | Build consequence |
|---|---|---|---|
| 9 | Pilot parts? | 🔶 Plant decides later | Build/demo against the 4 mudguard assemblies + components (highest-volume in the real sale report); swap via admin before pilot. |
| 10 | Vendor participation? | ✅ Internal roles first; vendor portal later | **M6 (P37–P39) resequenced after M7.** Pilot = internal users only. Vendor scoping still built into services from day one (cheaper now than retrofitted). |
| 12 | Timeline + admin? | ✅ 4–6 weeks to floor pilot; Kartik is admin | Aggressive: thin-slice packets only, nothing speculative. Vendor-portal deferral buys the time back. Admin guide in docs/human/ targets Kartik. |

## Production confirmation — clarified scope (13 Jun 2026)

| # | Question | Answer | Build consequence |
|---|---|---|---|
| 13 | Is production confirmation in the approved scope? | ✅ **YES — it is the core new module.** Earlier phrasing meant: it's the one flow *not digitized at the floor today*. | M4 (P29–P33) stays exactly as planned. |
| 14 | What's wrong with today's process? | Confirmations happen **once every ~3 hours** — the confirmer must sit at a PC; there are **no computers on the shop floor**, so output waits in batches. | The app's job: phone-based confirmation at the line, posted as often as the supervisor wants (interim posts). Latency 3 h → minutes. This is the demo's money shot. |
| 15 | Who is the source of truth for production? | ✅ **SAP.** The app captures at the floor and **uploads to SAP** — app is the capture layer, never a parallel truth. | Outbox postback for CONFIRMATION records is core MVP, not phase-2 polish: P40's CONFIRMATION batch path gets priority, and the SAP team's CSV spec for confirmations (AFRU-style) becomes the most urgent SAP-side input. Reinforces ADR-002/003. |

## Build-order impact (playbook §4 re-sequence)

M0 ✓ → M1 (P10–P14, parser ⛔ on sample — P11 last) → M2 (P15–P22, + weighbridge fields) →
M3 (P23–P28) → M4 (P29–P33, + per-line shifts) → M5 (P34–P36) → **M7 (P40–P45) → M6 (P37–P39, post-pilot-start)**.
