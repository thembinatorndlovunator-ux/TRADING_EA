"""pattern_validation.py -- Python ports of
``CandlestickPatternEngine.mqh``'s pattern predicates and
``ChartPatternEngine.mqh``'s double top/bottom + head-and-shoulders/
inverse chart patterns, validated against hand-constructed synthetic OHLC
fixtures, for independent cross-checking against the MQL5 source.

**TASK-033 (2026-07-22): candlestick coverage completed.** All 20
detector/predicate functions from ``CandlestickPatternEngine.mqh`` are now
ported: the original 4 (bullish/bearish pin bar incl. TASK-017's
wick-to-body fix, bullish/bearish engulfing) plus the 16 TASK-033 added
(dragonfly/gravestone rejection, marubozu, doji, spinning top, inside/
outside bar, tweezer top/bottom, harami-detect + harami-confirmed,
morning/evening star, three white soldiers/three black crows, three-bar
reversal). Each is kept algebraically identical to the MQL5 source, never
re-derived.

**Chart patterns (TASK-033):** double top/bottom and head-and-shoulders/
inverse, ported from ``ChartPatternEngine.mqh``, including the sloped-
neckline linear interpolation. **Scope boundary, matching
``ChartPatternEngine.mqh``'s own current implementation exactly:** triple
top/bottom and the other 13 master-prompt chart-pattern families
(triangles, rectangle, flags, pennant, wedges, parallel channel,
cup-and-handle) are NOT ported here -- ``TASK-039_CHART_PATTERN_COMPLETION.md``
owns building those in MQL5 first; this module cannot port what does not
exist in the MQL5 source yet.

These chart patterns depend on a minimal port of ``SwingEngine.mqh``'s own
confirmed-pivot predicate (``is_confirmed_swing_high``/
``is_confirmed_swing_low`` and their nearest-match finders below) --
**explicitly scoped to just the pivot predicate this file's own patterns
need, not a full ``SwingEngine.mqh`` port** (that module has its own
broader responsibilities this task does not attempt to replicate).

**Array convention, stated explicitly (a common point of confusion this
project has flagged before):** these functions use the SAME "logical
index" convention as the MQL5 side -- index 0 is the MOST RECENTLY
completed bar, increasing index is OLDER (opposite of a typical
chronologically-ascending pandas DataFrame). A caller building these
arrays from ascending-time OHLC data must reverse it first.

**Cross-check against a real MQL5-exported detector-results CSV** is
possible for the original 4 patterns via ``Export_PatternDetectorResults.mq5``
(``TASK-037``), but that export is intentionally scoped to only those 4
(matching what ``detect_all_patterns()`` computed when that export was
built) -- extending the export to cover TASK-033's newly-ported patterns
is a follow-up, not yet done. No MQL5 export exists yet for the chart
patterns either. ``compare_to_mql5_export`` remains a generic join/diff
utility for whichever exports exist.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Optional, Sequence

import pandas as pd

from analysis.csv_io import (
    CsvSchemaError,
    assert_finite_columns,
    assert_high_low_geometry,
    assert_output_paths_distinct,
    assert_path_not_same_file,
    assert_unique_ids,
    atomic_write_dataframe_csv,
    read_csv_with_required_columns,
    read_csv_with_required_columns_and_hash,
)
from analysis.report_metadata import atomic_write_text, build_report_metadata

CP_BODY_EPSILON = 0.00001
CP_PIN_BAR_MIN_WICK_TO_BODY = 2.0

REQUIRED_OHLC_COLUMNS = {"open", "high", "low", "close"}


@dataclass(frozen=True)
class CandleRatios:
    body: float
    range: float
    upper_wick: float
    lower_wick: float
    body_ratio: float
    upper_wick_ratio: float
    lower_wick_ratio: float
    upper_wick_to_body: float
    lower_wick_to_body: float
    valid: bool


def measure_ratios(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
) -> CandleRatios:
    """Direct port of CP_MeasureRatiosArray. A zero-range bar (high==low)
    never qualifies for any pattern, per section 5 -- 'valid' is False in
    that case, matching the MQL5 source's own early return."""

    n = len(closes)
    invalid = CandleRatios(0, 0, 0, 0, 0, 0, 0, 0, 0, False)
    if k < 0 or k >= n:
        return invalid

    o, h, low, c = opens[k], highs[k], lows[k], closes[k]
    candle_range = h - low
    if candle_range <= 0.0:
        return invalid

    body = abs(c - o)
    upper_wick = h - max(o, c)
    lower_wick = min(o, c) - low

    return CandleRatios(
        body=body,
        range=candle_range,
        upper_wick=upper_wick,
        lower_wick=lower_wick,
        body_ratio=body / candle_range,
        upper_wick_ratio=upper_wick / candle_range,
        lower_wick_ratio=lower_wick / candle_range,
        upper_wick_to_body=upper_wick / max(body, CP_BODY_EPSILON),
        lower_wick_to_body=lower_wick / max(body, CP_BODY_EPSILON),
        valid=True,
    )


def size_percentile(highs: Sequence[float], lows: Sequence[float], k: int, window: int) -> float:
    """Direct port of CP_SizePercentileArray (average-rank percentile of
    range[k] against the trailing 'window' OLDER candles, k+1..k+window)."""

    n = len(highs)
    if k < 0 or k >= n:
        return 0.0

    end = min(k + window, n - 1)
    total = end - k
    if total <= 0:
        return 1.0  # no comparison history -- cannot be disproven as large

    range_k = highs[k] - lows[k]
    less_count = 0.0
    for i in range(k + 1, end + 1):
        r = highs[i] - lows[i]
        if r < range_k:
            less_count += 1.0
        elif r == range_k:
            less_count += 0.5
    return less_count / total


def atr_size(
    highs: Sequence[float], lows: Sequence[float], atr_values: Sequence[float], k: int
) -> float:
    """Direct port of CP_AtrSizeArray: range[k]/ATR[k]."""

    n = len(highs)
    if k < 0 or k >= n:
        return 0.0
    candle_range = highs[k] - lows[k]
    a = atr_values[k]
    if a <= 0.0:
        return 0.0
    return candle_range / a


def is_bullish_pin_bar(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    trend_lookback: int,
    min_lower_wick_ratio: float = 0.60,
    max_body_ratio: float = 0.30,
    max_opposite_wick_ratio: float = 0.15,
) -> bool:
    """Direct port of CP_IsBullishPinBarArray, including TASK-017's
    wick-to-body ratio fix (CP_PIN_BAR_MIN_WICK_TO_BODY)."""

    n = len(closes)
    if k < 0 or k + trend_lookback >= n:
        return False

    m = measure_ratios(opens, highs, lows, closes, k)
    if not m.valid:
        return False
    if m.lower_wick_ratio < min_lower_wick_ratio:
        return False
    if m.body_ratio > max_body_ratio:
        return False
    if m.upper_wick_ratio > max_opposite_wick_ratio:
        return False
    if m.lower_wick_to_body < CP_PIN_BAR_MIN_WICK_TO_BODY:
        return False

    close_position = (closes[k] - lows[k]) / (highs[k] - lows[k])
    if close_position < 0.60:
        return False

    return closes[k + trend_lookback] > closes[k]  # preceding down-move


