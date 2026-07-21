from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from analysis.csv_io import (
    CsvSchemaError,
    assert_high_low_geometry,
    assert_output_paths_distinct,
    assert_unique_ids,
    assert_valid_stop_geometry,
    parse_is_long,
    read_csv_with_required_columns,
    sanitize_for_csv,
)


# --- read_csv_with_required_columns (duplicate-header detection) -----------


def test_duplicate_csv_header_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22): pandas
    silently mangles a duplicate CSV header (e.g. two 'trade_id' columns
    become 'trade_id'/'trade_id.1') BEFORE the required-column check ever
    sees it, so a genuinely malformed CSV with a repeated column name
    previously passed silently."""

    path = tmp_path / "trades.csv"
    path.write_text("trade_id,profit,trade_id\nt1,10.0,t1\n", encoding="utf-8")
    with pytest.raises(CsvSchemaError):
        read_csv_with_required_columns(path, {"trade_id", "profit"})


def test_missing_required_column_still_raises(tmp_path):
    path = tmp_path / "trades.csv"
    path.write_text("trade_id,profit\nt1,10.0\n", encoding="utf-8")
    with pytest.raises(CsvSchemaError):
        read_csv_with_required_columns(path, {"trade_id", "profit", "symbol"})


def test_no_duplicate_header_reads_fine(tmp_path):
    path = tmp_path / "trades.csv"
    path.write_text("trade_id,profit\nt1,10.0\n", encoding="utf-8")
    df = read_csv_with_required_columns(path, {"trade_id", "profit"})
    assert len(df) == 1


# --- assert_unique_ids (blank/null ID rejection) -----------------------------


def test_assert_unique_ids_rejects_blank_id():
    """Regression for a Codex review finding: blank IDs were previously
    excluded from duplicate-checking entirely (to avoid every empty-
    signal_id row trivially "duplicating"), which let a blank
    event_id/trade_id pass silently -- one was later observed written out
    as the literal string "nan"."""

    df = pd.DataFrame({"trade_id": ["t1", ""], "profit": [10.0, -5.0]})
    with pytest.raises(CsvSchemaError):
        assert_unique_ids(df, "trade_id", Path("trades.csv"))


def test_assert_unique_ids_rejects_null_id():
    df = pd.DataFrame({"trade_id": ["t1", None], "profit": [10.0, -5.0]})
    with pytest.raises(CsvSchemaError):
        assert_unique_ids(df, "trade_id", Path("trades.csv"))


def test_assert_unique_ids_rejects_duplicate():
    df = pd.DataFrame({"trade_id": ["t1", "t1"], "profit": [10.0, -5.0]})
    with pytest.raises(CsvSchemaError):
        assert_unique_ids(df, "trade_id", Path("trades.csv"))


def test_assert_unique_ids_passes_for_valid_data():
    df = pd.DataFrame({"trade_id": ["t1", "t2"], "profit": [10.0, -5.0]})
    assert_unique_ids(df, "trade_id", Path("trades.csv"))  # must not raise


# --- assert_high_low_geometry (full OHLC geometry) --------------------------


def test_assert_high_low_geometry_rejects_high_below_low():
    df = pd.DataFrame({"high": [100.0], "low": [105.0]})
    with pytest.raises(CsvSchemaError):
        assert_high_low_geometry(df, "high", "low", Path("bars.csv"))


def test_assert_high_low_geometry_rejects_open_outside_range():
    """Regression for a Codex review finding (2026-07-22): only high>=low
    was checked, not that open/close also fall within [low, high] -- an
    equally impossible bar geometry."""

    df = pd.DataFrame({"open": [110.0], "high": [105.0], "low": [95.0], "close": [100.0]})
    with pytest.raises(CsvSchemaError):
        assert_high_low_geometry(df, "high", "low", Path("bars.csv"), open_column="open", close_column="close")


def test_assert_high_low_geometry_rejects_close_outside_range():
    df = pd.DataFrame({"open": [100.0], "high": [105.0], "low": [95.0], "close": [90.0]})
    with pytest.raises(CsvSchemaError):
        assert_high_low_geometry(df, "high", "low", Path("bars.csv"), open_column="open", close_column="close")


def test_assert_high_low_geometry_passes_for_valid_bar():
    df = pd.DataFrame({"open": [100.0], "high": [105.0], "low": [95.0], "close": [102.0]})
    assert_high_low_geometry(df, "high", "low", Path("bars.csv"), open_column="open", close_column="close")


def test_assert_high_low_geometry_without_open_close_only_checks_high_low():
    # No open/close columns given -- only the high>=low check applies,
    # matching calculate_mfe_mae.py's bars.csv shape (no open column).
    df = pd.DataFrame({"high": [105.0], "low": [95.0]})
    assert_high_low_geometry(df, "high", "low", Path("bars.csv"))  # must not raise


# --- assert_valid_stop_geometry ---------------------------------------------


def test_assert_valid_stop_geometry_rejects_long_stop_on_wrong_side():
    """Regression for a Codex review finding: compute_r_multiple's live
    fail-safe silently returns 0R for malformed stop geometry -- correct
    for a live guard, wrong for evidence cleaning. A long trade with
    entry 100 and stop 101 is malformed and must be rejected."""

    is_long = pd.Series([True])
    entry = pd.Series([100.0])
    stop = pd.Series([101.0])
    with pytest.raises(CsvSchemaError):
        assert_valid_stop_geometry(is_long, entry, stop, Path("trades.csv"))


def test_assert_valid_stop_geometry_rejects_short_stop_on_wrong_side():
    is_long = pd.Series([False])
    entry = pd.Series([100.0])
    stop = pd.Series([99.0])
    with pytest.raises(CsvSchemaError):
        assert_valid_stop_geometry(is_long, entry, stop, Path("trades.csv"))


def test_assert_valid_stop_geometry_rejects_stop_equal_to_entry():
    is_long = pd.Series([True])
    entry = pd.Series([100.0])
    stop = pd.Series([100.0])
    with pytest.raises(CsvSchemaError):
        assert_valid_stop_geometry(is_long, entry, stop, Path("trades.csv"))


def test_assert_valid_stop_geometry_passes_for_valid_trades():
    is_long = pd.Series([True, False])
    entry = pd.Series([100.0, 100.0])
    stop = pd.Series([98.0, 102.0])
    assert_valid_stop_geometry(is_long, entry, stop, Path("trades.csv"))  # must not raise


# --- assert_output_paths_distinct -------------------------------------------


def test_assert_output_paths_distinct_rejects_same_path_twice():
    p = Path("out.json")
    with pytest.raises(CsvSchemaError):
        assert_output_paths_distinct([p, p])


def test_assert_output_paths_distinct_ignores_none():
    assert_output_paths_distinct([None, Path("a.json"), None])  # must not raise


def test_assert_output_paths_distinct_passes_for_distinct_paths(tmp_path):
    assert_output_paths_distinct([tmp_path / "a.json", tmp_path / "b.csv"])  # must not raise


# --- sanitize_for_csv (formula-injection defense) ---------------------------


@pytest.mark.parametrize("prefix", ["=", "+", "-", "@", "\t", "\r"])
def test_sanitize_for_csv_neutralizes_formula_prefixes(prefix):
    """Regression for a Codex review finding: caller-controlled journal
    strings written directly to CSV could become live spreadsheet
    formulas (e.g. "=CMD(...)") when a reviewer opens the export."""

    value = f"{prefix}CMD(...)"
    result = sanitize_for_csv(value)
    assert result == f"'{value}"
    assert result.startswith("'")  # neutralized as inert text, not a live formula


def test_sanitize_for_csv_leaves_normal_strings_unchanged():
    assert sanitize_for_csv("normal strategy name") == "normal strategy name"


def test_sanitize_for_csv_passes_through_non_strings():
    assert sanitize_for_csv(42) == 42
    assert sanitize_for_csv(3.14) == 3.14
    assert sanitize_for_csv(None) is None


# --- parse_is_long (existing behavior, sanity-checked here too) ------------


def test_parse_is_long_rejects_unknown_value():
    with pytest.raises(ValueError):
        parse_is_long("sideways")
