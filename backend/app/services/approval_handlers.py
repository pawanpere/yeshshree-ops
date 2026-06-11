"""Approval apply/reject handler registry (contract between the approvals engine and
domain services — same pattern as the anomaly rule registry).

The engine (services/approvals.py) calls these when an approval reaches its terminal
state. Domain services register handlers for their own approval types:

    @on_approve("credit_waiver")
    def _apply(db, approval): ...   # post the blocked issue

Handlers run INSIDE the engine's transaction. Importing app.services registers all.
"""
from typing import Callable

from sqlalchemy.orm import Session

APPLY: dict[str, Callable[[Session, object], None]] = {}
REJECT: dict[str, Callable[[Session, object], None]] = {}


def on_approve(approval_type: str):
    def deco(fn):
        APPLY[approval_type] = fn
        return fn
    return deco


def on_reject(approval_type: str):
    def deco(fn):
        REJECT[approval_type] = fn
        return fn
    return deco
