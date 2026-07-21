from __future__ import annotations

import pytest

from analysis.schema import SchemaValidationError, validate_record
from tests.conftest import make_current_ea_record, make_valid_record


def test_valid_record_parses_successfully():
    record = validate_record(make_valid_record())
    assert record.symbol == "XAUUSD"
    assert record.market_family == "METAL"
    assert record.direction == "BUY"
    assert record.targets == [2361.45]


def test_current_ea_record_fails_validation_on_market_family_and_mode():
    """The documented, confirmed cross-layer gap: the live EA build never
    sets market_family/intraday_mode, so a real journal row today MUST be
    rejected by this schema, not silently accepted."""

    with pytest.raises(SchemaValidationError) as exc_info:
        validate_record(make_current_ea_record())
    message = str(exc_info.value)
    assert "market_family" in message or "intraday_mode" in message


def test_unknown_regime_rejected():
    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(regime="REGIME_MADE_UP"))


def test_naive_timestamp_rejected():
    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(timestamp_utc="2026-07-21T14:05:30"))


def test_non_utc_offset_timestamp_rejected():
    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(timestamp_utc="2026-07-21T14:05:30+02:00"))


def test_missing_required_field_rejected():
    record = make_valid_record()
    del record["symbol"]
    with pytest.raises(SchemaValidationError):
        validate_record(record)


def test_unexpected_extra_field_rejected():
    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(unexpected_field="surprise"))


def test_null_entry_and_stop_accepted_for_no_trade_decision():
    record = make_valid_record(
        direction="NONE",
        strategy="NoTrade",
        setup="daily_loss_cap_breached_change_-2.10pct",
        entry=None,
        stop=None,
        targets=[],
        candlestick_pattern=None,
        chart_pattern=None,
    )
    parsed = validate_record(record)
    assert parsed.entry is None
    assert parsed.stop is None
    assert parsed.targets == []


def test_regime_confidence_out_of_range_rejected():
    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(regime_confidence=150.0))


def test_score_out_of_range_rejected():
    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(score=-1.0))


def test_invalid_direction_literal_rejected():
    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(direction="HOLD"))


def test_nan_entry_rejected():
    record = make_valid_record()
    record["entry"] = float("nan")
    with pytest.raises(SchemaValidationError):
        validate_record(record)
