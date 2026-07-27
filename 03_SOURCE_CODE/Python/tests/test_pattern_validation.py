from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from analysis.csv_io import CsvSchemaError
from analysis.pattern_validation import (
    HaramiDirection,
    atr_size,
    check_retest,
    compare_to_mql5_export,
    detect_all_patterns,
    detect_double_bottom,
    detect_double_top,
    detect_harami,
    detect_head_and_shoulders,
    detect_inverse_head_and_shoulders,
    detect_triple_bottom,
    detect_triple_top,
    find_nearest_confirmed_swing_high,
    find_nearest_confirmed_swing_low,
    has_prior_trend,
    is_bearish_engulfing,
    is_bearish_pin_bar,
    is_bullish_engulfing,
    is_bullish_pin_bar,
    is_confirmed_swing_high,
    is_confirmed_swing_low,
    is_doji,
    is_dragonfly_rejection,
    is_evening_star,
    is_gravestone_rejection,
    is_harami_confirmed,
    is_inside_bar,
    is_marubozu,
    is_morning_star,
    is_outside_bar,
    is_spinning_top,
    is_three_bar_reversal,
    is_three_black_crows,
    is_three_white_soldiers,
    is_tweezer_bottom,
    is_tweezer_top,
    linear_interpolate,
    main,
    measure_ratios,
    run,
    size_percentile,
)


# --- measure_ratios -----------------------------------------------------------


def test_measure_ratios_zero_range_is_invalid():
    m = measure_ratios([100.0], [100.0], [100.0], [100.0], 0)
    assert m.valid is False


def test_measure_ratios_out_of_bounds_index_is_invalid():
    m = measure_ratios([100.0], [110.0], [90.0], [105.0], 5)
    assert m.valid is False


def test_measure_ratios_hand_computed():
    m = measure_ratios([116.0], [120.0], [100.0], [118.0], 0)
    assert m.valid is True
    assert m.body == pytest.approx(2.0)
    assert m.range == pytest.approx(20.0)
    assert m.upper_wick == pytest.approx(2.0)
    assert m.lower_wick == pytest.approx(16.0)
    assert m.body_ratio == pytest.approx(0.1)
    assert m.upper_wick_ratio == pytest.approx(0.1)
    assert m.lower_wick_ratio == pytest.approx(0.8)
    assert m.lower_wick_to_body == pytest.approx(8.0)


# --- bullish/bearish pin bar (hand-constructed fixtures, k=0 newest) -----------


def test_bullish_pin_bar_detected():
    # candle 0 (newest, the pin bar): open 116, high 120, low 100, close 118
    # -> body_ratio 0.1, lower_wick_ratio 0.8, upper_wick_ratio 0.1,
    # lower_wick_to_body 8.0, close_position 0.9 -- all clear the thresholds.
    # candle 1 (older): close 125 > 118 -- a preceding down-move into the pin bar.
    opens = [116.0, 124.0]
    highs = [120.0, 126.0]
    lows = [100.0, 123.0]
    closes = [118.0, 125.0]
    assert is_bullish_pin_bar(opens, highs, lows, closes, 0, trend_lookback=1) is True
    assert is_bearish_pin_bar(opens, highs, lows, closes, 0, trend_lookback=1) is False


def test_bearish_pin_bar_detected():
    # candle 0 (newest, the pin bar): open 104, high 120, low 100, close 102
    # -> body_ratio 0.1, upper_wick_ratio 0.8, lower_wick_ratio 0.1,
    # upper_wick_to_body 8.0, close_position 0.1 -- all clear the thresholds.
    # candle 1 (older): close 95 < 102 -- a preceding up-move into the pin bar.
    opens = [104.0, 90.0]
    highs = [120.0, 96.0]
    lows = [100.0, 89.0]
    closes = [102.0, 95.0]
    assert is_bearish_pin_bar(opens, highs, lows, closes, 0, trend_lookback=1) is True
    assert is_bullish_pin_bar(opens, highs, lows, closes, 0, trend_lookback=1) is False


def test_pin_bar_fails_when_body_too_large():
    # Same shape as the bullish case but with a much larger body (11 vs the
    # 20-point range): body_ratio = 11/20 = 0.55 > the 0.30 threshold.
    # (Note: TASK-017's own wick-to-body check, lower_wick_to_body >= 2.0,
    # is algebraically implied whenever lower_wick_ratio >= 0.60 AND
    # body_ratio <= 0.30 both hold simultaneously -- lower_wick_to_body =
    # lower_wick_ratio / body_ratio >= 0.60 / 0.30 = 2.0 -- so it cannot be
    # independently triggered while the other two thresholds pass; this is
    # exactly the redundancy CandlestickPatternEngine.mqh's own TASK-017
    # comment already documents, not a gap in this test.)
    opens = [107.0, 124.0]
    highs = [120.0, 126.0]
    lows = [100.0, 123.0]
    closes = [118.0, 125.0]
    assert is_bullish_pin_bar(opens, highs, lows, closes, 0, trend_lookback=1) is False


def test_pin_bar_out_of_bounds_trend_lookback_returns_false():
    opens, highs, lows, closes = [116.0], [120.0], [100.0], [118.0]
    assert is_bullish_pin_bar(opens, highs, lows, closes, 0, trend_lookback=1) is False


# --- bullish/bearish engulfing --------------------------------------------------


def test_bullish_engulfing_detected():
    # candle 0 (newest, engulfing): open 99, close 112 (bullish, body 13)
    # candle 1 (older, engulfed): open 110, close 100 (bearish, body 10)
    opens = [99.0, 110.0]
    highs = [113.0, 111.0]
    lows = [98.0, 99.0]
    closes = [112.0, 100.0]
    assert is_bullish_engulfing(opens, highs, lows, closes, 0) is True
    assert is_bearish_engulfing(opens, highs, lows, closes, 0) is False


