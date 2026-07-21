"""join_news_events.py -- joins ThembaEA journal decisions against a news-
events export, independently recomputing whether each decision fell inside
a NEWS_BLACKOUT window (per ``NewsManager.mqh``'s TASK-029 blackout-window
definition, section 10 of ``TASK-002_PHASE2_SPECIFICATION.md``).

**Why this is a genuinely useful independent check, not a duplicate of the
MQL5 side:** every real journal record's ``news_state`` field is currently
always empty (``ThembaAdaptiveIntradayEA.mq5`` never populates it -- see
``analysis/schema.py``'s docstring for the broader market_family/
intraday_mode gap this is part of). This script recomputes blackout status
from raw news events independently of whatever (currently nothing) the live
EA recorded, so it can quantify how many past decisions WOULD have fallen
inside a blackout window once ``news_state`` is actually wired up.

**Simplification, stated explicitly:** this compares each decision's
``timestamp_utc`` directly against each news event's ``scheduled_utc`` --
both already in UTC -- rather than converting through broker SERVER time
the way ``MT5CalendarProvider.mqh``'s live check does. That server-time
detour exists on the MQL5 side only because server time is what's readily
available intraday there; comparing UTC-to-UTC directly here is simpler
and avoids introducing an extra (and here, unnecessary) conversion step.
This ALSO does not implement the spread-normalization EXTENSION
(``NM_IsInBlackoutWindowExtended`` in ``NewsManager.mqh``) -- the journal
does not record spread/ATR at decision time, so only the base
before/after window is checked here.

Required news-events CSV columns: ``event_id, event_name, currency,
importance, scheduled_utc`` (a subset of ``SNewsEvent``'s full field list --
the fields this join actually needs).
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path
from typing import Optional

import pandas as pd

from analysis.csv_io import (
    CsvSchemaError,
    assert_finite_columns,
    assert_path_not_same_file,
    assert_unique_ids,
    atomic_write_dataframe_csv,
    read_csv_with_required_columns,
    sanitize_for_csv,
)
from analysis.report_metadata import (
    atomic_write_text,
    build_report_metadata,
    compute_dataset_hash,
    default_repo_root,
)
from analysis.time_utils import TimezoneValidationError, parse_utc_series
from data_collection.journal_reader import (
    find_duplicate_signal_ids,
    find_duplicate_timestamp_symbol,
    read_journal_directory,
    to_dataframe,
)

REQUIRED_NEWS_COLUMNS = {"event_id", "event_name", "currency", "importance", "scheduled_utc"}
# **Fixed, 2026-07-22 Codex review finding (third round): hard-limiting to
# {0,1,2,3} assumed an MT5-only source (MT5CalendarProvider.mqh casts
# ENUM_CALENDAR_EVENT_IMPORTANCE to that exact range), but NewsManager.mqh's
# own SNewsEvent docstring states 'importance' is a PROVIDER-NEUTRAL ordinal
# -- "whatever scale the provider uses" (e.g. the FairEconomy feed chosen
# for TASK-034 may use a different scale entirely). The genuine
# provider-neutral contract is simply: a non-negative INTEGER (not a bool,
# which Python's own type hierarchy makes a subtype of int and would
# otherwise be silently admitted as 0/1; not a float with a fractional
# part).**
MIN_IMPORTANCE_VALUE = 0


@dataclass(frozen=True)
class NewsJoinResult:
    joined: pd.DataFrame  # one row per decision, + in_blackout / triggering_event_id
    n_decisions: int
    n_news_events_considered: int
    n_in_blackout: int
    n_parse_errors: int
    n_validation_errors: int


def _find_triggering_event(
    decision_utc: pd.Timestamp, events: pd.DataFrame, before_minutes: int, after_minutes: int
) -> Optional[str]:
    for _, event in events.iterrows():
        window_start = event["scheduled_utc"] - timedelta(minutes=before_minutes)
        window_end = event["scheduled_utc"] + timedelta(minutes=after_minutes)
        if window_start <= decision_utc <= window_end:
            return str(event["event_id"])
    return None


def run(
    journal_dir: Path,
    news_events_csv: Path,
    output_csv: Optional[Path] = None,
    summary_json: Optional[Path] = None,
    errors_json: Optional[Path] = None,
    *,
    currency: Optional[str] = None,
    before_minutes: int = 15,
    after_minutes: int = 15,
    min_importance: int = 2,
    seed: Optional[int] = None,
    repo_path: Optional[Path] = None,
) -> NewsJoinResult:
    """Raises FileNotFoundError if 'journal_dir' does not exist (propagated
    from read_journal_directory) or CsvSchemaError if 'news_events_csv' is
    missing a required column.

    If 'currency' is None, EVERY news event is considered regardless of
    its own currency field -- a documented fallback, not a recommended
    default (a caller should supply the traded symbol's actual quote/base
    currency whenever it's known).

    **Fixed, 2026-07-22 Codex review finding:** this previously read ONLY
    'valid_records', silently excluding every parse/schema failure from
    the joined output with no row-level error artifact and a `main()`
    that returned 0 regardless -- reachable in practice today, since the
    live EA's `DJ_NewDecision` never sets `market_family`/`intraday_mode`
    and the strict schema rejects both empty, meaning a REAL current-EA
    journal directory previously produced a successful EMPTY CSV rather
    than a visibly failing analysis. If 'errors_json' is given, every
    parse/validation error is now written out row-by-row (matching
    join_trade_journal.py's already-fixed pattern), and the CLI's exit
    code reflects their presence.
    """

    resolved_journal_dir = journal_dir.resolve()
    for out_path in (output_csv, summary_json, errors_json):
        if out_path is None:
            continue
        if out_path.resolve() == resolved_journal_dir:
            raise CsvSchemaError(f"output path {out_path} must not be the same as journal_dir")
        # Uses OS-level file-identity (not just Path.resolve()) so a hard
        # link to news_events_csv is also caught -- Codex review finding, third round.
        assert_path_not_same_file(out_path, news_events_csv, "output path")
        # **Fixed, 2026-07-22 Codex review finding:** an output written
        # INSIDE journal_dir (even under a different name) could later be
        # picked up by a SUBSEQUENT run's "decisions_*.jsonl" glob as if
        # it were a real journal input, folding a derived output into its
        # own future dataset hash. Outputs must live outside journal_dir
        # entirely.
        if out_path.resolve().parent == resolved_journal_dir:
            raise CsvSchemaError(
                f"output path {out_path} must not be written inside journal_dir "
                f"({journal_dir}) -- it could be picked up as a journal input by a future run"
            )
    output_resolved = [
        p.resolve() for p in (output_csv, summary_json, errors_json) if p is not None
    ]
    if len(set(output_resolved)) != len(output_resolved):
        raise CsvSchemaError("output_csv, summary_json, and errors_json must all be distinct paths")

    # **Fixed, 2026-07-22 Codex review finding:** the dataset hash was
    # previously computed AFTER read_journal_directory had already parsed
    # every journal file -- hashing the journal files here, BEFORE
    # parsing, narrows the window in which a concurrent append or a torn
    # final line could make the reported hash describe different bytes
    # than the ones actually analyzed. The resulting metadata is reused
    # for both summary_json and errors_json below rather than recomputed
    # (which would re-read the files a second time anyway).
    journal_files = sorted(journal_dir.glob("decisions_*.jsonl"))
    dataset_paths = [news_events_csv, *journal_files] if journal_files else [news_events_csv]
    metadata = build_report_metadata(
        dataset_paths, currency=currency, random_seed=seed, repo_path=repo_path
    )

    read_result = read_journal_directory(journal_dir)

    # **Fixed, 2026-07-22 Codex review finding (third round): hashing
    # before parsing narrows, but does NOT eliminate, the race a
    # concurrent writer creates -- re-hashing after parsing and comparing
    # catches a change that occurred in between (a detection, not a full
    # transactional guarantee).**
    if journal_files:
        hash_root = repo_path if repo_path is not None else default_repo_root()
        post_parse_hash = compute_dataset_hash(dataset_paths, repo_root=hash_root)
        if post_parse_hash != metadata.dataset_hash:
            raise RuntimeError(
                f"{journal_dir}: input files changed between hashing and parsing -- "
                "the analyzed content and the reported dataset_hash would not match. "
                "Re-run against a stable snapshot."
            )

    decisions_df = to_dataframe(read_result.valid_records)

    # **Fixed, 2026-07-22 Codex review finding (third round): this script
    # never ran the journal duplicate detectors that join_trade_journal.py
    # already has -- two identical valid decisions were counted TWICE,
    # silently biasing the blackout count (the CLI returned 0 despite the
    # underlying duplication).**
    dup_signal_id = find_duplicate_signal_ids(decisions_df)
    dup_timestamp_symbol = find_duplicate_timestamp_symbol(decisions_df)
    if not dup_signal_id.empty or not dup_timestamp_symbol.empty:
        raise CsvSchemaError(
            f"{journal_dir}: duplicate journal decisions found "
            f"({len(dup_signal_id)} duplicate signal_id row(s), "
            f"{len(dup_timestamp_symbol)} duplicate (timestamp_utc, symbol) row(s)) -- "
            "would silently double-count decisions in the blackout analysis"
        )

    news = read_csv_with_required_columns(news_events_csv, REQUIRED_NEWS_COLUMNS)
    assert_unique_ids(news, "event_id", news_events_csv)
    assert_finite_columns(news, ["importance"], news_events_csv)
    # **Fixed, 2026-07-22 Codex review finding (third round): the
    # provider-neutral contract is a non-negative INTEGER, not a hard
    # {0,1,2,3} range (see the MIN_IMPORTANCE_VALUE comment above) --
    # AND Python bools (a subtype of int) were previously admitted
    # silently as 0/1 rather than rejected as the wrong type entirely.
    if pd.api.types.is_bool_dtype(news["importance"]):
        raise CsvSchemaError(
            f"{news_events_csv}: 'importance' must be an integer ordinal, not boolean"
        )
    importance_numeric = pd.to_numeric(news["importance"], errors="coerce")
    bad_importance = news[
        (importance_numeric < MIN_IMPORTANCE_VALUE)
        | (importance_numeric != importance_numeric.round())
    ]
    if not bad_importance.empty:
        raise CsvSchemaError(
            f"{news_events_csv}: {len(bad_importance)} row(s) have a non-integer or negative "
            f"'importance' value (must be a non-negative integer ordinal): rows {bad_importance.index.tolist()}"
        )
    news = news.copy()
    news["scheduled_utc"] = parse_utc_series(news["scheduled_utc"])
    news = news[news["importance"] >= min_importance]
    if currency is not None:
        news = news[news["currency"] == currency]

    in_blackout_flags = []
    triggering_ids = []
    for _, decision in decisions_df.iterrows():
        triggering_id = _find_triggering_event(
            decision["timestamp_utc"], news, before_minutes, after_minutes
        )
        triggering_ids.append(triggering_id)
        in_blackout_flags.append(triggering_id is not None)

    joined = decisions_df.copy()
    joined["in_news_blackout"] = in_blackout_flags
    joined["triggering_event_id"] = triggering_ids

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        # Sanitize caller-controlled journal strings against spreadsheet-
        # formula injection before export -- same fix as join_trade_journal.py.
        safe_joined = joined.copy()
        for col in safe_joined.select_dtypes(include=["object", "str"]).columns:
            safe_joined[col] = safe_joined[col].map(sanitize_for_csv)
        atomic_write_dataframe_csv(safe_joined, output_csv)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_decisions": len(decisions_df),
                "n_news_events_considered": len(news),
                "n_in_blackout": int(sum(in_blackout_flags)),
                "n_parse_errors": len(read_result.parse_errors),
                "n_validation_errors": len(read_result.validation_errors),
                "currency_filter": currency,
                "before_minutes": before_minutes,
                "after_minutes": after_minutes,
                "min_importance": min_importance,
            },
        }
        atomic_write_text(summary_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    # **Fixed, 2026-07-22 Codex review finding (third round): row-level
    # invalid-journal details were previously persisted ONLY if the
    # caller happened to request errors_json explicitly -- otherwise an
    # all-invalid run could write an empty output_csv, exit nonzero, and
    # retain no reviewable error artifact anywhere on disk. Auto-derive
    # a path whenever any other output is requested, matching
    # join_trade_journal.py's own fix for the identical gap.**
    if errors_json is None:
        base = output_csv if output_csv is not None else summary_json
        if base is not None:
            errors_json = base.parent / f"{base.stem}.errors.json"

    if errors_json is not None:
        errors_json.parent.mkdir(parents=True, exist_ok=True)
        error_payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_valid_decisions": len(decisions_df),
                "n_parse_errors": len(read_result.parse_errors),
                "n_validation_errors": len(read_result.validation_errors),
            },
            "parse_errors": [
                {
                    "source_file": e.source_file,
                    "line_number": e.line_number,
                    "raw_line": e.raw_line,
                    "error": e.error,
                }
                for e in read_result.parse_errors
            ],
            "validation_errors": [
                {
                    "source_file": e.source_file,
                    "line_number": e.line_number,
                    "raw_record": e.raw_record,
                    "error": e.error,
                }
                for e in read_result.validation_errors
            ],
        }
        atomic_write_text(
            errors_json, json.dumps(error_payload, indent=2, default=str, allow_nan=False)
        )

    return NewsJoinResult(
        joined=joined,
        n_decisions=len(decisions_df),
        n_news_events_considered=len(news),
        n_in_blackout=int(sum(in_blackout_flags)),
        n_parse_errors=len(read_result.parse_errors),
        n_validation_errors=len(read_result.validation_errors),
    )


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal-dir", required=True, type=Path)
    parser.add_argument("--news-events-csv", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--summary-json", type=Path, default=None)
    parser.add_argument("--errors-json", type=Path, default=None)
    parser.add_argument("--currency", default=None)
    parser.add_argument("--before-minutes", type=int, default=15)
    parser.add_argument("--after-minutes", type=int, default=15)
    parser.add_argument("--min-importance", type=int, default=2)
    parser.add_argument("--seed", type=int, default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        result = run(
            journal_dir=args.journal_dir,
            news_events_csv=args.news_events_csv,
            output_csv=args.output_csv,
            summary_json=args.summary_json,
            errors_json=args.errors_json,
            currency=args.currency,
            before_minutes=args.before_minutes,
            after_minutes=args.after_minutes,
            min_importance=args.min_importance,
            seed=args.seed,
        )
    except (FileNotFoundError, CsvSchemaError, TimezoneValidationError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"join_news_events: {result.n_decisions} decisions, "
        f"{result.n_news_events_considered} news events considered, "
        f"{result.n_in_blackout} in blackout, "
        f"{result.n_parse_errors} parse errors, {result.n_validation_errors} validation errors."
    )
    return 1 if (result.n_parse_errors or result.n_validation_errors) else 0


if __name__ == "__main__":
    sys.exit(main())
