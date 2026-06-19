"""Regression: a confirmation's shift_date is the PLANT-LOCAL calendar date, not the
UTC date. Between 18:30–24:00 UTC (00:00–05:30 IST) the two differ, and deriving
shift_date from UTC filed that work under the previous day — so the cockpit's live
`confirmed_good` join (line_plans.plan_date == IST today) missed it.

Deterministic (pins the instant) so it guards the fix regardless of when tests run —
unlike the thin slice, which only exposes the bug during the early-IST-morning window."""
import datetime as dt

from app.services.production import _business_date

UTC = dt.timezone.utc


def test_early_ist_morning_uses_local_day_not_utc():
    # 2026-06-19 22:34 UTC == 2026-06-20 04:04 IST → the shift day is the 20th.
    instant = dt.datetime(2026, 6, 19, 22, 34, tzinfo=UTC)
    assert instant.date() == dt.date(2026, 6, 19)          # UTC date (the old bug)
    assert _business_date(instant) == dt.date(2026, 6, 20)  # IST date (correct)


def test_ist_daytime_matches_utc_day():
    # 2026-06-20 10:00 UTC == 15:30 IST → same calendar day in both zones.
    instant = dt.datetime(2026, 6, 20, 10, 0, tzinfo=UTC)
    assert _business_date(instant) == dt.date(2026, 6, 20)