def test_bearish_engulfing_detected():
    # candle 0 (newest, engulfing): open 112, close 99 (bearish, body 13)
    # candle 1 (older, engulfed): open 100, close 110 (bullish, body 10)
    opens = [112.0, 100.0]
    highs = [113.0, 111.0]
    lows = [98.0, 99.0]
    closes = [99.0, 110.0]
    assert is_bearish_engulfing(opens, highs, lows, closes, 0) is True
    assert is_bullish_engulfing(opens, highs, lows, closes, 0) is False


def test_engulfing_fails_size_percentile_when_engulfing_candle_is_smaller_range():
    # Same directional/body conditions as the bullish case, but candle 0's
    # own high/low range is made much smaller than every comparison
    # candle, so its size percentile falls below the default 0.50 minimum.
    opens = [99.0, 110.0, 110.0, 110.0]
    highs = [112.5, 200.0, 200.0, 200.0]
    lows = [99.0, 50.0, 50.0, 50.0]
    closes = [112.0, 100.0, 100.0, 100.0]
    assert is_bullish_engulfing(opens, highs, lows, closes, 0, size_window=3) is False


def test_engulfing_out_of_bounds_returns_false():
    opens, highs, lows, closes = [100.0], [110.0], [90.0], [105.0]
    assert is_bullish_engulfing(opens, highs, lows, closes, 0) is False


# --- size_percentile ------------------------------------------------------------


def test_size_percentile_no_comparison_history_is_one():
    assert size_percentile([100.0], [90.0], 0, window=20) == pytest.approx(1.0)


def test_size_percentile_hand_computed():
    # range[0] = 20; comparison ranges [10, 30] -> one smaller (10), one
    # larger (30) -> less_count = 1, total = 2 -> percentile = 0.5
    highs = [120.0, 110.0, 130.0]
    lows = [100.0, 100.0, 100.0]
    assert size_percentile(highs, lows, 0, window=20) == pytest.approx(0.5)


# --- TASK-033: atr_size -------------------------------------------------------


def test_atr_size_hand_computed():
    highs = [110.0]
    lows = [100.0]
    atr_values = [5.0]
    assert atr_size(highs, lows, atr_values, 0) == pytest.approx(2.0)


def test_atr_size_zero_atr_is_zero():
    assert atr_size([110.0], [100.0], [0.0], 0) == 0.0


# --- TASK-033: dragonfly/gravestone rejection ----------------------------------


def test_dragonfly_rejection_detected():
    # open=100, close=100.05, high=100.1, low=90 -> range=10.1,
    # body_ratio~0.005 (<=0.10), lower_wick_ratio=10/10.1~0.99 (>=0.70),
    # upper_wick_ratio~0.005 (<=0.10).
    opens = [100.0]
    highs = [100.1]
    lows = [90.0]
    closes = [100.05]
    assert is_dragonfly_rejection(opens, highs, lows, closes, 0) is True
    assert is_gravestone_rejection(opens, highs, lows, closes, 0) is False


def test_gravestone_rejection_detected():
    # open=100, close=100.05, high=110, low=99.95 -> range=10.05,
    # body_ratio~0.005 (<=0.10), upper_wick_ratio=9.95/10.05~0.99 (>=0.70),
    # lower_wick_ratio~0.005 (<=0.10).
    opens = [100.0]
    highs = [110.0]
    lows = [99.95]
    closes = [100.05]
    assert is_gravestone_rejection(opens, highs, lows, closes, 0) is True
    assert is_dragonfly_rejection(opens, highs, lows, closes, 0) is False


# --- TASK-033: marubozu --------------------------------------------------------


def test_marubozu_detected():
    # open=100, close=110, high=110.2, low=99.8 -> range=10.4, body=10,
    # body_ratio~0.96 (>=0.90); atr=5 -> atr_size=10.4/5=2.08 (>=1.5).
    opens = [100.0]
    highs = [110.2]
    lows = [99.8]
    closes = [110.0]
    atr_values = [5.0]
    assert is_marubozu(opens, highs, lows, closes, atr_values, 0) is True


def test_marubozu_fails_when_displacement_too_small():
    opens = [100.0]
    highs = [110.2]
    lows = [99.8]
    closes = [110.0]
    atr_values = [50.0]  # atr_size = 10.4/50 = 0.208, well below 1.5
    assert is_marubozu(opens, highs, lows, closes, atr_values, 0) is False


# --- TASK-033: doji / spinning top ----------------------------------------------


def test_doji_detected():
    # open=100, close=100.2, high=105, low=95 -> range=10, body=0.2,
    # body_ratio=0.02 (<=0.10).
    assert is_doji([100.0], [105.0], [95.0], [100.2], 0) is True


def test_doji_fails_when_body_too_large():
    assert is_doji([100.0], [105.0], [95.0], [103.0], 0) is False


def test_spinning_top_detected():
    # open=100, close=102, high=106, low=96 -> range=10, body=2,
    # body_ratio=0.2 (between 0.10 and 0.35); upper_wick=4 (ratio 0.4),
    # lower_wick=4 (ratio 0.4) -- both >= 0.20.
    assert is_spinning_top([100.0], [106.0], [96.0], [102.0], 0) is True


def test_spinning_top_fails_when_body_is_doji_sized():
    # body_ratio 0.02 <= doji_max_body_ratio(0.10) -- rejected as a doji,
    # not a spinning top.
    assert is_spinning_top([100.0], [105.0], [95.0], [100.2], 0) is False


# --- TASK-033: inside/outside bar ------------------------------------------------


def test_inside_bar_detected():
    # candle 0 (newer) fully contained within candle 1 (older)'s range.
    highs = [105.0, 110.0]
    lows = [95.0, 90.0]
    assert is_inside_bar(highs, lows, 0) is True
    assert is_outside_bar(highs, lows, 0) is False


def test_outside_bar_detected():
    # candle 0 (newer) fully engulfs candle 1 (older)'s range.
    highs = [110.0, 105.0]
    lows = [90.0, 95.0]
    assert is_outside_bar(highs, lows, 0) is True
    assert is_inside_bar(highs, lows, 0) is False


# --- TASK-033: tweezer top/bottom ------------------------------------------------