def is_bearish_pin_bar(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    trend_lookback: int,
    min_upper_wick_ratio: float = 0.60,
    max_body_ratio: float = 0.30,
    max_opposite_wick_ratio: float = 0.15,
) -> bool:
    """Direct port of CP_IsBearishPinBarArray (mirror of the bullish case)."""

    n = len(closes)
    if k < 0 or k + trend_lookback >= n:
        return False

    m = measure_ratios(opens, highs, lows, closes, k)
    if not m.valid:
        return False
    if m.upper_wick_ratio < min_upper_wick_ratio:
        return False
    if m.body_ratio > max_body_ratio:
        return False
    if m.lower_wick_ratio > max_opposite_wick_ratio:
        return False
    if m.upper_wick_to_body < CP_PIN_BAR_MIN_WICK_TO_BODY:
        return False

    close_position = (closes[k] - lows[k]) / (highs[k] - lows[k])
    if close_position > 0.40:  # lower 40% of range
        return False

    return closes[k + trend_lookback] < closes[k]  # preceding up-move


def is_bullish_engulfing(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    size_window: int = 20,
    min_size_percentile: float = 0.50,
) -> bool:
    """Direct port of CP_IsBullishEngulfingArray."""

    n = len(closes)
    if k < 0 or k + 1 >= n:
        return False

    cond = (
        closes[k] > opens[k + 1]
        and opens[k] < closes[k + 1]
        and abs(closes[k] - opens[k]) > abs(closes[k + 1] - opens[k + 1])
        and closes[k + 1] < opens[k + 1]
    )
    if not cond:
        return False

    return size_percentile(highs, lows, k, size_window) >= min_size_percentile


def is_bearish_engulfing(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    size_window: int = 20,
    min_size_percentile: float = 0.50,
) -> bool:
    """Direct port of CP_IsBearishEngulfingArray."""

    n = len(closes)
    if k < 0 or k + 1 >= n:
        return False

    cond = (
        closes[k] < opens[k + 1]
        and opens[k] > closes[k + 1]
        and abs(closes[k] - opens[k]) > abs(closes[k + 1] - opens[k + 1])
        and closes[k + 1] > opens[k + 1]
    )
    if not cond:
        return False

    return size_percentile(highs, lows, k, size_window) >= min_size_percentile


# --- TASK-033: the remaining 15 CP_Is*Array predicates + CP_DetectHaramiArray --


def is_dragonfly_rejection(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    max_body_ratio: float = 0.10,
    min_wick_ratio: float = 0.70,
) -> bool:
    """Direct port of CP_IsDragonflyRejectionArray."""

    m = measure_ratios(opens, highs, lows, closes, k)
    if not m.valid:
        return False
    return (
        m.body_ratio <= max_body_ratio
        and m.lower_wick_ratio >= min_wick_ratio
        and m.upper_wick_ratio <= max_body_ratio
    )


def is_gravestone_rejection(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    max_body_ratio: float = 0.10,
    min_wick_ratio: float = 0.70,
) -> bool:
    """Direct port of CP_IsGravestoneRejectionArray."""

    m = measure_ratios(opens, highs, lows, closes, k)
    if not m.valid:
        return False
    return (
        m.body_ratio <= max_body_ratio
        and m.upper_wick_ratio >= min_wick_ratio
        and m.lower_wick_ratio <= max_body_ratio
    )


def is_marubozu(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    atr_values: Sequence[float],
    k: int,
    min_body_ratio: float = 0.90,
    displacement_atr_multiple: float = 1.5,
) -> bool:
    """Direct port of CP_IsMarubozuArray."""

    m = measure_ratios(opens, highs, lows, closes, k)
    if not m.valid or m.body_ratio < min_body_ratio:
        return False
    return atr_size(highs, lows, atr_values, k) >= displacement_atr_multiple


def is_doji(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    max_body_ratio: float = 0.10,
) -> bool:
    """Direct port of CP_IsDojiArray."""

    m = measure_ratios(opens, highs, lows, closes, k)
    return m.valid and m.body_ratio <= max_body_ratio


def is_spinning_top(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    doji_max_body_ratio: float = 0.10,
    max_body_ratio: float = 0.35,
    min_wick_ratio: float = 0.20,
) -> bool:
    """Direct port of CP_IsSpinningTopArray."""

    m = measure_ratios(opens, highs, lows, closes, k)
    if not m.valid:
        return False
    if m.body_ratio <= doji_max_body_ratio or m.body_ratio > max_body_ratio:
        return False
    return m.upper_wick_ratio >= min_wick_ratio and m.lower_wick_ratio >= min_wick_ratio


def is_inside_bar(highs: Sequence[float], lows: Sequence[float], k: int) -> bool:
    """Direct port of CP_IsInsideBarArray."""

    n = len(highs)
    if k < 0 or k + 1 >= n:
        return False
    return highs[k] < highs[k + 1] and lows[k] > lows[k + 1]


def is_outside_bar(highs: Sequence[float], lows: Sequence[float], k: int) -> bool:
    """Direct port of CP_IsOutsideBarArray."""

    n = len(highs)
    if k < 0 or k + 1 >= n:
        return False
    return highs[k] > highs[k + 1] and lows[k] < lows[k + 1]


def is_tweezer_top(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    atr_values: Sequence[float],
    k: int,
    tolerance_atr: float = 0.10,
) -> bool:
    """Direct port of CP_IsTweezerTopArray."""

    n = len(highs)
    if k < 0 or k + 1 >= n:
        return False
    atr = atr_values[k]
    if atr <= 0.0:
        return False

    close_highs = abs(highs[k] - highs[k + 1]) <= atr * tolerance_atr
    prior_up = closes[k + 1] > opens[k + 1]
    current_down = closes[k] < opens[k]
    return close_highs and prior_up and current_down


def is_tweezer_bottom(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    atr_values: Sequence[float],
    k: int,
    tolerance_atr: float = 0.10,
) -> bool:
    """Direct port of CP_IsTweezerBottomArray."""

    n = len(lows)
    if k < 0 or k + 1 >= n:
        return False
    atr = atr_values[k]
    if atr <= 0.0:
        return False

    close_lows = abs(lows[k] - lows[k + 1]) <= atr * tolerance_atr
    prior_down = closes[k + 1] < opens[k + 1]
    current_up = closes[k] > opens[k]
    return close_lows and prior_down and current_up


class HaramiDirection(str, Enum):
    """Direct port of ENUM_HARAMI_DIRECTION."""

    NONE = "NONE"
    BULLISH_IMPLIED = "BULLISH_IMPLIED"
    BEARISH_IMPLIED = "BEARISH_IMPLIED"


def detect_harami(
    opens: Sequence[float],
    closes: Sequence[float],
    k: int,
    max_ratio: float = 0.50,
) -> HaramiDirection:
    """Direct port of CP_DetectHaramiArray."""

    n = len(closes)
    if k < 0 or k + 1 >= n:
        return HaramiDirection.NONE

    bh_k = max(opens[k], closes[k])
    bl_k = min(opens[k], closes[k])
    bh_k1 = max(opens[k + 1], closes[k + 1])
    bl_k1 = min(opens[k + 1], closes[k + 1])
    body_k = bh_k - bl_k
    body_k1 = bh_k1 - bl_k1

    if body_k1 <= 0.0 or body_k >= body_k1 * max_ratio:
        return HaramiDirection.NONE
    if not (bh_k <= bh_k1 and bl_k >= bl_k1):
        return HaramiDirection.NONE

    return (
        HaramiDirection.BEARISH_IMPLIED
        if closes[k + 1] > opens[k + 1]
        else HaramiDirection.BULLISH_IMPLIED
    )


