"""P04/P05 acceptance: login, rotation, role guard, PIN device rules, mock OTP."""
import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

from app.api.auth import router as auth_router
from app.core.deps import require
from app.core.security import hash_password
from app.models.identity import StationDevice, User
import app.core.db as db_mod


@pytest.fixture()
def client(engine, db):
    """App wired to the test SQLite engine, with seeded users."""
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

    db.add_all([
        User(username="planner", password_hash=hash_password("pw1"), full_name="P",
             role="planning", language="en"),
        User(username="gate1", password_hash=hash_password("pw2"),
             pin_hash=hash_password("4321"), full_name="G", role="plant_ops",
             station="gate", language="mr"),
        User(username="qc1", password_hash=hash_password("pw3"),
             pin_hash=hash_password("9999"), full_name="Q", role="plant_ops",
             station="qc", language="mr"),
        User(username="v1", password_hash=hash_password("pwv"), full_name="V",
             role="vendor", phone="+919800000001", language="en"),
    ])
    db.commit()
    admin = db.query(User).filter_by(username="planner").one()
    db.add(StationDevice(device_key="gate-kiosk-1", station="gate", label="Gate",
                         registered_by=admin.id))
    db.commit()

    app = FastAPI()
    app.include_router(auth_router)

    @app.get("/api/v1/guarded", dependencies=[Depends(require("admin", "planning"))])
    def guarded():
        return {"ok": True}

    yield TestClient(app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def test_login_ok_and_bad(client):
    r = client.post("/api/v1/auth/login", json={"username": "planner", "password": "pw1"})
    assert r.status_code == 200 and r.json()["role"] == "planning"
    r2 = client.post("/api/v1/auth/login", json={"username": "planner", "password": "no"})
    assert r2.status_code == 401
    assert r2.json()["detail"]["code"] == "AUTH_BAD_CREDENTIALS"
    assert r2.json()["detail"]["message_mr"]  # i18n envelope present


def test_role_guard(client):
    token = client.post("/api/v1/auth/login",
                        json={"username": "gate1", "password": "pw2"}).json()
    # plant_ops not in (admin, planning) → 403
    r = client.get("/api/v1/guarded", headers={"Authorization": f"Bearer {token['access_token']}"})
    assert r.status_code == 403
    token2 = client.post("/api/v1/auth/login",
                         json={"username": "planner", "password": "pw1"}).json()
    r2 = client.get("/api/v1/guarded", headers={"Authorization": f"Bearer {token2['access_token']}"})
    assert r2.status_code == 200
    assert client.get("/api/v1/guarded").status_code == 401  # no token


def test_refresh_rotation_and_reuse_detection(client):
    t1 = client.post("/api/v1/auth/login",
                     json={"username": "planner", "password": "pw1"}).json()
    t2 = client.post("/api/v1/auth/refresh", json={"refresh_token": t1["refresh_token"]}).json()
    assert t2["refresh_token"] != t1["refresh_token"]
    # reusing the OLD (rotated) token = theft signal → all sessions revoked
    r = client.post("/api/v1/auth/refresh", json={"refresh_token": t1["refresh_token"]})
    assert r.status_code == 401 and r.json()["detail"]["code"] == "AUTH_REUSE"
    r2 = client.post("/api/v1/auth/refresh", json={"refresh_token": t2["refresh_token"]})
    assert r2.status_code == 401  # collateral revocation


def test_pin_switch_station_rules(client):
    ok = client.post("/api/v1/auth/pin-switch",
                     json={"device_key": "gate-kiosk-1", "username": "gate1", "pin": "4321"})
    assert ok.status_code == 200 and ok.json()["station"] == "gate"
    wrong_station = client.post("/api/v1/auth/pin-switch",
                                json={"device_key": "gate-kiosk-1", "username": "qc1", "pin": "9999"})
    assert wrong_station.status_code == 403
    assert wrong_station.json()["detail"]["code"] == "STATION_MISMATCH"
    unknown_device = client.post("/api/v1/auth/pin-switch",
                                 json={"device_key": "nope", "username": "gate1", "pin": "4321"})
    assert unknown_device.status_code == 403


def test_vendor_mock_otp_flow(client):
    req = client.post("/api/v1/auth/vendor-otp/request", json={"phone": "+919800000001"})
    assert req.status_code == 200
    code = req.json()["dev_code"]
    bad = client.post("/api/v1/auth/vendor-otp/verify",
                      json={"phone": "+919800000001", "code": "000000" if code != "000000" else "111111"})
    assert bad.status_code == 401
    ok = client.post("/api/v1/auth/vendor-otp/verify",
                     json={"phone": "+919800000001", "code": code})
    assert ok.status_code == 200 and ok.json()["role"] == "vendor"
    # code is single-use
    again = client.post("/api/v1/auth/vendor-otp/verify",
                        json={"phone": "+919800000001", "code": code})
    assert again.status_code == 401
