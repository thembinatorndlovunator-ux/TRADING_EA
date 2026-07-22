from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.join_trade_journal import main, run
from tests.conftest import make_current_ea_record, make_valid_record

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
    result = run(input_dir=tmp_path, repo_path=REPO_ROOT)
    assert result.read_result.valid_records == []
    assert result.metadata.dataset_hash == ""
    assert result.metadata.dataset_paths == ()


def test_spread_and_slippage_note_persisted_even_with_no_journal_files(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    spread_note/slippage_note exist on ReportMetadata but no analysis
    caller exposed or populated them -- checked here specifically against
    the empty-directory branch, which manually constructs ReportMetadata
    rather than going through build_report_metadata."""

    result = run(
        input_dir=tmp_path,
        repo_path=REPO_ROOT,
        spread_note="2-pip fixed spread assumed",
        slippage_note="no slippage modelled",
    )
    assert result.metadata.spread_note == "2-pip fixed spread assumed"
    assert result.metadata.slippage_note == "no slippage modelled"


def test_race_between_hash_and_parse_is_detected(tmp_path, monkeypatch):
    """Regression for a Codex review finding (2026-07-22, third round):
    hashing before parsing narrows, but does not eliminate, the race a
    concurrent writer creates -- a probe changed a journal file AFTER
    metadata hashing but BEFORE parsing, and the result analyzed the NEW
    record while retaining the OLD hash. Simulated here by mutating the
    journal file inside a monkeypatched read_journal_directory, i.e.
    exactly the window between this module's hash call and its parse
    call."""

    import analysis.join_trade_journal as jtj_module
    from data_collection.journal_reader import read_journal_directory as real_read

    journal_path = tmp_path / "decisions_20260721.jsonl"
    _write_journal_file(tmp_path, "decisions_20260721.jsonl", [make_valid_record(signal_id="a")])

    def mutating_read(directory, *args, **kwargs):
        # Simulate a concurrent writer appending AFTER this module already
        # hashed the file but BEFORE it parses -- mutate then delegate.
        with journal_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(make_valid_record(signal_id="b")) + "\n")
        return real_read(directory, *args, **kwargs)

    monkeypatch.setattr(jtj_module, "read_journal_directory", mutating_read)

    with pytest.raises(RuntimeError):
        jtj_module.run(input_dir=tmp_path, repo_path=REPO_ROOT)


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
        [make_valid_record(signal_id="ok-1"), make_current_ea_record()],
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
    the hash-race check (RuntimeError) and JournalReaderLimitError (a
    RuntimeError subclass) were previously uncaught by this CLI's own
    except clause -- an expected input-integrity failure surfaced as an
    unhandled traceback instead of a controlled ERROR exit."""

    import analysis.join_trade_journal as jtj_module
    from data_collection.journal_reader import read_journal_directory as real_read

    journal_path = tmp_path / "decisions_20260721.jsonl"
    _write_journal_file(tmp_path, "decisions_20260721.jsonl", [make_valid_record(signal_id="a")])

    def mutating_read(directory, *args, **kwargs):
        with journal_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(make_valid_record(signal_id="b")) + "\n")
        return real_read(directory, *args, **kwargs)

    monkeypatch.setattr(jtj_module, "read_journal_directory", mutating_read)

    exit_code = jtj_module.main(["--input-dir", str(tmp_path)])
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err