def is_harami_confirmed(
    closes: Sequence[float],
    k: int,
    implied_direction: HaramiDirection,
) -> bool:
    """Direct port of CP_IsHaramiConfirmedArray."""

    n = len(closes)
    if k < 1 or k + 1 >= n:
        return False
    if implied_direction == HaramiDirection.BULLISH_IMPLIED:
        return closes[k - 1] > closes[k + 1]
    if implied_direction == HaramiDirection.BEARISH_IMPLIED:
        return closes[k - 1] < closes[k + 1]
    return False


def is_morning_star(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    max_middle_body_ratio: float = 0.30,
    max_overlap: float = 0.50,
) -> bool:
    """Direct port of CP_IsMorningStarArray."""

    n = len(closes)
    if k < 0 or k + 2 >= n:
        return False
    if not (closes[k + 2] < opens[k + 2]):  # first candle bearish
        return False

    mid = measure_ratios(opens, highs, lows, closes, k + 1)
    if not mid.valid or mid.body_ratio > max_middle_body_ratio:
        return False

    bh1 = max(opens[k + 2], closes[k + 2])
    bl1 = min(opens[k + 2], closes[k + 2])
    body1 = bh1 - bl1
    if body1 <= 0.0:
        return False

    overlap = max(0.0, min(highs[k + 1], bh1) - max(lows[k + 1], bl1))
    if overlap / body1 > max_overlap:
        return False

    if not (closes[k] > opens[k]):  # third candle bullish
        return False
    midpoint1 = (opens[k + 2] + closes[k + 2]) / 2.0
    return closes[k] > midpoint1


def is_evening_star(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    max_middle_body_ratio: float = 0.30,
    max_overlap: float = 0.50,
) -> bool:
    """Direct port of CP_IsEveningStarArray."""

    n = len(closes)
    if k < 0 or k + 2 >= n:
        return False
    if not (closes[k + 2] > opens[k + 2]):  # first candle bullish
        return False

    mid = measure_ratios(opens, highs, lows, closes, k + 1)
    if not mid.valid or mid.body_ratio > max_middle_body_ratio:
        return False

    bh1 = max(opens[k + 2], closes[k + 2])
    bl1 = min(opens[k + 2], closes[k + 2])
    body1 = bh1 - bl1
    if body1 <= 0.0:
        return False

    overlap = max(0.0, min(highs[k + 1], bh1) - max(lows[k + 1], bl1))
    if overlap / body1 > max_overlap:
        return False

    if not (closes[k] < opens[k]):  # third candle bearish
        return False
    midpoint1 = (opens[k + 2] + closes[k + 2]) / 2.0
    return closes[k] < midpoint1


def is_three_white_soldiers(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    min_body_ratio: float = 0.55,
    max_upper_wick_ratio: float = 0.20,
) -> bool:
    """Direct port of CP_IsThreeWhiteSoldiersArray."""

    n = len(closes)
    if k < 0 or k + 2 >= n:
        return False

    for i in range(3):
        idx = k + i
        if not (closes[idx] > opens[idx]):
            return False
        m = measure_ratios(opens, highs, lows, closes, idx)
        if (
            not m.valid
            or m.body_ratio < min_body_ratio
            or m.upper_wick_ratio > max_upper_wick_ratio
        ):
            return False
    if not (opens[k] > opens[k + 1] > opens[k + 2]):
        return False
    if not (closes[k] > closes[k + 1] > closes[k + 2]):
        return False
    return True


def is_three_black_crows(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    min_body_ratio: float = 0.55,
    max_lower_wick_ratio: float = 0.20,
) -> bool:
    """Direct port of CP_IsThreeBlackCrowsArray."""

    n = len(closes)
    if k < 0 or k + 2 >= n:
        return False

    for i in range(3):
        idx = k + i
        if not (closes[idx] < opens[idx]):
            return False
        m = measure_ratios(opens, highs, lows, closes, idx)
        if (
            not m.valid
            or m.body_ratio < min_body_ratio
            or m.lower_wick_ratio > max_lower_wick_ratio
        ):
            return False
    if not (opens[k] < opens[k + 1] < opens[k + 2]):
        return False
    if not (closes[k] < closes[k + 1] < closes[k + 2]):
        return False
    return True


# --- Minimal SwingEngine.mqh pivot-predicate port -------------------------------
# Scoped to exactly what CP_IsThreeBarReversalArray and this file's own chart
# patterns need -- see module docstring for why this is not a full port.


def is_confirmed_swing_high(highs: Sequence[float], k: int, depth: int) -> bool:
    """Direct port of SE_IsConfirmedSwingHighArray."""

    n = len(highs)
    if depth <= 0 or k < depth or k + depth >= n:
        return False
    high_k = highs[k]
    for offset in range(1, depth + 1):
        if highs[k - offset] >= high_k or highs[k + offset] >= high_k:
            return False
    return True


def is_confirmed_swing_low(lows: Sequence[float], k: int, depth: int) -> bool:
    """Direct port of SE_IsConfirmedSwingLowArray."""

    n = len(lows)
    if depth <= 0 or k < depth or k + depth >= n:
        return False
    low_k = lows[k]
    for offset in range(1, depth + 1):
        if lows[k - offset] <= low_k or lows[k + offset] <= low_k:
            return False
    return True


def find_nearest_confirmed_swing_high(
    highs: Sequence[float], min_index: int, depth: int, max_lookback: int
) -> Optional[int]:
    """Direct port of SE_FindNearestConfirmedSwingHighArray. Returns None
    (MQL5's found_index=-1/False) if none found in range."""

    if depth <= 0 or max_lookback <= 0:
        return None
    start = max(min_index, depth)
    last_k = start + max_lookback - 1
    if last_k + depth >= len(highs):
        return None
    for k in range(start, last_k + 1):
        if is_confirmed_swing_high(highs, k, depth):
            return k
    return None


def find_nearest_confirmed_swing_low(
    lows: Sequence[float], min_index: int, depth: int, max_lookback: int
) -> Optional[int]:
    """Direct port of SE_FindNearestConfirmedSwingLowArray."""

    if depth <= 0 or max_lookback <= 0:
        return None
    start = max(min_index, depth)
    last_k = start + max_lookback - 1
    if last_k + depth >= len(lows):
        return None
    for k in range(start, last_k + 1):
        if is_confirmed_swing_low(lows, k, depth):
            return k
    return None


def is_three_bar_reversal(
    highs: Sequence[float],
    lows: Sequence[float],
    opens: Sequence[float],
    closes: Sequence[float],
    k: int,
    swing_depth: int,
) -> bool:
    """Direct port of CP_IsThreeBarReversalArray."""

    n = len(closes)
    if k < 0 or k + 2 >= n:
        return False

    if is_confirmed_swing_low(lows, k + 1, swing_depth):
        return closes[k] > opens[k + 2]
    if is_confirmed_swing_high(highs, k + 1, swing_depth):
        return closes[k] < opens[k + 2]
    return False