def test_tweezer_top_detected():
    # highs nearly equal (within tolerance_atr*atr), candle 1 (older) up,
    # candle 0 (newer) down.
    opens = [102.0, 100.0]
    highs = [110.0, 110.05]
    lows = [98.0, 99.0]
    closes = [99.0, 109.0]
    atr_values = [5.0, 5.0]
    assert is_tweezer_top(opens, highs, lows, closes, atr_values, 0) is True


def test_tweezer_bottom_detected():
    # lows nearly equal, candle 1 (older) down, candle 0 (newer) up.
    opens = [98.0, 100.0]
    highs = [102.0, 101.0]
    lows = [90.0, 89.95]
    closes = [101.0, 91.0]
    atr_values = [5.0, 5.0]
    assert is_tweezer_bottom(opens, highs, lows, closes, atr_values, 0) is True


# --- TASK-033: harami detect + confirmed -----------------------------------------


def test_harami_bearish_implied_and_confirmed():
    # index 2 (oldest): big bullish candle, body 10 (open 100, close 110).
    # index 1 (middle, the harami): small body 2 (open 105, close 107),
    # fully inside index 2's body -- implied BEARISH (index 2 was bullish).
    # index 0 (newest): closes at 104 < closes[2]=110 -- confirms the
    # implied bearish reversal.
    opens = [102.0, 105.0, 100.0]
    closes = [104.0, 107.0, 110.0]

    direction = detect_harami(opens, closes, 1)
    assert direction == HaramiDirection.BEARISH_IMPLIED
    assert is_harami_confirmed(closes, 1, direction) is True


def test_harami_not_detected_when_inside_body_too_large():
    # inside body (index 1) is NOT small enough relative to index 2's body.
    opens = [102.0, 101.0, 100.0]
    closes = [104.0, 109.0, 110.0]  # body_1 = 8, body_2 = 10 -- 8 >= 10*0.5
    assert detect_harami(opens, closes, 1) == HaramiDirection.NONE


# --- TASK-033: morning/evening star ----------------------------------------------


def test_morning_star_detected():
    # index 2 (oldest): bearish, open 110 -> close 100 (body 10).
    # index 1 (middle): small body (99.5 -> 99.7), no overlap with index 2's
    # body (100-110).
    # index 0 (newest): bullish, close 108 > midpoint(105).
    opens = [104.0, 99.5, 110.0]
    highs = [109.0, 100.0, 111.0]
    lows = [103.0, 99.0, 99.0]
    closes = [108.0, 99.7, 100.0]
    assert is_morning_star(opens, highs, lows, closes, 0) is True
    assert is_evening_star(opens, highs, lows, closes, 0) is False


def test_evening_star_detected():
    # index 2 (oldest): bullish, open 100 -> close 110 (body 10).
    # index 1 (middle): small body (110.3 -> 110.5), no overlap.
    # index 0 (newest): bearish, close 102 < midpoint(105).
    opens = [106.0, 110.3, 100.0]
    highs = [107.0, 111.0, 111.0]
    lows = [101.0, 110.0, 99.0]
    closes = [102.0, 110.5, 110.0]
    assert is_evening_star(opens, highs, lows, closes, 0) is True
    assert is_morning_star(opens, highs, lows, closes, 0) is False


# --- TASK-033: three white soldiers / three black crows --------------------------


def test_three_white_soldiers_detected():
    # Three consecutive marubozu-like bullish candles, each strictly
    # higher (open and close) than the older one before it.
    opens = [108.0, 104.0, 100.0]
    highs = [112.0, 108.0, 104.0]
    lows = [108.0, 104.0, 100.0]
    closes = [112.0, 108.0, 104.0]
    assert is_three_white_soldiers(opens, highs, lows, closes, 0) is True
    assert is_three_black_crows(opens, highs, lows, closes, 0) is False


def test_three_black_crows_detected():
    opens = [104.0, 108.0, 112.0]
    highs = [104.0, 108.0, 112.0]
    lows = [100.0, 104.0, 108.0]
    closes = [100.0, 104.0, 108.0]
    assert is_three_black_crows(opens, highs, lows, closes, 0) is True
    assert is_three_white_soldiers(opens, highs, lows, closes, 0) is False


# --- TASK-033: minimal SwingEngine pivot-predicate port + three-bar reversal -----


def test_is_confirmed_swing_high_and_low():
    highs = [90.0, 100.0, 90.0]
    assert is_confirmed_swing_high(highs, 1, depth=1) is True
    lows = [95.0, 90.0, 95.0]
    assert is_confirmed_swing_low(lows, 1, depth=1) is True


def test_is_confirmed_swing_rejects_a_non_pivot():
    highs = [100.0, 100.0, 90.0]  # neighbor NOT strictly lower -- not a pivot
    assert is_confirmed_swing_high(highs, 1, depth=1) is False


def test_find_nearest_confirmed_swing_high_and_low():
    highs = [90.0, 100.0, 90.0, 80.0, 70.0]
    assert find_nearest_confirmed_swing_high(highs, 0, depth=1, max_lookback=3) == 1

    lows = [95.0, 90.0, 95.0, 85.0, 75.0]
    assert find_nearest_confirmed_swing_low(lows, 0, depth=1, max_lookback=3) == 1


def test_find_nearest_confirmed_swing_returns_none_when_absent():
    highs = [80.0, 81.0, 82.0, 83.0, 84.0]  # monotonic -- no pivot anywhere
    assert find_nearest_confirmed_swing_high(highs, 0, depth=1, max_lookback=3) is None


def test_three_bar_reversal_detected_on_confirmed_swing_low():
    # lows[1] is a confirmed swing low (depth=1): lows[0]=95 > 90, lows[2]=95 > 90.
    highs = [100.0, 95.0, 100.0]
    lows = [95.0, 90.0, 95.0]
    opens = [105.0, 92.0, 100.0]
    closes = [110.0, 93.0, 96.0]
    # closes[0]=110 > opens[2]=100 -- confirms the reversal.
    assert is_three_bar_reversal(highs, lows, opens, closes, 0, swing_depth=1) is True


