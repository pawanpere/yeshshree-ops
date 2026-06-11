"""Test fixtures. Default: in-memory SQLite (verify-lite, Cowork-safe).
Tests needing real Postgres behaviour are marked @pytest.mark.postgres and excluded
from verify-lite (see Makefile)."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.models import Base


@pytest.fixture()
def engine():
    # StaticPool + check_same_thread=False: ONE shared in-memory DB across threads —
    # TestClient executes requests in a worker thread (classic SQLite-test gotcha).
    eng = create_engine("sqlite://",
                        connect_args={"check_same_thread": False},
                        poolclass=StaticPool)
    Base.metadata.create_all(eng)
    yield eng
    eng.dispose()


@pytest.fixture()
def db(engine):
    Session = sessionmaker(bind=engine)
    s = Session()
    yield s
    s.close()