# --- TASK-033: ChartPatternEngine.mqh port (double top/bottom, --------------
# head-and-shoulders/inverse) -- see module docstring for the exact scope
# boundary (triple top/bottom and the other 13 master-prompt chart-pattern
# families are TASK-039's, not ported here).


class ChartPatternType(str, Enum):
    NONE = "NONE"
    DOUBLE_TOP = "DOUBLE_TOP"
    DOUBLE_BOTTOM = "DOUBLE_BOTTOM"
    HEAD_SHOULDERS = "HEAD_SHOULDERS"
    INV_HEAD_SHOULDERS = "INV_HEAD_SHOULDERS"
    TRIPLE_TOP = "TRIPLE_TOP"  # TASK-039
    TRIPLE_BOTTOM = "TRIPLE_BOTTOM"  # TASK-039


@dataclass(frozen=True)
class ChartPatternResult:
    found: bool
    type: ChartPatternType
    boundary_price: float
    extreme_price: float
    target: float
    stop: float
    breakout_index: int  # -1 if no confirmed breakout found yet


def _empty_chart_pattern_result() -> ChartPatternResult:
    return ChartPatternResult(False, ChartPatternType.NONE, 0.0, 0.0, 0.0, 0.0, -1)


def linear_interpolate(x1: int, y1: float, x2: int, y2: float, k: int) -> float:
    """Direct port of CPT_LinearInterpolate."""

    if x1 == x2:
        return y1
    return y1 + (y2 - y1) * (x1 - k) / (x1 - x2)


def has_prior_trend(
    closes: Sequence[float], reference_index: int, trend_bars: int, require_up: bool
) -> bool:
    """Direct port of CPT_HasPriorTrend."""

    n = len(closes)
    if reference_index < 0 or reference_index + trend_bars >= n:
        return False
    earlier = closes[reference_index + trend_bars]
    later = closes[reference_index]
    return earlier < later if require_up else earlier > later


def detect_double_top(
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    depth: int,
    max_lookback: int,
    current_atr: float,
    price_tolerance_atr: float,
    min_pullback_atr: float,
    trend_bars: int,
    breakout_buffer_atr: float,
) -> ChartPatternResult:
    """Direct port of CPT_DetectDoubleTopArray."""

    if current_atr <= 0.0:
        return _empty_chart_pattern_result()

    h1 = find_nearest_confirmed_swing_high(highs, 0, depth, max_lookback)
    if h1 is None:
        return _empty_chart_pattern_result()
    h2 = find_nearest_confirmed_swing_high(highs, h1 + 1, depth, max_lookback)
    if h2 is None:
        return _empty_chart_pattern_result()

    if abs(highs[h1] - highs[h2]) > current_atr * price_tolerance_atr:
        return _empty_chart_pattern_result()

    trough = find_nearest_confirmed_swing_low(lows, h1 + 1, depth, h2 - h1)
    if trough is None or trough >= h2:
        return _empty_chart_pattern_result()

    neckline = lows[trough]
    extreme = max(highs[h1], highs[h2])  # highest peak, per the reference source

    if extreme - neckline < min_pullback_atr * current_atr:
        return _empty_chart_pattern_result()
    if not has_prior_trend(closes, h2, trend_bars, True):
        return _empty_chart_pattern_result()

    breakout_level_index = -1
    breakout_level = neckline - current_atr * breakout_buffer_atr
    for k in range(h1 - 1, -1, -1):
        if closes[k] < breakout_level:
            breakout_level_index = k
            break

    return ChartPatternResult(
        found=True,
        type=ChartPatternType.DOUBLE_TOP,
        boundary_price=neckline,
        extreme_price=extreme,
        target=neckline - (extreme - neckline),
        stop=highs[h1] + current_atr * breakout_buffer_atr,
        breakout_index=breakout_level_index,
    )


def detect_double_bottom(
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    depth: int,
    max_lookback: int,
    current_atr: float,
    price_tolerance_atr: float,
    min_pullback_atr: float,
    trend_bars: int,
    breakout_buffer_atr: float,
) -> ChartPatternResult:
    """Direct port of CPT_DetectDoubleBottomArray (mirror of double top)."""

    if current_atr <= 0.0:
        return _empty_chart_pattern_result()

    l1 = find_nearest_confirmed_swing_low(lows, 0, depth, max_lookback)
    if l1 is None:
        return _empty_chart_pattern_result()
    l2 = find_nearest_confirmed_swing_low(lows, l1 + 1, depth, max_lookback)
    if l2 is None:
        return _empty_chart_pattern_result()

    if abs(lows[l1] - lows[l2]) > current_atr * price_tolerance_atr:
        return _empty_chart_pattern_result()

    peak = find_nearest_confirmed_swing_high(highs, l1 + 1, depth, l2 - l1)
    if peak is None or peak >= l2:
        return _empty_chart_pattern_result()

    neckline = highs[peak]
    extreme = min(lows[l1], lows[l2])  # lowest trough

    if neckline - extreme < min_pullback_atr * current_atr:
        return _empty_chart_pattern_result()
    if not has_prior_trend(closes, l2, trend_bars, False):
        return _empty_chart_pattern_result()

    breakout_level_index = -1
    breakout_level = neckline + current_atr * breakout_buffer_atr
    for k in range(l1 - 1, -1, -1):
        if closes[k] > breakout_level:
            breakout_level_index = k
            break

    return ChartPatternResult(
        found=True,
        type=ChartPatternType.DOUBLE_BOTTOM,
        boundary_price=neckline,
        extreme_price=extreme,
        target=neckline + (neckline - extreme),
        stop=lows[l1] - current_atr * breakout_buffer_atr,
        breakout_index=breakout_level_index,
    )


