from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

import pandas as pd

from analysis.time_utils import (
    TimezoneValidationError,
    ensure_utc,
    is_duplicate_timestamp_symbol,
    parse_iso8601_utc,
    parse_utc_series,
    to_botswana_time,
    to_server_time,
)


def test_parse_iso8601_utc_matches_dj_format_exactly():
    parsed = parse_iso8601_utc("2026-07-21T14:05:30Z")
    assert parsed == datetime(2026, 7, 21, 14, 5, 30, tzinfo=timezone.utc)


def test_ensure_utc_rejects_naive_datetime():
    with pytest.raises(TimezoneValidationError):
        ensure_utc(datetime(2026, 7, 21, 14, 5, 30))


def test_ensure_utc_rejects_non_utc_offset():
    non_utc = datetime(2026, 7, 21, 14, 5, 30, tzinfo=timezone(timedelta(hours=2)))
    with pytest.raises(TimezoneValidationError):
        ensure_utc(non_utc)


def test_ensure_utc_accepts_utc_and_returns_unchanged():
    value = datetime(2026, 7, 21, 14, 5, 30, tzinfo=timezone.utc)
    assert ensure_utc(value) == value


def test_to_botswana_time_preserves_the_instant():
    """Regression for a Codex review finding (2026-07-21): the previous
    implementation added the offset while leaving tzinfo=UTC, which
    changed WHICH INSTANT was represented rather than merely its
    wall-clock display. A correct conversion represents the identical
    moment -- aware-datetime equality compares instants, so
    `to_botswana_time(x) == x` must hold, and subtracting them must give
    a ZERO timedelta, not two hours."""

    utc_value = datetime(2026, 7, 21, 14, 0, 0, tzinfo=timezone.utc)
    botswana = to_botswana_time(utc_value)

    assert botswana == utc_value  # same instant
    assert botswana - utc_value == timedelta(0)
    assert botswana.utcoffset() == timedelta(hours=2)
    assert botswana.hour == 16  # wall-clock DISPLAY is +2, the instant is not


def test_to_server_time_preserves_the_instant():
    utc_value = datetime(2026, 7, 21, 14, 0, 0, tzinfo=timezone.utc)
    server = to_server_time(utc_value, server_utc_offset_hours=3.0)

    assert server == utc_value  # same instant
    assert server - utc_value == timedelta(0)
    assert server.utcoffset() == timedelta(hours=3)
    assert server.hour == 17  # wall-clock DISPLAY is +3


def test_to_botswana_time_rejects_naive_input():
    with pytest.raises(TimezoneValidationError):
        to_botswana_time(datetime(2026, 7, 21, 14, 0, 0))


def test_is_duplicate_timestamp_symbol():
    seen = {(datetime(2026, 7, 21, 14, 0, 0, tzinfo=timezone.utc), "XAUUSD")}
    assert is_duplicate_timestamp_symbol(
        seen, datetime(2026, 7, 21, 14, 0, 0, tzinfo=timezone.utc), "XAUUSD"
    )
    assert not is_duplicate_timestamp_symbol(
        seen, datetime(2026, 7, 21, 15, 0, 0, tzinfo=timezone.utc), "XAUUSD"
    )


# --- parse_utc_series --------------------------------------------------------


def test_parse_utc_series_accepts_valid_utc_strings():
    series = pd.Series(["2026-07-21T14:05:30Z", "2026-07-22T00:00:00Z"])
    parsed = parse_utc_series(series)
    assert parsed.iloc[0] == pd.Timestamp("2026-07-21T14:05:30Z")
    assert isinstance(parsed.dtype, pd.DatetimeTZDtype)
    assert str(parsed.dtype.tz) == "UTC"


def test_parse_utc_series_rejects_naive_string():
    """Regression for a Codex review finding (2026-07-21): pandas'
    `pd.to_datetime(..., utc=True)` silently treats a naive timestamp
    string as UTC. This must be a visible failure instead."""

    series = pd.Series(["2026-07-21T01:00:00"])  # no "Z", no offset
    with pytest.raises(TimezoneValidationError):
        parse_utc_series(series)


def test_parse_utc_series_rejects_non_utc_offset_string():
    series = pd.Series(["2026-07-21T14:00:00+02:00"])
    with pytest.raises(TimezoneValidationError):
        parse_utc_series(series)


def test_parse_utc_series_reports_the_bad_row_index():
    series = pd.Series(["2026-07-21T14:00:00Z", "not-a-timestamp", "2026-07-22T00:00:00Z"])
    with pytest.raises(TimezoneValidationError) as exc_info:
        parse_utc_series(series)
    assert "1" in str(exc_info.value)  # the bad row's index
