"""Approvals engine (P25/P26; Architecture §5.6 + §11.2).

Generic co-approval: an `approvals` row carries `required_roles`; it completes only
when EVERY required role has at least one 'approve' decision. A delegate's decision
counts for the PRINCIPAL's role (`on_behalf_of_user_id`); the delegation validity
window is checked at DECISION time, not grant time (§11.2). Terminal states call the
per-type handlers from services/approval_handlers (APPLY/REJECT registries) INSIDE
the same transaction; a missing handler is a no-op recorded in the audit note.

Decisions (documented per packet brief):
- `create_approval` does NOT commit — it is the engine primitive domain services call
  inside their own transaction (invariant 3). `decide`/`override`/delegation CRUD own
  their commit (they are endpoint-backed).
- inbox shows status in ('pending','hold') — a held approval stays actionable.
- a second decision by a role that already approved is allowed (idempotent coverage:
  the role-set check dedupes); deciding a terminal approval → 409.
- override (§11.2): management/admin only (router guard + service re-check), mandatory
  reason, one transaction: overridden + APPLY + auto `override_review` approval with
  the ORIGINAL required_roles + blocker notifications (CLAUDE.md invariant 12).
"""
import datetime as dt

from sqlalchemy.orm import Session

from app.core.audit import record
from app.core.deps import CurrentUser, _error
from app.models.identity import User
from app.models.workflow import Approval, ApprovalDecision, ApprovalDelegation
from app.services import approval_handlers
from app.services.notifications import create_notification

OPEN_STATUSES = ("pending", "hold")


def _now(now: dt.datetime | None) -> dt.datetime:
    return now if now is not None else dt.datetime.now(dt.timezone.utc)


def _active_delegations(db: Session, today: dt.date, *,
                        delegate_user_id: int | None = None) -> list[ApprovalDelegation]:
    q = db.query(ApprovalDelegation).filter(
        ApprovalDelegation.is_active.is_(True),
        ApprovalDelegation.valid_from <= today,
        ApprovalDelegation.valid_to >= today,
    )
    if delegate_user_id is not None:
        q = q.filter(ApprovalDelegation.delegate_user_id == delegate_user_id)
    return q.all()


def approval_recipients(db: Session, required_roles: list,
                        approval_type: str | None = None,
                        now: dt.datetime | None = None) -> list[User]:
    """Active users whose role is required, PLUS active delegates of such role-holders
    (delegation type filter respected, window checked against `now`)."""
    today = _now(now).date()
    recipients: dict[int, User] = {
        u.id: u for u in db.query(User)
        .filter(User.is_active.is_(True), User.role.in_(list(required_roles))).all()
    }
    for d in _active_delegations(db, today):
        if d.approval_type is not None and approval_type is not None \
                and d.approval_type != approval_type:
            continue
        principal = db.get(User, d.principal_user_id)
        if principal is None or not principal.is_active \
                or principal.role not in required_roles:
            continue
        delegate = db.get(User, d.delegate_user_id)
        if delegate is not None and delegate.is_active:
            recipients[delegate.id] = delegate
    return list(recipients.values())


def create_approval(db: Session, *, approval_type: str, ref_type: str, ref_id: int,
                    payload: dict, required_roles: list, created_by: int,
                    now: dt.datetime | None = None) -> Approval:
    """Engine primitive — NO commit; joins the caller's transaction (§5.6)."""
    if not required_roles:
        raise _error("APPROVAL_ROLES_REQUIRED", "Approval needs at least one role",
                     "मंजुरीसाठी किमान एक भूमिका आवश्यक आहे", 422, {})
    now = _now(now)
    approval = Approval(approval_type=approval_type, ref_type=ref_type, ref_id=ref_id,
                        payload=payload, required_roles=list(required_roles),
                        status="pending", created_by=created_by)
    db.add(approval)
    db.flush()  # need the id for the notification ref
    for u in approval_recipients(db, required_roles, approval_type, now=now):
        create_notification(db, user_id=u.id, kind="approval_request", tier="blocker",
                            title=f"Approval needed: {approval_type}",
                            body=f"{ref_type} #{ref_id} awaits your decision",
                            ref_type="approvals", ref_id=approval.id, now=now)
    return approval


def inbox(db: Session, user: CurrentUser,
          now: dt.datetime | None = None) -> list[Approval]:
    """Open approvals the caller can act on — own role OR via active delegation
    (principal's role is what matters, resolved here; §11.2)."""
    today = _now(now).date()
    delegated: list[tuple[str, str | None]] = []  # (principal_role, type filter)
    for d in _active_delegations(db, today, delegate_user_id=user.id):
        principal = db.get(User, d.principal_user_id)
        if principal is not None and principal.is_active:
            delegated.append((principal.role, d.approval_type))
    rows = (db.query(Approval).filter(Approval.status.in_(OPEN_STATUSES))
            .order_by(Approval.id.desc()).all())
    out = []
    for ap in rows:
        if user.role in ap.required_roles or any(
                pr in ap.required_roles and (t is None or t == ap.approval_type)
                for pr, t in delegated):
            out.append(ap)
    return out


