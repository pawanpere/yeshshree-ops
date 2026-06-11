"""P10 acceptance: CRUD round-trips, role guards, manual-source creates,
audit diffs on every change, no delete routes anywhere."""
import pytest
from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.models.identity import User
from app.models.master import Material
from app.models.system import AuditLog
import app.core.db as db_mod


@pytest.fixture()
def client(engine, db):
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    db.add_all([
        User(username="admin", password_hash=hash_password("a"), full_name="A",
             role="admin", language="en"),
        User(username="gate1", password_hash=hash_password("g"), full_name="G",
             role="plant_ops", station="gate", language="mr"),
        User(username="v1", password_hash=hash_password("v"), full_name="V",
             role="vendor", language="en"),
    ])
    db.add(Material(sap_code="1101030569", description="CRCA SHEET D TG04",
                    mat_type="ROH", mat_group="1103", uom="KG"))
    db.commit()
    from app.main import app
    yield TestClient(app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def _token(client, username, password):
    r = client.post("/api/v1/auth/login", json={"username": username, "password": password})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_role_matrix(client):
    admin, gate, vendor = (_token(client, u, p) for u, p in
                           [("admin", "a"), ("gate1", "g"), ("v1", "v")])
    assert client.get("/api/v1/master/materials", headers=gate).status_code == 200
    assert client.get("/api/v1/master/materials", headers=vendor).status_code == 403
    body = {"sap_code": "TMP-001", "description": "Temp part", "uom": "EA"}
    assert client.post("/api/v1/master/materials", json=body, headers=gate).status_code == 403
    assert client.post("/api/v1/master/materials", json=body, headers=admin).status_code == 201


def test_manual_source_on_admin_create(client, db):
    admin = _token(client, "admin", "a")
    r = client.post("/api/v1/master/materials", headers=admin,
                    json={"sap_code": "TMP-002", "description": "Urgent new part", "uom": "EA"})
    assert r.json()["source"] == "manual"  # §11.15: importer reconciles it later


def test_update_audited_with_field_diff(client, db):
    admin = _token(client, "admin", "a")
    vid = client.post("/api/v1/master/vendors", headers=admin,
                      json={"sap_code": "V-900", "name": "Test Vendor",
                            "credit_limit": "1400000.00"}).json()["id"]
    client.patch(f"/api/v1/master/vendors/{vid}", headers=admin,
                 json={"credit_limit": "1650000.00"})
    row = (db.query(AuditLog).filter_by(entity="vendors", entity_id=vid, action="update")
           .one())
    assert row.before["credit_limit"] == "1400000.00"
    assert row.after["credit_limit"] == "1650000.00"


def test_immutable_field_rejected(db):
    """Two layers protect sap_code: it's absent from update schemas (pydantic drops it)
    AND apply_update's allowed-set raises if a future schema mistakenly includes it."""
    from fastapi import HTTPException
    from app.core.deps import CurrentUser
    from app.services.master import apply_update
    mat = db.query(Material).first() or Material(
        sap_code="X1", description="d", mat_type="ROH", uom="EA")
    db.add(mat)
    db.commit()
    user = CurrentUser(id=1, username="admin", role="admin", station=None,
                       vendor_id=None, device_key=None)
    with pytest.raises(HTTPException) as exc:
        apply_update(db, mat, {"sap_code": "HACKED"}, user, "materials",
                     allowed={"description"})
    assert exc.value.detail["code"] == "FIELD_NOT_EDITABLE"
    assert db.query(Material).filter_by(sap_code="HACKED").count() == 0


def test_split_must_total_100(client):
    admin = _token(client, "admin", "a")
    r = client.post("/api/v1/config/splits", headers=admin,
                    json={"family": "RE Max UG", "yesh_pct": 60, "laxmi_pct": 30,
                          "effective_from": "2026-07-01"})
    assert r.status_code == 422 and r.json()["detail"]["code"] == "SPLIT_NOT_100"
    ok = client.post("/api/v1/config/splits", headers=admin,
                     json={"family": "RE Max UG", "yesh_pct": 70, "laxmi_pct": 30,
                           "effective_from": "2026-07-01"})
    assert ok.status_code == 201


def test_settings_put_audited(client, db):
    admin = _token(client, "admin", "a")
    from app.models.config_tables import AppSetting
    db.add(AppSetting(key="ops_mode", value={"mode": "parallel_run"}))
    db.commit()
    r = client.put("/api/v1/config/settings/ops_mode", headers=admin,
                   json={"value": {"mode": "authoritative"}})
    assert r.status_code == 200
    row = db.query(AuditLog).filter_by(entity="app_settings", action="update").one()
    assert row.before["value"] == {"mode": "parallel_run"}


def test_line_materials_put(client, db):
    admin = _token(client, "admin", "a")
    line_id = client.post("/api/v1/master/lines", headers=admin,
                          json={"name": "Front Body"}).json()["id"]
    mat_id = db.query(Material).first().id
    r = client.put(f"/api/v1/master/lines/{line_id}/materials", headers=admin,
                   json={"material_ids": [mat_id]})
    assert r.json()["material_ids"] == [mat_id]
    r2 = client.put(f"/api/v1/master/lines/{line_id}/materials", headers=admin,
                    json={"material_ids": []})
    assert r2.json()["material_ids"] == []


def test_no_delete_routes_exist(client):
    """CLAUDE.md never-do: master data is never deleted. Guard the whole router."""
    from app.main import app
    for route in app.routes:
        methods = getattr(route, "methods", set()) or set()
        assert "DELETE" not in methods, f"DELETE route found: {route.path}"
