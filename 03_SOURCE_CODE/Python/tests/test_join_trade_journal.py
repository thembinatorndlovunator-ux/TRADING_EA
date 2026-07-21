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
