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
    # **Fixed, 2026-07-22 Codex review finding (fifth round): the
    # empty-directory case previously reported dataset_hash="" elsewhere
    # in this project (see join_trade_journal.py's own fix) -- here,
    # 'dataset_hash' is always a genuine SHA-256 digest (of zero files'
    # worth of bytes when none are read), never an empty string.**
    assert result.dataset_hash != ""
    assert len(result.dataset_hash) == 64


def test_dataset_hash_is_aba_safe_reflects_actual_content_read(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    a hash computed via a SEPARATE, LATER file open (the "hash-then-
    parse" pattern every prior caller used) is a race DETECTOR, not proof
    the parsed content equals the reported hash -- a deterministic
    ABA-mutation probe changed the file, had this reader parse the
    changed bytes, then restored the original bytes before a caller's own
    post-parse rehash, which matched the ORIGINAL hash despite the
    changed content being what was actually parsed.
    JournalReadResult.dataset_hash is instead accumulated INLINE, one
    line at a time, from the very same single-pass read that produces
    valid_records -- there is no second read, so there is no window for
    this exact race. Proven here: two distinct byte states of the same
    path must produce two distinct hashes, each reflecting that specific
    read's own valid_records."""

    path = tmp_path / "decisions_20260721.jsonl"
    path.write_text(json.dumps(make_valid_record(signal_id="a")) + "\n", encoding="utf-8")
    result_a = read_journal_directory(tmp_path)

    path.write_text(json.dumps(make_valid_record(signal_id="a-mutated")) + "\n", encoding="utf-8")
    result_b = read_journal_directory(tmp_path)

    assert result_a.dataset_hash != result_b.dataset_hash
    assert result_a.valid_records[0].signal_id == "a"
    assert result_b.valid_records[0].signal_id == "a-mutated"


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


def test_deeply_nested_json_row_is_a_parse_error_not_an_aborted_directory(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    a deeply-nested-but-sub-megabyte JSON row exhausts Python's own call
    stack inside json.loads, raising RecursionError -- NOT a ValueError,
    so it previously propagated straight out of read_journal_directory,
    aborting the read of the ENTIRE directory (including every other,
    perfectly valid file) instead of becoming a single row error."""

    # A deeply nested array is well under any byte-size limit but still
    # exhausts the interpreter's recursion limit while json.loads walks it.
    deeply_nested = "[" * 100_000 + "]" * 100_000
    good_record = make_valid_record(signal_id="after-deep-nesting")
    (tmp_path / "decisions_20260721.jsonl").write_text(
        deeply_nested + "\n" + json.dumps(good_record) + "\n", encoding="utf-8"
    )

    result = read_journal_directory(tmp_path)
    assert len(result.valid_records) == 1
    assert result.valid_records[0].signal_id == "after-deep-nesting"
    assert len(result.parse_errors) == 1


def test_multi_byte_utf8_line_over_byte_limit_but_under_char_limit_rejected(tmp_path, monkeypatch):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    MAX_LINE_BYTES previously bounded CHARACTERS (via
    TextIOWrapper.readline's own size semantics), not real bytes -- a
    line under the character limit can still exceed it in actual UTF-8
    bytes if it contains multi-byte characters. A genuine byte-length
    check must catch this even when the character-based read alone would
    not have flagged it as oversized."""

    import data_collection.journal_reader as journal_reader_module

    monkeypatch.setattr(journal_reader_module, "MAX_LINE_BYTES", 100)
    # Each "é" is 1 character but 2 UTF-8 bytes -- 80 of them is 80
    # characters (under the 100-character readline bound) but 160 bytes
    # (over the 100-byte limit). ensure_ascii=False is required so the
    # literal multi-byte character reaches the file, not an escaped
    # "é" ASCII sequence.
    multi_byte_line = json.dumps({"note": "é" * 80}, ensure_ascii=False)
    assert len(multi_byte_line) <= 100  # under the character-based readline bound
    assert len(multi_byte_line.encode("utf-8")) > 100  # over the real byte limit
    (tmp_path / "decisions_20260721.jsonl").write_text(multi_byte_line + "\n", encoding="utf-8")

    result = read_journal_directory(tmp_path)
    assert len(result.valid_records) == 0
    assert len(result.parse_errors) == 1
    assert "exceeds max line length" in result.parse_errors[0].error


def test_byte_distinct_line_endings_and_bom_produce_different_hashes(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round):
    the file was previously opened in TEXT mode ("utf-8-sig"), which
    performs universal newline translation (CRLF/CR silently rewritten to
    LF) and strips a leading BOM BEFORE the per-line hash was computed by
    re-encoding that already-translated/stripped text. Byte-distinct
    LF-only, CRLF, and BOM+LF variants of otherwise identical content
    previously all produced the SAME digest -- the documented claim that
    this hash represents "the exact parsed bytes" was false. Each of the
    three byte-distinct variants below must now hash differently."""

    record_json = json.dumps(make_valid_record(signal_id="s1"))

    lf_dir = tmp_path / "lf"
    lf_dir.mkdir()
    (lf_dir / "decisions_20260721.jsonl").write_bytes((record_json + "\n").encode("utf-8"))

    crlf_dir = tmp_path / "crlf"
    crlf_dir.mkdir()
    (crlf_dir / "decisions_20260721.jsonl").write_bytes((record_json + "\r\n").encode("utf-8"))

    bom_lf_dir = tmp_path / "bom_lf"
    bom_lf_dir.mkdir()
    (bom_lf_dir / "decisions_20260721.jsonl").write_bytes(
        b"\xef\xbb\xbf" + (record_json + "\n").encode("utf-8")
    )

    lf_result = read_journal_directory(lf_dir)
    crlf_result = read_journal_directory(crlf_dir)
    bom_lf_result = read_journal_directory(bom_lf_dir)

    # All three parse to the identical valid record (proving the BOM/CRLF
    # tolerance for PARSING is preserved), but each must hash differently
    # since their real on-disk bytes genuinely differ.
    assert len(lf_result.valid_records) == 1
    assert len(crlf_result.valid_records) == 1
    assert len(bom_lf_result.valid_records) == 1
    hashes = {lf_result.dataset_hash, crlf_result.dataset_hash, bom_lf_result.dataset_hash}
    assert len(hashes) == 3


def test_distinct_invalid_byte_streams_produce_different_hashes(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round): a
    decode failure previously raised INSIDE the text-mode readline() call
    itself, before any bytes for that call reached the hasher -- two
    byte-distinct invalid UTF-8 streams could therefore collapse to the
    same digest. Raw bytes are now hashed BEFORE decoding is attempted, so
    two different invalid streams must hash differently even though both
    fail to decode."""

    dir_a = tmp_path / "a"
    dir_a.mkdir()
    (dir_a / "decisions_20260721.jsonl").write_bytes(b"\xff\xfe garbage one")

    dir_b = tmp_path / "b"
    dir_b.mkdir()
    (dir_b / "decisions_20260721.jsonl").write_bytes(b"\xff\xfe garbage two, longer")

    result_a = read_journal_directory(dir_a)
    result_b = read_journal_directory(dir_b)

    assert result_a.valid_records == []
    assert result_b.valid_records == []
    assert len(result_a.parse_errors) == 1
    assert len(result_b.parse_errors) == 1
    assert "decode failure" in result_a.parse_errors[0].error
    assert result_a.dataset_hash != result_b.dataset_hash


def test_max_total_source_bytes_limit_raises_even_for_all_blank_lines(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round): a
    flood of whitespace-only lines previously bypassed both the
    record-count budget AND any byte-based budget entirely, since each is
    discarded (as blank) before either check ran. The byte-budget check
    must fire on every line read, blank or not."""

    from data_collection.journal_reader import JournalReaderLimitError

    blank_lines = "   \n" * 100
    (tmp_path / "decisions_20260721.jsonl").write_text(blank_lines, encoding="utf-8")

    with pytest.raises(JournalReaderLimitError):
        read_journal_directory(tmp_path, max_total_source_bytes=50)


def test_max_files_limit_raises(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round): no
    cap previously existed on the number of candidate files a directory
    read would process."""

    from data_collection.journal_reader import JournalReaderLimitError

    for i in range(5):
        (tmp_path / f"decisions_2026072{i}.jsonl").write_text(
            json.dumps(make_valid_record(signal_id=f"s{i}")) + "\n", encoding="utf-8"
        )

    with pytest.raises(JournalReaderLimitError):
        read_journal_directory(tmp_path, max_files=3)


def test_max_retained_errors_limit_raises(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round): no
    cap previously existed on the number of retained parse/validation
    error records -- up to DEFAULT_MAX_RECORDS_PER_DIRECTORY (1,000,000)
    retained 2000-char error payloads can approach gigabytes."""

    from data_collection.journal_reader import JournalReaderLimitError

    bad_lines = "\n".join(["{not valid json"] * 50)
    (tmp_path / "decisions_20260721.jsonl").write_text(bad_lines + "\n", encoding="utf-8")

    with pytest.raises(JournalReaderLimitError):
        read_journal_directory(tmp_path, max_retained_errors=10)


def test_glob_traversal_outside_directory_is_reported_not_silently_skipped(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round): a
    candidate path resolving outside 'directory' was previously silently
    skipped with a bare 'continue' -- indistinguishable from "this file
    simply does not exist". It must now be reported as a ParseError."""

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
    assert len(result.parse_errors) == 1
    assert "excluded" in result.parse_errors[0].error
    assert "outside" in result.parse_errors[0].error


def test_directory_matching_pattern_is_reported_not_a_crash(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round): a
    subdirectory whose NAME happens to match 'pattern' previously reached
    _read_lines_from_file's own path.open() call directly, raising an
    unhandled PermissionError (Windows) / IsADirectoryError (POSIX) that
    aborted the entire directory read."""

    (tmp_path / "decisions_20260721.jsonl").mkdir()
    good_file = tmp_path / "decisions_20260722.jsonl"
    good_file.write_text(json.dumps(make_valid_record(signal_id="s1")) + "\n", encoding="utf-8")

    result = read_journal_directory(tmp_path)
    assert len(result.valid_records) == 1
    assert result.valid_records[0].signal_id == "s1"
    assert any("not a regular file" in e.error for e in result.parse_errors)
