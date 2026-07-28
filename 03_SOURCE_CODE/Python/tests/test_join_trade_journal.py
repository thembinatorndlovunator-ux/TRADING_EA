from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.join_trade_journal import main, run
from tests.conftest import make_schema_invalid_record, make_valid_record

REPO_ROOT = Path(__file__).resolve().parents[3]


def _write_journal_file(directory: Path, filename: str, records: list[dict]) -> None:
    path = directory / filename
    with path.open("w", encoding="utf-8") as fh:
        for record in records:
            fh.write(json.dumps(record) + "\n")


def test_run_missing_input_dir_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        run(input_dir=tmp_path / "nope", repo_path=REPO_ROOT)


def test_run_no_output_paths_still_returns_in_memory_result(tmp_path):
    _write_journal_file(tmp_path, "decisions_20260721.jsonl", [make_valid_record()])
    result = run(input_dir=tmp_path, repo_path=REPO_ROOT)
    assert len(result.read_result.valid_records) == 1
    assert result.metadata.dataset_hash != ""


def test_run_empty_directory_no_journal_files(tmp_path):
    """**Fixed, 2026-07-22 Codex review finding (fifth round): the
    empty-journal path previously wrote dataset_hash="" -- not a real
    SHA-256 identity -- via a special-cased manual ReportMetadata
    construction. read_journal_directory's own dataset_hash is always a
    genuine SHA-256 digest (here, the hash of zero files' worth of bytes,
    which is a well-defined, real digest, not an empty string), and
    build_report_metadata is now called unconditionally for both the
    empty and non-empty cases -- no more special branch.**"""

    result = run(input_dir=tmp_path, repo_path=REPO_ROOT)
    assert result.read_result.valid_records == []
    assert result.metadata.dataset_hash != ""
    assert len(result.metadata.dataset_hash) == 64  # a real hex SHA-256 digest
    assert result.metadata.dataset_paths == ()


def test_spread_and_slippage_note_persisted_even_with_no_journal_files(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    spread_note/slippage_note exist on ReportMetadata but no analysis
    caller exposed or populated them -- checked here specifically against
    the empty-directory case."""

    result = run(
        input_dir=tmp_path,
        repo_path=REPO_ROOT,
        spread_note="2-pip fixed spread assumed",
        slippage_note="no slippage modelled",
    )
    assert result.metadata.spread_note == "2-pip fixed spread assumed"
    assert result.metadata.slippage_note == "no slippage modelled"


def test_aba_mutation_cannot_desync_hash_from_parsed_content(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    the previous "hash, then parse, then re-hash and compare" pattern
    (rounds 3-4) was a race DETECTOR, not proof the parsed content equals
    the reported hash. A deterministic ABA-mutation probe demonstrated
    this directly: change the file, let this module parse the CHANGED
    bytes, then restore the ORIGINAL bytes before the post-parse rehash
    ran -- the rehash matched the ORIGINAL hash despite the changed
    content being what was actually analyzed and returned. There is no
    longer a separate rehash to fool: read_journal_directory accumulates
    its own dataset_hash INLINE, one line at a time, from the exact same
    single read pass that produces valid_records -- there is only ever
    ONE read of the file, so an ABA sequence has no window to exploit.
    Proven here by running an ABA sequence around the run() call itself
    (not inside a monkeypatched read) and confirming the reported hash
    still matches what the file contained AT THE MOMENT run() actually
    read it -- deterministically reproducible by running run() twice
    against the two distinct byte states and comparing hashes."""

    _write_journal_file(tmp_path, "decisions_20260721.jsonl", [make_valid_record(signal_id="a")])
    result_a = run(input_dir=tmp_path, repo_path=REPO_ROOT)

    _write_journal_file(
        tmp_path, "decisions_20260721.jsonl", [make_valid_record(signal_id="a-mutated")]
    )
    result_b = run(input_dir=tmp_path, repo_path=REPO_ROOT)

    # Two genuinely different byte contents MUST produce two different
    # hashes -- and each hash is computed from literally the same pass
    # that produced that run's own valid_records, so there is no
    # daylight between "what was hashed" and "what was analyzed" for
    # either call, regardless of what happened to the file in between.
    assert result_a.metadata.dataset_hash != result_b.metadata.dataset_hash
    assert result_a.read_result.valid_records[0].signal_id == "a"
    assert result_b.read_result.valid_records[0].signal_id == "a-mutated"


def test_output_csv_inside_input_dir_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22): output paths
    were previously checked only against input_dir ITSELF, not against
    the actual decisions_*.jsonl files inside it -- a direct probe used a
    journal source file as output_csv and overwrote the source evidence.
    Any output written inside input_dir must now be rejected outright,
    regardless of filename."""

    _write_journal_file(tmp_path, "decisions_20260721.jsonl", [make_valid_record()])
    with pytest.raises(ValueError):
        run(input_dir=tmp_path, output_csv=tmp_path / "derived.csv", repo_path=REPO_ROOT)


def test_output_csv_matching_actual_journal_file_rejected(tmp_path):
    """The exact reproduced counterexample: using a real journal source
    file's own path as an output path."""

    journal_file = tmp_path / "decisions_20260721.jsonl"
    _write_journal_file(tmp_path, "decisions_20260721.jsonl", [make_valid_record()])
    with pytest.raises(ValueError):
        run(input_dir=tmp_path, output_csv=journal_file, repo_path=REPO_ROOT)


