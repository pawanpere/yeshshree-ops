"""Anomaly engine v1 (P21; Architecture §5.5, §11). The INTERFACE lives here and is
stable; rules are pure functions registered below (added in P20/P21, more over time).

Usage inside a service write path (invariant 3 step 2):

    results = run_rules(db, "gr_pre_post", gr=draft, po=po, tolerance_pct=tol)
    raise_hard(results)                      # aborts the request if any hard hit
    ... domain writes ...
    persist_soft(db, results, ref_type="goods_receipts", ref_id=gr.id)  # same txn

Hard = entry refused (422, envelope code ANOMALY_HARD, en+mr). Soft = saved + registered.
Thresholds come from app_settings('anomaly_thresholds'), never hardcoded in rules.
"""
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Callable

from sqlalchemy.orm import Session

from app.core.deps import _error
from app.models.config_tables import AppSetting
from app.models.workflow import Anomaly


@dataclass
class AnomalyResult:
    rule_code: str
    severity: str  # 'hard' | 'soft'
    message_en: str
    message_mr: str
    observed: dict = field(default_factory=dict)
    expected: dict = field(default_factory=dict)


# context -> list of rule callables(db, thresholds, **kwargs) -> AnomalyResult | None
RULES: dict[str, list[Callable]] = {}


def rule(context: str):
    def deco(fn):
        RULES.setdefault(context, []).append(fn)
        return fn
    return deco


def thresholds(db: Session) -> dict:
    row = db.get(AppSetting, "anomaly_thresholds")
    return row.value if row else {"hard_qty_multiple": 5, "soft_deviation_pct": 20,
                                  "rejection_spike_factor": 2.0}


def run_rules(db: Session, context: str, **kwargs) -> list[AnomalyResult]:
    th = thresholds(db)
    results = []
    for fn in RULES.get(context, []):
        r = fn(db, th, **kwargs)
        if r is not None:
            results.append(r)
    return results


def raise_hard(results: list[AnomalyResult]) -> None:
    hard = [r for r in results if r.severity == "hard"]
    if hard:
        h = hard[0]
        raise _error("ANOMALY_HARD", h.message_en, h.message_mr, 422, {
            "rule_code": h.rule_code, "observed": h.observed, "expected": h.expected,
            "all_hard": [r.rule_code for r in hard],
        })


def persist_soft(db: Session, results: list[AnomalyResult], *, ref_type: str,
                 ref_id: int) -> list[Anomaly]:
    rows = []
    for r in results:
        if r.severity != "soft":
            continue
        row = Anomaly(rule_code=r.rule_code, severity="soft", ref_type=ref_type,
                      ref_id=ref_id, observed=r.observed, expected=r.expected,
                      message_en=r.message_en, message_mr=r.message_mr, status="open")
        db.add(row)
        rows.append(row)
    return rows


def register_hard(db: Session, result: AnomalyResult, *, ref_type: str, ref_id: int) -> Anomaly:
    """Hard blocks ALSO appear in the register (status open, escalation path) when the
    operator chooses 'confirm — escalate' instead of re-typing."""
    row = Anomaly(rule_code=result.rule_code, severity="hard", ref_type=ref_type,
                  ref_id=ref_id, observed=result.observed, expected=result.expected,
                  message_en=result.message_en, message_mr=result.message_mr, status="open")
    db.add(row)
    return row


def to_decimal(v) -> Decimal:
    return v if isinstance(v, Decimal) else Decimal(str(v))