def test_three_bar_reversal_fails_when_close_does_not_clear_opens_k2():
    highs = [100.0, 95.0, 100.0]
    lows = [95.0, 90.0, 95.0]
    opens = [105.0, 92.0, 100.0]
    closes = [90.0, 93.0, 96.0]  # 90 is NOT > opens[2]=100
    assert is_three_bar_reversal(highs, lows, opens, closes, 0, swing_depth=1) is False


# --- TASK-033: linear_interpolate / has_prior_trend ------------------------------


def test_linear_interpolate_hand_computed():
    # A line from (x1=5, y1=100) to (x2=0, y2=110) -- interpolate at k=2.
    # Slope over the 5-unit run is (110-100)/(0-5) = -2 per unit of x;
    # at k=2 (3 units from x1=5 toward x2=0): y = 100 + (110-100)*(5-2)/(5-0) = 106.
    assert linear_interpolate(5, 100.0, 0, 110.0, 2) == pytest.approx(106.0)


def test_linear_interpolate_same_x_returns_y1():
    assert linear_interpolate(3, 50.0, 3, 60.0, 3) == pytest.approx(50.0)


def test_has_prior_trend_up_and_down():
    closes = [110.0, 105.0, 100.0]  # index 0 newest
    assert has_prior_trend(closes, reference_index=0, trend_bars=2, require_up=True) is True
    assert has_prior_trend(closes, reference_index=0, trend_bars=2, require_up=False) is False


def test_has_prior_trend_out_of_bounds_is_false():
    closes = [110.0, 105.0]
    assert has_prior_trend(closes, reference_index=0, trend_bars=5, require_up=True) is False


# --- TASK-033: check_retest -------------------------------------------------------


def test_check_retest_holds_when_no_close_breaks_the_boundary():
    closes = [101.0, 100.5, 100.2]
    assert (
        check_retest(
            closes,
            touch_index=2,
            boundary_price=100.0,
            is_bullish_breakout=True,
            current_atr=1.0,
            failure_tolerance_atr=0.1,
            max_bars=5,
        )
        is True
    )


def test_check_retest_fails_when_a_close_breaks_the_boundary():
    closes = [101.0, 98.0, 100.2]  # index 1 closes well below the boundary
    assert (
        check_retest(
            closes,
            touch_index=2,
            boundary_price=100.0,
            is_bullish_breakout=True,
            current_atr=1.0,
            failure_tolerance_atr=0.1,
            max_bars=5,
        )
        is False
    )


def test_check_retest_negative_touch_index_returns_none():
    assert (
        check_retest(
            [100.0],
            touch_index=-1,
            boundary_price=100.0,
            is_bullish_breakout=True,
            current_atr=1.0,
            failure_tolerance_atr=0.1,
            max_bars=5,
        )
        is None
    )


# --- TASK-033: chart patterns (double top/bottom, head-and-shoulders/inverse) ----


# Shared fixture: two equal-height confirmed swing highs (indices 1 and 5)
# separated by a confirmed swing low (index 3), matching CPT_DetectDoubleTopArray's
# own requirements. depth=1, current_atr=2.0.
_DT_HIGHS = [100.0, 110.0, 100.0, 90.0, 100.0, 110.0, 100.0, 95.0, 90.0, 85.0]
_DT_LOWS = [95.0, 100.0, 95.0, 80.0, 95.0, 100.0, 95.0, 85.0, 80.0, 75.0]
_DT_CLOSES = [98.0, 105.0, 97.0, 85.0, 97.0, 105.0, 97.0, 90.0, 85.0, 80.0]


def test_detect_double_top_found():
    result = detect_double_top(
        _DT_HIGHS,
        _DT_LOWS,
        _DT_CLOSES,
        depth=1,
        max_lookback=5,
        current_atr=2.0,
        price_tolerance_atr=0.5,
        min_pullback_atr=1.0,
        trend_bars=2,
        breakout_buffer_atr=0.1,
    )
    assert result.found is True
    assert result.type.value == "DOUBLE_TOP"
    assert result.boundary_price == pytest.approx(80.0)  # the trough (neckline)
    assert result.extreme_price == pytest.approx(110.0)  # the higher/equal peak


def test_detect_double_top_not_found_when_atr_non_positive():
    result = detect_double_top(
        _DT_HIGHS,
        _DT_LOWS,
        _DT_CLOSES,
        depth=1,
        max_lookback=5,
        current_atr=0.0,
        price_tolerance_atr=0.5,
        min_pullback_atr=1.0,
        trend_bars=2,
        breakout_buffer_atr=0.1,
    )
    assert result.found is False


# Mirror fixture for double bottom (highs/lows swapped in shape).
_DB_HIGHS = [105.0, 100.0, 105.0, 120.0, 105.0, 100.0, 105.0, 115.0, 120.0, 125.0]
_DB_LOWS = [100.0, 90.0, 100.0, 110.0, 100.0, 90.0, 100.0, 105.0, 110.0, 115.0]
_DB_CLOSES = [102.0, 95.0, 103.0, 115.0, 103.0, 95.0, 103.0, 110.0, 115.0, 120.0]


def test_detect_double_bottom_found():
    result = detect_double_bottom(
        _DB_HIGHS,
        _DB_LOWS,
        _DB_CLOSES,
        depth=1,
        max_lookback=5,
        current_atr=2.0,
        price_tolerance_atr=0.5,
        min_pullback_atr=1.0,
        trend_bars=2,
        breakout_buffer_atr=0.1,
    )
    assert result.found is True
    assert result.type.value == "DOUBLE_BOTTOM"
    assert result.boundary_price == pytest.approx(120.0)  # the peak (neckline)
    assert result.extreme_price == pytest.approx(90.0)  # the lower/equal trough


# --- TASK-039: triple top/bottom (natural 3-peak/trough extensions of ----------
# double top/bottom, reusing the same swing-finder plumbing).