def _acting_capacity(db: Session, user: CurrentUser, approval: Approval,
                     now: dt.datetime) -> tuple[str, int | None]:
    """(role the decision counts for, on_behalf_of principal id or None) — or 403."""
    if user.role in approval.required_roles:
        return user.role, None
    for d in _active_delegations(db, now.date(), delegate_user_id=user.id):
        if d.approval_type is not None and d.approval_type != approval.approval_type:
            continue
        principal = db.get(User, d.principal_user_id)
        if principal is not None and principal.is_active \
                and principal.role in approval.required_roles:
            return principal.role, principal.id
    raise _error("NOT_AN_APPROVER",
                 "You are not an approver for this request (no role or valid delegation)",
                 "तुम्ही या विनंतीचे मंजूरकर्ते नाही (भूमिका किंवा वैध प्रतिनिधित्व नाही)", 403,
                 {"approval_id": approval.id, "required_roles": list(approval.required_roles)})


def _get_open_approval(db: Session, approval_id: int) -> Approval:
    approval = db.get(Approval, approval_id)
    if approval is None:
        raise _error("NOT_FOUND", "Approval not found", "मंजुरी विनंती सापडली नाही", 404,
                     {"approval_id": approval_id})
    if approval.status not in OPEN_STATUSES:
        raise _error("APPROVAL_ALREADY_DECIDED",
                     f"Approval is already {approval.status}",
                     "मंजुरी विनंतीवर आधीच निर्णय झाला आहे", 409,
                     {"approval_id": approval_id, "status": approval.status})
    return approval


def _run_handler(db: Session, registry: dict, approval: Approval) -> str:
    """Handler runs INSIDE this transaction; missing handler = no-op, audit-noted."""
    handler = registry.get(approval.approval_type)
    if handler is None:
        return "missing"
    handler(db, approval)
    return "ran"


def _approved_roles(db: Session, approval: Approval) -> set[str]:
    """Roles covered by ≥1 approve decision; a delegate's decision counts for the
    PRINCIPAL's role."""
    covered: set[str] = set()
    decisions = (db.query(ApprovalDecision)
                 .filter_by(approval_id=approval.id, decision="approve").all())
    for d in decisions:
        actor = db.get(User, d.on_behalf_of_user_id or d.user_id)
        if actor is not None:
            covered.add(actor.role)
    return covered


def decide(db: Session, user: CurrentUser, approval_id: int, decision: str,
           note: str | None = None) -> Approval:
    if decision not in ("approve", "decline", "hold"):
        raise _error("DECISION_INVALID", "Decision must be approve, decline or hold",
                     "निर्णय approve, decline किंवा hold असावा", 422,
                     {"decision": decision})
    approval = _get_open_approval(db, approval_id)
    now = dt.datetime.now(dt.timezone.utc)
    acting_role, on_behalf_of = _acting_capacity(db, user, approval, now)
    before_status = approval.status
    db.add(ApprovalDecision(approval_id=approval.id, user_id=user.id,
                            decision=decision, note=note, decided_at=now,
                            on_behalf_of_user_id=on_behalf_of))
    db.flush()

    handler_result = None
    if decision == "decline":  # any decline is terminal (§5.6)
        approval.status = "declined"
        approval.decided_at = now
        handler_result = _run_handler(db, approval_handlers.REJECT, approval)
    elif decision == "hold":
        approval.status = "hold"  # stays in the inbox
    else:  # approve — complete only when EVERY required role has approved
        if set(approval.required_roles) <= _approved_roles(db, approval):
            approval.status = "approved"
            approval.decided_at = now
            handler_result = _run_handler(db, approval_handlers.APPLY, approval)

    record(db, user_id=user.id, entity="approvals", entity_id=approval.id,
           action="decision", before={"status": before_status},
           after={"status": approval.status, "decision": decision,
                  "acting_role": acting_role, "on_behalf_of_user_id": on_behalf_of,
                  "note": note, "handler": handler_result})
    db.commit()
    db.refresh(approval)
    return approval


