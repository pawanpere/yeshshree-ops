"""P07 acceptance: golden-file tests against the REAL SAP exports in data/.
If SAP changes the export layout, these fail loudly (Failure Scenarios #28 analogue)."""
from decimal import Decimal
from pathlib import Path

import pytest
from sqlalchemy.orm import Session

from app.importers import sap_files

DATA = Path(__file__).resolve().parents[2] / "data"

pytestmark = pytest.mark.skipif(
    not (DATA / "1117 material code list.xls").exists(),
    reason="golden files not present (see data/README.md)",
)


def test_materials_golden():
    rows = sap_files.parse_materials(DATA / "1117 material code list.xls")
    assert len(rows) >= 150  # export had ~190 data lines
    by_code = {r["sap_code"]: r for r in rows}
    m = by_code["1101030569"]  # CRCA sheet seen in planning session
    assert m["description"].startswith("CRCA SHEET D TG04")
    assert m["mat_type"] == "ROH"
    assert m["uom"] == "KG"
    assert m["price"] == Decimal("51.00")


def test_bom_golden():
    rows = sap_files.parse_bom(DATA / "1117 bill of material.xls")
    assert rows, "no BOM lines parsed"
    front_mudguard = [r for r in rows if r["bom_no"] == "00005901"]
    assert front_mudguard, "BOM 00005901 (SF Mudguard Assly Front) missing"
    assert {r["component_code"] for r in front_mudguard} >= {"1601010002", "1401010397"}
    scrap = [r for r in front_mudguard if r["component_code"] == "1601010002"][0]
    assert scrap["is_scrap_credit"] and scrap["qty_per"] < 0


def test_grn_golden():
    rows = sap_files.parse_grn_report(DATA / "1117 purchase report.xls")
    assert len(rows) >= 80
    saigan = [r for r in rows if r["vendor_code"] == "10105"]
    assert saigan and saigan[0]["vendor_name"] == "SHREE SAIGAN INDUSTRIES"
    assert all(r["po_no"] for r in saigan)
    tata = [r for r in rows if "TATA" in r["vendor_name"].upper()]
    assert tata and tata[0]["material_desc"].startswith("CRCA SHEET D TG04")


def test_seed_idempotent(engine, monkeypatch):
    """Running seed twice creates zero new rows the second time."""
    import app.importers.seed as seed_mod
    import app.core.db as db_mod
    monkeypatch.setattr(db_mod, "_engine", engine)
    monkeypatch.setattr(db_mod, "_SessionLocal", None)
    monkeypatch.setattr(seed_mod, "get_engine", lambda: engine)

    first = seed_mod.run()
    assert first["materials"] > 100 and first["vendors"] > 3 and first["users"] == len(
        __import__("app.importers.mock", fromlist=["USERS"]).USERS
    )
    second = seed_mod.run()
    assert all(v == 0 for v in second.values()), f"seed not idempotent: {second}"

    with Session(engine) as db:
        from app.models.config_tables import ReasonCode
        from app.models.master import PurchaseOrder
        assert db.query(ReasonCode).filter_by(kind="reject").count() == 6
        assert db.query(PurchaseOrder).count() > 0
