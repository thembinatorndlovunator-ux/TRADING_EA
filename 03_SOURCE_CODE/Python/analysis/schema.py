"""Pydantic schema for a single TradeDecision journal record.

Field-for-field match to the repo-root ``TRADE_DECISION_SCHEMA.json`` and to
``03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh``'s
``STradeDecision``/``DJ_SerializeDecision`` (the MQL5 side that actually
writes these lines). This module owns validation only -- it does not read
files (see ``data_collection/journal_reader.py``) and does not compute any
statistic.

Deliberately strict, per the reproducibility contract in
``TASK-028_PYTHON_STATISTICAL_LAB.md``: "Schema errors, missing timestamps,
duplicates, and timezone failures are visible failures, never silently
coerced into plausible results." A record that fails validation is a
reportable error for the caller to surface, not something this module
silently repairs.

**Known, confirmed cross-layer gap (not a bug in this module):**
``market_family`` and ``intraday_mode`` are part of the documented schema
(``METAL|SYNTHETIC`` and ``SCALP|DAY_TRADE`` respectively) but
``ThembaAdaptiveIntradayEA.mq5`` (TASK-025/027) never actually sets either
field -- both stay at ``DJ_NewDecision()``'s empty-string default in every
real journal line the current EA build produces. This model still enforces
the DOCUMENTED schema strictly (rejecting an empty string for either field),
so real journal files from the current EA build will show up as schema
validation failures on these two fields until a future MQL5-side task
populates them -- that is the correct, visible behavior per reproducibility
rule 5, not something this module should paper over by silently loosening
the constraint. See TASK-028_PYTHON_STATISTICAL_LAB.md's Risks section.
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


class TradeDecision(BaseModel):
    """One TradeDecision journal record, per TRADE_DECISION_SCHEMA.json."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=False)

    signal_id: str
    timestamp_utc: datetime
    symbol: str = Field(min_length=1)
    market_family: Literal["METAL", "SYNTHETIC"]
    intraday_mode: Literal["SCALP", "DAY_TRADE"]
    regime: str
    regime_confidence: StrictFloat = Field(ge=0.0, le=100.0)
    direction: Literal["BUY", "SELL", "NONE"]
    strategy: str
    setup: str
    candlestick_pattern: Optional[str] = None
    chart_pattern: Optional[str] = None
    score: StrictFloat = Field(ge=0.0, le=100.0)
    score_breakdown: dict = Field(default_factory=dict)
    entry: Optional[StrictFloat] = None
    stop: Optional[StrictFloat] = None
    targets: list[StrictFloat] = Field(default_factory=list)
    risk_percent: StrictFloat
    news_state: str
    session_state: str
    reasons_passed: list[str] = Field(default_factory=list)
    reasons_rejected: list[str] = Field(default_factory=list)
    ea_version: str
    git_commit: str
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
