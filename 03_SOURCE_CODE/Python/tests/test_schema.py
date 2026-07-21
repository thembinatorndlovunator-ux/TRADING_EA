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


def test_score_as_string_rejected():
    """Regression for a Codex review finding: pydantic's default (lax)
    float coercion silently accepted score="50" (a string) as 50.0."""

    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(score="50"))


def test_risk_percent_as_string_rejected():
    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(risk_percent="0.3"))


def test_targets_with_string_element_rejected():
    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(targets=["2.5"]))


def test_regime_confidence_as_string_rejected():
    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(regime_confidence="50"))


def test_integer_epoch_timestamp_rejected():
    """Regression for a Codex review finding: pydantic's default datetime
    coercion silently accepted timestamp_utc=0 as the 1970 Unix epoch,
    even though the schema requires an ISO-8601 string."""

    record = make_valid_record()
    record["timestamp_utc"] = 0
    with pytest.raises(SchemaValidationError):
        validate_record(record)


def test_risk_percent_nan_rejected():
    """Regression for a Codex review finding: risk_percent had no
    finiteness check at all (only entry/stop did)."""

    record = make_valid_record()
    record["risk_percent"] = float("nan")
    with pytest.raises(SchemaValidationError):
        validate_record(record)


def test_targets_nan_element_rejected():
    record = make_valid_record()
    record["targets"] = [float("nan")]
    with pytest.raises(SchemaValidationError):
        validate_record(record)


def test_targets_infinity_element_rejected():
    record = make_valid_record()
    record["targets"] = [float("inf")]
    with pytest.raises(SchemaValidationError):
        validate_record(record)


def test_empty_string_candlestick_pattern_rejected():
    """Regression for a Codex review finding: the validator's own comment
    said an empty string must be rejected (only JSON null is valid per
    DJ_SerializeDecision's convention), but the code was a no-op that
    silently accepted it."""

    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(candlestick_pattern=""))


def test_empty_string_chart_pattern_rejected():
    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(chart_pattern=""))


def test_plain_int_score_still_accepted():
    """Strict float mode must still accept a plain int (e.g. score=50,
    not score=50.0) -- only string/bool coercion should be rejected, not
    every non-float-typed number."""

    record = validate_record(make_valid_record(score=50))
    assert record.score == 50.0
