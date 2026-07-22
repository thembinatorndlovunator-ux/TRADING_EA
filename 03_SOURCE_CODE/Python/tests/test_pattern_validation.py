from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from analysis.csv_io import CsvSchemaError
from analysis.pattern_validation import (
    compare_to_mql5_export,
    detect_all_patterns,
    is_bearish_engulfing,
    is_bearish_pin_bar,
    is_bullish_engulfing,
    is_bullish_pin_bar,
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
