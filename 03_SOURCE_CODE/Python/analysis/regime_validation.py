"""regime_validation.py -- Python port of MarketRegimeEngine.mqh's
(TASK-016) ``MRE_ClassifyArray`` classification formula, for independent
cross-checking and synthetic-fixture confusion-matrix validation. This is
the deferred work TASK-016's own task file named ("regime
fixtures/confusion matrix") and TASK-028_PYTHON_STATISTICAL_LAB.md folds
in as work this Python layer now owns.

**Not a full port of the regime engine.** ``MRE_ClassifyArray`` itself
computes ``swing_agreement``/``direction_agree`` from
``MarketStructure.mqh``'s bias output (BOS/CHoCH-derived structure), which
is a separate, substantial module this task does not re-implement in
Python. This port accepts ``swing_agreement``/``direction_agree`` as
CALLER-SUPPLIED inputs instead -- it validates the regime-selection
FORMULA (the T/T_final/E/ER math and the nine-state decision tree) given
already-known structure inputs, not the structure computation itself. A
future task porting ``MarketStructure.mqh`` to Python would let this
module's fixtures also cross-check a real bias computation end-to-end.

**No confusion matrix against independently-labelled evidence yet** -- per
reproducibility rule 7, no real, independently-labelled regime dataset
exists in this project. ``build_confusion_matrix`` is provided as a
ready-to-use utility for when one does; this module's own tests instead
validate the classification formula itself against hand-constructed
synthetic fixtures for each of the seven directly-computed regime states.
Producing that real evidence is ``TASK-037``'s own deliverable (its
``Export_PredictedRegime.mq5`` + ``REGIME_LABELLING_PROTOCOL.md``), not
this module's -- see ``TASK-031_REGIME_VALIDATION_COMPLETION.md``'s own
Objective for why this scope split exists.

**TASK-031 additions (2026-07-22): gating overrides, hysteresis, and a
transition-history buffer, all ported from ``MarketRegimeEngine.mqh``:**

- ``is_untradeable_spread_or_liquidity`` -- direct port of
  ``MRE_IsUntradeableSpreadOrLiquidity``. ``NEWS_BLACKOUT``'s own trigger
  (an active news-blackout window) lives in ``NewsManager.mqh``, a
  separate module outside this task's scope -- this port only covers the
  spread/liquidity gate; a caller applies both gates as overrides BEFORE
  ``classify()``'s own decision tree, exactly as
  ``RegimeGateComposer.mqh`` does on the MQL5 side.
- ``RegimeHysteresisState``/``init_hysteresis_state``/``apply_hysteresis``
  -- direct port of ``SRegimeHysteresisState``/``MRE_InitHysteresisState``/
  ``MRE_ApplyHysteresis``. Stateful across calls, by design (matching the
  MQL5 struct's own mutate-in-place convention) -- callers thread the same
  ``RegimeHysteresisState`` instance across a multi-bar sequence, never a
  fresh one per bar.
- ``RegimeTransitionHistory`` -- a NEW, Python-side-only offline analysis
  tool: a bounded ring buffer of ``(timestamp, from_regime, to_regime)``
  entries, appended only on a genuine CONFIRMED transition (never a
  pending/unconfirmed flap). **This is explicitly NOT the same thing as
  the live MQL5 ``MarketRegimeEngine.mqh``'s own required transition-
  history buffer** (``00_MASTER_PROMPT_FOR_CLAUDE.md`` section 6) -- that
  live-engine deliverable remains unregistered and unowned by any
  numbered task; this class only replays/analyzes already-recorded
  regime sequences offline and does not close that requirement.
- **Bias/structure-input decision (TASK-031 Specification item 4),
  explicitly confirmed, not silently deferred again:** ``classify()``
  continues to accept ``swing_agreement``/``direction_agree`` as
  CALLER-SUPPLIED inputs. Porting ``MarketStructure.mqh``'s own BOS/CHoCH
  bias computation to Python is a separate, substantial module this task
  does not attempt -- a future task may port it; until then, any fixture
  or real-data run using this module must supply its own bias inputs
  (synthetic fixtures do so directly; a real run would need
  ``MarketStructure.mqh``'s own live output recorded alongside the
  regime, which no export currently produces).
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import Enum
from typing import Optional, Sequence

import pandas as pd


class Regime(str, Enum):
    TRENDING_UP = "TRENDING_UP"
    TRENDING_DOWN = "TRENDING_DOWN"
    RANGING = "RANGING"
    VOLATILITY_EXPANSION_UP = "VOLATILITY_EXPANSION_UP"
    VOLATILITY_EXPANSION_DOWN = "VOLATILITY_EXPANSION_DOWN"
    COMPRESSION = "COMPRESSION"
    TRANSITION_OR_UNCERTAIN = "TRANSITION_OR_UNCERTAIN"
    NEWS_BLACKOUT = "NEWS_BLACKOUT"
    UNTRADEABLE_SPREAD_OR_LIQUIDITY = "UNTRADEABLE_SPREAD_OR_LIQUIDITY"


def _clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


@dataclass(frozen=True)
class RegimeRead:
    valid: bool
    regime: Regime
    confidence: float
    T: float
    T_final: float
    E: float
    ER: float


def classify(
    closes: Sequence[float],
    atr_percentile_values: Sequence[float],
    current_atr: float,
    ema_now: float,
    ema_prior: float,
    adx_now: float,
    efficiency_window: int,
    trend_threshold: float,
    expansion_threshold: float,
    compression_threshold: float,
    min_efficiency: float,
    trend_slope_atr_divisor: float,
    swing_agreement: float,
    direction_agree: bool,
) -> RegimeRead:
    """Direct port of MRE_ClassifyArray's math (structure/bias inputs
    supplied by the caller -- see module docstring). 'closes' index 0 must
    be the most recent bar (this project's logical-index convention, same
    as the MQL5 source); index 'efficiency_window' is the bar
    'efficiency_window' bars ago."""

    invalid = RegimeRead(False, Regime.TRANSITION_OR_UNCERTAIN, 0.0, 0.0, 0.0, 0.0, 0.0)

    n = len(closes)
    if efficiency_window <= 0 or efficiency_window >= n:
        return invalid

    # **Added, 2026-07-22 Codex review finding (seventh round, P1 finding
    # 15): non-finite inputs (NaN/inf) must be rejected outright, not
    # silently propagated through _clamp01 -- a NaN current_atr previously
    # slipped past the `current_atr <= 0.0` guard below (NaN comparisons
    # are always False in Python) and could still classify as a "valid"
    # TRENDING_UP/etc. result. A zero trend_slope_atr_divisor previously
    # raised a raw ZeroDivisionError instead of a clean domain error.**
    scalar_inputs = {
        "current_atr": current_atr,
        "ema_now": ema_now,
        "ema_prior": ema_prior,
        "adx_now": adx_now,
        "trend_threshold": trend_threshold,
        "expansion_threshold": expansion_threshold,
        "compression_threshold": compression_threshold,
        "min_efficiency": min_efficiency,
        "trend_slope_atr_divisor": trend_slope_atr_divisor,
        "swing_agreement": swing_agreement,
    }
    for name, value in scalar_inputs.items():
        if not math.isfinite(value):
            raise ValueError(f"classify: {name} must be finite, got {value!r}")

    # **Extended, 2026-07-22 Codex review finding (eighth round, P1 finding
    # 19): the seventh-round fix above only rejected non-finite/exactly-zero
    # inputs -- trend_threshold=0 still reached a raw division by zero
    # below (confidence = 1.0 - t_final / trend_threshold), and a NEGATIVE
    # trend_slope_atr_divisor previously returned a "valid" read even
    # though MarketRegimeEngine.mqh's own MRE_ClampTrendSlopeAtrDivisor
    # documents the canonical domain as strictly positive and bounded
    # ([0.05, 5.0], per that file's own clamper -- this Python port
    # validates against the SAME bounds the MQL5 source clamps to, rather
    # than silently clamping itself, per this project's own "visible
    # failures, never silently coerced" reproducibility contract: a caller
    # supplying an out-of-domain value at this PUBLIC ingestion boundary
    # has a real, reportable bug upstream, not something to paper over).
    # Every other threshold/agreement/ADX domain MarketRegimeEngine.mqh's
    # own clampers document is validated here too.**
    domain_bounds = {
        "trend_threshold": (0.3, 0.9),
        "expansion_threshold": (0.55, 0.95),
        "compression_threshold": (0.05, 0.45),
        "min_efficiency": (0.05, 0.6),
        "trend_slope_atr_divisor": (0.05, 5.0),
        "swing_agreement": (0.0, 1.0),
        "adx_now": (0.0, 100.0),
    }
    for name, (lo, hi) in domain_bounds.items():
        value = scalar_inputs[name]
        if not (lo <= value <= hi):
            raise ValueError(
                f"classify: {name}={value!r} is outside its canonical domain [{lo}, {hi}] "
                f"(see MarketRegimeEngine.mqh's own MRE_Clamp* functions)"
            )

    if any(not math.isfinite(c) for c in closes):
        raise ValueError("classify: 'closes' contains a non-finite value")
    if any(not math.isfinite(v) for v in atr_percentile_values):
        raise ValueError("classify: 'atr_percentile_values' contains a non-finite value")

    # --- Efficiency ratio ----------------------------------------------------
    num = abs(closes[0] - closes[efficiency_window])
    den = sum(abs(closes[i] - closes[i - 1]) for i in range(1, efficiency_window + 1))
    if den == 0.0:
        er = 0.0
        er_fails_efficiency = True
    else:
        er = num / den
        er_fails_efficiency = er < min_efficiency

    # --- Expansion/compression evidence E (ATR percentile) --------------------
    atr_n = len(atr_percentile_values)
    if atr_n < 2 or current_atr <= 0.0:
        return invalid

    total = atr_n - 1
    less_count = 0.0
    for i in range(1, atr_n):
        if atr_percentile_values[i] < current_atr:
            less_count += 1.0
        elif atr_percentile_values[i] == current_atr:
            less_count += 0.5
    e = less_count / total

    # --- Trend strength T ------------------------------------------------------
    ema_diff = ema_now - ema_prior
    ema_slope_norm = _clamp01(abs(ema_diff) / (current_atr * trend_slope_atr_divisor))
    t = _clamp01(0.5 * swing_agreement + 0.5 * ema_slope_norm)

    # --- T_final via ADX ---------------------------------------------------------
    adx_multiplier = _clamp01(0.5 + adx_now / 100.0)
    t_final = t * adx_multiplier

    overall_up = ema_diff > 0.0

    # --- State selection, strict priority, no fallthrough --------------------------
    if er_fails_efficiency:
        regime = Regime.RANGING
        confidence = _clamp01(1.0 - t_final / trend_threshold)
    elif e > expansion_threshold:
        if direction_agree:
            regime = (
                Regime.VOLATILITY_EXPANSION_UP if overall_up else Regime.VOLATILITY_EXPANSION_DOWN
            )
            confidence = _clamp01((e - expansion_threshold) / (1.0 - expansion_threshold))
        else:
            regime = Regime.TRANSITION_OR_UNCERTAIN
            confidence = 0.0
    elif t_final >= trend_threshold and direction_agree:
        regime = Regime.TRENDING_UP if overall_up else Regime.TRENDING_DOWN
        confidence = _clamp01((t_final - trend_threshold) / (1.0 - trend_threshold))
    elif e < compression_threshold:
        regime = Regime.COMPRESSION
        confidence = _clamp01((compression_threshold - e) / compression_threshold)
    else:
        regime = Regime.RANGING
        confidence = _clamp01(1.0 - t_final / trend_threshold)

    return RegimeRead(
        valid=True, regime=regime, confidence=confidence, T=t, T_final=t_final, E=e, ER=er
    )


def is_untradeable_spread_or_liquidity(
    current_spread: float,
    atr: float,
    max_spread_atr_multiple: float,
    avg_ticks_per_bar: float,
    min_liquidity_ticks_per_bar: float,
) -> bool:
    """Direct port of MRE_IsUntradeableSpreadOrLiquidity -- see module
    docstring for why NEWS_BLACKOUT's own trigger is not ported here."""

    if atr > 0.0 and current_spread > atr * max_spread_atr_multiple:
        return True
    if min_liquidity_ticks_per_bar > 0.0 and avg_ticks_per_bar < min_liquidity_ticks_per_bar:
        return True
    return False


