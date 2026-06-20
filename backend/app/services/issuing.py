"""Issues + credit/qty limit checks + waiver + corrections (P24/P27).
Spec: Architecture §4.6 (issues), §5.5a (vendor exposure), §11.1 (ops_mode warn path),
§11.12 (issue corrections), CLAUDE.md invariants 2/3/4/6/11.

Decisions (documented per packet brief):
- DOUBLE-ENTRY for vendor destinations (vendor_sale, job_work): one ISSUE_OUT row at
  RM with NEGATIVE qty (stock leaves our store) AND one ISSUE_OUT row at AT_VENDOR
  with POSITIVE qty (the material now sits at the vendor). The AT_VENDOR side is
  exactly what §5.5a exposure sums — issuing to a vendor raises exposure by
  construction, no separate counter to drift. Inhouse issues write only the RM row.
- Exposure (§5.5a): credit = Σ(AT_VENDOR qty × material price) per vendor; qty
  position = Σ(AT_VENDOR qty)/1000 for KG materials ONLY — there is no honest
  KG-conversion for EA/M2 etc., so non-KG rows are skipped from the MT position
  (flagged in the snapshot) but still valued in the credit exposure.
- limit_check JSON is the FULL decision-time snapshot (stock check + limits +
  breach reasons) — frozen evidence, later master edits never rewrite history.
- waiver path: breach → status='waiver_pending', Approval(credit_waiver,
  required_roles=['management']) + blocker notifications to management, NO stock
  movement and NO outbox until approval. Approve-handler reuses _post_movements so
  the direct-post and waiver-approve paths cannot drift. Stock is NOT re-checked at
  approval time — the management decision happened against the frozen snapshot.
- corrections (§11.12): approver = "store head". No store-head ROLE exists in §4.1;
  the store head is the supervisor with station='store' (see seeds/tests), so
  required_roles=['supervisor','admin'] — admin as the standing fallback.
- correction apply: reversal rows negate the ORIGINAL ledger rows verbatim
  (ref_type='issue_correction', created_by=NULL — system-written per §4.6), then a
  brand-new posted Issue with corrected values gets its own ledger + outbox rows;
  original.status='corrected'. Never a silent edit (invariant 6).
- Handlers registered via approval_handlers (@on_approve/@on_reject) run INSIDE the
  approvals engine's transaction — no commit here; they are also written to be
  idempotent (re-applying a decided approval is a no-op).
"""
import uuid
from decimal import Decimal

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.audit import record
from app.core.deps import CurrentUser, _error
from app.models.identity import User
from app.models.inventory import Issue, IssueCorrection, StockLedger
from app.models.master import Material, Vendor
from app.models.workflow import Anomaly, Approval, Notification
from app.services import inventory
from app.services.anomaly import to_decimal
from app.services.approval_handlers import on_approve, on_reject
from app.services.numbering import next_doc_no
from app.services.tx import enqueue_outbox, idempotent_replay

QTY = Decimal("0.001")    # NUMERIC(14,3)
MONEY = Decimal("0.01")   # NUMERIC(14,2)
KG_PER_MT = Decimal("1000")

VENDOR_DESTINATIONS = ("vendor_sale", "job_work")
CORRECTION_ROLES = ["supervisor", "admin"]  # store head ≈ supervisor(station=store)


def vendor_exposure(db: Session, vendor_id: int) -> dict:
    """§5.5a: credit = Σ(AT_VENDOR qty × material price); qty_mt = Σ(KG qty)/1000.
    Non-KG materials are valued in credit but skipped from the MT position."""
    rows = (db.query(func.sum(StockLedger.qty), Material.price, Material.uom)
            .join(Material, Material.id == StockLedger.material_id)
            .filter(StockLedger.location == "AT_VENDOR",
                    StockLedger.vendor_id == vendor_id)
            .group_by(StockLedger.material_id, Material.price, Material.uom).all())
    credit, qty_mt = Decimal("0"), Decimal("0")
    for qty, price, uom in rows:
        qty = to_decimal(qty or 0)
        credit += qty * to_decimal(price or 0)
        if uom == "KG":
            qty_mt += qty / KG_PER_MT
    return {"credit_exposure": credit.quantize(MONEY), "qty_mt": qty_mt.quantize(QTY)}


