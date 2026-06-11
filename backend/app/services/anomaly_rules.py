"""Anomaly rule functions v1 (P21; Architecture §5.5). Rules are PURE: no DB access,
no side effects — thresholds arrive via the injected `th` dict (anomaly.thresholds()
reads app_settings['anomaly_thresholds']), facts arrive as kwargs from the service.

Adding a rule = one function here + one test (Architecture §5.5). The `db` parameter
exists only because the engine passes it uniformly; rules in this file never use it.
"""
from decimal import Decimal

from app.services.anomaly import AnomalyResult, rule, to_decimal


@rule("gr_pre_post")
def gr_qty_vs_po(db, th, *, expected, received, within_tolerance=False, **_):
    """HARD: received qty is >= hard_qty_multiple x expected (or <= expected / multiple).
    Almost certainly a unit error (pcs vs KG) or a wrong PO match — refuse the entry."""
    expected = to_decimal(expected)
    received = to_decimal(received)
    multiple = to_decimal(th.get("hard_qty_multiple", 5))
    if expected <= 0 or multiple <= 1:
        return None
    if received >= expected * multiple or received <= expected / multiple:
        return AnomalyResult(
            rule_code="gr_qty_vs_po",
            severity="hard",
            message_en=(f"Received qty {received} is {multiple}x or more away from "
                        f"the expected {expected} — check unit / PO match"),
            message_mr=(f"प्राप्त प्रमाण {received} हे अपेक्षित {expected} पेक्षा "
                        f"{multiple} पट किंवा जास्त वेगळे आहे — युनिट / PO तपासा"),
            observed={"received_qty": str(received)},
            expected={"expected_qty": str(expected), "hard_qty_multiple": str(multiple)},
        )
    return None


@rule("gr_pre_post")
def gr_qty_deviation(db, th, *, expected, received, within_tolerance=False, **_):
    """SOFT: deviation beyond soft_deviation_pct AFTER the material-group tolerance
    (§11.7) was applied — `within_tolerance=True` means the GR accepted clean and
    must never soft-flag (in-tolerance steel GRs stay silent)."""
    if within_tolerance:
        return None
    expected = to_decimal(expected)
    received = to_decimal(received)
    soft_pct = to_decimal(th.get("soft_deviation_pct", 20))
    if expected <= 0:
        return None
    deviation_pct = (abs(received - expected) / expected * 100).quantize(Decimal("0.01"))
    if deviation_pct > soft_pct:
        return AnomalyResult(
            rule_code="gr_qty_deviation",
            severity="soft",
            message_en=(f"Received qty {received} deviates {deviation_pct}% from "
                        f"expected {expected} (limit {soft_pct}%)"),
            message_mr=(f"प्राप्त प्रमाण {received} अपेक्षित {expected} पासून "
                        f"{deviation_pct}% ने वेगळे आहे (मर्यादा {soft_pct}%)"),
            observed={"received_qty": str(received), "deviation_pct": str(deviation_pct)},
            expected={"expected_qty": str(expected), "soft_deviation_pct": str(soft_pct)},
        )
    return None