def override(db: Session, user: CurrentUser, approval_id: int, reason: str) -> Approval:
    """§11.2 emergency override — ONE transaction: overridden + APPLY + post-facto
    override_review approval (invariant 12) + blocker notifications."""
    if user.role not in ("management", "admin"):  # belt: router also guards
        raise _error("FORBIDDEN", "Only management/admin may override",
                     "फक्त व्यवस्थापन/प्रशासक ओव्हरराइड करू शकतात", 403,
                     {"required": ["management", "admin"]})
    if not (reason or "").strip():
        raise _error("OVERRIDE_REASON_REQUIRED", "Override needs a reason",
                     "ओव्हरराइडसाठी कारण आवश्यक आहे", 422, {})
    approval = _get_open_approval(db, approval_id)
    now = dt.datetime.now(dt.timezone.utc)
    before_status = approval.status
    approval.status = "overridden"
    approval.decided_at = now
    approval.overridden_by = user.id
    approval.override_reason = reason
    handler_result = _run_handler(db, approval_handlers.APPLY, approval)
    review = create_approval(  # post-facto sign-off by the ORIGINAL roles
        db, approval_type="override_review", ref_type="approvals", ref_id=approval.id,
        payload={"original_approval_id": approval.id, "reason": reason},
        required_roles=list(approval.required_roles), created_by=user.id, now=now)
    # audit_log CHECK allows no 'override' action — 'status_change' carries the detail
    record(db, user_id=user.id, entity="approvals", entity_id=approval.id,
           action="status_change", before={"status": before_status},
           after={"status": "overridden", "override": True, "reason": reason,
                  "handler": handler_result, "override_review_id": review.id})
    db.commit()
    db.refresh(approval)
    return approval


# --- delegations CRUD (§11.2) ---

def create_delegation(db: Session, user: CurrentUser, *, principal_user_id: int,
                      delegate_user_id: int, approval_type: str | None,
                      valid_from: dt.date, valid_to: dt.date) -> ApprovalDelegation:
    if user.role != "admin" and principal_user_id != user.id:
        raise _error("DELEGATION_NOT_PRINCIPAL",
                     "You can only delegate your own approval authority",
                     "तुम्ही फक्त स्वतःचे मंजुरी अधिकार सोपवू शकता", 403,
                     {"principal_user_id": principal_user_id})
    if principal_user_id == delegate_user_id:
        raise _error("DELEGATION_SELF", "Cannot delegate to yourself",
                     "स्वतःलाच प्रतिनिधित्व देता येत नाही", 422, {})
    if valid_from > valid_to:
        raise _error("DELEGATION_WINDOW_INVALID", "valid_from must be on/before valid_to",
                     "valid_from ही valid_to च्या आधी/त्याच दिवशी असावी", 422,
                     {"valid_from": str(valid_from), "valid_to": str(valid_to)})
    for uid, label in ((principal_user_id, "principal"), (delegate_user_id, "delegate")):
        u = db.get(User, uid)
        if u is None or not u.is_active:
            raise _error("NOT_FOUND", f"{label} user not found or inactive",
                         "वापरकर्ता सापडला नाही किंवा निष्क्रिय आहे", 404,
                         {"user_id": uid, "which": label})
    row = ApprovalDelegation(principal_user_id=principal_user_id,
                             delegate_user_id=delegate_user_id,
                             approval_type=approval_type, valid_from=valid_from,
                             valid_to=valid_to, created_by=user.id, is_active=True)
    db.add(row)
    db.flush()
    record(db, user_id=user.id, entity="approval_delegations", entity_id=row.id,
           action="create", before=None,
           after={"principal_user_id": principal_user_id,
                  "delegate_user_id": delegate_user_id,
                  "approval_type": approval_type,
                  "valid_from": str(valid_from), "valid_to": str(valid_to)})
    db.commit()
    db.refresh(row)
    return row


def list_delegations(db: Session, user: CurrentUser) -> list[ApprovalDelegation]:
    q = db.query(ApprovalDelegation)
    if user.role not in ("admin", "management"):
        q = q.filter((ApprovalDelegation.principal_user_id == user.id)
                     | (ApprovalDelegation.delegate_user_id == user.id))
    return q.order_by(ApprovalDelegation.id.desc()).all()


def deactivate_delegation(db: Session, user: CurrentUser,
                          delegation_id: int) -> ApprovalDelegation:
    """Soft deactivate — rows are never deleted (CLAUDE.md never-do)."""
    row = db.get(ApprovalDelegation, delegation_id)
    if row is None:
        raise _error("NOT_FOUND", "Delegation not found", "प्रतिनिधित्व सापडले नाही", 404,
                     {"delegation_id": delegation_id})
    if user.role != "admin" and row.principal_user_id != user.id:
        raise _error("DELEGATION_NOT_PRINCIPAL",
                     "Only the principal or an admin can deactivate a delegation",
                     "फक्त मूळ अधिकारी किंवा प्रशासक प्रतिनिधित्व निष्क्रिय करू शकतात", 403,
                     {"delegation_id": delegation_id})
    if row.is_active:
        row.is_active = False
        record(db, user_id=user.id, entity="approval_delegations", entity_id=row.id,
               action="update", before={"is_active": True}, after={"is_active": False})
        db.commit()
        db.refresh(row)
    return row
