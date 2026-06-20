"""Phase 5: admin user + station-device management. Admin-only; passwords/PINs are
hashed and never read back; changes are audited; no deletes (deactivate)."""
import uuid

import pytest
from fastapi.testclient import TestClient

from app.core.security import hash_password, verify_password
from app.models.identity import StationDevice, User
from app.models.system import AuditLog
import app.core.db as db_mod


@pytest.fixture()
def client(engine, db):
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False,
                                        expire_on_commit=False)
    db.add_all([
        User(username="admin", password_hash=hash_password("a"), full_name="A",
             role="admin", language="en"),
        User(username="boss", password_hash=hash_password("b"), full_name="B",
             role="management", language="en"),
    ])
    db.commit()
    from app.main import app
    yield TestClient(app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def _token(client, u, p):
    r = client.post("/api/v1/auth/login", json={"username": u, "password": p})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_only_admin_can_manage_users(client):
    boss = _token(client, "boss", "b")
    assert client.get("/api/v1/master/users", headers=boss).status_code == 403
    r = client.get("/api/v1/master/users", headers=_token(client, "admin", "a"))
    assert r.status_code == 200
    assert {u["username"] for u in r.json()} == {"admin", "boss"}


def test_create_user_hashes_password_and_pin_and_can_login(client, db):
    admin = _token(client, "admin", "a")
    r = client.post("/api/v1/master/users", headers=admin, json={
        "username": "gate1", "full_name": "Gate One", "role": "plant_ops",
        "station": "gate", "password": "secret", "pin": "4321", "language": "mr"})
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["has_pin"] is True
    assert "password" not in body and "password_hash" not in body
    u = db.query(User).filter_by(username="gate1").one()
    assert u.password_hash != "secret" and verify_password("secret", u.password_hash)
    assert verify_password("4321", u.pin_hash)
    # the new user can actually authenticate
    assert client.post("/api/v1/auth/login",
                       json={"username": "gate1", "password": "secret"}).status_code == 200


def test_duplicate_username_conflicts(client):
    admin = _token(client, "admin", "a")
    body = {"username": "dup", "full_name": "D", "role": "supervisor", "password": "x"}
    assert client.post("/api/v1/master/users", headers=admin, json=body).status_code == 201
    r2 = client.post("/api/v1/master/users", headers=admin, json=body)
    assert r2.status_code == 409
    assert r2.json()["detail"]["code"] == "ALREADY_EXISTS"


def test_invalid_role_rejected(client):
    admin = _token(client, "admin", "a")
    r = client.post("/api/v1/master/users", headers=admin, json={
        "username": "bad", "full_name": "B", "role": "wizard", "password": "x"})
    assert r.status_code == 422  # pydantic Literal rejects the unknown role


def test_update_user_rehashes_password_and_audits_role(client, db):
    admin = _token(client, "admin", "a")
    uid = client.post("/api/v1/master/users", headers=admin, json={
        "username": "u2", "full_name": "U Two", "role": "supervisor",
        "password": "old"}).json()["id"]
    r = client.patch(f"/api/v1/master/users/{uid}", headers=admin,
                     json={"role": "planning", "password": "new"})
    assert r.status_code == 200 and r.json()["role"] == "planning"
    u = db.get(User, uid)
    assert verify_password("new", u.password_hash)
    assert not verify_password("old", u.password_hash)
    assert db.query(AuditLog).filter_by(entity="users", entity_id=uid,
                                        action="update").count() >= 1


def test_deactivate_user_hides_from_default_list(client, db):
    admin = _token(client, "admin", "a")
    uid = client.post("/api/v1/master/users", headers=admin, json={
        "username": "leaver", "full_name": "L", "role": "supervisor",
        "password": "x"}).json()["id"]
    client.patch(f"/api/v1/master/users/{uid}", headers=admin,
                 json={"is_active": False})
    active = client.get("/api/v1/master/users", headers=admin).json()
    assert all(u["id"] != uid for u in active)
    allu = client.get("/api/v1/master/users?active_only=false", headers=admin).json()
    assert any(u["id"] == uid for u in allu)


def test_station_device_crud(client, db):
    admin = _token(client, "admin", "a")
    r = client.post("/api/v1/master/station-devices", headers=admin, json={
        "device_key": "gate-kiosk-9", "station": "gate", "label": "Gate kiosk 9"})
    assert r.status_code == 201, r.text
    did = r.json()["id"]
    assert r.json()["registered_by"] is not None
    # duplicate device_key conflicts
    dup = client.post("/api/v1/master/station-devices", headers=admin, json={
        "device_key": "gate-kiosk-9", "station": "gate", "label": "dup"})
    assert dup.status_code == 409
    # deactivate → drops from the default (active-only) list
    client.patch(f"/api/v1/master/station-devices/{did}", headers=admin,
                 json={"is_active": False})
    active = client.get("/api/v1/master/station-devices", headers=admin).json()
    assert all(d["id"] != did for d in active)
