"""Pydantic schema for a single TradeDecision journal record.

Field-for-field match to the repo-root ``TRADE_DECISION_SCHEMA.json`` and to
``03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh``'s
``STradeDecision``/``DJ_SerializeDecision`` (the MQL5 side that actually
writes these lines).

**Corrected, 2026-07-22 (Codex review finding, eighth round, P1 finding 19):**
this docstring previously claimed `order_id`/`deal_id` existed ONLY here and
in the JSON schema, ahead of any MQL5-side population -- stale since TASK-036
shipped: `DecisionJournal.mqh`'s `STradeDecision` struct has carried both
fields for several rounds now (`order_id` = `SOrderOpenResult.position_id`,
`deal_id` = `SOrderOpenResult.deal_ticket`, both nullable per that struct's
own field comments), `TRADE_DECISION_SCHEMA.json` documents both as
`"string|null"`, and the live EA (`ThembaAdaptiveIntradayEA.mq5`'s
`AttemptOrderSubmission`) populates `order_id` on every synchronous fill. This
module owns validation only -- it does not read files (see
``data_collection/journal_reader.py``) and does not compute any statistic.

Deliberately strict, per the reproducibility contract in
``TASK-028_PYTHON_STATISTICAL_LAB.md``: "Schema errors, missing timestamps,
duplicates, and timezone failures are visible failures, never silently
coerced into plausible results." A record that fails validation is a
reportable error for the caller to surface, not something this module
silently repairs.

**Formerly a known, confirmed cross-layer gap -- now closed (2026-07-22,
TASK-040 / Codex review finding, seventh round, P1 finding 18):**
``market_family`` and ``intraday_mode`` were part of the documented schema
but ``ThembaAdaptiveIntradayEA.mq5`` (TASK-025/027) did not yet set either
field. TASK-040 wired ``IntradayModeRouter.mqh``'s live classifier into the
EA's own decision journaling, so both fields are now populated on every
real journal line. **The vocabulary itself needed a fix too:** this schema
previously declared ``market_family: Literal["METAL", "SYNTHETIC"]``, but
the live router (``IMR_MarketFamilyToString``) emits exactly one of
``METAL``, ``FOREX``, ``SYNTHETIC_INDEX``, or ``UNKNOWN`` -- three of the
four real values (including the intended synthetic-index value itself)
previously failed schema validation on every real journal line. The
``Literal`` below now matches the live producer's actual vocabulary
exactly, not an earlier, never-implemented two-value guess.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, StrictFloat, field_validator

from analysis.time_utils import TimezoneValidationError, ensure_utc

# Regime enum values, verbatim from MarketRegimeEngine.mqh's ENUM_MARKET_REGIME
# (via EnumToString, which returns the C-style enum member name).
KNOWN_REGIMES = frozenset(
    {
        "REGIME_TRENDING_UP",
        "REGIME_TRENDING_DOWN",
        "REGIME_RANGING",
        "REGIME_VOLATILITY_EXPANSION_UP",
        "REGIME_VOLATILITY_EXPANSION_DOWN",
        "REGIME_COMPRESSION",
        "REGIME_TRANSITION_OR_UNCERTAIN",
        "REGIME_NEWS_BLACKOUT",
        "REGIME_UNTRADEABLE_SPREAD_OR_LIQUIDITY",
    }
)


class SchemaValidationError(ValueError):
    """Raised (wrapping pydantic's own error) when a single journal record
    fails schema validation -- callers must treat this as a reportable
    failure, never silently skip it without recording why."""


# Identity/provenance fields where a whitespace-only value is exactly as
# meaningless as an empty one -- Codex review finding, ninth round, P1
# finding 17: `Field(min_length=1)` alone is not sufficient here because
# this model deliberately runs with `str_strip_whitespace=False` (so that
# OTHER string fields -- candlestick_pattern/chart_pattern/regime/free-text
# reasons -- are never silently mangled by an implicit strip this schema
# does not intend for them); a lone space satisfies min_length=1 without
# ever being stripped first. See `_strip_and_reject_blank` below.
# ('session_state' is not listed here -- it is now a Literal of its real
# three-value producer vocabulary, which cannot match a blank/whitespace
# string in the first place.)
IDENTITY_PROVENANCE_FIELDS = (
    "signal_id",
    "symbol",
    "strategy",
    "setup",
    "ea_version",
    "git_commit",
)


class TradeDecision(BaseModel):
    """One TradeDecision journal record, per TRADE_DECISION_SCHEMA.json."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=False)

    # **Fixed, 2026-07-22 Codex review finding (eighth round, P1 finding
    # 19): signal_id/strategy/setup/session_state/ea_version/git_commit
    # below were all plain `str` (no min_length), so a blank value for any
    # of them was silently accepted -- inconsistent with 'symbol', which
    # already required min_length=1 as a real identity field. Every one of
    # these is likewise a real identity/provenance field this project's
    # own journal-uniqueness/join/audit-trail guarantees depend on (a
    # blank signal_id in particular defeats the whole point of it being a
    # durable join key); blank is now rejected at this schema boundary for
    # all of them, matching 'symbol''s own established precedent, rather
    # than relying on an assumed prior producer never emitting one.**
    signal_id: str = Field(min_length=1)
    timestamp_utc: datetime
    symbol: str = Field(min_length=1)
    market_family: Literal["METAL", "FOREX", "SYNTHETIC_INDEX", "UNKNOWN"]
    # **Fixed, 2026-07-22 Codex review finding (eighth round, P1 finding 12):
    # IntradayModeRouter.mqh's own IMR_ApplyModeHysteresis legitimately
    # returns INTRADAY_MODE_NONE (-> "NONE") for a gating regime, an
    # invalid/undefined mode score, or the initial neutral state before any
    # mode has ever been confirmed -- these are normal, fail-closed
    # decisions, not producer bugs. Restricting this Literal to only
    # SCALP/DAY_TRADE rejected every one of them at the schema boundary,
    # right alongside JournalDataFailureDecision's own data-read-failure
    # rows (which previously fabricated "SCALP" specifically to dodge this
    # same rejection -- see that function's own corrected comment). "NONE"
    # is now the real producer's third legitimate value, not an omission.**
    intraday_mode: Literal["SCALP", "DAY_TRADE", "NONE"]
    regime: str
    regime_confidence: StrictFloat = Field(ge=0.0, le=100.0)
    direction: Literal["BUY", "SELL", "NONE"]
    strategy: str = Field(min_length=1)
    setup: str = Field(min_length=1)
    candlestick_pattern: Optional[str] = None
    chart_pattern: Optional[str] = None
    score: StrictFloat = Field(ge=0.0, le=100.0)
    score_breakdown: dict = Field(default_factory=dict)
    entry: Optional[StrictFloat] = None
    stop: Optional[StrictFloat] = None
    targets: list[StrictFloat] = Field(default_factory=list)
    risk_percent: StrictFloat
    # **Fixed, 2026-07-22 Codex review finding (seventh round, P1 finding
    # 17): this accepted ANY string -- ThembaAdaptiveIntradayEA.mq5's own
    # ResolveNewsBlackout (TASK-034) defines news_state as EXACTLY "CLEAR"
    # or "BLACKOUT" (JournalDataFailureDecision also only ever emits
    # "CLEAR" -- see that function's own comment), so a direct "BANANA"
    # probe was accepted even though the two-value producer contract was
    # already documented in this module's own comments. Restricted to
    # match the real producer's vocabulary exactly.**
    # **Extended, 2026-07-22 Codex review finding (eighth round, P1 finding
    # 12): JournalDataFailureDecision previously fabricated "CLEAR" on a
    # data-read failure ("unknown -- not evaluated this bar") specifically
    # because this Literal had no legitimate "not evaluated" value to emit
    # instead -- silently attributing a data-failure bar to a real "no
    # news" reading it never actually confirmed, contaminating any
    # analysis grouped by news_state. "UNKNOWN" is now that producer's
    # real, honest third value ("BANANA"-style genuinely invalid input
    # remains rejected -- see test_unknown_news_state_rejected).**
    news_state: Literal["CLEAR", "BLACKOUT", "UNKNOWN"]
    # **Fixed, 2026-07-27 Codex review finding (ninth round, P1 finding 17):
    # this accepted ANY non-blank string, even though
    # ThembaAdaptiveIntradayEA.mq5's own producer has an exact three-value
    # vocabulary (KNOWN_SESSION_STATES above) -- matching market_family/
    # intraday_mode/news_state's own established Literal precedent rather
    # than leaving this one provenance field as free text.**
    session_state: Literal[
        "SESSION_TIME_REMAINING_UNKNOWN",
        "SESSION_TIME_REMAINING_HIGH",
        "SESSION_TIME_REMAINING_LOW",
    ]
    reasons_passed: list[str] = Field(default_factory=list)
    reasons_rejected: list[str] = Field(default_factory=list)
    ea_version: str = Field(min_length=1)
    git_commit: str = Field(min_length=1)
    # **Added, 2026-07-22 Codex review finding (third round): the durable
    # journal-decision-to-trade-outcome join (analysis/join_signal_to_outcome.py,
    # new) needs a stable key. Both optional/nullable since the live EA does
    # not populate them yet (TASK-036_JOURNAL_PRODUCER_COMPLETION.md owns
    # the MQL5-side population; this is the Python-schema half of that
    # task, done here so the consuming join pipeline can be real and
    # tested now rather than perpetually deferred). A decision rejected
    # before order submission legitimately has neither.**
    order_id: Optional[str] = None
    deal_id: Optional[str] = None

    @field_validator("timestamp_utc", mode="before")
    @classmethod
    def _timestamp_must_be_string(cls, value: object) -> object:
        # **Fixed, 2026-07-21 Codex review finding:** pydantic's default
        # (non-strict) datetime coercion accepts a bare int/float as a Unix
        # timestamp, even though the schema requires an ISO-8601 STRING
        # (DJ_FormatIso8601Utc never emits anything else). Reproduced
        # counterexample: `timestamp_utc=0` was silently converted to the
        # 1970 Unix epoch instead of being rejected. This `mode="before"`
        # check runs ahead of pydantic's own datetime parsing and rejects
        # any non-string input outright.
        if not isinstance(value, str):
            raise ValueError(
                f"timestamp_utc must be an ISO-8601 string, got {type(value).__name__}: {value!r}"
            )
        return value

    @field_validator("timestamp_utc")
    @classmethod
    def _must_be_utc(cls, value: datetime) -> datetime:
        # DJ_FormatIso8601Utc always writes a trailing "Z" -- pydantic parses
        # that as tz-aware UTC. A naive/non-UTC datetime here means the "Z"
        # was lost or the source was hand-edited; treat as a visible
        # failure, not an implicit UTC assumption (reproducibility rule 5).
        # Reuses time_utils.ensure_utc rather than re-deriving the check.
        try:
            return ensure_utc(value)
        except TimezoneValidationError as exc:
            raise ValueError(str(exc)) from exc

    # **Added, 2026-07-27 Codex review finding (ninth round, P1 finding 17):
    # `Field(min_length=1)` alone did not reject a whitespace-only value
    # (e.g. a single space) for any of IDENTITY_PROVENANCE_FIELDS -- this
    # model deliberately keeps `str_strip_whitespace=False` at the config
    # level (so candlestick_pattern/chart_pattern/regime/free-text reasons
    # are never silently mangled), so min_length's own length check ran
    # against the UN-stripped value, where a lone space has length 1. A
    # focused probe reproduced this for signal_id/symbol/strategy/setup/
    # session_state/ea_version/git_commit (session_state is now a Literal
    # instead, see that field's own comment, but the others remain plain
    # identity/provenance strings). This validator strips first, THEN
    # rejects if the result is empty -- applied ONLY to the fields named
    # above, never globally.**
    @field_validator(*IDENTITY_PROVENANCE_FIELDS, mode="before")
    @classmethod
    def _strip_and_reject_blank(cls, value: object) -> object:
        if isinstance(value, str):
            stripped = value.strip()
            if stripped == "":
                raise ValueError(
                    "must not be blank or whitespace-only -- this is a real identity/"
                    "provenance field, not free text"
                )
            return stripped
        return value

    @field_validator("regime")
    @classmethod
    def _known_regime(cls, value: str) -> str:
        if value not in KNOWN_REGIMES:
            raise ValueError(f"unrecognized regime '{value}' -- not in KNOWN_REGIMES")
        return value

    @field_validator("candlestick_pattern", "chart_pattern", mode="before")
    @classmethod
    def _reject_empty_string(cls, value: object) -> object:
        # **Fixed, 2026-07-21 Codex review finding:** this validator's own
        # comment always said an empty string must be REJECTED (only JSON
        # null is valid, per DJ_SerializeDecision's own convention -- see
        # class docstring), but the code simply returned the value
        # unchanged, so an empty string was silently accepted as if it
        # were a normal (if unusual) pattern name -- a no-op that
        # contradicted its own stated intent. Now actually raises.
        if value == "":
            raise ValueError(
                "must be JSON null (not an empty string) when absent, per "
                "DJ_SerializeDecision's own null-for-empty convention"
            )
        return value

    @field_validator("entry", "stop", "risk_percent")
    @classmethod
    def _finite_or_none(cls, value: Optional[float]) -> Optional[float]:
        if value is not None and not _is_finite(value):
            raise ValueError("must be a finite number (or null for entry/stop)")
        return value

    @field_validator("targets")
    @classmethod
    def _targets_all_finite(cls, value: list[float]) -> list[float]:
        # **Fixed, 2026-07-21 Codex review finding:** finiteness was
        # previously checked only for entry/stop; risk_percent and every
        # element of targets could carry NaN/Infinity straight through
        # (regime_confidence/score happen to already reject NaN as a side
        # effect of their ge/le bounds, since any comparison against NaN
        # is False in Python, but that was never a deliberate, tested
        # guarantee for targets or risk_percent). risk_percent is now
        # covered by the shared validator above.
        for v in value:
            if not _is_finite(v):
                raise ValueError(f"every target must be a finite number, got {v!r}")
        return value


def _is_finite(value: float) -> bool:
    return value == value and value not in (float("inf"), float("-inf"))  # noqa: PLR0124


def validate_record(raw: dict) -> TradeDecision:
    """Validates one raw (already-JSON-parsed) journal record.

    Raises ``SchemaValidationError`` (chaining pydantic's own
    ``ValidationError`` for detail) on any failure -- callers must catch
    this per-record and report it, never let a bad record silently vanish.
    """

    try:
        return TradeDecision.model_validate(raw)
    except Exception as exc:  # pydantic.ValidationError, or a manual raise above
        raise SchemaValidationError(str(exc)) from exc