def _post_movements(db: Session, issue: Issue) -> None:
    """The ONE place posted issues touch stock + outbox — shared by direct post and
    waiver-approve so the two paths cannot drift. Caller owns the transaction."""
    material = db.get(Material, issue.material_id)
    db.add(StockLedger(material_id=issue.material_id, location="RM",
                       movement="ISSUE_OUT", qty=-issue.qty, uom=issue.uom,
                       vendor_id=issue.vendor_id, ref_type="issues", ref_id=issue.id,
                       created_by=issue.created_by))
    if issue.destination in VENDOR_DESTINATIONS:
        # double-entry: the same material now sits AT the vendor (feeds §5.5a).
        db.add(StockLedger(material_id=issue.material_id, location="AT_VENDOR",
                           movement="ISSUE_OUT", qty=issue.qty, uom=issue.uom,
                           vendor_id=issue.vendor_id, ref_type="issues",
                           ref_id=issue.id, created_by=issue.created_by))
    enqueue_outbox(db, "ISSUE", issue.id, payload={
        "doc_no": issue.doc_no,
        "destination": issue.destination,
        "material_sap_code": material.sap_code if material else None,
        "qty": str(issue.qty),
        "uom": issue.uom,
        "value": str(issue.value),
        "vendor_id": issue.vendor_id,
        "line_id": issue.line_id,
    })


def _notify_roles(db: Session, roles: list[str], *, kind: str, title: str, body: str,
                  ref_type: str, ref_id: int, tier: str = "blocker") -> None:
    targets = (db.query(User)
               .filter(User.is_active.is_(True), User.role.in_(roles)).all())
    for u in targets:
        db.add(Notification(user_id=u.id, kind=kind, tier=tier, title=title,
                            body=body, ref_type=ref_type, ref_id=ref_id))


def post_issue(db: Session, user: CurrentUser, body) -> Issue:
    # Invariant 4: retried request returns the original result.
    existing = idempotent_replay(db, Issue, body.client_ref)
    if existing:
        return existing

    material = db.get(Material, body.material_id)
    if material is None:
        raise _error("NOT_FOUND", "Material not found", "सामग्री सापडली नाही", 404,
                     {"material_id": body.material_id})
    # Phase 4 boundary: components are received into the COMP store, but outbound
    # (issue/consume) routing for components is a later phase. Until then issuing a
    # component is refused outright rather than silently posting against RM (which,
    # in parallel_run, would not block and would strand COMP stock / drive RM negative).
    if material.category == "component":
        raise _error(
            "ISSUE_COMPONENT_UNSUPPORTED",
            "Issuing components is not supported yet — component stock lives in the "
            "COMP store and outbound component routing is a later phase",
            "घटक इश्यू करणे अद्याप समर्थित नाही", 422,
            {"material_id": material.id, "category": material.category})
    qty = to_decimal(body.qty).quantize(QTY)
    if qty <= 0:
        raise _error("ISSUE_QTY_INVALID", "Quantity must be greater than zero",
                     "प्रमाण शून्यापेक्षा जास्त असावे", 422, {"qty": str(qty)})
    if body.uom and body.uom != material.uom:
        raise _error("ISSUE_UOM_MISMATCH",
                     f"Issue UoM must match the material master ({material.uom})",
                     f"इश्यू UoM सामग्री मास्टरशी जुळले पाहिजे ({material.uom})", 422,
                     {"uom": body.uom, "material_uom": material.uom})
    uom = material.uom

    vendor = None
    if body.destination in VENDOR_DESTINATIONS:
        if body.vendor_id is None:
            raise _error("ISSUE_VENDOR_REQUIRED",
                         "Vendor is required for vendor sale / job work",
                         "विक्रेता विक्री/जॉब वर्कसाठी विक्रेता आवश्यक आहे", 422,
                         {"destination": body.destination})
        vendor = db.get(Vendor, body.vendor_id)
        if vendor is None:
            raise _error("NOT_FOUND", "Vendor not found", "विक्रेता सापडला नाही", 404,
                         {"vendor_id": body.vendor_id})

    value = (qty * to_decimal(material.price or 0)).quantize(MONEY)

    # §11.1 stock policy: warn in parallel_run, hard-block in authoritative.
    chk = inventory.check_stock(db, material.id, qty, "RM")
    if chk["blocking"]:
        raise _error("STOCK_INSUFFICIENT",
                     "Insufficient stock to issue this quantity",
                     "हे प्रमाण देण्यासाठी पुरेसा साठा नाही", 422,
                     {"balance": str(chk["balance"]), "requested": str(qty),
                      "material_id": material.id})
    warned = not chk["sufficient"]

    snapshot: dict = {"stock": {"sufficient": chk["sufficient"],
                                "balance": str(chk["balance"]),
                                "mode": chk["mode"], "warned": warned},
                      "limits": None}

    breaches: list[str] = []
    if body.destination != "inhouse":
        exposure = vendor_exposure(db, vendor.id)
        exposure_after = (exposure["credit_exposure"] + value).quantize(MONEY)
        qty_mt = (qty / KG_PER_MT).quantize(QTY) if uom == "KG" else Decimal("0")
        qty_mt_after = (exposure["qty_mt"] + qty_mt).quantize(QTY)
        if vendor.credit_limit is not None and exposure_after > to_decimal(vendor.credit_limit):
            breaches.append("credit_limit")
        if uom == "KG" and vendor.qty_limit_mt is not None \
                and qty_mt_after > to_decimal(vendor.qty_limit_mt):
            breaches.append("qty_limit_mt")
        snapshot["limits"] = {
            "value": str(value),
            "exposure_before": str(exposure["credit_exposure"]),
            "exposure_after": str(exposure_after),
            "qty_mt_before": str(exposure["qty_mt"]),
            "qty_mt_after": str(qty_mt_after),
            "credit_limit": str(vendor.credit_limit) if vendor.credit_limit is not None else None,
            "qty_limit_mt": str(vendor.qty_limit_mt) if vendor.qty_limit_mt is not None else None,
            "uom_counted_in_mt": uom == "KG",
            "breaches": breaches,
        }

    issue = Issue(doc_no=next_doc_no(db, "ISS"), destination=body.destination,
                  line_id=body.line_id, vendor_id=body.vendor_id,
                  material_id=material.id, qty=qty, uom=uom, value=value,
                  limit_check=snapshot,
                  status="waiver_pending" if breaches else "posted",
                  client_ref=body.client_ref, created_by=user.id)
    db.add(issue)
    db.flush()

    if breaches:
        # §5.5/§11: blocked — approval + blocker notifications, NO stock, NO outbox.
        approval = Approval(approval_type="credit_waiver", ref_type="issues",
                            ref_id=issue.id, payload=snapshot,
                            required_roles=["management"], status="pending",
                            created_by=user.id)
        db.add(approval)
        db.flush()
        issue.approval_id = approval.id
        _notify_roles(db, ["management"], kind="credit_waiver",
                      title=f"Credit waiver needed for {issue.doc_no} ({vendor.name})",
                      body=f"Limit breach: {', '.join(breaches)} / "
                           f"मर्यादा ओलांडली: {', '.join(breaches)}",
                      ref_type="issues", ref_id=issue.id)
    else:
        _post_movements(db, issue)
        if warned:
            # invariant 11 / ADR-003: posted anyway, registered as a soft anomaly.
            db.add(Anomaly(rule_code="stock_insufficient_warned", severity="soft",
                           ref_type="issues", ref_id=issue.id,
                           observed={"balance": str(chk["balance"]),
                                     "requested": str(qty)},
                           expected={"balance_at_least": str(qty)},
                           message_en="Issue posted with insufficient app stock "
                                      "(parallel run — warn only)",
                           message_mr="अपुऱ्या अ‍ॅप साठ्यासह इश्यू पोस्ट केला "
                                      "(समांतर रन — फक्त इशारा)",
                           status="open"))

    record(db, user_id=user.id, entity="issues", entity_id=issue.id, action="create",
           before=None,
           after={"doc_no": issue.doc_no, "destination": issue.destination,
                  "qty": str(qty), "uom": uom, "value": str(value),
                  "status": issue.status, "stock_warned": warned,
                  "breaches": breaches})
    db.commit()  # invariant 3: everything above or nothing
    db.refresh(issue)
    return issue


