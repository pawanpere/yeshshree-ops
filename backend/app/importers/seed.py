"""Seed the database from the REAL SAP exports in data/ + mock config (importers/mock.py).

Idempotent: keyed upserts (sap_code / username / code / key) — safe to re-run any time;
`python -m app.importers.seed --reset` drops and recreates first (dev only).
On SQLite (sandbox dev) tables are created via metadata; on Postgres, Alembic owns DDL.

Run: make seed   (DATA_DIR env var overrides the default ../data)
"""
import os
import sys
from datetime import date
from decimal import Decimal
from pathlib import Path

from sqlalchemy.orm import Session

from app.core.db import get_engine
from app.core.security import hash_password
from app.importers import mock, sap_files
from app.models import Base
from app.models.config_tables import (AppSetting, DocSequence, MaterialGroupTolerance,
                                      Mill, ModelFamilySplit, PlanCalendar, ReasonCode)
from app.models.identity import StationDevice, User
from app.models.master import (Bom, BomLine, Customer, Line, LineMaterial, Material,
                               ProductionOrder, PurchaseOrder, Vendor)

DATA_DIR = Path(os.environ.get("DATA_DIR", Path(__file__).resolve().parents[3] / "data"))

FILES = {
    "materials": DATA_DIR / "1117 material code list.xls",
    "bom": DATA_DIR / "1117 bill of material.xls",
    "grn": DATA_DIR / "1117 purchase report.xls",
}


def _get_or_create(db: Session, model, defaults: dict | None = None, **keys):
    obj = db.query(model).filter_by(**keys).one_or_none()
    if obj is None:
        obj = model(**keys, **(defaults or {}))
        db.add(obj)
        db.flush()
        return obj, True
    return obj, False


def seed_materials(db: Session) -> int:
    n = 0
    for row in sap_files.parse_materials(FILES["materials"]):
        _, created = _get_or_create(
            db, Material, sap_code=row["sap_code"],
            defaults=dict(description=row["description"], mat_type=row["mat_type"] or "ROH",
                          mat_group=row["mat_group"] or None, uom=row["uom"] or "EA",
                          price=row["price"], abc=row["abc"]),
        )
        n += created
    return n


def seed_boms(db: Session) -> int:
    """Group component lines by (bom_no, parent). Components missing from the material
    master become source='manual' stubs (Architecture §11.15) — reconciled on next import."""
    rows = sap_files.parse_bom(FILES["bom"])
    n = 0
    by_parent: dict[tuple[str, str], list[dict]] = {}
    for r in rows:
        by_parent.setdefault((r["bom_no"], r["parent_code"]), []).append(r)
    for (bom_no, parent_code), lines in by_parent.items():
        parent, _ = _get_or_create(
            db, Material, sap_code=parent_code,
            defaults=dict(description=lines[0]["parent_desc"], mat_type="FERT",
                          uom="EA", source="manual"),
        )
        bom, created = _get_or_create(
            db, Bom, parent_material_id=parent.id,
            defaults=dict(alt_bom=lines[0]["alt_bom"] or "1"),
        )
        if not created:
            continue
        for ln in lines:
            comp, _ = _get_or_create(
                db, Material, sap_code=ln["component_code"],
                defaults=dict(description=ln["component_desc"], mat_type="ROH",
                              uom=ln["uom"] or "EA", source="manual"),
            )
            db.add(BomLine(bom_id=bom.id, component_material_id=comp.id,
                           item_no=ln["item_no"], qty_per=ln["qty_per"], uom=ln["uom"],
                           is_scrap_credit=ln["is_scrap_credit"]))
        n += 1
    return n


def seed_vendors_and_pos(db: Session) -> tuple[int, int]:
    """Vendors + open POs derived from the real GRN history: real codes, names, PO numbers
    and rates; ordered/open quantities are mock (real open POs arrive via SFTP later)."""
    rows = sap_files.parse_grn_report(FILES["grn"])
    nv = npo = 0
    po_lines: dict[tuple[str, str], dict] = {}
    for r in rows:
        if not r["vendor_code"]:
            continue
        vendor, created = _get_or_create(
            db, Vendor, sap_code=r["vendor_code"],
            defaults=dict(name=r["vendor_name"],
                          credit_limit=Decimal(mock.DEFAULT_VENDOR_LIMITS["credit_limit"]),
                          qty_limit_mt=Decimal(mock.DEFAULT_VENDOR_LIMITS["qty_limit_mt"])),
        )
        nv += created
        if r["po_no"] and r["material_code"]:
            key = (r["po_no"], r["material_code"])
            entry = po_lines.setdefault(key, dict(vendor_id=vendor.id, rate=r["po_rate"],
                                                  uom=r["uom"], total=Decimal(0)))
            entry["total"] += r["received_qty"] or Decimal(0)
            entry["rate"] = r["po_rate"] or entry["rate"]
    item_counters: dict[str, int] = {}
    for (po_no, mat_code), e in sorted(po_lines.items()):
        mat = db.query(Material).filter_by(sap_code=mat_code).one_or_none()
        if mat is None:
            continue
        ordered = e["total"] * Decimal(2)  # mock: history ×2 ordered, half still open
        # One real PO covers several materials → item_no sequences per PO
        # (UQ is (sap_po_no, item_no); found by golden-file test on real data, 2026-06-11).
        existing = db.query(PurchaseOrder).filter_by(sap_po_no=po_no, material_id=mat.id).one_or_none()
        if existing is not None:
            continue
        item_counters[po_no] = item_counters.get(
            po_no, db.query(PurchaseOrder).filter_by(sap_po_no=po_no).count()
        ) + 1
        db.add(PurchaseOrder(sap_po_no=po_no, item_no=item_counters[po_no],
                             material_id=mat.id, vendor_id=e["vendor_id"],
                             ordered_qty=ordered, open_qty=e["total"], rate=e["rate"],
                             uom=e["uom"], status="open"))
        db.flush()
        npo += 1
    return nv, npo