_TT_HIGHS = [
    100.0,
    110.0,
    100.0,
    90.0,
    100.0,
    110.0,
    100.0,
    90.0,
    100.0,
    110.0,
    100.0,
    95.0,
    90.0,
    85.0,
]
_TT_LOWS = [
    95.0,
    100.0,
    95.0,
    80.0,
    95.0,
    100.0,
    95.0,
    80.0,
    95.0,
    100.0,
    95.0,
    85.0,
    80.0,
    75.0,
]
_TT_CLOSES = [
    98.0,
    105.0,
    97.0,
    85.0,
    97.0,
    105.0,
    97.0,
    85.0,
    97.0,
    105.0,
    97.0,
    90.0,
    85.0,
    80.0,
]


def test_detect_triple_top_found():
    result = detect_triple_top(
        _TT_HIGHS,
        _TT_LOWS,
        _TT_CLOSES,
        depth=1,
        max_lookback=5,
        current_atr=2.0,
        price_tolerance_atr=0.5,
        min_pullback_atr=1.0,
        trend_bars=2,
        breakout_buffer_atr=0.1,
    )
    assert result.found is True
    assert result.type.value == "TRIPLE_TOP"
    assert result.boundary_price == pytest.approx(80.0)  # the lower of the two troughs
    assert result.extreme_price == pytest.approx(110.0)


_TB_HIGHS = [
    105.0,
    100.0,
    105.0,
    120.0,
    105.0,
    100.0,
    105.0,
    120.0,
    105.0,
    100.0,
    105.0,
    115.0,
    120.0,
    125.0,
]
_TB_LOWS = [
    100.0,
    90.0,
    100.0,
    110.0,
    100.0,
    90.0,
    100.0,
    110.0,
    100.0,
    90.0,
    100.0,
    105.0,
    110.0,
    115.0,
]
_TB_CLOSES = [
    102.0,
    95.0,
    103.0,
    115.0,
    103.0,
    95.0,
    103.0,
    115.0,
    103.0,
    95.0,
    103.0,
    110.0,
    115.0,
    120.0,
]


def test_detect_triple_bottom_found():
    result = detect_triple_bottom(
        _TB_HIGHS,
        _TB_LOWS,
        _TB_CLOSES,
        depth=1,
        max_lookback=5,
        current_atr=2.0,
        price_tolerance_atr=0.5,
        min_pullback_atr=1.0,
        trend_bars=2,
        breakout_buffer_atr=0.1,
    )
    assert result.found is True
    assert result.type.value == "TRIPLE_BOTTOM"
    assert result.boundary_price == pytest.approx(120.0)  # the higher of the two peaks
    assert result.extreme_price == pytest.approx(90.0)


def test_detect_triple_top_not_found_when_atr_non_positive():
    result = detect_triple_top(
        _TT_HIGHS,
        _TT_LOWS,
        _TT_CLOSES,
        depth=1,
        max_lookback=5,
        current_atr=0.0,
        price_tolerance_atr=0.5,
        min_pullback_atr=1.0,
        trend_bars=2,
        breakout_buffer_atr=0.1,
    )
    assert result.found is False


# **Added, 2026-07-22 Codex review finding (seventh round, P1 finding 11):**
# same shape as _TT_HIGHS/_TT_LOWS, but h1=110.0, h2=109.0, h3=108.0 -- each
# ADJACENT pair (h1-h2=1.0, h2-h3=1.0) is exactly at the tolerance
# (price_tolerance_atr=0.5 * current_atr=2.0 = 1.0), yet h1-h3=2.0 exceeds
# it. The previous version checked only the two adjacent pairs and would
# have wrongly ACCEPTED this as a valid triple top.
_TT_HIGHS_DIVERGING_OUTER_PAIR = [
    100.0,
    110.0,
    100.0,
    90.0,
    100.0,
    109.0,
    100.0,
    90.0,
    100.0,
    108.0,
    100.0,
    95.0,
    90.0,
    85.0,
]


def test_detect_triple_top_rejects_when_outer_pair_exceeds_tolerance():
    """Regression for a Codex review finding (2026-07-22, seventh round,
    P1 finding 11): TASK-002_PHASE2_SPECIFICATION.md section 6 requires
    all THREE peaks pairwise within price_tolerance_atr of each other,
    not just the two adjacent pairs -- h1 and h3 diverging by 2x the
    adjacent-pair tolerance must be rejected."""

    result = detect_triple_top(
        _TT_HIGHS_DIVERGING_OUTER_PAIR,
        _TT_LOWS,
        _TT_CLOSES,
        depth=1,
        max_lookback=5,
        current_atr=2.0,
        price_tolerance_atr=0.5,
        min_pullback_atr=1.0,
        trend_bars=2,
        breakout_buffer_atr=0.1,
    )
    assert result.found is False


# **Added, 2026-07-22 Codex review finding (seventh round, P1 finding 11):**
# same shape as _TT_LOWS, but trough1 (index 3) = 85.0 and trough2 (index 7)
# = 70.0 -- a genuinely SLOPED neckline (the previous flat
# min(85.0, 70.0)=70.0 neckline is a different, wrong value from the
# correct sloped-at-h1 value hand-traced below).
_TT_LOWS_SLOPED_NECKLINE = [
    95.0,
    100.0,
    95.0,
    85.0,
    95.0,
    100.0,
    95.0,
    70.0,
    95.0,
    100.0,
    95.0,
    85.0,
    80.0,
    75.0,
]


