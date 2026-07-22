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
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
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
        tmp_path,
        news_path,
        output_csv=out_csv,
        summary_json=summary_json,
        currency="USD",
        seed=1,
        repo_path=REPO_ROOT,
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
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )
    exit_code = main(["--journal-dir", str(tmp_path), "--news-events-csv", str(news_path)])
    assert exit_code == 0
    assert "1 decisions" in capsys.readouterr().out


def test_cli_main_missing_journal_dir(tmp_path, capsys):
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
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
            {
                "event_id": "dup",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            },
            {
                "event_id": "dup",
                "event_name": "NFP revision",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            },
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path)


def test_non_finite_importance_rejected(tmp_path):
    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": float("nan"),
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path)


def test_duplicate_journal_decisions_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    this script never ran the journal duplicate detectors -- two
    identical valid decisions were counted TWICE, silently biasing the
    blackout count."""

    dup_record = make_valid_record(signal_id="dup-1")
    _write_journal(tmp_path, [dup_record, dup_record])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path)


def test_importance_beyond_mt5_range_is_valid_provider_neutral_ordinal(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    NewsManager.mqh's own SNewsEvent docstring states 'importance' is a
    PROVIDER-NEUTRAL ordinal ("whatever scale the provider uses"), not
    hard-limited to MT5's own [0, 3] ENUM_CALENDAR_EVENT_IMPORTANCE range
    -- a value of 5 (e.g. from a differently-scaled provider such as the
    FairEconomy feed) must be accepted, not rejected as "out of range"."""

    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 5,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )
    result = run(tmp_path, news_path, min_importance=0)
    assert result.n_news_events_considered == 1


def test_negative_importance_rejected(tmp_path):
    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": -1,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path)


def test_non_integer_importance_rejected(tmp_path):
    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 1.5,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path)


def test_boolean_importance_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    Python booleans (a subtype of int) were previously admitted silently
    as 0/1 instead of rejected as the wrong type entirely."""

    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": True,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path)


def test_invalid_journal_records_surfaced_not_silently_dropped(tmp_path):
    """Regression for a Codex review finding (2026-07-22): this script
    previously read ONLY valid_records, silently excluding every parse/
    schema failure from the joined output -- reachable in practice since
    a real current-EA journal record fails schema validation on
    market_family/intraday_mode (both always empty). A wholly-invalid
    real journal directory must not silently produce a successful empty
    analysis."""

    bad_record = make_valid_record()
    bad_record["market_family"] = ""  # matches the live EA's actual current output
    _write_journal(tmp_path, [bad_record])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )

    errors_json = tmp_path / "out" / "errors.json"
    result = run(tmp_path, news_path, errors_json=errors_json)

    assert result.n_decisions == 0  # the invalid record is correctly excluded from the JOIN
    assert result.n_validation_errors == 1  # but it is NOT silently invisible
    assert errors_json.exists()
    payload = json.loads(errors_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_validation_errors"] == 1
    assert len(payload["validation_errors"]) == 1


def test_cli_reports_nonzero_exit_when_errors_present(tmp_path, capsys):
    bad_record = make_valid_record()
    bad_record["market_family"] = ""
    _write_journal(tmp_path, [bad_record])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )
    exit_code = main(["--journal-dir", str(tmp_path), "--news-events-csv", str(news_path)])
    assert exit_code == 1


def test_errors_auto_persisted_even_without_explicit_errors_json(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    row-level invalid-journal details were previously persisted ONLY if
    the caller happened to request errors_json explicitly."""

    bad_record = make_valid_record()
    bad_record["market_family"] = ""
    _write_journal(tmp_path, [bad_record])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )
    out_dir = tmp_path / "out"
    output_csv = out_dir / "joined.csv"
    run(tmp_path, news_path, output_csv=output_csv)

    errors_path = out_dir / "joined.errors.json"
    assert errors_path.exists()
    payload = json.loads(errors_path.read_text(encoding="utf-8"))
    assert payload["summary"]["n_validation_errors"] == 1


