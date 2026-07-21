from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from analysis.time_utils import (
    TimezoneValidationError,
    ensure_utc,
    is_duplicate_timestamp_symbol,
    parse_iso8601_utc,
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


def test_to_botswana_time_adds_exactly_two_hours():
    utc_value = datetime(2026, 7, 21, 14, 0, 0, tzinfo=timezone.utc)
    botswana = to_botswana_time(utc_value)
    assert botswana - utc_value == timedelta(hours=2)
    assert botswana.hour == 16


def test_to_server_time_adds_given_offset():
    utc_value = datetime(2026, 7, 21, 14, 0, 0, tzinfo=timezone.utc)
    server = to_server_time(utc_value, server_utc_offset_hours=3.0)
    assert server - utc_value == timedelta(hours=3)


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
