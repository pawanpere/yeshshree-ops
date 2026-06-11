"""Test fixtures. Default: in-memory SQLite (verify-lite, Cowork-safe).
Tests needing real Postgres behaviour are marked @pytest.mark.postgres and excluded
from verify-lite (see Makefile)."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.models import Base


@pytest.fixture()
def engine():
    eng = create_engine("sqlite://")  # in-memory, fresh per test
    Base.metadata.create_all(eng)
    yield eng
    eng.dispose()


@pytest.fixture()
def db(engine):
    Session = sessionmaker(bind=engine)
    s = Session()
    yield s
    s.close()