# --- credit waiver handlers (engine calls these; it owns the transaction) ---

@on_approve("credit_waiver")
def _apply_credit_waiver(db: Session, approval) -> None:
    issue = db.get(Issue, approval.ref_id)
    if issue is None or issue.status != "waiver_pending":
        return  # idempotent: already applied / cancelled elsewhere
    issue.status = "posted"
    issue.approval_id = approval.id
    _post_movements(db, issue)
    record(db, user_id=None, entity="issues", entity_id=issue.id,
           action="status_change", before={"status": "waiver_pending"},
           after={"status": "posted", "approval_id": approval.id,
                  "via": "credit_waiver"})


@on_reject("credit_waiver")
def _reject_credit_waiver(db: Session, approval) -> None:
    issue = db.get(Issue, approval.ref_id)
    if issue is None or issue.status != "waiver_pending":
        return
    issue.status = "cancelled"
    db.add(Notification(user_id=issue.created_by, kind="credit_waiver_declined",
                        tier="digest",
                        title=f"Credit waiver declined — {issue.doc_no} cancelled",
                        body="Management declined the credit waiver / "
                             "व्यवस्थापनाने क्रेडिट सूट नाकारली",
                        ref_type="issues", ref_id=issue.id))
    record(db, user_id=None, entity="issues", entity_id=issue.id,
           action="status_change", before={"status": "waiver_pending"},
           after={"status": "cancelled", "via": "credit_waiver"})


# --- issue corrections (P27, §11.12) ---

