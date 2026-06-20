"""Phase 4: material stock category (rm/component/fg), COMP stock location,
job_work_return inward category.

Revision ID: 0001_material_category
Revises:
Create Date: 2026-06-20

NOTE ON BASELINE: this repo does not yet keep an Alembic baseline — the schema is
currently materialised from the SQLAlchemy models via `Base.metadata.create_all`
(tests + dev seed). This migration is the hand-authored DIFF for the Phase 4 change,
to be reconciled on the dev machine where `make migration` autogenerates against a
real Postgres baseline (CLAUDE.md). It assumes the base tables already exist. The
models in app/models/ are the source of truth and already carry these changes.
"""
from alembic import op
import sqlalchemy as sa

revision = "0001_material_category"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1) materials.category — plant stock-routing class, distinct from SAP mat_type.
    op.add_column(
        "materials",
        sa.Column("category", sa.Text(), nullable=False, server_default="rm"),
    )
    # Backfill: finished goods → fg; everything else keeps the 'rm' default. Purchased
    # parts are re-tagged 'component' via admin/import (no reliable SAP signal).
    op.execute("UPDATE materials SET category = 'fg' WHERE mat_type = 'FERT'")
    op.create_check_constraint(
        "category_valid", "materials", "category IN ('rm','component','fg')"
    )

    # 2) stock_ledger.location — add the COMP store for components.
    op.drop_constraint("location_valid", "stock_ledger", type_="check")
    op.create_check_constraint(
        "location_valid", "stock_ledger",
        "location IN ('RM','COMP','WIP','FG','AT_VENDOR')",
    )

    # 3) gate_entries.inward_category — add job_work_return.
    op.drop_constraint("inward_category_valid", "gate_entries", type_="check")
    op.create_check_constraint(
        "inward_category_valid", "gate_entries",
        "inward_category IN "
        "('po_supply','customer_return','consumable','repair','job_work_return')",
    )


def downgrade() -> None:
    op.drop_constraint("inward_category_valid", "gate_entries", type_="check")
    op.create_check_constraint(
        "inward_category_valid", "gate_entries",
        "inward_category IN ('po_supply','customer_return','consumable','repair')",
    )

    op.drop_constraint("location_valid", "stock_ledger", type_="check")
    op.create_check_constraint(
        "location_valid", "stock_ledger",
        "location IN ('RM','WIP','FG','AT_VENDOR')",
    )

    op.drop_constraint("category_valid", "materials", type_="check")
    op.drop_column("materials", "category")