def detect_triple_top(
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    depth: int,
    max_lookback: int,
    current_atr: float,
    price_tolerance_atr: float,
    min_pullback_atr: float,
    trend_bars: int,
    breakout_buffer_atr: float,
) -> ChartPatternResult:
    """Direct port of CPT_DetectTripleTopArray: three confirmed swing
    highs PAIRWISE within price_tolerance_atr of EACH OTHER -- all three
    pairs (h1-h2, h2-h3, AND h1-h3), per
    TASK-002_PHASE2_SPECIFICATION.md section 6's own literal wording, not
    just the two adjacent pairs. Separated by two confirmed swing-low
    troughs forming a POSSIBLY SLOPED neckline through those two points
    (linear_interpolate, the same machinery detect_head_and_shoulders
    already uses).

    **Fixed, 2026-07-22 Codex review finding (seventh round, P1 finding
    11): the previous version checked only the two ADJACENT pairwise
    tolerances (h1-h2, h2-h3), letting h1 and h3 diverge by up to 2x the
    stated tolerance, and used a flat MathMin(trough1,trough2) neckline
    instead of the specified sloped neckline evaluated at the breakout
    bar -- see CPT_DetectTripleTopArray's own header for the full
    corrected geometry this mirrors exactly.**"""

    if current_atr <= 0.0:
        return _empty_chart_pattern_result()

    h1 = find_nearest_confirmed_swing_high(highs, 0, depth, max_lookback)
    if h1 is None:
        return _empty_chart_pattern_result()
    h2 = find_nearest_confirmed_swing_high(highs, h1 + 1, depth, max_lookback)
    if h2 is None:
        return _empty_chart_pattern_result()
    h3 = find_nearest_confirmed_swing_high(highs, h2 + 1, depth, max_lookback)
    if h3 is None:
        return _empty_chart_pattern_result()

    if abs(highs[h1] - highs[h2]) > current_atr * price_tolerance_atr:
        return _empty_chart_pattern_result()
    if abs(highs[h2] - highs[h3]) > current_atr * price_tolerance_atr:
        return _empty_chart_pattern_result()
    if abs(highs[h1] - highs[h3]) > current_atr * price_tolerance_atr:
        return _empty_chart_pattern_result()

    trough1 = find_nearest_confirmed_swing_low(lows, h1 + 1, depth, h2 - h1)
    if trough1 is None or trough1 >= h2:
        return _empty_chart_pattern_result()

    trough2 = find_nearest_confirmed_swing_low(lows, h2 + 1, depth, h3 - h2)
    if trough2 is None or trough2 >= h3:
        return _empty_chart_pattern_result()

    extreme = max(highs[h1], highs[h2], highs[h3])

    if extreme - lows[trough1] < min_pullback_atr * current_atr:
        return _empty_chart_pattern_result()
    if extreme - lows[trough2] < min_pullback_atr * current_atr:
        return _empty_chart_pattern_result()
    if not has_prior_trend(closes, h3, trend_bars, True):
        return _empty_chart_pattern_result()

    extreme_index = h1
    if highs[h2] > highs[extreme_index]:
        extreme_index = h2
    if highs[h3] > highs[extreme_index]:
        extreme_index = h3

    breakout_index = -1
    for k in range(h1 - 1, -1, -1):
        neck_k = linear_interpolate(trough1, lows[trough1], trough2, lows[trough2], k)
        if closes[k] < neck_k - current_atr * breakout_buffer_atr:
            breakout_index = k
            break

    neckline_at_extreme = linear_interpolate(
        trough1, lows[trough1], trough2, lows[trough2], extreme_index
    )
    target_reference = breakout_index if breakout_index >= 0 else h1
    neckline_at_target = linear_interpolate(
        trough1, lows[trough1], trough2, lows[trough2], target_reference
    )

    return ChartPatternResult(
        found=True,
        type=ChartPatternType.TRIPLE_TOP,
        # **Fixed, 2026-07-22 (Codex review finding, eighth round, P1 finding
        # 14): previously evaluated at 'h1' (an old pivot bar), mirroring the
        # same bug ChartPatternEngine.mqh's own CPT_DetectTripleTopArray had
        # -- projects to index 0 (the current/most recent bar) instead, so
        # boundary_price is genuinely comparable to closes[0] whenever the
        # neckline has any slope. See that MQL5 function's own fix comment
        # for the full rationale (both sides are meant to mirror the same
        # algorithm for this project's own Python-vs-MQL cross-check).**
        boundary_price=linear_interpolate(trough1, lows[trough1], trough2, lows[trough2], 0),
        extreme_price=extreme,
        target=neckline_at_target - (extreme - neckline_at_extreme),
        stop=highs[h1] + current_atr * breakout_buffer_atr,
        breakout_index=breakout_index,
    )


def detect_triple_bottom(
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    depth: int,
    max_lookback: int,
    current_atr: float,
    price_tolerance_atr: float,
    min_pullback_atr: float,
    trend_bars: int,
    breakout_buffer_atr: float,
) -> ChartPatternResult:
    """Direct port of CPT_DetectTripleBottomArray (mirror of triple top) --
    see detect_triple_top's own docstring for the seventh-round Codex
    review fix (three-way pairwise tolerance + sloped neckline) this
    mirrors."""

    if current_atr <= 0.0:
        return _empty_chart_pattern_result()

    l1 = find_nearest_confirmed_swing_low(lows, 0, depth, max_lookback)
    if l1 is None:
        return _empty_chart_pattern_result()
    l2 = find_nearest_confirmed_swing_low(lows, l1 + 1, depth, max_lookback)
    if l2 is None:
        return _empty_chart_pattern_result()
    l3 = find_nearest_confirmed_swing_low(lows, l2 + 1, depth, max_lookback)
    if l3 is None:
        return _empty_chart_pattern_result()

    if abs(lows[l1] - lows[l2]) > current_atr * price_tolerance_atr:
        return _empty_chart_pattern_result()
    if abs(lows[l2] - lows[l3]) > current_atr * price_tolerance_atr:
        return _empty_chart_pattern_result()
    if abs(lows[l1] - lows[l3]) > current_atr * price_tolerance_atr:
        return _empty_chart_pattern_result()

    peak1 = find_nearest_confirmed_swing_high(highs, l1 + 1, depth, l2 - l1)
    if peak1 is None or peak1 >= l2:
        return _empty_chart_pattern_result()

    peak2 = find_nearest_confirmed_swing_high(highs, l2 + 1, depth, l3 - l2)
    if peak2 is None or peak2 >= l3:
        return _empty_chart_pattern_result()

    extreme = min(lows[l1], lows[l2], lows[l3])

    if highs[peak1] - extreme < min_pullback_atr * current_atr:
        return _empty_chart_pattern_result()
    if highs[peak2] - extreme < min_pullback_atr * current_atr:
        return _empty_chart_pattern_result()
    if not has_prior_trend(closes, l3, trend_bars, False):
        return _empty_chart_pattern_result()

    extreme_index = l1
    if lows[l2] < lows[extreme_index]:
        extreme_index = l2
    if lows[l3] < lows[extreme_index]:
        extreme_index = l3

    breakout_index = -1
    for k in range(l1 - 1, -1, -1):
        neck_k = linear_interpolate(peak1, highs[peak1], peak2, highs[peak2], k)
        if closes[k] > neck_k + current_atr * breakout_buffer_atr:
            breakout_index = k
            break

    neckline_at_extreme = linear_interpolate(
        peak1, highs[peak1], peak2, highs[peak2], extreme_index
    )
    target_reference = breakout_index if breakout_index >= 0 else l1
    neckline_at_target = linear_interpolate(
        peak1, highs[peak1], peak2, highs[peak2], target_reference
    )

    return ChartPatternResult(
        found=True,
        type=ChartPatternType.TRIPLE_BOTTOM,
        # **Fixed, 2026-07-22 (Codex review finding, eighth round, P1 finding
        # 14): see the triple-top boundary_price fix's own comment above --
        # projects to index 0 instead of the old 'l1' pivot.**
        boundary_price=linear_interpolate(peak1, highs[peak1], peak2, highs[peak2], 0),
        extreme_price=extreme,
        target=neckline_at_target + (neckline_at_extreme - extreme),
        stop=lows[l1] - current_atr * breakout_buffer_atr,
        breakout_index=breakout_index,
    )


