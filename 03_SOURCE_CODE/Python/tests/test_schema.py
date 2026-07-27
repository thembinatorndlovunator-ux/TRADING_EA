from __future__ import annotations

import pytest

from analysis.schema import SchemaValidationError, validate_record
from tests.conftest import make_schema_invalid_record, make_valid_record


def test_valid_record_parses_successfully():
    record = validate_record(make_valid_record())
    assert record.symbol == "XAUUSD"
    assert record.market_family == "METAL"
    assert record.direction == "BUY"
    assert record.targets == [2361.45]


def test_schema_invalid_record_fails_validation_on_market_family_and_mode():
    """A record with blank market_family/intraday_mode (the schema-invalid
    fixture's own shape) must be rejected, not silently accepted -- this
    is no longer what the live EA actually emits (TASK-040 populates both
    fields for real), but the schema must still reject a blank value on
    either field regardless."""

    with pytest.raises(SchemaValidationError) as exc_info:
        validate_record(make_schema_invalid_record())
    message = str(exc_info.value)
    assert "market_family" in message or "intraday_mode" in message


def test_unknown_news_state_rejected():
    """Regression for a Codex review finding (2026-07-22, seventh round,
    P1 finding 17): the live producer (ThembaAdaptiveIntradayEA.mq5's
    ResolveNewsBlackout) defines news_state as exactly "CLEAR" or
    "BLACKOUT", but this schema previously accepted any string -- a
    direct "BANANA" probe was accepted despite the two-value producer
    contract already being documented in this module's own comments."""

    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(news_state="BANANA"))


def test_both_real_news_state_values_accepted():
    for value in ("CLEAR", "BLACKOUT"):
        record = validate_record(make_valid_record(news_state=value))
        assert record.news_state == value


def test_unknown_news_state_literal_accepted():
    """Regression for a Codex review finding (2026-07-22, eighth round, P1
    finding 12): JournalDataFailureDecision (ThembaAdaptiveIntradayEA.mq5)
    previously fabricated "CLEAR" on a data-read failure because this
    schema had no legitimate "not evaluated" value -- "UNKNOWN" is now
    that producer's real, honest third value, distinct from a genuinely
    invalid probe like "BANANA" (still rejected, see
    test_unknown_news_state_rejected)."""

    record = validate_record(make_valid_record(news_state="UNKNOWN"))
    assert record.news_state == "UNKNOWN"


def test_none_intraday_mode_accepted():
    """Regression for a Codex review finding (2026-07-22, eighth round, P1
    finding 12): IntradayModeRouter.mqh's own IMR_ApplyModeHysteresis
    legitimately returns "NONE" for a gating regime, an invalid/undefined
    mode score, or the initial neutral state -- these are normal,
    fail-closed decisions the schema must accept, not reject alongside a
    genuinely invalid mode string."""

    record = validate_record(make_valid_record(intraday_mode="NONE"))
    assert record.intraday_mode == "NONE"


def test_invalid_intraday_mode_literal_rejected():
    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(intraday_mode="SWING"))


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


@pytest.mark.parametrize(
    "field",
    ["signal_id", "strategy", "setup", "session_state", "ea_version", "git_commit"],
)
def test_blank_identity_provenance_field_rejected(field):
    """Regression for a Codex review finding (2026-07-22, eighth round, P1
    finding 19): signal_id/strategy/setup/session_state/ea_version/
    git_commit were all plain `str` (no min_length), so a blank value for
    any of them was silently accepted -- inconsistent with 'symbol', which
    already required min_length=1. Every one of these is a real identity/
    provenance field this project's own journal-uniqueness/join/audit-trail
    guarantees depend on."""

    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(**{field: ""}))


@pytest.mark.parametrize(
    "field",
    ["signal_id", "symbol", "strategy", "setup", "session_state", "ea_version", "git_commit"],
)
def test_whitespace_only_identity_provenance_field_rejected(field):
    """Regression for a Codex review finding (2026-07-27, ninth round, P1
    finding 17): `Field(min_length=1)` alone did NOT reject a
    whitespace-only value -- this model deliberately runs with
    `str_strip_whitespace=False`, so a lone space satisfies min_length=1
    without ever being stripped first. A focused probe reproduced this for
    every field in this list (session_state now rejects via its own
    Literal restriction instead of the shared strip-and-reject validator,
    but the OUTCOME -- rejection -- must be identical)."""

    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(**{field: "   "}))


@pytest.mark.parametrize(
    "field", ["signal_id", "symbol", "strategy", "setup", "ea_version", "git_commit"]
)
def test_identity_provenance_field_is_stripped_not_merely_rejected_when_blank(field):
    """The fix strips THEN rejects if blank -- a genuinely non-blank value
    with incidental leading/trailing whitespace must be accepted (and
    normalized), not rejected outright as if it were blank."""

    record = validate_record(make_valid_record(**{field: "  real-value  "}))
    assert getattr(record, field) == "real-value"


def test_session_state_accepts_all_three_real_producer_values():
    """Regression for a Codex review finding (2026-07-27, ninth round, P1
    finding 17): session_state previously accepted ANY non-blank string,
    even though ThembaAdaptiveIntradayEA.mq5's own producer has an exact
    three-value vocabulary."""

    for value in (
        "SESSION_TIME_REMAINING_UNKNOWN",
        "SESSION_TIME_REMAINING_HIGH",
        "SESSION_TIME_REMAINING_LOW",
    ):
        record = validate_record(make_valid_record(session_state=value))
        assert record.session_state == value


def test_session_state_rejects_out_of_vocabulary_value():
    """The review's own reproduced counterexample: an arbitrary token
    (e.g. a session-name string like 'london') was previously accepted as
    a valid session_state despite not being one of the producer's own
    three real values."""

    with pytest.raises(SchemaValidationError):
        validate_record(make_valid_record(session_state="london"))
