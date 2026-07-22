from __future__ import annotations

import json

import pytest

from data_collection.journal_reader import (
    find_duplicate_signal_ids,
    find_duplicate_timestamp_symbol,
    read_journal_directory,
    to_dataframe,
)
from tests.conftest import make_current_ea_record, make_valid_record


def test_read_journal_directory_missing_dir_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        read_journal_directory(tmp_path / "does_not_exist")


def test_read_journal_directory_empty_dir_returns_empty_result(tmp_path):
    result = read_journal_directory(tmp_path)
    assert result.valid_records == []
    assert result.parse_errors == []
    assert result.validation_errors == []
    assert result.total_lines == 0


def test_read_journal_directory_mixed_valid_and_malformed(tmp_path):
    valid_a = make_valid_record(signal_id="a")
    valid_b = make_valid_record(signal_id="b", timestamp_utc="2026-07-21T15:00:00Z")
    bad_record = make_current_ea_record()  # schema-invalid (see conftest)

    path = tmp_path / "decisions_20260721.jsonl"
    with path.open("w", encoding="utf-8") as fh:
        fh.write(json.dumps(valid_a) + "\n")
        fh.write("{not valid json,,,\n")  # parse error
        fh.write(json.dumps(valid_b) + "\n")
        fh.write("[1, 2, 3]\n")  # valid JSON, but not an object -> parse error
        fh.write(json.dumps(bad_record) + "\n")  # validation error
        fh.write("\n")  # blank line -- must be silently skipped, not an error

    result = read_journal_directory(tmp_path)
    assert len(result.valid_records) == 2
    assert len(result.parse_errors) == 2
    assert len(result.validation_errors) == 1
    assert result.total_lines == 5  # blank line excluded from the count entirely