def request_correction(db: Session, user: CurrentUser, issue_id: int,
                       corrected: dict, reason: str) -> IssueCorrection:
    issue = db.get(Issue, issue_id)
    if issue is None:
        raise _error("NOT_FOUND", "Issue not found", "इश्यू सापडला नाही", 404,
                     {"issue_id": issue_id})
    if issue.status != "posted":
        raise _error("ISSUE_NOT_CORRECTABLE",
                     "Only posted issues can be corrected",
                     "फक्त पोस्ट केलेले इश्यूच दुरुस्त करता येतात", 422,
                     {"status": issue.status})
    # JSON columns can't hold Decimal — store qty as str (to_decimal parses it back).
    corrected = {k: (str(v) if isinstance(v, Decimal) else v)
                 for k, v in corrected.items() if v is not None}
    if not corrected:
        raise _error("CORRECTION_EMPTY", "Nothing to correct",
                     "दुरुस्त करण्यासारखे काही नाही", 422, {})
    approval = Approval(approval_type="issue_correction", ref_type="issues",
                        ref_id=issue.id,
                        payload={"corrected": corrected, "reason": reason},
                        required_roles=list(CORRECTION_ROLES), status="pending",
                        created_by=user.id)
    db.add(approval)
    db.flush()
    corr = IssueCorrection(issue_id=issue.id, corrected=corrected, reason=reason,
                           approval_id=approval.id, status="pending")
    db.add(corr)
    db.flush()
    _notify_roles(db, CORRECTION_ROLES, kind="issue_correction",
                  title=f"Issue correction requested on {issue.doc_no}",
                  body=f"{reason} / दुरुस्तीची विनंती",
                  ref_type="issues", ref_id=issue.id)
    record(db, user_id=user.id, entity="issue_corrections", entity_id=corr.id,
           action="create", before=None,
           after={"issue_id": issue.id, "corrected": approval.payload["corrected"],
                  "reason": reason, "approval_id": approval.id})
    db.commit()
    db.refresh(corr)
    return corr


@on_approve("issue_correction")
def _apply_issue_correction(db: Session, approval) -> None:
    corr = (db.query(IssueCorrection)
            .filter_by(approval_id=approval.id).one_or_none())
    if corr is None or corr.status != "pending":
        return  # idempotent
    original = db.get(Issue, corr.issue_id)

    # 1) reversal: negate the ORIGINAL movements verbatim (§11.12). created_by NULL —
    #    system-written; the human actor lives on the approval + audit_log (§4.6).
    originals = (db.query(StockLedger)
                 .filter_by(ref_type="issues", ref_id=original.id)
                 .order_by(StockLedger.id).all())
    for row in originals:
        db.add(StockLedger(material_id=row.material_id, location=row.location,
                           movement=row.movement, qty=-row.qty, uom=row.uom,
                           vendor_id=row.vendor_id, ref_type="issue_correction",
                           ref_id=corr.id, created_by=None))

    # 2) repost: new Issue with corrected values, own ledger + outbox rows.
    corrected = corr.corrected or {}
    material_id = int(corrected.get("material_id", original.material_id))
    material = db.get(Material, material_id)
    qty = to_decimal(corrected.get("qty", original.qty)).quantize(QTY)
    replacement = Issue(
        doc_no=next_doc_no(db, "ISS"),
        destination=corrected.get("destination", original.destination),
        line_id=corrected.get("line_id", original.line_id),
        vendor_id=corrected.get("vendor_id", original.vendor_id),
        material_id=material_id, qty=qty, uom=material.uom,
        value=(qty * to_decimal(material.price or 0)).quantize(MONEY),
        limit_check={"corrected_from": original.id, "correction_id": corr.id},
        status="posted", approval_id=approval.id,
        client_ref=uuid.uuid4(), created_by=approval.created_by)
    db.add(replacement)
    db.flush()
    _post_movements(db, replacement)

    original.status = "corrected"
    corr.status = "applied"
    record(db, user_id=None, entity="issues", entity_id=original.id,
           action="status_change", before={"status": "posted"},
           after={"status": "corrected", "correction_id": corr.id,
                  "replacement_issue_id": replacement.id})


@on_reject("issue_correction")
def _reject_issue_correction(db: Session, approval) -> None:
    corr = (db.query(IssueCorrection)
            .filter_by(approval_id=approval.id).one_or_none())
    if corr is None or corr.status != "pending":
        return
    corr.status = "declined"
    db.add(Notification(user_id=approval.created_by, kind="issue_correction_declined",
                        tier="digest",
                        title="Issue correction declined",
                        body="The correction request was declined / "
                             "दुरुस्तीची विनंती नाकारली गेली",
                        ref_type="issue_corrections", ref_id=corr.id))
    record(db, user_id=None, entity="issue_corrections", entity_id=corr.id,
           action="status_change", before={"status": "pending"},
           after={"status": "declined"})