def test_detect_triple_top_uses_sloped_neckline_not_flat_min():
    """Regression for a Codex review finding (2026-07-22, seventh round,
    P1 finding 11): the neckline through trough1 (index 3, price 85.0) and
    trough2 (index 7, price 70.0) must be LINEARLY INTERPOLATED/
    EXTRAPOLATED (per TASK-002_PHASE2_SPECIFICATION.md section 6's
    "possibly sloped neckline"), not flattened to min(85.0, 70.0)=70.0.

    Hand-traced: h1=1, h2=5, h3=9 (unchanged from the base fixture, all
    exactly 110.0 -- pairwise tolerance trivially satisfied). trough1=3
    (85.0), trough2=7 (70.0). Sloped neckline at k:
    linear_interpolate(3, 85.0, 7, 70.0, k) = 85.0 + (70.0-85.0)*(3-k)/(3-7)
    = 85.0 + 15.0*(3-k)/4.0.

    **Extended, 2026-07-22 (Codex review finding, eighth round, P1 finding
    14):** boundary_price is now evaluated at index 0 (the current bar),
    not at h1 -- the live strategy compares this value directly against
    closes[0], and a value frozen at an old pivot bar is simply wrong
    whenever the neckline has any slope (see pattern_validation.py's own
    fix comment, mirroring ChartPatternEngine.mqh's identical fix):
      85.0 + 15.0*(3-0)/4.0 = 85.0 + 11.25 = 96.25 -- NOT the flat 70.0 the
      pre-seventh-round version would have reported, and NOT the
      92.5 (evaluated at the now-stale h1=1) an intermediate version did.

    No breakout is found (closes[0]=98.0 never drops below the neckline
    minus the buffer at any scanned k), so target_reference=h1=1, and
    neckline_at_extreme is evaluated at h1 (extreme_index==h1 here, since
    all three peaks tie at 110.0 and ties never advance extreme_index past
    the first/newest one) -- BOTH of these are unaffected by the
    boundary_price fix (target_reference/extreme_index still use h1, never
    index 0): neckline_at_h1 = 85.0 + 15.0*(3-1)/4.0 = 92.5, giving
    target = 92.5 - (110.0 - 92.5) = 75.0, unchanged.
    """

    result = detect_triple_top(
        _TT_HIGHS,
        _TT_LOWS_SLOPED_NECKLINE,
        _TT_CLOSES,
        depth=1,
        max_lookback=5,
        current_atr=2.0,
        price_tolerance_atr=0.5,
        min_pullback_atr=1.0,
        trend_bars=2,
        breakout_buffer_atr=0.1,
    )
    assert result.found is True
    assert result.boundary_price == pytest.approx(96.25)
    assert result.extreme_price == pytest.approx(110.0)
    assert result.target == pytest.approx(75.0)


# **Added, 2026-07-22 Codex review finding (seventh round, P1 finding 11):**
# mirror of the outer-pair rejection test above, on swing lows.
_TB_LOWS_DIVERGING_OUTER_PAIR = [
    100.0,
    90.0,
    100.0,
    110.0,
    100.0,
    91.0,
    100.0,
    110.0,
    100.0,
    92.0,
    100.0,
    105.0,
    110.0,
    115.0,
]


def test_detect_triple_bottom_rejects_when_outer_pair_exceeds_tolerance():
    """Mirror of test_detect_triple_top_rejects_when_outer_pair_exceeds_tolerance
    on swing lows: l1=90.0, l2=91.0, l3=92.0 -- each adjacent pair (1.0) is
    exactly at tolerance, but l1-l3=2.0 exceeds it."""

    result = detect_triple_bottom(
        _TB_HIGHS,
        _TB_LOWS_DIVERGING_OUTER_PAIR,
        _TB_CLOSES,
        depth=1,
        max_lookback=5,
        current_atr=2.0,
        price_tolerance_atr=0.5,
        min_pullback_atr=1.0,
        trend_bars=2,
        breakout_buffer_atr=0.1,
    )
    assert result.found is False


# Head-and-shoulders fixture: three confirmed swing highs (RS newest, Head,
# LS oldest) with the head strictly higher, roughly symmetric in time, and
# two confirmed swing-low troughs between them for the (sloped) neckline.
_HS_HIGHS = [
    100.0,
    105.0,
    100.0,
    95.0,
    100.0,
    120.0,
    100.0,
    95.0,
    100.0,
    105.0,
    100.0,
    90.0,
]
_HS_LOWS = [
    95.0,
    96.0,
    95.0,
    80.0,
    95.0,
    96.0,
    95.0,
    78.0,
    95.0,
    96.0,
    95.0,
    85.0,
]
_HS_CLOSES = [
    98.0,
    100.0,
    97.0,
    82.0,
    97.0,
    115.0,
    97.0,
    80.0,
    97.0,
    100.0,
    97.0,
    87.0,
]


def test_detect_head_and_shoulders_found():
    # max_lookback=5: rs found at index 1; head must be reachable from
    # index 2 (rs+1) within the scan window, and it sits at index 5 --
    # max_lookback=3 would stop scanning at index 4 and miss it entirely.
    result = detect_head_and_shoulders(
        _HS_HIGHS,
        _HS_LOWS,
        _HS_CLOSES,
        depth=1,
        max_lookback=5,
        current_atr=2.0,
        price_tolerance_atr=0.5,
        time_tolerance=0.5,
        min_head_prominence_atr=1.0,
        breakout_buffer_atr=0.1,
        trend_bars=2,
    )
    assert result.found is True
    assert result.type.value == "HEAD_SHOULDERS"
    assert result.extreme_price == pytest.approx(120.0)


# Inverse head-and-shoulders: mirror of the above on swing lows. The head
# (index 5, low=80) is the deepest trough; the two shoulders (index 1 and
# 9, low=95) are roughly equal -- unlike the head-and-shoulders fixture's
# highs array (reused here unchanged, since its two intervening swing
# highs at index 3/7 already serve as this pattern's own neckline points).
_IHS_HIGHS = [
    105.0,
    104.0,
    105.0,
    120.0,
    105.0,
    104.0,
    105.0,
    122.0,
    105.0,
    104.0,
    105.0,
    115.0,
]
_IHS_LOWS = [
    100.0,
    95.0,
    100.0,
    105.0,
    100.0,
    80.0,
    100.0,
    107.0,
    100.0,
    95.0,
    100.0,
    105.0,
]
_IHS_CLOSES = [
    102.0,
    100.0,
    103.0,
    118.0,
    103.0,
    85.0,
    103.0,
    120.0,
    103.0,
    100.0,
    103.0,
    113.0,
]


