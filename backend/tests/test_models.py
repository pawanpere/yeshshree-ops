"""P03 acceptance: full schema materialises; CHECKs + idempotency uniqueness enforce.
SQLite enforces CHECK constraints and unique indexes, so these run in verify-lite."""
import uuid
from decimal import Decimal

import pytest
from sqlalchemy.exc import IntegrityError

from app.models import Base
from app.models.identity import User
from app.models.master import Material, Vendor
from app.models.inventory import StockLedger
from app.models.workflow import Approval

EXPECTED_TABLES = {
    # §4.1
    "users", "station_devices", "auth_sessions", "otp_codes",
    # §4.2
    "vendors", "materials", "boms", "bom_lines", "purchase_orders",
    "lines", "line_materials", "production_orders", "customers",
    # §4.3 + §11.7
    "model_family_splits", "model_part_factors", "reason_codes", "mills",
    "plan_calendar", "app_settings", "doc_sequences", "material_group_tolerances",
    # §4.4
    "schedules", "schedule_lines", "line_plans", "vendor_calloffs",
    # §4.5 + §11.9
    "files", "gate_scans", "gate_entries", "return_gate_passes",
    # §4.6 + §11.12
    "goods_receipts", "debit_notes", "stock_ledger", "issues", "issue_corrections",
    # §4.7 + §11.10/11.11
    "production_confirmations", "confirmation_corrections", "shift_contexts",
    "confirmation_holds", "dispatches", "dispatch_lines",
    "sales_invoices", "sales_invoice_lines",
    # §4.8 + §11.2/11.8/11.4
    "approvals", "approval_decisions", "approval_delegations", "anomalies",
    "notifications", "escalation_rules", "escalation_events",
    "audit_log", "sap_outbox", "sap_export_batches", "import_jobs", "station_status",
}


def test_every_architecture_table_exists(engine):
    assert set(Base.metadata.tables.keys()) == EXPECTED_TABLES


def test_role_check_constraint_rejects_bad_role(db):
    db.add(User(username="x", password_hash="h", full_name="X", role="hacker"))
    with pytest.raises(IntegrityError):
        db.commit()


def test_status_check_on_approvals(db):
    db.add(Approval(approval_type="credit_waiver", ref_type="issues", ref_id=1,
                    payload={}, required_roles=["management"], status="bogus", created_by=None))
    with pytest.raises(IntegrityError):
        db.commit()


def test_signed_stock_ledger_roundtrip(db):
    m = Material(sap_code="1101030569", description="CRCA SHEET D TG04", mat_type="ROH", uom="KG")
    db.add(m)
    db.commit()
    db.add_all([
        StockLedger(plant="1117", material_id=m.id, location="RM", movement="GR_IN",
                    qty=Decimal("100.000"), uom="KG", ref_type="goods_receipts", ref_id=1),
        StockLedger(plant="1117", material_id=m.id, location="RM", movement="ISSUE_OUT",
                    qty=Decimal("-40.000"), uom="KG", ref_type="issues", ref_id=1),
    ])
    db.commit()
    total = sum(r.qty for r in db.query(StockLedger).all())
    assert total == Decimal("60.000")


def test_vendor_source_default_is_sap_import(db):
    v = Vendor(sap_code="10105", name="SHREE SAIGAN INDUSTRIES")
    db.add(v)
    db.commit()
    assert v.source == "sap_import"
