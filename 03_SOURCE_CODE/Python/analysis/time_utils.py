"""Timezone normalization shared by every pipeline in this analysis layer.

Three time references appear throughout this project (mirroring the MQL5
side's ``SNewsEvent`` fields in ``NewsManager.mqh``): UTC (the canonical
storage format everywhere -- journal timestamps, calendar events), broker
server time (variable per broker, never assumed fixed), and Botswana time
(this project's stated operator-local reference).

**Stated assumption, carried over verbatim from
``MT5CalendarProvider.mqh``'s own header comment (TASK-029):** Botswana is
UTC+2 (Central Africa Time), no daylight saving. No project document states
an explicit offset value; this is that task's documented choice, reused
here rather than re-derived, so the MQL5 and Python sides agree.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

# Matches MT5CalendarProvider.mqh's MTC_BOTSWANA_UTC_OFFSET_SECONDS (2*3600).
BOTSWANA_UTC_OFFSET = timedelta(hours=2)


class TimezoneValidationError(ValueError):
    """Raised when a timestamp is missing timezone info or is not UTC --
    per the reproducibility contract, this must never be silently coerced
    (e.g. by assuming naive-means-UTC)."""


def ensure_utc(value: datetime) -> datetime:
    """Returns 'value' unchanged if it is timezone-aware and exactly UTC;
    raises TimezoneValidationError otherwise. Never guesses a timezone for
    a naive datetime."""

    if value.tzinfo is None:
        raise TimezoneValidationError(
            f"datetime {value!r} is naive (no timezone) -- refusing to assume UTC"
        )
    if value.utcoffset() != timezone.utc.utcoffset(value):
        raise TimezoneValidationError(
            f"datetime {value!r} has offset {value.utcoffset()!r}, expected UTC (+00:00)"
        )
    return value


def parse_iso8601_utc(text: str) -> datetime:
    """Parses an ISO-8601 UTC timestamp string, e.g.
    "2026-07-21T14:05:30Z" (DJ_FormatIso8601Utc's own output format).
    Raises TimezoneValidationError (not a bare ValueError) if the string
    parses but is not actually UTC, or ValueError if it does not parse at
    all -- both are visible failures, never silently coerced."""

    # datetime.fromisoformat handles the "Z" suffix directly since Python
    # 3.11; this project's requirements.txt does not pin a Python version
    # below that, so no manual "Z" -> "+00:00" replacement is needed here.
    parsed = datetime.fromisoformat(text)
    return ensure_utc(parsed)


def to_botswana_time(utc_value: datetime) -> datetime:
    """Converts a UTC datetime to this project's stated Botswana-time
    reference (UTC+2, no DST) -- see module docstring for the assumption
    this reuses from MT5CalendarProvider.mqh."""

    ensure_utc(utc_value)
    return utc_value + BOTSWANA_UTC_OFFSET


def to_server_time(utc_value: datetime, server_utc_offset_hours: float) -> datetime:
    """Converts a UTC datetime to broker server time, given the broker's
    OWN UTC offset in hours (never assumed fixed across brokers, unlike
    Botswana time above -- a caller must supply the real value, e.g.
    measured the same way MT5CalendarProvider.mqh's MTC_FetchEvents does:
    TimeTradeServer() - TimeGMT() at the moment of interest)."""

    ensure_utc(utc_value)
    return utc_value + timedelta(hours=server_utc_offset_hours)


def is_duplicate_timestamp_symbol(seen: set[tuple[datetime, str]], value: datetime, symbol: str) -> bool:
    """Membership check against a caller-maintained (timestamp, symbol) set
    -- the practical interim duplicate-detection key used by
    ``data_collection/journal_reader.py`` while ``signal_id`` remains
    unpopulated by the live EA (see that module's own docstring for why)."""

    return (value, symbol) in seen