def detect_head_and_shoulders(
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    depth: int,
    max_lookback: int,
    current_atr: float,
    price_tolerance_atr: float,
    time_tolerance: float,
    min_head_prominence_atr: float,
    breakout_buffer_atr: float,
    trend_bars: int,
) -> ChartPatternResult:
    """Direct port of CPT_DetectHeadAndShouldersArray."""

    if current_atr <= 0.0:
        return _empty_chart_pattern_result()

    rs = find_nearest_confirmed_swing_high(highs, 0, depth, max_lookback)
    if rs is None:
        return _empty_chart_pattern_result()
    head = find_nearest_confirmed_swing_high(highs, rs + 1, depth, max_lookback)
    if head is None:
        return _empty_chart_pattern_result()
    ls = find_nearest_confirmed_swing_high(highs, head + 1, depth, max_lookback)
    if ls is None:
        return _empty_chart_pattern_result()

    head_price, rs_price, ls_price = highs[head], highs[rs], highs[ls]
    if head_price <= max(ls_price, rs_price):
        return _empty_chart_pattern_result()
    if head_price - max(ls_price, rs_price) < min_head_prominence_atr * current_atr:
        return _empty_chart_pattern_result()
    if abs(ls_price - rs_price) > current_atr * price_tolerance_atr:
        return _empty_chart_pattern_result()

    ls_to_head = float(ls - head)
    head_to_rs = float(head - rs)
    if ls_to_head <= 0.0 or head_to_rs <= 0.0:
        return _empty_chart_pattern_result()
    time_diff_ratio = abs(ls_to_head - head_to_rs) / max(ls_to_head, head_to_rs)
    if time_diff_ratio > time_tolerance:
        return _empty_chart_pattern_result()

    if not has_prior_trend(closes, ls, trend_bars, True):
        return _empty_chart_pattern_result()

    trough1 = find_nearest_confirmed_swing_low(lows, head + 1, depth, ls - head)
    if trough1 is None or trough1 >= ls:
        return _empty_chart_pattern_result()

    trough2 = find_nearest_confirmed_swing_low(lows, rs + 1, depth, head - rs)
    if trough2 is None or trough2 >= head:
        return _empty_chart_pattern_result()

    breakout_index = -1
    for k in range(rs - 1, -1, -1):
        neck_k = linear_interpolate(trough1, lows[trough1], trough2, lows[trough2], k)
        if closes[k] < neck_k - current_atr * breakout_buffer_atr:
            breakout_index = k
            break

    neckline_at_head = linear_interpolate(trough1, lows[trough1], trough2, lows[trough2], head)
    target_reference = breakout_index if breakout_index >= 0 else rs
    neckline_at_target = linear_interpolate(
        trough1, lows[trough1], trough2, lows[trough2], target_reference
    )

    return ChartPatternResult(
        found=True,
        type=ChartPatternType.HEAD_SHOULDERS,
        # **Fixed, 2026-07-22 (Codex review finding, eighth round, P1 finding
        # 14): see the triple-top boundary_price fix's own comment above --
        # projects to index 0 instead of the old 'rs' pivot.**
        boundary_price=linear_interpolate(trough1, lows[trough1], trough2, lows[trough2], 0),
        extreme_price=head_price,
        target=neckline_at_target - (head_price - neckline_at_head),
        stop=rs_price + current_atr * breakout_buffer_atr,
        breakout_index=breakout_index,
    )


def detect_inverse_head_and_shoulders(
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    depth: int,
    max_lookback: int,
    current_atr: float,
    price_tolerance_atr: float,
    time_tolerance: float,
    min_head_prominence_atr: float,
    breakout_buffer_atr: float,
    trend_bars: int,
) -> ChartPatternResult:
    """Direct port of CPT_DetectInverseHeadAndShouldersArray (mirror of
    head-and-shoulders on swing lows)."""

    if current_atr <= 0.0:
        return _empty_chart_pattern_result()

    rs = find_nearest_confirmed_swing_low(lows, 0, depth, max_lookback)
    if rs is None:
        return _empty_chart_pattern_result()
    head = find_nearest_confirmed_swing_low(lows, rs + 1, depth, max_lookback)
    if head is None:
        return _empty_chart_pattern_result()
    ls = find_nearest_confirmed_swing_low(lows, head + 1, depth, max_lookback)
    if ls is None:
        return _empty_chart_pattern_result()

    head_price, rs_price, ls_price = lows[head], lows[rs], lows[ls]
    if head_price >= min(ls_price, rs_price):
        return _empty_chart_pattern_result()
    if min(ls_price, rs_price) - head_price < min_head_prominence_atr * current_atr:
        return _empty_chart_pattern_result()
    if abs(ls_price - rs_price) > current_atr * price_tolerance_atr:
        return _empty_chart_pattern_result()

    ls_to_head = float(ls - head)
    head_to_rs = float(head - rs)
    if ls_to_head <= 0.0 or head_to_rs <= 0.0:
        return _empty_chart_pattern_result()
    time_diff_ratio = abs(ls_to_head - head_to_rs) / max(ls_to_head, head_to_rs)
    if time_diff_ratio > time_tolerance:
        return _empty_chart_pattern_result()

    if not has_prior_trend(closes, ls, trend_bars, False):
        return _empty_chart_pattern_result()

    peak1 = find_nearest_confirmed_swing_high(highs, head + 1, depth, ls - head)
    if peak1 is None or peak1 >= ls:
        return _empty_chart_pattern_result()

    peak2 = find_nearest_confirmed_swing_high(highs, rs + 1, depth, head - rs)
    if peak2 is None or peak2 >= head:
        return _empty_chart_pattern_result()

    breakout_index = -1
    for k in range(rs - 1, -1, -1):
        neck_k = linear_interpolate(peak1, highs[peak1], peak2, highs[peak2], k)
        if closes[k] > neck_k + current_atr * breakout_buffer_atr:
            breakout_index = k
            break

    neckline_at_head = linear_interpolate(peak1, highs[peak1], peak2, highs[peak2], head)
    target_reference = breakout_index if breakout_index >= 0 else rs
    neckline_at_target = linear_interpolate(
        peak1, highs[peak1], peak2, highs[peak2], target_reference
    )

    return ChartPatternResult(
        found=True,
        type=ChartPatternType.INV_HEAD_SHOULDERS,
        # **Fixed, 2026-07-22 (Codex review finding, eighth round, P1 finding
        # 14): see the triple-top boundary_price fix's own comment above --
        # projects to index 0 instead of the old 'rs' pivot.**
        boundary_price=linear_interpolate(peak1, highs[peak1], peak2, highs[peak2], 0),
        extreme_price=head_price,
        target=neckline_at_target + (neckline_at_head - head_price),
        stop=rs_price - current_atr * breakout_buffer_atr,
        breakout_index=breakout_index,
    )


def check_retest(
    closes: Sequence[float],
    touch_index: int,
    boundary_price: float,
    is_bullish_breakout: bool,
    current_atr: float,
    failure_tolerance_atr: float,
    max_bars: int,
) -> Optional[bool]:
    """Direct port of CPT_CheckRetestArray. Returns None if touch_index < 0
    (matching the MQL5 source's own False return -- 'holds' is not
    meaningful in that case); otherwise returns whether the retest holds."""

    if touch_index < 0:
        return None

    end = max(0, touch_index - max_bars)
    for k in range(touch_index, end - 1, -1):
        if k < 0:
            break
        if is_bullish_breakout:
            if closes[k] < boundary_price - current_atr * failure_tolerance_atr:
                return False
        else:
            if closes[k] > boundary_price + current_atr * failure_tolerance_atr:
                return False
    return True


