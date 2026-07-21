from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.csv_io import CsvSchemaError
from analysis.join_news_events import main, run
from analysis.time_utils import TimezoneValidationError
from tests.conftest import make_valid_record

REPO_ROOT = Path(__file__).resolve().parents[3]


def _write_journal(directory: Path, records: list[dict]) -> None:
    import json as _json

    path = directory / "decisions_20260721.jsonl"
    with path.open("w", encoding="utf-8") as fh:
        for record in records:
            fh.write(_json.dumps(record) + "\n")


def _write_news(path: Path, rows: list[dict]) -> None:
    pd.DataFrame(rows).to_csv(path, index=False)


def test_missing_news_column_raises(tmp_path):
    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    pd.DataFrame({"event_id": ["e1"]}).to_csv(news_path, index=False)

    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path)


def test_missing_journal_dir_raises(tmp_path):
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [{"event_id": "e1", "event_name": "NFP", "currency": "USD", "importance": 2,
          "scheduled_utc": "2026-07-21T14:10:00Z"}],
    )
    with pytest.raises(FileNotFoundError):
        run(tmp_path / "missing_journal", news_path)


def test_decision_inside_blackout_window_flagged(tmp_path):
    _write_journal(tmp_path, [make_valid_record(signal_id="a")])  # 2026-07-21T14:05:30Z
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e-nfp",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",  # 4m30s after the decision
            }
        ],
    )

    result = run(tmp_path, news_path, before_minutes=15, after_minutes=15, min_importance=2)
    assert result.n_decisions == 1
    assert result.n_in_blackout == 1
    assert result.joined.iloc[0]["in_news_blackout"] == True  # noqa: E712
    assert result.joined.iloc[0]["triggering_event_id"] == "e-nfp"


def test_decision_outside_blackout_window_not_flagged(tmp_path):
    _write_journal(tmp_path, [make_valid_record(signal_id="a")])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e-far",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-22T14:10:00Z",  # a day later -- far outside
            }
        ],
    )

    result = run(tmp_path, news_path, before_minutes=15, after_minutes=15, min_importance=2)
    assert result.n_in_blackout == 0
    assert result.joined.iloc[0]["triggering_event_id"] is None


def test_min_importance_filter_excludes_low_importance_events(tmp_path):
    _write_journal(tmp_path, [make_valid_record(signal_id="a")])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e-low",
                "event_name": "Minor release",
                "currency": "USD",
                "importance": 0,  # below min_importance=2
                "scheduled_utc": "2026-07-21T14:05:30Z",  # exact same instant
            }
        ],
    )

    result = run(tmp_path, news_path, min_importance=2)
    assert result.n_news_events_considered == 0
    assert result.n_in_blackout == 0


def test_currency_filter_excludes_other_currencies(tmp_path):
    _write_journal(tmp_path, [make_valid_record(signal_id="a")])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e-eur",
                "event_name": "ECB rate decision",
                "currency": "EUR",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:05:30Z",
            }
        ],
    )

    result_filtered = run(tmp_path, news_path, currency="USD", min_importance=2)
    assert result_filtered.n_news_events_considered == 0
    assert result_filtered.n_in_blackout == 0

    result_unfiltered = run(tmp_path, news_path, currency=None, min_importance=2)
    assert result_unfiltered.n_news_events_considered == 1
    assert result_unfiltered.n_in_blackout == 1


def test_writes_output_csv_and_summary_json(tmp_path):
    _write_journal(tmp_path, [make_valid_record(signal_id="a")])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e-nfp",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )

    out_csv = tmp_path / "out" / "joined.csv"
    summary_json = tmp_path / "out" / "summary.json"
    run(
        tmp_path, news_path, output_csv=out_csv, summary_json=summary_json,
        currency="USD", seed=1, repo_path=REPO_ROOT,
    )

    assert out_csv.exists()
    df = pd.read_csv(out_csv)
    assert len(df) == 1

    assert summary_json.exists()
    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_in_blackout"] == 1
    assert payload["summary"]["currency_filter"] == "USD"


def test_cli_main_success(tmp_path, capsys):
    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [{"event_id": "e1", "event_name": "NFP", "currency": "USD", "importance": 2,
          "scheduled_utc": "2026-07-21T14:10:00Z"}],
    )
    exit_code = main(["--journal-dir", str(tmp_path), "--news-events-csv", str(news_path)])
    assert exit_code == 0
    assert "1 decisions" in capsys.readouterr().out


def test_cli_main_missing_journal_dir(tmp_path, capsys):
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [{"event_id": "e1", "event_name": "NFP", "currency": "USD", "importance": 2,
          "scheduled_utc": "2026-07-21T14:10:00Z"}],
    )
    exit_code = main(
        ["--journal-dir", str(tmp_path / "missing"), "--news-events-csv", str(news_path)]
    )
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err


def test_duplicate_event_id_rejected(tmp_path):
    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {"event_id": "dup", "event_name": "NFP", "currency": "USD", "importance": 2,
             "scheduled_utc": "2026-07-21T14:10:00Z"},
            {"event_id": "dup", "event_name": "NFP revision", "currency": "USD", "importance": 2,
             "scheduled_utc": "2026-07-21T14:10:00Z"},
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path)


def test_non_finite_importance_rejected(tmp_path):
    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [{"event_id": "e1", "event_name": "NFP", "currency": "USD", "importance": float("nan"),
          "scheduled_utc": "2026-07-21T14:10:00Z"}],
    )
    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path)


def test_naive_news_timestamp_rejected(tmp_path):
    """Regression for a Codex review finding: pd.to_datetime(utc=True)
    silently accepted a naive news-event timestamp as UTC."""

    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [{"event_id": "e1", "event_name": "NFP", "currency": "USD", "importance": 2,
          "scheduled_utc": "2026-07-21T14:10:00"}],  # no "Z"
    )
    with pytest.raises(TimezoneValidationError):
        run(tmp_path, news_path)


def test_output_path_colliding_with_input_rejected(tmp_path):
    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [{"event_id": "e1", "event_name": "NFP", "currency": "USD", "importance": 2,
          "scheduled_utc": "2026-07-21T14:10:00Z"}],
    )
    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path, output_csv=news_path)


def test_dataset_hash_includes_journal_files_not_just_news(tmp_path):
    """Regression for a Codex review finding: the reported dataset hash
    previously covered only news_events_csv, so a changed journal file
    would go undetected even though it directly affects the join result."""

    _write_journal(tmp_path, [make_valid_record(signal_id="a")])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [{"event_id": "e1", "event_name": "NFP", "currency": "USD", "importance": 2,
          "scheduled_utc": "2026-07-21T14:10:00Z"}],
    )
    summary_json_a = tmp_path / "out_a" / "summary.json"
    run(tmp_path, news_path, summary_json=summary_json_a, currency="USD", repo_path=REPO_ROOT)
    hash_a = json.loads(summary_json_a.read_text(encoding="utf-8"))["metadata"]["dataset_hash"]

    # Change the JOURNAL only (not the news file) and confirm the hash changes.
    _write_journal(tmp_path, [make_valid_record(signal_id="b")])
    summary_json_b = tmp_path / "out_b" / "summary.json"
    run(tmp_path, news_path, summary_json=summary_json_b, currency="USD", repo_path=REPO_ROOT)
    hash_b = json.loads(summary_json_b.read_text(encoding="utf-8"))["metadata"]["dataset_hash"]

    assert hash_a != hash_b