def test_oversized_validation_error_raw_record_is_capped(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    ValidationError.raw_record previously retained the FULL parsed dict
    verbatim with no size bound -- unlike ParseError.raw_line (already
    capped at 2000 chars). An unconstrained nested field (score_breakdown
    has no schema of its own) could make one validation-error record an
    unbounded in-memory payload."""

    bad_record = make_current_ea_record()  # schema-invalid (see conftest)
    # Large enough to exceed the 2000-char ValidationError.raw_record cap,
    # but well under MAX_LINE_BYTES so this exercises the raw_record cap
    # specifically, not the oversized-physical-line path.
    bad_record["score_breakdown"] = {f"component_{i}": float(i) for i in range(300)}

    path = tmp_path / "decisions_20260721.jsonl"
    path.write_text(json.dumps(bad_record) + "\n", encoding="utf-8")

    result = read_journal_directory(tmp_path)
    assert len(result.validation_errors) == 1
    raw_record = result.validation_errors[0].raw_record
    assert raw_record.get("_truncated") is True
    assert len(raw_record["preview"]) <= 2000


def test_read_journal_directory_processes_files_in_sorted_order(tmp_path):
    (tmp_path / "decisions_20260722.jsonl").write_text(
        json.dumps(make_valid_record(signal_id="second-day")) + "\n", encoding="utf-8"
    )
    (tmp_path / "decisions_20260721.jsonl").write_text(
        json.dumps(make_valid_record(signal_id="first-day")) + "\n", encoding="utf-8"
    )

    result = read_journal_directory(tmp_path)
    assert [r.signal_id for r in result.valid_records] == ["first-day", "second-day"]


def test_read_journal_directory_ignores_non_matching_files(tmp_path):
    (tmp_path / "decisions_20260721.jsonl").write_text(
        json.dumps(make_valid_record()) + "\n", encoding="utf-8"
    )
    (tmp_path / "unrelated_notes.txt").write_text("not a journal file", encoding="utf-8")

    result = read_journal_directory(tmp_path)
    assert len(result.valid_records) == 1


def test_to_dataframe_empty_has_correct_columns():
    df = to_dataframe([])
    assert df.empty
    assert "symbol" in df.columns
    assert "signal_id" in df.columns


def test_to_dataframe_nonempty():
    from analysis.schema import validate_record

    records = [validate_record(make_valid_record(signal_id="x"))]
    df = to_dataframe(records)
    assert len(df) == 1
    assert df.iloc[0]["symbol"] == "XAUUSD"


def test_find_duplicate_signal_ids_excludes_empty_signal_ids():
    from analysis.schema import validate_record

    records = [
        validate_record(make_valid_record(signal_id="")),
        validate_record(make_valid_record(signal_id="")),
    ]
    df = to_dataframe(records)
    duplicates = find_duplicate_signal_ids(df)
    assert duplicates.empty  # both have signal_id=="" -> excluded per design


def test_find_duplicate_signal_ids_flags_real_duplicates():
    from analysis.schema import validate_record

    records = [
        validate_record(make_valid_record(signal_id="dup-1")),
        validate_record(make_valid_record(signal_id="dup-1", timestamp_utc="2026-07-21T16:00:00Z")),
        validate_record(make_valid_record(signal_id="unique-1")),
    ]
    df = to_dataframe(records)
    duplicates = find_duplicate_signal_ids(df)
    assert len(duplicates) == 2
    assert set(duplicates["signal_id"]) == {"dup-1"}


def test_find_duplicate_timestamp_symbol():
    from analysis.schema import validate_record

    same_ts = "2026-07-21T14:05:30Z"
    records = [
        validate_record(make_valid_record(signal_id="a", timestamp_utc=same_ts, symbol="XAUUSD")),
        validate_record(make_valid_record(signal_id="b", timestamp_utc=same_ts, symbol="XAUUSD")),
        validate_record(make_valid_record(signal_id="c", timestamp_utc=same_ts, symbol="EURUSD")),
    ]
    df = to_dataframe(records)
    duplicates = find_duplicate_timestamp_symbol(df)
    assert len(duplicates) == 2  # only the two XAUUSD rows collide


def test_glob_traversal_outside_directory_is_ignored(tmp_path):
    """Regression for a Codex review finding: a caller-supplied glob
    pattern like "../*.jsonl" could previously escape the intended
    directory and read a parent file."""

    from data_collection.journal_reader import read_journal_directory

    parent_file = tmp_path / "outside.jsonl"
    parent_file.write_text(
        json.dumps(make_valid_record(signal_id="escaped")) + "\n", encoding="utf-8"
    )

    subdir = tmp_path / "journal"
    subdir.mkdir()
    (subdir / "decisions_20260721.jsonl").write_text(
        json.dumps(make_valid_record(signal_id="inside")) + "\n", encoding="utf-8"
    )

    result = read_journal_directory(subdir, pattern="../*.jsonl")
    assert result.valid_records == []  # the parent file must NOT be read


def test_nan_json_constant_is_a_parse_error_not_silently_accepted(tmp_path):
    """Regression for a Codex review finding: Python's json module
    silently accepts the non-standard NaN/Infinity tokens by default."""

    from data_collection.journal_reader import read_journal_directory

    record = make_valid_record()
    raw = json.dumps(record).replace('"risk_percent": 0.3', '"risk_percent": NaN')
    (tmp_path / "decisions_20260721.jsonl").write_text(raw + "\n", encoding="utf-8")

    result = read_journal_directory(tmp_path)
    assert result.valid_records == []
    assert len(result.parse_errors) == 1
    assert "NaN" in result.parse_errors[0].error


def test_utf8_bom_is_handled_transparently(tmp_path):
    """A leading UTF-8 BOM must not be mistaken for a malformed first
    line (a real, benign case some editors/exports produce)."""

    from data_collection.journal_reader import read_journal_directory

    path = tmp_path / "decisions_20260721.jsonl"
    with path.open("w", encoding="utf-8-sig") as fh:
        fh.write(json.dumps(make_valid_record()) + "\n")

    result = read_journal_directory(tmp_path)
    assert len(result.valid_records) == 1
    assert result.parse_errors == []


def test_numeric_overflow_to_infinity_is_a_parse_error(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round): a
    numeric literal that OVERFLOWS to infinity (e.g. 1e400) is a
    completely standard-looking JSON number token -- it never reaches
    parse_constant at all. Because nested score_breakdown is an
    unconstrained dict, a record containing {"overflow": 1e400}
    previously validated successfully and was written out as
    {'overflow': inf}."""

    from data_collection.journal_reader import read_journal_directory

    record = make_valid_record()
    record["score_breakdown"] = {"overflow": "PLACEHOLDER"}
    raw = json.dumps(record).replace('"PLACEHOLDER"', "1e400")
    (tmp_path / "decisions_20260721.jsonl").write_text(raw + "\n", encoding="utf-8")

    result = read_journal_directory(tmp_path)
    assert result.valid_records == []
    assert len(result.parse_errors) == 1
    assert (
        "overflow" in result.parse_errors[0].error.lower()
        or "1e400" in result.parse_errors[0].error
    )


def test_duplicate_json_key_is_a_parse_error(tmp_path):
    """Regression for a Codex review finding (2026-07-22): json.loads'
    default last-value-wins semantics for a duplicate object key meant a
    record containing two "score" keys parsed as one valid record with
    zero parse errors, silently dropping the first value."""

    from data_collection.journal_reader import read_journal_directory

    record = make_valid_record()
    raw = json.dumps(record)
    # Inject a literal duplicate "score" key into the raw JSON text.
    raw = raw.replace('"score":', '"score": 1.0, "score":', 1)
    (tmp_path / "decisions_20260721.jsonl").write_text(raw + "\n", encoding="utf-8")

    result = read_journal_directory(tmp_path)
    assert result.valid_records == []
    assert len(result.parse_errors) == 1
    assert "duplicate" in result.parse_errors[0].error.lower()


def test_max_records_limit_raises(tmp_path):
    """Regression for a Codex review finding: no cap existed on the
    number of lines a journal directory read would load into memory."""

    from data_collection.journal_reader import JournalReaderLimitError, read_journal_directory

    lines = [json.dumps(make_valid_record(signal_id=f"s{i}")) for i in range(5)]
    (tmp_path / "decisions_20260721.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")

    with pytest.raises(JournalReaderLimitError):
        read_journal_directory(tmp_path, max_records=3)


def test_oversized_single_line_is_a_parse_error_not_unbounded_memory(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    a single physical line with no newline was previously materialized
    in full (arbitrarily large) via plain line iteration BEFORE any
    length check -- the 2000-char cap only applied to what got RETAINED
    in the error record, not to what was read into memory to produce it.
    An oversized line must now be capped while reading, reported as one
    ParseError, and the file must continue reading subsequent lines
    correctly (proving the discarded remainder didn't desync line
    tracking)."""

    from data_collection.journal_reader import MAX_LINE_BYTES

    oversized_line = "x" * (MAX_LINE_BYTES + 500)  # no trailing newline until after this
    good_record = make_valid_record(signal_id="after-oversized")
    (tmp_path / "decisions_20260721.jsonl").write_text(
        oversized_line + "\n" + json.dumps(good_record) + "\n", encoding="utf-8"
    )

    result = read_journal_directory(tmp_path)
    assert len(result.valid_records) == 1
    assert result.valid_records[0].signal_id == "after-oversized"
    assert len(result.parse_errors) == 1
    assert "exceeds max line length" in result.parse_errors[0].error
    assert len(result.parse_errors[0].raw_line) <= 2000