@dataclass
class RegimeHysteresisState:
    """Direct port of SRegimeHysteresisState. Mutable and stateful by
    design -- a caller threads the SAME instance across a multi-bar
    sequence of apply_hysteresis() calls, exactly matching
    MRE_ApplyHysteresis's own mutate-in-place convention on the MQL5 side.
    Construct via init_hysteresis_state(), not directly, to match that
    function's exact defaults."""

    has_confirmed: bool
    confirmed_regime: Regime
    pending_regime: Regime
    pending_count: int


def init_hysteresis_state() -> RegimeHysteresisState:
    """Direct port of MRE_InitHysteresisState."""

    return RegimeHysteresisState(
        has_confirmed=False,
        confirmed_regime=Regime.TRANSITION_OR_UNCERTAIN,
        pending_regime=Regime.TRANSITION_OR_UNCERTAIN,
        pending_count=0,
    )


def apply_hysteresis(
    state: RegimeHysteresisState,
    raw_regime: Regime,
    bypass_hysteresis: bool,
    required_bars: int = 2,
) -> Regime:
    """Direct port of MRE_ApplyHysteresis. Mutates 'state' in place and
    returns the EFFECTIVE (confirmed, or bypassed) regime -- before a
    first confirmation exists, an unconfirmed read reports
    TRANSITION_OR_UNCERTAIN rather than a half-confirmed guess, matching
    the MQL5 source exactly."""

    # **Added, 2026-07-22 Codex review finding (seventh round, P1 finding
    # 15): required_bars=0 was previously accepted even though a
    # confirmation-bar count must be positive -- required_bars=0 makes
    # `pending_count >= required_bars` true on the FIRST ever pending read,
    # confirming a regime with zero actual hysteresis at all.**
    if required_bars <= 0:
        raise ValueError(f"apply_hysteresis: required_bars must be positive, got {required_bars}")

    if bypass_hysteresis:
        state.confirmed_regime = raw_regime
        state.has_confirmed = True
        state.pending_regime = raw_regime
        state.pending_count = required_bars
        return raw_regime

    if state.pending_regime != raw_regime:
        state.pending_regime = raw_regime
        state.pending_count = 1
    else:
        state.pending_count += 1

    if state.pending_count >= required_bars:
        state.confirmed_regime = raw_regime
        state.has_confirmed = True

    return state.confirmed_regime if state.has_confirmed else Regime.TRANSITION_OR_UNCERTAIN