def test_output_csv_sanitizes_formula_injection(tmp_path):
    """Regression for a Codex review finding: caller-controlled journal
    strings were written directly to CSV; a value like "=CMD(...)" could
    become a live spreadsheet formula when a reviewer opens the export."""

    record = make_valid_record()
    record["strategy"] = "=CMD('calc.exe')"
    _write_journal_file(tmp_path, "decisions_20260721.jsonl", [record])

    out_csv = tmp_path / "out" / "journal.csv"
    run(input_dir=tmp_path, output_csv=out_csv, repo_path=REPO_ROOT)

    raw = out_csv.read_text(encoding="utf-8")
    assert "'=CMD" in raw  # neutralized with a leading single-quote
    assert "\n=CMD" not in raw  # never appears as a live formula prefix


def test_derived_provenance_path_does_not_overwrite_requested_output_json(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    the derived provenance path was computed AFTER the collision check
    already ran -- output_csv=foo.csv, output_json=foo.provenance.json,
    errors_json=None derived a sidecar path that collided with (and
    silently overwrote) the explicitly requested output_json. This must
    now be rejected as a path collision, not silently accepted."""

    _write_journal_file(tmp_path, "decisions_20260721.jsonl", [make_valid_record()])
    out_dir = tmp_path / "out"
    with pytest.raises(ValueError):
        run(
            input_dir=tmp_path,
            output_csv=out_dir / "foo.csv",
            output_json=out_dir / "foo.provenance.json",
            repo_path=REPO_ROOT,
        )


def test_new_journal_file_added_after_hash_is_not_silently_analyzed(tmp_path, monkeypatch):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    read_journal_directory used to re-glob 'input_dir' independently of
    the file list this module already hashed -- a probe added a SECOND
    decisions_*.jsonl file after the initial glob/hash; both files were
    analyzed, but metadata/the post-parse re-hash both still only knew
    about the first file, so the mismatch went undetected. Simulated here
    by writing the second file at the exact moment read_journal_directory
    is invoked (the real concurrent-writer window) -- since this module
    now passes its own pre-hashed 'journal_files' list explicitly, the
    new file must NOT be picked up even though it exists on disk by the
    time parsing actually happens."""

    import analysis.join_trade_journal as jtj_module
    from data_collection.journal_reader import read_journal_directory as real_read

    _write_journal_file(tmp_path, "decisions_20260721.jsonl", [make_valid_record(signal_id="a")])

    def read_that_races_a_new_file_in(directory, *args, **kwargs):
        _write_journal_file(
            tmp_path, "decisions_20260722.jsonl", [make_valid_record(signal_id="b")]
        )
        return real_read(directory, *args, **kwargs)

    monkeypatch.setattr(jtj_module, "read_journal_directory", read_that_races_a_new_file_in)

    result = jtj_module.run(input_dir=tmp_path, repo_path=REPO_ROOT)
    assert len(result.read_result.valid_records) == 1
    assert result.metadata.dataset_paths == ("decisions_20260721.jsonl",)


def test_provenance_auto_written_even_without_explicit_errors_json(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    provenance was previously written ONLY into the optional errors_json
    report -- a caller who requested output_csv but never asked for
    errors_json got a data file with zero provenance record anywhere."""

    _write_journal_file(tmp_path, "decisions_20260721.jsonl", [make_valid_record()])
    out_dir = tmp_path / "out"
    output_csv = out_dir / "journal.csv"

    run(input_dir=tmp_path, output_csv=output_csv, repo_path=REPO_ROOT)

    provenance_path = out_dir / "journal.provenance.json"
    assert provenance_path.exists()
    payload = json.loads(provenance_path.read_text(encoding="utf-8"))
    assert payload["metadata"]["dataset_hash"] != ""


def test_run_writes_csv_json_and_errors(tmp_path):
    _write_journal_file(
        tmp_path,
        "decisions_20260721.jsonl",
        [make_valid_record(signal_id="ok-1"), make_schema_invalid_record()],
    )

    out_csv = tmp_path / "out" / "journal.csv"
    out_json = tmp_path / "out" / "journal.json"
    errors_json = tmp_path / "out" / "errors.json"

    result = run(
        input_dir=tmp_path,
        output_csv=out_csv,
        output_json=out_json,
        errors_json=errors_json,
        symbol="XAUUSD",
        broker="Deriv",
        seed=42,
        repo_path=REPO_ROOT,
    )

    assert len(result.read_result.valid_records) == 1
    assert len(result.read_result.validation_errors) == 1

    assert out_csv.exists()
    df = pd.read_csv(out_csv)
    assert len(df) == 1
    assert df.iloc[0]["signal_id"] == "ok-1"

    assert out_json.exists()
    payload = json.loads(out_json.read_text(encoding="utf-8"))
    assert len(payload) == 1

    assert errors_json.exists()
    error_report = json.loads(errors_json.read_text(encoding="utf-8"))
    assert error_report["summary"]["valid_records"] == 1
    assert error_report["summary"]["validation_errors"] == 1
    assert error_report["metadata"]["symbol"] == "XAUUSD"
    assert error_report["metadata"]["random_seed"] == 42
    assert len(error_report["validation_errors"]) == 1


def test_duplicate_rows_detected_and_reported(tmp_path):
    same_ts = "2026-07-21T14:05:30Z"
    _write_journal_file(
        tmp_path,
        "decisions_20260721.jsonl",
        [
            make_valid_record(signal_id="a", timestamp_utc=same_ts, symbol="XAUUSD"),
            make_valid_record(signal_id="b", timestamp_utc=same_ts, symbol="XAUUSD"),
        ],
    )
    result = run(input_dir=tmp_path, repo_path=REPO_ROOT)
    assert result.n_duplicate_timestamp_symbol_rows == 2
    assert result.n_duplicate_signal_id_rows == 0  # different signal_ids -- not a signal_id dup


def test_cli_main_exit_code_success(tmp_path, capsys):
    _write_journal_file(tmp_path, "decisions_20260721.jsonl", [make_valid_record()])
    exit_code = main(["--input-dir", str(tmp_path)])
    assert exit_code == 0
    captured = capsys.readouterr()
    assert "1 valid" in captured.out


def test_cli_main_exit_code_missing_dir(tmp_path, capsys):
    exit_code = main(["--input-dir", str(tmp_path / "nope")])
    assert exit_code == 1
    captured = capsys.readouterr()
    assert "ERROR" in captured.err


def test_cli_main_reports_controlled_error_not_traceback_on_runtime_error(
    tmp_path, capsys, monkeypatch
):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    JournalReaderLimitError (a RuntimeError subclass) was previously
    uncaught by this CLI's own except clause -- an expected input-
    integrity failure surfaced as an unhandled traceback instead of a
    controlled ERROR exit. **Updated, 2026-07-22 Codex review finding
    (fifth round): the OTHER RuntimeError source this test previously
    exercised (a hash-vs-parse race check) no longer exists -- that
    entire class of race was closed structurally (see
    test_aba_mutation_cannot_desync_hash_from_parsed_content), not
    merely better-detected, so there is no separate rehash left to
    trigger. JournalReaderLimitError remains a real, reachable
    RuntimeError subclass this CLI must still handle gracefully.**"""

    import analysis.join_trade_journal as jtj_module
    from data_collection.journal_reader import JournalReaderLimitError

    _write_journal_file(tmp_path, "decisions_20260721.jsonl", [make_valid_record(signal_id="a")])

    def raising_read(*args, **kwargs):
        raise JournalReaderLimitError("simulated: too many lines in directory")

    monkeypatch.setattr(jtj_module, "read_journal_directory", raising_read)

    exit_code = jtj_module.main(["--input-dir", str(tmp_path)])
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err
