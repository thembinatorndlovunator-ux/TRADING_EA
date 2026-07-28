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
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import pandas as pd

# Matches MT5CalendarProvider.mqh's MTC_BOTSWANA_UTC_OFFSET_SECONDS (2*3600).
BOTSWANA_UTC_OFFSET = timedelta(hours=2)
BOTSWANA_TZ = timezone(BOTSWANA_UTC_OFFSET)


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
    this reuses from MT5CalendarProvider.mqh.

    **Fixed, 2026-07-21 Codex review finding:** this previously ADDED the
    offset to the datetime's wall-clock value while leaving ``tzinfo`` set
    to UTC, which silently changed which INSTANT the datetime represented
    (e.g. "2026-01-01 12:00 UTC" became "2026-01-01 14:00 UTC" -- two
    hours LATER in absolute time, not the same moment relabelled). A
    correct timezone conversion changes only the REPRESENTATION, not the
    instant: this now uses ``astimezone``, so the wall-clock hour still
    reads +2 but the result is provably the identical moment in time
    (``to_botswana_time(x) == x`` holds for aware datetime equality, which
    compares instants, not wall-clock fields).
    """

    ensure_utc(utc_value)
    return utc_value.astimezone(BOTSWANA_TZ)


def to_server_time(utc_value: datetime, server_utc_offset_hours: float) -> datetime:
    """Converts a UTC datetime to broker server time, given the broker's
    OWN UTC offset in hours (never assumed fixed across brokers, unlike
    Botswana time above -- a caller must supply the real value, e.g.
    measured the same way MT5CalendarProvider.mqh's MTC_FetchEvents does:
    TimeTradeServer() - TimeGMT() at the moment of interest).

    Same instant-preserving fix as ``to_botswana_time`` above (uses
    ``astimezone``, not offset-addition-with-stale-tzinfo)."""

    ensure_utc(utc_value)
    return utc_value.astimezone(timezone(timedelta(hours=server_utc_offset_hours)))


def is_duplicate_timestamp_symbol(
    seen: set[tuple[datetime, str]], value: datetime, symbol: str
) -> bool:
    """Membership check against a caller-maintained (timestamp, symbol) set
    -- the practical interim duplicate-detection key used by
    ``data_collection/journal_reader.py`` while ``signal_id`` remains
    unpopulated by the live EA (see that module's own docstring for why)."""

    return (value, symbol) in seen


def parse_utc_series(values: "pd.Series") -> "pd.Series":
    """Strictly parses a pandas Series of ISO-8601 timestamp STRINGS as
    UTC, reusing ``parse_iso8601_utc``/``ensure_utc`` row-by-row.

    **Fixed, 2026-07-21 Codex review finding:** every CSV-consuming
    pipeline in this project previously called
    ``pd.to_datetime(column, utc=True, errors="raise")`` directly. Pandas'
    own ``utc=True`` SILENTLY treats a naive string (no "Z"/offset, e.g.
    "2026-01-01T01:00:00") as if it were already UTC -- exactly the
    "guess a timezone" behavior ``ensure_utc`` exists to refuse. This
    function raises ``TimezoneValidationError`` for any naive or
    non-UTC-offset value instead, with the offending row indices named,
    per the reproducibility contract's "visible failures" rule.
    """

    import pandas as pd

    parsed: list = []
    bad_rows: list[tuple[object, object]] = []
    for index, raw in values.items():
        try:
            parsed.append(parse_iso8601_utc(str(raw)))
        except (TimezoneValidationError, ValueError):
            bad_rows.append((index, raw))
            parsed.append(pd.NaT)

    if bad_rows:
        raise TimezoneValidationError(
            f"non-UTC, naive, or unparseable timestamps at rows (index, raw value): {bad_rows}"
        )

    # Every element has already been individually validated as aware UTC
    # above -- this second pd.to_datetime pass only normalizes dtype
    # (object list of datetimes -> proper datetime64[ns, UTC] column), it
    # does not re-introduce any naive-as-UTC guessing risk.
    return pd.Series(pd.to_datetime(parsed, utc=True), index=values.index)
