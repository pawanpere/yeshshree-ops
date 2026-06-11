"""Engine + session dependency. One engine per process; sessions per request."""
from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings

_engine = None
_SessionLocal = None


def get_engine():
    global _engine, _SessionLocal
    if _engine is None:
        _engine = create_engine(get_settings().database_url, pool_pre_ping=True)
        _SessionLocal = sessionmaker(bind=_engine, autoflush=False, expire_on_commit=False)
    return _engine


def get_db() -> Generator[Session, None, None]:
    """FastAPI dependency. Commit/rollback is owned by the service-layer write path
    (Architecture §5.3) — this dependency only guarantees the session closes."""
    get_engine()
    db = _SessionLocal()
    try:
        yield db
    finally:
        db.close()
