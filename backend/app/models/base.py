"""Model conventions — every model file imports from here. (Architecture §4 conventions.)

- BIGINT identity PKs (`intpk`), SQLite-compatible for verify-lite tests.
- Statuses: TEXT + named CheckConstraint — NEVER Postgres enums (CLAUDE.md invariant 9).
- money NUMERIC(14,2), qty NUMERIC(14,3), timestamptz everywhere.
- JSONB on Postgres, JSON on SQLite (JSONVariant). TEXT[] on Postgres, JSON on SQLite (ArrayVariant).
- `client_ref` UUID UNIQUE on user-created transactions (idempotency, invariant 4).
- Naming convention pinned so Alembic autogenerate produces stable constraint names.
"""
from datetime import datetime
from typing import Annotated

from sqlalchemy import BigInteger, DateTime, Integer, MetaData, Numeric, Text, func
from sqlalchemy.dialects import postgresql
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.types import JSON

NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}

# BIGINT pk on Postgres; plain INTEGER on SQLite so autoincrement works in tests.
BigIntPK = BigInteger().with_variant(Integer, "sqlite")

# JSONB on Postgres, JSON elsewhere.
JSONVariant = JSON().with_variant(postgresql.JSONB(astext_type=Text()), "postgresql")

# TEXT[] on Postgres, JSON list elsewhere (verify-lite).
ArrayVariant = postgresql.ARRAY(Text()).with_variant(JSON(), "sqlite")

Money = Numeric(14, 2)
Qty = Numeric(14, 3)


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


intpk = Annotated[int, mapped_column(BigIntPK, primary_key=True, autoincrement=True)]
created_at = Annotated[
    datetime, mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
]