def detect_all_patterns(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    trend_lookback: int = 5,
    size_window: int = 20,
    atr_values: Optional[Sequence[float]] = None,
    swing_depth: Optional[int] = None,
) -> pd.DataFrame:
    """Runs every ported pattern at every valid logical index k, returning
    a DataFrame with one row per k and one boolean column per pattern.

    Raises ValueError if trend_lookback/size_window is not a positive
    integer -- **added, 2026-07-22 Codex review finding (fourth round):**
    neither was previously validated. A negative size_window makes
    size_percentile's own "total <= 0" branch return 1.0 ("no comparison
    history -- cannot be disproven as large"), silently turning ANY bar
    into an automatic 100th-percentile pass regardless of its real size.
    A negative trend_lookback bypasses the `k + trend_lookback >= n`
    upper-bound guard while still being used as a list index, so
    `closes[k + trend_lookback]` can silently wrap around to the END of
    the array (Python negative-index semantics) and compare against an
    unrelated bar instead of raising.

    **Fixed, 2026-07-22 Codex review finding (seventh round, P1 finding
    11): this docstring previously (and wrongly) still described a
    "default 4-column output" -- that was true only of an early version
    of this function; TASK-033 added twelve more always-included
    patterns since (dragonfly/gravestone rejection, doji, spinning top,
    inside/outside bar, harami-detected/confirmed, morning/evening star,
    three white soldiers/three black crows), so the DEFAULT output (no
    atr_values/swing_depth) is actually 'k' plus SIXTEEN boolean pattern
    columns, not four. 'Export_PatternDetectorResults.mq5' (TASK-037) has
    also been extended this same round to match that full column set
    exactly (see that file's own header), closing the schema-
    incompatibility gap the stale docstring here was masking.**

    'atr_values'/'swing_depth' remain OPT-IN (default None): passing
    atr_values adds the ATR-dependent columns (marubozu, tweezer top/
    bottom); passing swing_depth additionally adds three_bar_reversal.
    `run()`'s own CLI path now always forwards both (see that function's
    own docstring) so the full pattern set is reachable through the
    advertised pipeline, not just by calling this function directly.
    """

    if trend_lookback < 1:
        raise ValueError(f"trend_lookback must be a positive integer, got {trend_lookback}")
    if size_window < 1:
        raise ValueError(f"size_window must be a positive integer, got {size_window}")

    n = len(closes)
    rows = []
    for k in range(n):
        harami_direction = detect_harami(opens, closes, k)
        row = {
            "k": k,
            "bullish_pin_bar": is_bullish_pin_bar(opens, highs, lows, closes, k, trend_lookback),
            "bearish_pin_bar": is_bearish_pin_bar(opens, highs, lows, closes, k, trend_lookback),
            "bullish_engulfing": is_bullish_engulfing(opens, highs, lows, closes, k, size_window),
            "bearish_engulfing": is_bearish_engulfing(opens, highs, lows, closes, k, size_window),
            "dragonfly_rejection": is_dragonfly_rejection(opens, highs, lows, closes, k),
            "gravestone_rejection": is_gravestone_rejection(opens, highs, lows, closes, k),
            "doji": is_doji(opens, highs, lows, closes, k),
            "spinning_top": is_spinning_top(opens, highs, lows, closes, k),
            "inside_bar": is_inside_bar(highs, lows, k),
            "outside_bar": is_outside_bar(highs, lows, k),
            "harami_detected": harami_direction != HaramiDirection.NONE,
            "harami_confirmed": is_harami_confirmed(closes, k, harami_direction),
            "morning_star": is_morning_star(opens, highs, lows, closes, k),
            "evening_star": is_evening_star(opens, highs, lows, closes, k),
            "three_white_soldiers": is_three_white_soldiers(opens, highs, lows, closes, k),
            "three_black_crows": is_three_black_crows(opens, highs, lows, closes, k),
        }
        if atr_values is not None:
            row["marubozu"] = is_marubozu(opens, highs, lows, closes, atr_values, k)
            row["tweezer_top"] = is_tweezer_top(opens, highs, lows, closes, atr_values, k)
            row["tweezer_bottom"] = is_tweezer_bottom(opens, highs, lows, closes, atr_values, k)
        if swing_depth is not None:
            row["three_bar_reversal"] = is_three_bar_reversal(
                highs, lows, opens, closes, k, swing_depth
            )
        rows.append(row)
    return pd.DataFrame(rows)


def compare_to_mql5_export(python_results: pd.DataFrame, mql5_export_csv: Path) -> pd.DataFrame:
    """Joins this module's own detect_all_patterns() output against a
    real MQL5-exported detector-results CSV (columns: k, <same pattern
    names as booleans>) and reports every row where they disagree.

    **Fixed, 2026-07-21 Codex review finding:** previously used an INNER
    merge, which silently drops any 'k' present in only one side --
    reproduced counterexample: Python results at k=1 and an MQL5 export at
    k=0 (i.e. the two datasets never actually overlap at all) returned an
    EMPTY disagreement DataFrame, the strongest possible false "pass". A
    duplicate 'k' on either side could also silently fan out into a
    Cartesian join. Now requires exact, unique key coverage on both sides
    (via an outer merge with an indicator column) and raises
    CsvSchemaError -- not a silent comparison -- if either side has a key
    the other lacks, or if either side has a duplicate key.

    **Not yet exercisable against real data** -- no MQL5 module in this
    project currently exports pattern results to a file. Also raises
    CsvSchemaError if the export is missing the 'k' column or any pattern
    column present in 'python_results'.
    """

    pattern_columns = [c for c in python_results.columns if c != "k"]
    if python_results["k"].duplicated().any():
        raise CsvSchemaError("compare_to_mql5_export: python_results has duplicate 'k' values")

    mql5_results = read_csv_with_required_columns(mql5_export_csv, {"k", *pattern_columns})
    assert_unique_ids(mql5_results, "k", mql5_export_csv)

    merged = python_results.merge(
        mql5_results, on="k", how="outer", suffixes=("_python", "_mql5"), indicator=True
    )

    left_only = merged[merged["_merge"] == "left_only"]
    right_only = merged[merged["_merge"] == "right_only"]
    if not left_only.empty or not right_only.empty:
        raise CsvSchemaError(
            f"compare_to_mql5_export: key coverage mismatch -- "
            f"{len(left_only)} k value(s) only in python_results ({sorted(left_only['k'].tolist())}), "
            f"{len(right_only)} k value(s) only in {mql5_export_csv} ({sorted(right_only['k'].tolist())})"
        )

    both = merged[merged["_merge"] == "both"]
    disagreement_mask = pd.Series(False, index=both.index)
    for col in pattern_columns:
        disagreement_mask |= both[f"{col}_python"] != both[f"{col}_mql5"]

    return both[disagreement_mask].drop(columns=["_merge"])