def test_output_inside_journal_dir_rejected(tmp_path):
    """Regression for a Codex review finding: an output written INSIDE
    journal_dir could later be picked up by a SUBSEQUENT run's own
    "decisions_*.jsonl" glob as if it were a real journal input."""

    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path, output_csv=tmp_path / "joined.csv")


def test_naive_news_timestamp_rejected(tmp_path):
    """Regression for a Codex review finding: pd.to_datetime(utc=True)
    silently accepted a naive news-event timestamp as UTC."""

    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00",
            }
        ],  # no "Z"
    )
    with pytest.raises(TimezoneValidationError):
        run(tmp_path, news_path)


def test_negative_before_minutes_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    a negative before_minutes flips window_start FORWARD in time
    (scheduled_utc - timedelta(minutes=negative) adds time), silently
    inverting or emptying the blackout window instead of raising."""

    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_valid_news(news_path)
    with pytest.raises(ValueError):
        run(tmp_path, news_path, before_minutes=-5)


def test_negative_after_minutes_rejected(tmp_path):
    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_valid_news(news_path)
    with pytest.raises(ValueError):
        run(tmp_path, news_path, after_minutes=-5)


def test_negative_min_importance_filter_rejected(tmp_path):
    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_valid_news(news_path)
    with pytest.raises(ValueError):
        run(tmp_path, news_path, min_importance=-1)


def test_nan_min_importance_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    min_importance=NaN previously passed the bare '< MIN_IMPORTANCE_VALUE'
    check outright, since every comparison against NaN is False in
    Python."""

    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_valid_news(news_path)
    with pytest.raises(ValueError):
        run(tmp_path, news_path, min_importance=float("nan"))


def test_fractional_min_importance_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    a fractional min_importance (e.g. 1.5) previously passed silently --
    the news CSV's own 'importance' column is enforced as a non-negative
    INTEGER ordinal, so a fractional threshold can never match anything
    meaningfully."""

    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_valid_news(news_path)
    with pytest.raises(ValueError):
        run(tmp_path, news_path, min_importance=1.5)


def test_boolean_min_importance_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    a Python bool (a subtype of int) previously passed silently as
    min_importance, comparing as 1/0."""

    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_valid_news(news_path)
    with pytest.raises(ValueError):
        run(tmp_path, news_path, min_importance=True)