@dataclass(frozen=True)
class RegimeTransition:
    """One CONFIRMED regime transition -- never a pending/unconfirmed flap
    that hysteresis never actually resolved. 'timestamp' is the real bar
    timestamp the transition was confirmed on (not a bar-index alone), so
    the buffer stays meaningful across gaps/resumptions in the underlying
    bar sequence."""

    timestamp: object  # a real timestamp (e.g. pandas.Timestamp/datetime) -- caller's own type
    from_regime: Regime
    to_regime: Regime


class RegimeTransitionHistory:
    """A bounded ring buffer of CONFIRMED regime transitions, for OFFLINE
    Python-side analysis of an already-recorded regime sequence -- see
    module docstring for why this is explicitly NOT the same deliverable
    as the live MQL5 MarketRegimeEngine.mqh's own required transition-
    history buffer (that remains a separate, unregistered task).

    Capacity default of 500 entries is this task's own stated, justified
    choice: even in the (implausible) worst case of a genuine confirmed
    transition on every single bar, 500 entries covers several weeks of
    M15-cadence trading activity; in practice transitions are far rarer
    (each requires 'required_bars' consecutive confirmations), so 500
    gives a generously long real window while keeping memory/
    serialization bounded, per this task's own capacity/retention
    requirement (Specification item 3a)."""

    def __init__(self, max_entries: int = 500) -> None:
        if max_entries <= 0:
            raise ValueError(f"max_entries must be a positive integer, got {max_entries}")
        self._max_entries = max_entries
        self._entries: list[RegimeTransition] = []
        self._last_confirmed_regime: Optional[Regime] = None

    def record_confirmed(
        self, timestamp: object, confirmed_regime: Regime, has_confirmed: bool
    ) -> None:
        """Call once per bar with apply_hysteresis()'s own return value AND
        the SAME RegimeHysteresisState's own 'has_confirmed' flag (i.e.
        'state.has_confirmed' right after that same apply_hysteresis()
        call) -- appends a new entry ONLY when the confirmed regime
        genuinely differs from the last one recorded -- repeated
        confirmations of the same regime (the common case, bar after
        bar) never append a duplicate entry. Evicts the oldest entry once
        max_entries is exceeded (a true ring buffer, not an unbounded
        list).

        **Fixed, 2026-07-22 Codex review finding (seventh round, P1 finding
        15): before hysteresis's FIRST genuine confirmation,
        apply_hysteresis() returns the TRANSITION_OR_UNCERTAIN sentinel --
        which is indistinguishable, at the enum level alone, from a
        regime that later becomes GENUINELY confirmed as
        TRANSITION_OR_UNCERTAIN. Calling this method during that
        pre-confirmation window previously seeded _last_confirmed_regime
        with the sentinel, so the very FIRST real confirmation recorded a
        phantom "transition" FROM that sentinel, even though no regime
        was ever actually confirmed before it. 'has_confirmed' (the
        caller's own state.has_confirmed) disambiguates this -- a call
        made before hysteresis has ever confirmed anything is ignored
        entirely, neither seeding _last_confirmed_regime nor recording a
        transition.**"""

        if not has_confirmed:
            return  # nothing genuinely confirmed yet -- never seed from or transition from a
                     # placeholder sentinel

        if (
            self._last_confirmed_regime is not None
            and confirmed_regime != self._last_confirmed_regime
        ):
            self._entries.append(
                RegimeTransition(timestamp, self._last_confirmed_regime, confirmed_regime)
            )
            if len(self._entries) > self._max_entries:
                self._entries.pop(0)
        self._last_confirmed_regime = confirmed_regime

    @property
    def entries(self) -> list[RegimeTransition]:
        """A defensive copy -- callers must not mutate this buffer's
        internal state directly."""

        return list(self._entries)

    def __len__(self) -> int:
        return len(self._entries)


def build_confusion_matrix(predicted: Sequence[str], actual: Sequence[str]) -> pd.DataFrame:
    """Standard confusion matrix (rows = actual, columns = predicted) for
    when a real, independently-labelled regime dataset exists (see module
    docstring -- none does yet in this project). Raises ValueError if the
    two sequences have different lengths or either is empty."""

    if len(predicted) != len(actual):
        raise ValueError(
            f"predicted (n={len(predicted)}) and actual (n={len(actual)}) must be equal length"
        )
    if not predicted:
        raise ValueError("build_confusion_matrix: empty input")

    df = pd.DataFrame({"actual": actual, "predicted": predicted})
    return pd.crosstab(df["actual"], df["predicted"])
