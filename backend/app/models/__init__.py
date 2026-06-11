"""All domain models. Importing this module registers every table on Base.metadata —
alembic/env.py and tests rely on that."""
from app.models.base import Base  # noqa: F401
from app.models import (  # noqa: F401
    config_tables,
    gate,
    identity,
    inventory,
    master,
    outbound,
    planning,
    production,
    system,
    workflow,
)