def test_leading_zero_event_id_preserved_not_collapsed_by_numeric_inference(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    'event_id' was previously read with generic pandas numeric inference
    -- NewsManager.mqh's SNewsEvent defines it as a durable STRING, but
    "001" was silently re-emitted as "1", and "001"/"1" then collapsed
    into a false duplicate under float64 inference."""

    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    pd.DataFrame(
        [
            {
                "event_id": "001",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 3,
                "scheduled_utc": "2026-07-21T14:00:00Z",
            },
            {
                "event_id": "1",
                "event_name": "CPI",
                "currency": "USD",
                "importance": 3,
                "scheduled_utc": "2026-07-22T14:00:00Z",
            },
        ]
    ).to_csv(news_path, index=False)
    # "001" and "1" are DISTINCT string identifiers -- must not be
    # rejected as a duplicate event_id.
    result = run(tmp_path, news_path)
    assert result.n_decisions == 1


def test_output_path_colliding_with_input_rejected(tmp_path):
    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path, output_csv=news_path)


def _write_valid_news(news_path: Path) -> None:
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )


def test_derived_errors_path_does_not_overwrite_requested_summary_json(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    the derived errors_json path was computed AFTER the collision check
    already ran -- output_csv=joined.csv, summary_json=joined.errors.json,
    errors_json=None derived a sidecar path that collided with (and
    silently overwrote) the explicitly requested summary_json. Must now
    be rejected as a path collision."""

    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_valid_news(news_path)
    out_dir = tmp_path / "out"
    with pytest.raises(CsvSchemaError):
        run(
            tmp_path,
            news_path,
            output_csv=out_dir / "joined.csv",
            summary_json=out_dir / "joined.errors.json",
        )


def test_news_input_named_like_derived_errors_path_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    the exact reproduced counterexample -- with the news input itself
    named 'joined.errors.json' and output_csv='joined.csv', the derived
    error report previously replaced the source news evidence. Must now
    be rejected as an input/output collision instead."""

    _write_journal(tmp_path, [make_valid_record()])
    out_dir = tmp_path / "out"
    out_dir.mkdir()
    news_path = out_dir / "joined.errors.json"
    _write_valid_news(news_path)
    with pytest.raises(CsvSchemaError):
        run(tmp_path, news_path, output_csv=out_dir / "joined.csv")


def test_aba_mutation_of_news_csv_cannot_desync_hash_from_parsed_content(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    the previous "hash, then parse, then re-hash and compare" pattern
    (rounds 3-4) was a race DETECTOR, not proof the parsed content equals
    the reported hash. A deterministic ABA-mutation probe demonstrated
    this directly for news_events_csv: change the file, let this module
    parse the CHANGED bytes, then restore the ORIGINAL bytes before the
    post-parse rehash ran -- the rehash matched the ORIGINAL hash despite
    the changed content being what was actually analyzed. There is no
    longer a separate rehash to fool: read_csv_with_required_columns_and_hash
    computes its hash from the exact same single read that produces the
    parsed DataFrame -- there is only ever ONE read of the file, so an
    ABA sequence has no window to exploit. Proven here the same way as
    join_trade_journal's equivalent test: two distinct byte states of the
    SAME path must produce two distinct hashes, each matching what that
    call actually parsed."""

    _write_journal(tmp_path, [make_valid_record()])
    news_path = tmp_path / "news.csv"
    _write_valid_news(news_path)  # event_name="NFP" (see _write_valid_news)
    summary_json_a = tmp_path / "out_a" / "summary.json"
    run(tmp_path, news_path, summary_json=summary_json_a, repo_path=REPO_ROOT)
    hash_a = json.loads(summary_json_a.read_text(encoding="utf-8"))["metadata"]["dataset_hash"]

    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP -- MUTATED",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
    )
    summary_json_b = tmp_path / "out_b" / "summary.json"
    run(tmp_path, news_path, summary_json=summary_json_b, repo_path=REPO_ROOT)
    hash_b = json.loads(summary_json_b.read_text(encoding="utf-8"))["metadata"]["dataset_hash"]

    assert hash_a != hash_b


def test_new_journal_file_added_after_hash_is_not_silently_analyzed(tmp_path, monkeypatch):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    read_journal_directory used to re-glob journal_dir independently of
    the file list this module already hashed -- a probe added a SECOND
    decisions_*.jsonl file after the initial glob/hash; both files would
    have been analyzed under the stale hash. Simulated here by writing
    the second file at the exact moment read_journal_directory is
    invoked; since this module now passes its pre-hashed 'journal_files'
    list explicitly, the new file must NOT be picked up."""

    import analysis.join_news_events as jne_module
    from data_collection.journal_reader import read_journal_directory as real_read

    _write_journal(tmp_path, [make_valid_record(signal_id="a")])
    news_path = tmp_path / "news.csv"
    _write_valid_news(news_path)

    def read_that_races_a_new_file_in(directory, *args, **kwargs):
        second = directory / "decisions_20260722.jsonl"
        with second.open("w", encoding="utf-8") as fh:
            fh.write(json.dumps(make_valid_record(signal_id="b")) + "\n")
        return real_read(directory, *args, **kwargs)

    monkeypatch.setattr(jne_module, "read_journal_directory", read_that_races_a_new_file_in)

    result = jne_module.run(tmp_path, news_path)
    assert result.n_decisions == 1


def test_dataset_hash_includes_journal_files_not_just_news(tmp_path):
    """Regression for a Codex review finding: the reported dataset hash
    previously covered only news_events_csv, so a changed journal file
    would go undetected even though it directly affects the join result."""

    _write_journal(tmp_path, [make_valid_record(signal_id="a")])
    news_path = tmp_path / "news.csv"
    _write_news(
        news_path,
        [
            {
                "event_id": "e1",
                "event_name": "NFP",
                "currency": "USD",
                "importance": 2,
                "scheduled_utc": "2026-07-21T14:10:00Z",
            }
        ],
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
