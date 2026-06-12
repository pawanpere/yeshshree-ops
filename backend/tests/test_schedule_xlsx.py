"""Golden tests for the REAL Bajaj schedule format (sample of 2026-06-12) +
the vehicles→parts factor cascade at release."""
import datetime as dt
from decimal import Decimal
from pathlib import Path

import pytest

from app.importers.schedule_xlsx import (normalize_family, parse_line_map,
                                         parse_monthly_plan)

GOLDEN = Path(__file__).resolve().parents[2] / "data" / "bajaj_schedule_sample_may2026.xlsx"

pytestmark = pytest.mark.skipif(not GOLDEN.exists(),
                                reason="golden schedule sample not present")

_CACHE: dict = {}


def _parsed():
    """Parse once per test session — the workbook's 65k-row tracking sheet makes
    each load_workbook call expensive."""
    if "rows" not in _CACHE:
        _CACHE["rows"], _CACHE["errors"] = parse_monthly_plan(str(GOLDEN), "2026-05")
        _CACHE["line_map"] = parse_line_map(str(GOLDEN))
    return _CACHE


def test_monthly_plan_golden():
    c = _parsed()
    rows, errors = c["rows"], c["errors"]
    # the SAME model can appear on both Bajaj lines (RE 4S PETROL on D and E) —
    # index by (model, line) and prove both blocks parsed with carry-forward.
    by_key = {(r["model"], r["line_code"]): r for r in rows}
    d_petrol = by_key[("RE 4S PETROL", "D")]
    e_petrol = by_key[("RE 4S PETROL", "E")]
    assert d_petrol["monthly_req"] == Decimal("15050")
    assert e_petrol["monthly_req"] == Decimal("10906")
    # 4 week buckets with dates from the '(2 to 9)' style ranges
    dates = [b["bucket_date"] for b in d_petrol["buckets"]]
    assert dates == [dt.date(2026, 5, 2), dt.date(2026, 5, 11),
                     dt.date(2026, 5, 18), dt.date(2026, 5, 25)]
    # subtotal/grand rows never leak in
    assert not any(r["model"].lower().startswith(("total", "grand")) for r in rows)
    # line carry-forward inside the E block
    assert by_key[("RE DIESEL OBD 2B", "E")]
    # 4WH-plant-only rows (monthly req 0, net 0) are skipped AND reported
    assert not any(r["model"].startswith("BAJAJ MAXIMA X WIDE DIESEL") for r in rows)
    assert any("skipped" in e for e in errors)


def test_family_normalization():
    assert normalize_family("RE 4S PETROL") == "RE Petrol"
    assert normalize_family("RE 4S CNG Bi-fuel OBD 2B") == "RE CNG"
    assert normalize_family("RE DIESEL OBD 2B") == "RE Diesel"
    assert normalize_family("RE EV 9.2 Kwh WEGO (Wider sc") == "EV GOGO"
    assert normalize_family("RE 4S LPG MF OBD 2B") == "RE LPG"
    # planner override beats defaults (checked first)
    assert normalize_family("BAJAJ MAXIMA Z CNG Bi-fuel",
                            {"MAXIMA": "Maxima"}) == "Maxima"
    # unmatched keeps raw → SPLIT_MISSING sanity surfaces it later
    assert normalize_family("RIKI P4005 (Base)") == "RIKI P4005 (Base)"


def test_line_map_golden():
    rows = _parsed()["line_map"]
    assert len(rows) >= 60
    by_code = {r["sap_code"]: r["line"] for r in rows}
    assert by_code.get("1502040216") == "FRONT MUDGAURD"
    lines = set(by_code.values())
    assert {"CRADEL", "DASH BOARD", "ENG BKT"} <= lines  # Yeshshree's REAL lines


def test_release_explodes_vehicle_lines_via_factors(db):
    """100 vehicles × factor 2 rear-mudguards × 74% split = 148 planned parts."""
    from app.core.deps import CurrentUser
    from app.core.security import hash_password
    from app.models.config_tables import ModelFamilySplit, ModelPartFactor
    from app.models.identity import User
    from app.models.master import Customer, Line, LineMaterial, Material
    from app.models.planning import LinePlan
    from app.services.plans import create_schedule, release

    u = User(username="planner", password_hash=hash_password("x"), full_name="P",
             role="planning", language="en")
    cust = Customer(sap_code="5000", name="Bajaj Auto Ltd")
    part = Material(sap_code="1402999001", description="REAR MUDGUARD ASSY",
                    mat_type="FERT", uom="EA")
    db.add_all([u, cust, part])
    db.flush()
    line = Line(name="REAR MUDGAURD", plant="1117")
    db.add(line)
    db.flush()
    db.add_all([
        LineMaterial(line_id=line.id, material_id=part.id),
        ModelFamilySplit(family="RE Petrol", yesh_pct=74, laxmi_pct=26,
                         effective_from=dt.date(2026, 5, 1)),
        ModelPartFactor(family="RE Petrol", material_id=part.id,
                        qty_per_vehicle=Decimal("2")),
    ])
    db.commit()
    user = CurrentUser(id=u.id, username="planner", role="planning", station=None,
                       vendor_id=None, device_key=None)
    sched = create_schedule(db, user, customer_id=cust.id, period="2026-05",
                            lines=[{"model_family": "RE Petrol",
                                    "bucket_date": "2026-05-02", "qty": "100"}])
    report = release(db, user, sched.id, confirm_warnings=True)
    assert report["plans_created"] == 1 and not report["unmapped"]
    plan = db.query(LinePlan).one()
    assert plan.planned_qty == Decimal("148.000")  # 100 × 2 × 0.74
    assert plan.line_id == line.id and plan.material_id == part.id


def test_release_reports_missing_factor(db):
    from app.core.deps import CurrentUser
    from app.core.security import hash_password
    from app.models.config_tables import ModelFamilySplit
    from app.models.identity import User
    from app.models.master import Customer
    from app.services.plans import create_schedule, release

    u = User(username="planner2", password_hash=hash_password("x"), full_name="P",
             role="planning", language="en")
    cust = Customer(sap_code="5001", name="Bajaj 2")
    db.add_all([u, cust,
                ModelFamilySplit(family="EV GOGO", yesh_pct=0, laxmi_pct=100,
                                 effective_from=dt.date(2026, 5, 1))])
    db.commit()
    user = CurrentUser(id=u.id, username="planner2", role="planning", station=None,
                       vendor_id=None, device_key=None)
    sched = create_schedule(db, user, customer_id=cust.id, period="2026-05",
                            lines=[{"model_family": "EV GOGO",
                                    "bucket_date": "2026-05-02", "qty": "50"}])
    report = release(db, user, sched.id, confirm_warnings=True)
    assert report["plans_created"] == 0
    assert report["unmapped"][0]["reason"] == "no_part_factor"
