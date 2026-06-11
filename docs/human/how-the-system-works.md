# How the system works — the 8 stages in plain words

The app is an operations layer over SAP for plant 1117. It captures what happens on the
floor, faster than today's paper-and-PC routine, and posts everything back to SAP.

## The parallel-run principle

During the pilot, **SAP and paper continue exactly as today**. The app runs alongside.
Two rules follow from this:

1. **The app never blocks the plant.** A truck never waits on the app. Stock checks warn
   instead of blocking while `ops_mode = parallel_run`. If the gate is offline, a minimal
   backfill entry is always accepted and completed later.
2. **SAP is the source of truth.** The app is the capture layer. Every GR, issue,
   confirmation, dispatch and invoice is queued for SAP (the "outbox") and a daily
   reconciliation CSV compares app entries against SAP's own reports until trust is earned.

## Stage 1 — Schedule in

Planning uploads the Bajaj schedule. The system stores it as a new version, computes the
difference against the previous version, and shows it for review. On release, sanity
checks run: wrong period, totals more than ±50% off the last release, or a model family
with no configured split. Warnings need an explicit confirm; an unconfigured family is a
hard stop until planning fixes the split in config. A bad release is never deleted —
rollback is a re-release of an earlier version. (The parser format is provisional until
the real Bajaj sample file arrives.)

## Stage 2 — Plan

Release turns the schedule into line plans (per date, line, part — using the
Yeshshree/Laxmi split percentages) and vendor call-offs (raw material needs, exploded
through the BOM). Old plan revisions are kept, never overwritten. These plans feed the
PPC view, the supervisor's screen, and the achievement dashboard.

## Stage 3 — Gate

The guard scans the vendor's invoice on the ScanJet. The gate-agent uploads it; the
server decodes the e-invoice QR (vendor, invoice number, date, value) and, for TATA,
the PDF417 barcode (PO number, vehicle, weight). The entry auto-fills and matches an
open PO. **When matched, material and quantity are locked from the PO** — nothing is
typed from paper. Phone QR scan and full manual key-in remain first-class fallbacks
(small vendors have no QR). Challans and other non-invoice documents have their own
doc type; an invoice can be attached later. A duplicate invoice number is refused
unless the guard explicitly continues it as consignment 2 of N.

**Blocks:** offline gate → backfill entry (vehicle, driver, free-text vendor, photos);
GR is blocked until someone completes the backfill with vendor/PO/invoice. Unmatched
entries sit in the unmatched folder; after 24 hours an escalation nags Purchase and
the planner daily until a PO is linked or the entry is marked consumable.

## Stage 4 — QC and goods receipt

Store/QC counts or weighs **everything** — the GR screen never prefills the received
quantity, by design. The system then applies the material-group tolerance (steel:
0.5%): inside tolerance is a clean accept, no flag. Outside it: a shortage drafts a
**5× debit note** that goes to the approval inbox. Weighbridge weight and slip photo
are captured. A full-lot rejection posts **zero stock**, prints a return gate pass,
and drafts a debit note.

**Blocks:** a received quantity ≥5× off the PO open quantity is a **hard** anomaly —
the save is refused; the user can re-type or confirm-and-escalate, which registers the
anomaly and notifies up the chain (supervisor → store head → plant head; any of them
can release it). A >20% deviation is a **soft** anomaly: the GR saves, but it lands in
the anomaly register and notifies the supervisor. A gate entry left without GR for 30
minutes escalates to the store head, then management.

## Stage 5 — Stock and issues

Stock only ever changes through ledger rows (GR in, issue out, production, dispatch,
adjustment) — balances are computed from them, so history is always reconstructible.
Issuing material to a vendor checks the vendor's exposure: the value of our RM lying
at that vendor (issues add, part GRs relieve via BOM) against the credit and quantity
limits. A breach **blocks the issue and creates a credit-waiver approval** (Materials
Head + CFO roles); approval auto-posts the issue. In parallel-run mode, *insufficient
stock* never blocks — it posts with a warning and a soft anomaly. Corrections are
reversal-plus-new-row through an approval, never a silent edit.

## Stage 6 — Production confirmation (the core new module)

Today confirmations happen every ~3 hours at a PC. With the app, the supervisor posts
from a phone at the line: good quantity, rejections (reason code mandatory), downtime,
process loss — as interim posts or a shift close. Components backflush from the BOM
into the ledger. **Plan pinning:** the first confirmation of a shift pins the plan
revision active at shift start, so a mid-shift schedule cut can never make honest work
look like an overrun. Confirming more than 120% of the remaining *pinned* plan is a
hard block. Shifts auto-close from the calendar (per-line shift patterns honored);
late posts are accepted but flagged.

**Blocks:** no matching production order → the confirmation goes to a **hold queue**
(nothing is lost); PPC resolves the hold by supplying the order and the confirmation
posts from the stored payload. Corrections after close go through approval.

## Stage 7 — Dispatch

Store creates the dispatch note (customer, vehicle, parts, quantities). FG stock is
checked under the same parallel-run policy: warn, don't block.

## Stage 8 — Billing

SAP creates the actual invoice (including IRN/e-way bill); the app only records it and
checks quantities against the dispatch. A mismatch needs a reason and raises a soft
anomaly — it never blocks. Confirm-sale feeds the live sales dashboard and queues the
invoice record for SAP.

## Behind every stage: the outbox to SAP

Every GR, issue, confirmation, dispatch and invoice writes an outbox row **in the same
database transaction** as the document itself — there is no state where a document
exists but SAP won't hear about it. The worker batches outbox rows into sequence-
numbered CSVs and uploads them by SFTP (atomic rename, row-count trailer, checksum).
Until SAP provides SFTP credentials the queue accumulates safely and nothing is lost.

## Approvals, delegates, and the emergency override

One approval engine handles everything needing sign-off: credit waivers, debit notes,
corrections, and more. Each approval names the required roles; co-approval means every
role must decide. Approvers can **delegate** to a named person for a validity window.
If an approval sits for 2 hours, the system reminds the approvers and delegates; at 4
hours it escalates to management/MD. When a truck genuinely cannot wait, management or
admin can use the **emergency override**: a mandatory reason is recorded, the action
applies immediately, and the system automatically opens a post-facto *override review*
approval for the original approvers. Overrides are counted on the management overview —
they are never invisible.
