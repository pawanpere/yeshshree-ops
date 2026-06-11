"""P06 acceptance: every mutating request leaves an audit row; bodies never stored;
service-level record() captures field diffs. (Postgres INSERT-only grant is proven by a
postgres-marked test added with the baseline migration — see docs/packets/P03.md handoff.)"""
import pytest
from fastapi.testclient import TestClient

from app.core.audit import record
from app.core.security import hash_password
from app.models.identity import User
from app.models.system import AuditLog
import app.core.db as db_mod


@pytest.fixture()
def client(engine, db):
    db_mod._engine = engine
    from sqlalchemy.orm import sessionmaker
    db_mod._SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    db.add(User(username="planner", password_hash=hash_password("pw1"),
                full_name="P", role="planning", language="en"))
    db.commit()
    from app.main import app
    yield TestClient(app)
    db_mod._engine = None
    db_mod._SessionLocal = None


def test_mutating_request_writes_audit_row(client, db):
    client.post("/api/v1/auth/login", json={"username": "planner", "password": "pw1"})
    rows = db.query(AuditLog).filter_by(path="/api/v1/auth/login").all()
    assert len(rows) == 1
    row = rows[0]
    assert row.action == "login" and row.method == "POST"
    # the password must never be in the audit trail
    assert row.before is None and "password" not in str(row.after)


def test_failed_mutations_are_audited_too(client, db):
    client.post("/api/v1/auth/login", json={"username": "planner", "password": "WRONG"})
    row = db.query(AuditLog).filter_by(path="/api/v1/auth/login").one()
    assert row.after == {"status": 401}


def test_get_requests_not_audited(client, db):
    client.get("/api/v1/system/healthz")
    assert db.query(AuditLog).count() == 0


def test_service_level_field_diff(db):
    record(db, user_id=1, entity="vendors", entity_id=7, action="update",
           before={"credit_limit": "1400000.00"}, after={"credit_limit": "1650000.00"})
    db.commit()
    row = db.query(AuditLog).filter_by(entity="vendors", entity_id=7).one()
    assert row.method is None  # no HTTP context on service-level records
    assert row.before["credit_limit"] == "1400000.00"
