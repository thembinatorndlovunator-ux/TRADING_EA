from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from analysis.csv_io import (
    CsvSchemaError,
    assert_high_low_geometry,
    assert_output_paths_distinct,
    assert_path_not_direct_child_of_directory,
    assert_path_not_same_file,
    assert_unique_ids,
    assert_valid_stop_geometry,
    atomic_write_dataframe_csv,
    parse_is_long,
    read_csv_with_required_columns,
    read_csv_with_required_columns_and_hash,
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


def test_quoted_multiline_duplicate_header_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    reading only the first PHYSICAL line missed a header row that itself
    spans multiple physical lines due to CSV quoting (a quoted field
    containing an embedded newline) -- a quoted multiline duplicate
    header previously bypassed the duplicate-header check entirely."""

    path = tmp_path / "trades.csv"
    # The header row's second field is a quoted string containing a
    # literal embedded newline -- csv.reader correctly parses this as
    # ONE logical header row spanning two physical lines; a naive
    # single-readline() approach would only see the truncated first
    # physical line and miss the duplicate "trade_id" entirely.
    path.write_text('trade_id,"pro\nfit",trade_id\nt1,10.0,t1\n', encoding="utf-8")
    with pytest.raises(CsvSchemaError):
        read_csv_with_required_columns(path, {"trade_id"})


def test_no_duplicate_header_reads_fine(tmp_path):
    path = tmp_path / "trades.csv"
    path.write_text("trade_id,profit\nt1,10.0\n", encoding="utf-8")
    df = read_csv_with_required_columns(path, {"trade_id", "profit"})
    assert len(df) == 1


# --- read_csv_with_required_columns_and_hash (ABA-safe dataset hash) --------


def test_read_csv_with_required_columns_and_hash_reflects_actual_bytes_parsed(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round): a
    hash computed via a SEPARATE, LATER file open (the "hash-then-parse"
    pattern most callers previously used) is a race DETECTOR, not proof
    the parsed content equals the reported hash. This function instead
    reads the file exactly ONCE and hashes/parses that same in-memory
    byte buffer -- proven here by confirming two distinct byte states of
    the same path produce two distinct hashes, each matching what that
    specific call actually parsed."""

    path = tmp_path / "trades.csv"
    path.write_text("trade_id,profit\nt1,10.0\n", encoding="utf-8")
    df_a, hash_a = read_csv_with_required_columns_and_hash(path, {"trade_id", "profit"})

    path.write_text("trade_id,profit\nt1,20.0\n", encoding="utf-8")
    df_b, hash_b = read_csv_with_required_columns_and_hash(path, {"trade_id", "profit"})

    assert hash_a != hash_b
    assert df_a.iloc[0]["profit"] == 10.0
    assert df_b.iloc[0]["profit"] == 20.0
    assert len(hash_a) == 64  # a real hex SHA-256 digest


def test_read_csv_with_required_columns_and_hash_still_validates_schema(tmp_path):
    path = tmp_path / "trades.csv"
    path.write_text("trade_id,profit,trade_id\nt1,10.0,t1\n", encoding="utf-8")
    with pytest.raises(CsvSchemaError):
        read_csv_with_required_columns_and_hash(path, {"trade_id", "profit"})


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
        assert_high_low_geometry(
            df, "high", "low", Path("bars.csv"), open_column="open", close_column="close"
        )


def test_assert_high_low_geometry_rejects_close_outside_range():
    df = pd.DataFrame({"open": [100.0], "high": [105.0], "low": [95.0], "close": [90.0]})
    with pytest.raises(CsvSchemaError):
        assert_high_low_geometry(
            df, "high", "low", Path("bars.csv"), open_column="open", close_column="close"
        )


def test_assert_high_low_geometry_passes_for_valid_bar():
    df = pd.DataFrame({"open": [100.0], "high": [105.0], "low": [95.0], "close": [102.0]})
    assert_high_low_geometry(
        df, "high", "low", Path("bars.csv"), open_column="open", close_column="close"
    )


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


def test_assert_output_paths_distinct_catches_hard_link():
    """Regression for a Codex review finding (2026-07-22, third round):
    path guards previously compared only Path.resolve(), which a hard
    link to an existing input trivially bypasses (different resolved
    name, identical underlying file) -- a direct probe used a hard-linked
    output path to overwrite an input's own inode."""

    import os
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        original = tmp_dir / "trades.csv"
        original.write_text("trade_id,profit\nt1,10.0\n", encoding="utf-8")
        hard_link = tmp_dir / "output.csv"
        os.link(original, hard_link)  # same inode, different path

        with pytest.raises(CsvSchemaError):
            assert_output_paths_distinct([original, hard_link])


def test_assert_path_not_same_file_catches_hard_link():
    import os
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        original = tmp_dir / "trades.csv"
        original.write_text("trade_id,profit\nt1,10.0\n", encoding="utf-8")
        hard_link = tmp_dir / "output.csv"
        os.link(original, hard_link)

        with pytest.raises(CsvSchemaError):
            assert_path_not_same_file(hard_link, original)


def test_assert_path_not_same_file_passes_for_distinct_files(tmp_path):
    a = tmp_path / "a.csv"
    a.write_text("x\n", encoding="utf-8")
    b = tmp_path / "b.csv"
    b.write_text("x\n", encoding="utf-8")
    assert_path_not_same_file(b, a)  # must not raise -- distinct files, even if same content


def test_assert_path_not_direct_child_of_directory_rejects_directory_itself(tmp_path):
    with pytest.raises(CsvSchemaError):
        assert_path_not_direct_child_of_directory(tmp_path, tmp_path)


def test_assert_path_not_direct_child_of_directory_rejects_direct_child(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    join_trade_journal.py/join_news_events.py previously hand-rolled this
    check with plain resolved-string equality instead of this shared
    helper."""

    with pytest.raises(CsvSchemaError):
        assert_path_not_direct_child_of_directory(tmp_path / "derived.csv", tmp_path)


def test_assert_path_not_direct_child_of_directory_allows_nested_subdirectory():
    """Deliberately does NOT reject a deeper subdirectory (e.g.
    'directory/out/result.csv') -- this project's own established pattern
    for colocating outputs near their input directory in their own
    subfolder, which a non-recursive glob never descends into anyway."""

    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        # Must not raise -- 'out' is a subdirectory, not a direct child file.
        assert_path_not_direct_child_of_directory(tmp_dir / "out" / "result.csv", tmp_dir)


def test_assert_path_not_direct_child_of_directory_allows_sibling_directory(tmp_path):
    sibling = tmp_path.parent / "sibling_dir" / "result.csv"
    assert_path_not_direct_child_of_directory(sibling, tmp_path)  # must not raise


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


def test_atomic_write_dataframe_csv_writes_correct_content(tmp_path):
    df = pd.DataFrame({"trade_id": ["t1", "t2"], "profit": [10.0, -5.0]})
    out_path = tmp_path / "out" / "trades.csv"
    atomic_write_dataframe_csv(df, out_path)

    assert out_path.exists()
    read_back = pd.read_csv(out_path)
    pd.testing.assert_frame_equal(read_back, df)


def test_atomic_write_dataframe_csv_leaves_no_temp_file_on_success(tmp_path):
    df = pd.DataFrame({"trade_id": ["t1"], "profit": [10.0]})
    out_path = tmp_path / "trades.csv"
    atomic_write_dataframe_csv(df, out_path)

    remaining = list(tmp_path.iterdir())
    assert remaining == [out_path]


def test_atomic_write_dataframe_csv_round_trips_non_ascii_text(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    the temp file was opened with no explicit encoding, so it defaulted
    to the active locale's code page (cp1252 on the tested Windows
    environment) -- writing "Café" produced byte 0xE9 instead of UTF-8's
    two-byte sequence, and reopening the result as UTF-8 raised
    UnicodeDecodeError. This writer must always use UTF-8 regardless of
    the runtime locale."""

    df = pd.DataFrame({"trade_id": ["t1"], "strategy": ["Café"]})
    out_path = tmp_path / "trades.csv"
    atomic_write_dataframe_csv(df, out_path)

    raw = out_path.read_text(encoding="utf-8")
    assert "Café" in raw
    read_back = pd.read_csv(out_path)
    assert read_back.iloc[0]["strategy"] == "Café"


def test_parse_is_long_rejects_unknown_value():
    with pytest.raises(ValueError):
        parse_is_long("sideways")
