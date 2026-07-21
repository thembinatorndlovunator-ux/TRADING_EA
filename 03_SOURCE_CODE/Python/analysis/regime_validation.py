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
synthetic fixtures for each of the seven directly-computed regime states
(``NEWS_BLACKOUT``/``UNTRADEABLE_SPREAD_OR_LIQUIDITY`` are gating
overrides applied BEFORE this function per section 2, not states this
function itself selects -- see ``MarketRegimeEngine.mqh``'s own
``MRE_IsUntradeableSpreadOrLiquidity``, not ported here either).
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Sequence

import pandas as pd


class Regime(str, Enum):
    TRENDING_UP = "TRENDING_UP"
    TRENDING_DOWN = "TRENDING_DOWN"
    RANGING = "RANGING"
    VOLATILITY_EXPANSION_UP = "VOLATILITY_EXPANSION_UP"
    VOLATILITY_EXPANSION_DOWN = "VOLATILITY_EXPANSION_DOWN"
    COMPRESSION = "COMPRESSION"
    TRANSITION_OR_UNCERTAIN = "TRANSITION_OR_UNCERTAIN"


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