def run(
    ohlc_csv: Path,
    output_csv: Optional[Path] = None,
    summary_json: Optional[Path] = None,
    *,
    trend_lookback: int = 5,
    size_window: int = 20,
    swing_depth: int = 3,
    ascending_input: bool = False,
    symbol: Optional[str] = None,
    seed: Optional[int] = None,
    # **Added, 2026-07-22 Codex review finding (fourth round): spread_note/
    # slippage_note exist on ReportMetadata but no analysis caller exposed
    # or populated them.**
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> pd.DataFrame:
    """Reads 'ohlc_csv' (columns open/high/low/close, plus an OPTIONAL
    'atr' column) and detects every ported pattern at every valid index.

    **Fixed, 2026-07-22 Codex review finding (seventh round, P1 finding
    11): this public/CLI path previously exposed neither ATR values nor
    swing depth to detect_all_patterns, so marubozu/tweezer top/tweezer
    bottom/three_bar_reversal could never be persisted through the
    advertised pipeline -- only by calling detect_all_patterns() directly
    with those arguments, which no CLI path did. 'swing_depth' is now a
    real, always-forwarded parameter (three_bar_reversal has no CSV data
    dependency, so there is no reason it should ever be opt-out from this
    path). ATR values are read from an OPTIONAL 'atr' column in
    'ohlc_csv' if present (this project's own established discipline of
    never re-deriving a live MQL5 indicator formula independently means
    this function does not compute ATR itself from OHLC -- a caller
    supplies it, e.g. from the same MT5 export that produced the OHLC
    columns); if 'atr' is absent, marubozu/tweezer columns are simply not
    produced, exactly as detect_all_patterns() itself already documents.**

    'ascending_input' makes the required array convention an explicit,
    caller-declared choice instead of a silent assumption (a Codex review
    finding: there is no timestamp/order column in this CSV shape with
    which to verify the convention from the data alone, so a normal
    chronologically-ascending export could otherwise be silently analyzed
    backwards). Default False means 'ohlc_csv' is ALREADY in the MQL5
    logical-index convention (row 0 = most recent bar); pass True if
    'ohlc_csv' is in the more common chronologically-ascending order
    (row 0 = oldest bar) and this function will reverse it first.

    'summary_json', if given, records this pipeline's provenance --
    **added, 2026-07-22 Codex review finding (third round): this script
    previously emitted an entirely unprovenanced CSV, unlike every other
    pipeline in this layer.**
    """

    # **Added, 2026-07-22 Codex review finding (sixth round): a caller
    # requesting output_csv without summary_json previously got a CSV
    # with NO accompanying provenance metadata anywhere. An implicit
    # sidecar path is now derived (matching join_trade_journal.py/
    # join_news_events.py/join_signal_to_outcome.py's own pattern),
    # derived FIRST so the collision checks below cover it too.**
    if summary_json is None and output_csv is not None:
        summary_json = output_csv.parent / f"{output_csv.stem}.summary.json"

    # **Fixed, 2026-07-22 Codex review finding:** this script had no
    # input/output collision guard at all -- unlike every other pipeline
    # in this layer. **Fixed, 2026-07-22 Codex review finding (fourth
    # round): the guard used a bare Path.resolve() == comparison, which a
    # hard link to ohlc_csv (different resolved name, identical
    # underlying file) would bypass -- every other pipeline in this
    # layer already uses the OS-level file-identity check.**
    assert_path_not_same_file(output_csv, ohlc_csv, "output_csv")
    assert_path_not_same_file(summary_json, ohlc_csv, "summary_json")
    assert_output_paths_distinct([output_csv, summary_json])

    # **Fixed, 2026-07-22 Codex review finding (sixth round): previously
    # read via the plain (non-hashing) helper, then re-read a second time
    # inside build_report_metadata below to compute its hash -- the same
    # ABA-mutation race round 5 already closed for
    # join_trade_journal.py/join_news_events.py/analyse_baseline.py but
    # left open here.**
    ohlc, ohlc_csv_hash = read_csv_with_required_columns_and_hash(ohlc_csv, REQUIRED_OHLC_COLUMNS)
    assert_finite_columns(ohlc, ["open", "high", "low", "close"], ohlc_csv)
    # Full OHLC geometry (open/close must also fall within [low, high]),
    # not just high >= low -- see assert_high_low_geometry's own
    # docstring for the Codex review finding this closes.
    assert_high_low_geometry(
        ohlc, "high", "low", ohlc_csv, open_column="open", close_column="close"
    )
    has_atr = "atr" in ohlc.columns
    if has_atr:
        assert_finite_columns(ohlc, ["atr"], ohlc_csv)
        if (ohlc["atr"] <= 0.0).any():
            raise CsvSchemaError(f"{ohlc_csv}: 'atr' must be strictly positive on every row")
    if ascending_input:
        ohlc = ohlc.iloc[::-1].reset_index(drop=True)

    result = detect_all_patterns(
        ohlc["open"].tolist(),
        ohlc["high"].tolist(),
        ohlc["low"].tolist(),
        ohlc["close"].tolist(),
        trend_lookback=trend_lookback,
        size_window=size_window,
        atr_values=ohlc["atr"].tolist() if has_atr else None,
        swing_depth=swing_depth,
    )

    # **Reordered, 2026-07-22 Codex review finding (seventh round, P1
    # finding 16): metadata (git commit/dirty state, which capture_git_commit
    # can raise GitMetadataError computing) is now captured BEFORE
    # output_csv is written, not after -- previously, an invalid repo_path
    # raised AFTER the result CSV already existed on disk, leaving an
    # apparently-valid result with no provenance sidecar at all.**
    if summary_json is not None:
        metadata = build_report_metadata(
            [ohlc_csv],
            symbol=symbol,
            random_seed=seed,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=repo_path,
            dataset_hash_override=ohlc_csv_hash,
        )
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_bars": len(ohlc),
                "trend_lookback": trend_lookback,
                "size_window": size_window,
                "swing_depth": swing_depth,
                "atr_column_present": has_atr,
                "ascending_input": ascending_input,
                "n_detections": int(result.drop(columns=["k"]).sum().sum()),
            },
        }

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_dataframe_csv(result, output_csv)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_text(summary_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return result


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ohlc-csv", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--summary-json", type=Path, default=None)
    parser.add_argument("--trend-lookback", type=int, default=5)
    parser.add_argument("--size-window", type=int, default=20)
    parser.add_argument("--swing-depth", type=int, default=3)
    parser.add_argument(
        "--ascending-input",
        action="store_true",
        help="Set if ohlc_csv is chronologically ascending (row 0 = oldest); "
        "default assumes it is already in the MQL5 logical-index convention (row 0 = newest).",
    )
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        result = run(
            args.ohlc_csv,
            args.output_csv,
            args.summary_json,
            trend_lookback=args.trend_lookback,
            size_window=args.size_window,
            swing_depth=args.swing_depth,
            ascending_input=args.ascending_input,
            symbol=args.symbol,
            seed=args.seed,
            spread_note=args.spread_note,
            slippage_note=args.slippage_note,
        )
    except (FileNotFoundError, CsvSchemaError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    n_detections = int(result.drop(columns=["k"]).sum().sum())
    print(
        f"pattern_validation: {len(result)} bars scanned, {n_detections} total pattern detections."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