def seed_lines_and_orders(db: Session) -> int:
    parents = [b for b in db.query(Material).join(Bom, Bom.parent_material_id == Material.id)
               .order_by(Material.sap_code).all()]
    n = 0
    for i, name in enumerate(mock.LINES):
        line, created = _get_or_create(db, Line, name=name, defaults=dict(plant="1117"))
        n += created
        mat = parents[i % len(parents)] if parents else None
        if mat is not None:
            _get_or_create(db, LineMaterial, line_id=line.id, material_id=mat.id)
            _get_or_create(db, ProductionOrder, sap_order_no=mock.PRODUCTION_ORDERS[name],
                           defaults=dict(line_id=line.id, material_id=mat.id, status="released"))
    return n


def seed_config(db: Session) -> None:
    for code, en, mr in mock.REJECT_REASONS:
        _get_or_create(db, ReasonCode, code=code,
                       defaults=dict(kind="reject", label_en=en, label_mr=mr, sort=0))
    for code, en, mr in mock.DOWNTIME_REASONS:
        _get_or_create(db, ReasonCode, code=code,
                       defaults=dict(kind="downtime", label_en=en, label_mr=mr, sort=0))
    for family, y, l in mock.SPLITS:
        _get_or_create(db, ModelFamilySplit, family=family,
                       defaults=dict(yesh_pct=y, laxmi_pct=l, effective_from=date(2026, 6, 1)))
    for name, lead, moq, sourcing in mock.MILLS:
        _get_or_create(db, Mill, name=name,
                       defaults=dict(lead_days=lead, moq_mt=moq, sourcing=sourcing))
    for group, uom, pct in mock.TOLERANCES:
        _get_or_create(db, MaterialGroupTolerance, mat_group=group, uom=uom,
                       defaults=dict(pct_tolerance=Decimal(pct)))
    for key, value in mock.APP_SETTINGS.items():
        _get_or_create(db, AppSetting, key=key, defaults=dict(value=value))
    for doc_type in ("G", "GR", "ISS", "DN", "RGP"):
        _get_or_create(db, DocSequence, doc_type=doc_type, fiscal_year="2026-27")
    # June 2026 calendar: Mon–Sat working, two shifts (app map; refined in admin screen)
    for day in range(1, 31):
        d = date(2026, 6, day)
        _get_or_create(db, PlanCalendar, cal_date=d,
                       defaults=dict(is_working=d.weekday() != 6,
                                     shifts={"A": "06:00-14:30", "B": "14:30-23:00"}))


def seed_users(db: Session) -> int:
    n = 0
    pw = hash_password("demo1234")
    for username, full_name, role, station, lang in mock.USERS:
        _, created = _get_or_create(
            db, User, username=username,
            defaults=dict(password_hash=pw, pin_hash=hash_password("1234"),
                          full_name=full_name, role=role, station=station, language=lang),
        )
        n += created
    admin = db.query(User).filter_by(username="admin").one()
    _get_or_create(db, StationDevice, device_key="gate-kiosk-1",
                   defaults=dict(station="gate", label="Main gate kiosk",
                                 registered_by=admin.id))
    return n


def run(reset: bool = False) -> dict:
    engine = get_engine()
    if reset or engine.dialect.name == "sqlite":
        Base.metadata.create_all(engine)  # PG schema is Alembic's job; this is dev/sandbox
    with Session(engine) as db:
        stats = {}
        stats["materials"] = seed_materials(db)
        stats["boms"] = seed_boms(db)
        stats["vendors"], stats["purchase_orders"] = seed_vendors_and_pos(db)
        stats["lines"] = seed_lines_and_orders(db)
        seed_config(db)
        stats["users"] = seed_users(db)
        db.commit()
    return stats


if __name__ == "__main__":
    stats = run(reset="--reset" in sys.argv)
    print("Seed complete (new rows):", stats)