def test_detect_inverse_head_and_shoulders_found():
    result = detect_inverse_head_and_shoulders(
        _IHS_HIGHS,
        _IHS_LOWS,
        _IHS_CLOSES,
        depth=1,
        max_lookback=5,
        current_atr=2.0,
        price_tolerance_atr=0.5,
        time_tolerance=0.5,
        min_head_prominence_atr=1.0,
        breakout_buffer_atr=0.1,
        trend_bars=2,
    )
    assert result.found is True
    assert result.type.value == "INV_HEAD_SHOULDERS"
    assert result.extreme_price == pytest.approx(80.0)


# --- detect_all_patterns / run / CLI ---------------------------------------------


def test_detect_all_patterns_returns_one_row_per_bar():
    opens = [99.0, 110.0]
    highs = [113.0, 111.0]
    lows = [98.0, 99.0]
    closes = [112.0, 100.0]
    df = detect_all_patterns(opens, highs, lows, closes)
    assert len(df) == 2
    assert bool(df.iloc[0]["bullish_engulfing"]) is True


def test_negative_size_window_rejected():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    a negative size_window makes size_percentile's own "total <= 0"
    branch return 1.0 ("no comparison history -- cannot be disproven as
    large"), silently turning any bar into an automatic 100th-percentile
    pattern pass regardless of its real size."""

    opens = [99.0, 110.0]
    highs = [113.0, 111.0]
    lows = [98.0, 99.0]
    closes = [112.0, 100.0]
    with pytest.raises(ValueError):
        detect_all_patterns(opens, highs, lows, closes, size_window=-1)


def test_negative_trend_lookback_rejected():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    a negative trend_lookback bypasses the k + trend_lookback >= n
    upper-bound guard while still being used as a list index, so
    closes[k + trend_lookback] can silently wrap around to the end of
    the array (Python negative-index semantics) instead of raising."""

    opens = [99.0, 110.0, 105.0]
    highs = [113.0, 111.0, 108.0]
    lows = [98.0, 99.0, 100.0]
    closes = [112.0, 100.0, 104.0]
    with pytest.raises(ValueError):
        detect_all_patterns(opens, highs, lows, closes, trend_lookback=-1)


def test_run_missing_column_raises(tmp_path):
    path = tmp_path / "ohlc.csv"
    pd.DataFrame({"open": [1.0]}).to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        run(path)


def test_run_writes_output_csv(tmp_path):
    path = tmp_path / "ohlc.csv"
    pd.DataFrame(
        {
            "open": [99.0, 110.0],
            "high": [113.0, 111.0],
            "low": [98.0, 99.0],
            "close": [112.0, 100.0],
        }
    ).to_csv(path, index=False)
    out_csv = tmp_path / "out" / "patterns.csv"

    result = run(path, out_csv)
    assert out_csv.exists()
    assert len(pd.read_csv(out_csv)) == 2
    assert len(result) == 2


def test_run_writes_no_files_when_git_metadata_capture_fails(tmp_path):
    """Regression for a Codex review finding (2026-07-22, seventh round,
    P1 finding 16): a direct call with an invalid repo_path previously
    raised GitMetadataError AFTER output_csv already existed on disk --
    result and provenance were not one atomic publication. Metadata is
    now captured before either file is written."""

    from analysis.report_metadata import GitMetadataError

    path = tmp_path / "ohlc.csv"
    pd.DataFrame(
        {
            "open": [99.0, 110.0],
            "high": [113.0, 111.0],
            "low": [98.0, 99.0],
            "close": [112.0, 100.0],
        }
    ).to_csv(path, index=False)
    out_csv = tmp_path / "out" / "patterns.csv"
    summary_json = tmp_path / "out" / "patterns.summary.json"
    not_a_repo = tmp_path / "not_a_repo"
    not_a_repo.mkdir()

    with pytest.raises(GitMetadataError):
        run(path, out_csv, summary_json, repo_path=not_a_repo)

    assert not out_csv.exists()
    assert not summary_json.exists()


def test_run_always_includes_three_bar_reversal_column(tmp_path):
    """Regression for a Codex review finding (2026-07-22, seventh round,
    P1 finding 11): run()'s own CLI path previously exposed neither
    atr_values nor swing_depth to detect_all_patterns(), so
    three_bar_reversal (which needs only swing_depth, no extra CSV
    column) could never be persisted through the advertised pipeline."""

    path = tmp_path / "ohlc.csv"
    pd.DataFrame(
        {
            "open": [99.0, 110.0],
            "high": [113.0, 111.0],
            "low": [98.0, 99.0],
            "close": [112.0, 100.0],
        }
    ).to_csv(path, index=False)

    result = run(path)
    assert "three_bar_reversal" in result.columns
    assert "marubozu" not in result.columns  # no 'atr' column supplied -- correctly absent


def test_run_includes_atr_dependent_columns_when_atr_column_present(tmp_path):
    """An 'atr' column in ohlc_csv must enable the ATR-dependent pattern
    columns (marubozu, tweezer_top, tweezer_bottom) through run()'s own
    CLI path, per the same finding as
    test_run_always_includes_three_bar_reversal_column."""

    path = tmp_path / "ohlc.csv"
    pd.DataFrame(
        {
            "open": [99.0, 110.0],
            "high": [113.0, 111.0],
            "low": [98.0, 99.0],
            "close": [112.0, 100.0],
            "atr": [2.0, 2.0],
        }
    ).to_csv(path, index=False)

    result = run(path)
    for col in ("marubozu", "tweezer_top", "tweezer_bottom", "three_bar_reversal"):
        assert col in result.columns


def test_run_rejects_non_positive_atr(tmp_path):
    path = tmp_path / "ohlc.csv"
    pd.DataFrame(
        {
            "open": [99.0, 110.0],
            "high": [113.0, 111.0],
            "low": [98.0, 99.0],
            "close": [112.0, 100.0],
            "atr": [2.0, 0.0],
        }
    ).to_csv(path, index=False)

    with pytest.raises(CsvSchemaError):
        run(path)


def test_summary_json_auto_derived_when_omitted(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round): a
    caller requesting output_csv without summary_json previously got a
    CSV with NO accompanying provenance metadata anywhere. An implicit
    sidecar path is now derived from output_csv."""

    path = tmp_path / "ohlc.csv"
    pd.DataFrame(
        {
            "open": [99.0, 110.0],
            "high": [113.0, 111.0],
            "low": [98.0, 99.0],
            "close": [112.0, 100.0],
        }
    ).to_csv(path, index=False)
    out_csv = tmp_path / "out" / "patterns.csv"

    run(path, out_csv)

    import json

    derived_summary_json = tmp_path / "out" / "patterns.summary.json"
    assert derived_summary_json.exists()
    payload = json.loads(derived_summary_json.read_text(encoding="utf-8"))
    assert payload["metadata"]["dataset_hash"]


def test_run_writes_provenance_sidecar(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    this script previously emitted an entirely unprovenanced CSV, unlike
    every other pipeline in this layer."""

    path = tmp_path / "ohlc.csv"
    pd.DataFrame(
        {
            "open": [99.0, 110.0],
            "high": [113.0, 111.0],
            "low": [98.0, 99.0],
            "close": [112.0, 100.0],
        }
    ).to_csv(path, index=False)
    summary_json = tmp_path / "out" / "summary.json"

    run(path, summary_json=summary_json, symbol="XAUUSD")

    import json

    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["metadata"]["dataset_hash"] != ""
    assert payload["metadata"]["symbol"] == "XAUUSD"
    assert payload["summary"]["n_bars"] == 2


def test_compare_to_mql5_export_reports_disagreements(tmp_path):
    python_results = pd.DataFrame(
        {"k": [0, 1], "bullish_engulfing": [True, False], "bearish_engulfing": [False, False]}
    )
    mql5_export = tmp_path / "mql5_export.csv"
    pd.DataFrame(
        {"k": [0, 1], "bullish_engulfing": [False, False], "bearish_engulfing": [False, False]}
    ).to_csv(mql5_export, index=False)

    disagreements = compare_to_mql5_export(python_results, mql5_export)
    assert len(disagreements) == 1
    assert disagreements.iloc[0]["k"] == 0


def test_cli_main_success(tmp_path, capsys):
    path = tmp_path / "ohlc.csv"
    pd.DataFrame(
        {
            "open": [99.0, 110.0],
            "high": [113.0, 111.0],
            "low": [98.0, 99.0],
            "close": [112.0, 100.0],
        }
    ).to_csv(path, index=False)
    exit_code = main(["--ohlc-csv", str(path)])
    assert exit_code == 0
    assert "2 bars scanned" in capsys.readouterr().out


def test_cli_main_missing_file(tmp_path, capsys):
    exit_code = main(["--ohlc-csv", str(tmp_path / "nope.csv")])
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err


def test_compare_to_mql5_export_rejects_non_overlapping_keys(tmp_path):
    """Regression for a Codex review finding (2026-07-21): the previous
    INNER merge silently dropped non-overlapping keys, so Python results
    at k=1 and an MQL5 export at k=0 (datasets that never actually
    overlap) returned an EMPTY disagreement DataFrame -- the strongest
    possible false "pass" for two datasets that were never compared."""

    python_results = pd.DataFrame({"k": [1], "bullish_engulfing": [True]})
    mql5_export = tmp_path / "mql5_export.csv"
    pd.DataFrame({"k": [0], "bullish_engulfing": [True]}).to_csv(mql5_export, index=False)

    with pytest.raises(CsvSchemaError):
        compare_to_mql5_export(python_results, mql5_export)


def test_compare_to_mql5_export_rejects_duplicate_python_key():
    python_results = pd.DataFrame({"k": [0, 0], "bullish_engulfing": [True, False]})
    with pytest.raises(CsvSchemaError):
        compare_to_mql5_export(python_results, Path("unused.csv"))


def test_compare_to_mql5_export_rejects_duplicate_mql5_key(tmp_path):
    python_results = pd.DataFrame({"k": [0], "bullish_engulfing": [True]})
    mql5_export = tmp_path / "mql5_export.csv"
    pd.DataFrame({"k": [0, 0], "bullish_engulfing": [True, False]}).to_csv(mql5_export, index=False)
    with pytest.raises(CsvSchemaError):
        compare_to_mql5_export(python_results, mql5_export)


def test_run_rejects_non_finite_ohlc(tmp_path):
    path = tmp_path / "ohlc.csv"
    pd.DataFrame({"open": [99.0], "high": [float("nan")], "low": [98.0], "close": [100.0]}).to_csv(
        path, index=False
    )
    with pytest.raises(CsvSchemaError):
        run(path)


def test_run_rejects_high_below_low(tmp_path):
    path = tmp_path / "ohlc.csv"
    pd.DataFrame({"open": [99.0], "high": [90.0], "low": [100.0], "close": [95.0]}).to_csv(
        path, index=False
    )
    with pytest.raises(CsvSchemaError):
        run(path)


def test_run_ascending_input_is_reversed_before_detection(tmp_path):
    """A caller declaring ascending_input=True gets the SAME detection
    result as passing the already-reversed (MQL5-convention) array
    directly -- confirms the reversal actually happens, not just accepted
    as a flag."""

    # MQL5-convention (newest first): bullish engulfing at k=0.
    opens = [99.0, 110.0]
    highs = [113.0, 111.0]
    lows = [98.0, 99.0]
    closes = [112.0, 100.0]
    path_newest_first = tmp_path / "ohlc_newest_first.csv"
    pd.DataFrame({"open": opens, "high": highs, "low": lows, "close": closes}).to_csv(
        path_newest_first, index=False
    )
    direct_result = run(path_newest_first)

    # Same data, chronologically ascending (oldest first) -- the reverse order.
    path_ascending = tmp_path / "ohlc_ascending.csv"
    pd.DataFrame(
        {"open": opens[::-1], "high": highs[::-1], "low": lows[::-1], "close": closes[::-1]}
    ).to_csv(path_ascending, index=False)
    reversed_result = run(path_ascending, ascending_input=True)

    assert bool(direct_result.iloc[0]["bullish_engulfing"]) is True
    assert bool(reversed_result.iloc[0]["bullish_engulfing"]) is True
