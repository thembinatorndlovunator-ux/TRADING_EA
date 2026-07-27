"""join_news_events.py -- joins ThembaEA journal decisions against a news-
events export, independently recomputing whether each decision fell inside
a NEWS_BLACKOUT window (per ``NewsManager.mqh``'s TASK-029 blackout-window
definition, section 10 of ``TASK-002_PHASE2_SPECIFICATION.md``).

**Why this is a genuinely useful independent check, not a duplicate of the
MQL5 side:** ``ThembaAdaptiveIntradayEA.mq5`` does populate ``news_state``
today (TASK-034's live ``ResolveNewsBlackout`` wiring), but this script
still recomputes blackout status independently, from the raw news events
export -- an independent cross-check against whatever the live EA's own
news provider (MT5 calendar or FairEconomy) actually recorded, not a
value this script merely trusts. A mismatch between the two is itself
useful evidence: it can mean a news-provider data gap, a timing edge
case, or a genuine EA bug, none of which a duplicate-of-the-source
computation could ever surface.

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
import math
import os
import sys
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path
from typing import Optional

import pandas as pd

from analysis.csv_io import (
    CsvSchemaError,
    assert_finite_columns,
    assert_output_paths_distinct,
    assert_path_not_direct_child_of_directory,
    assert_path_not_same_file,
    assert_unique_ids,
    read_csv_with_required_columns_and_hash,
    sanitize_for_csv,
    write_dataframe_csv_to_temp,
)
from analysis.report_metadata import (
    build_report_metadata,
    combine_labeled_hashes,
    write_text_to_temp,
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
    # **Added, 2026-07-22 Codex review finding (fourth round): spread_note/
    # slippage_note exist on ReportMetadata but no analysis caller exposed
    # or populated them.**
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
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

    # **Added, 2026-07-22 Codex review finding (fourth round):** none of
    # before_minutes/after_minutes/min_importance were validated -- a
    # negative before_minutes/after_minutes flips the corresponding side
    # of the blackout window (event.scheduled_utc - timedelta(minutes=
    # negative) moves FORWARD in time, not backward), which can silently
    # invert or empty the window rather than raise. A negative
    # min_importance is likewise inconsistent with MIN_IMPORTANCE_VALUE,
    # the same non-negative-integer domain floor already enforced on the
    # news CSV's own 'importance' column.
    if before_minutes < 0 or after_minutes < 0:
        raise ValueError(
            f"before_minutes/after_minutes must be >= 0, got before_minutes={before_minutes}, "
            f"after_minutes={after_minutes}"
        )
    # **Added, 2026-07-22 Codex review finding (fifth round): the bare
    # 'min_importance < MIN_IMPORTANCE_VALUE' check above admits several
    # wrong-typed/non-finite values that are not a legitimate importance
    # threshold: NaN (every comparison against NaN is False in Python, so
    # it silently passes), a fractional float like 1.5 (the news CSV's
    # own 'importance' column is enforced as a non-negative INTEGER
    # ordinal, so a fractional threshold can never match anything
    # meaningfully), and a Python bool (a subtype of int -- True/False
    # would silently compare as 1/0). All three now rejected outright,
    # matching the same type/finiteness discipline already enforced on
    # the news CSV's own 'importance' column below.**
    if isinstance(min_importance, bool):
        raise ValueError(
            f"min_importance must be an integer ordinal, not a bool, got {min_importance!r}"
        )
    if not isinstance(min_importance, int):
        if not (isinstance(min_importance, float) and math.isfinite(min_importance)):
            raise ValueError(
                f"min_importance must be a finite integer ordinal, got non-finite value "
                f"{min_importance!r}"
            )
        if min_importance != int(min_importance):
            raise ValueError(
                f"min_importance must be an integer ordinal, got fractional value {min_importance!r}"
            )
    if min_importance < MIN_IMPORTANCE_VALUE:
        raise ValueError(f"min_importance must be >= {MIN_IMPORTANCE_VALUE}, got {min_importance}")

    # **Fixed, 2026-07-22 Codex review finding (fourth round):** errors_json
    # used to be derived from output_csv/summary_json AFTER the collision
    # checks below already ran -- output_csv=joined.csv,
    # summary_json=joined.errors.json, errors_json=None derived a sidecar
    # path that collided with (and silently overwrote) the explicitly
    # requested summary_json. Every implicit path is now derived FIRST,
    # then the complete final path set is validated once.
    if errors_json is None:
        base = output_csv if output_csv is not None else summary_json
        if base is not None:
            errors_json = base.parent / f"{base.stem}.errors.json"

    # **Fixed, 2026-07-22 Codex review finding (fifth round): these
    # collision checks previously mixed a shared hard-link-aware helper
    # (for news_events_csv) with ad hoc resolved-STRING comparisons (for
    # journal_dir and output-output distinctness) -- now all three use
    # the same shared, hard-link-safe helpers every other pipeline in
    # this layer uses.**
    for out_path in (output_csv, summary_json, errors_json):
        assert_path_not_direct_child_of_directory(out_path, journal_dir, "output path")
        # Uses OS-level file-identity (not just Path.resolve()) so a hard
        # link to news_events_csv is also caught -- Codex review finding, third round.
        assert_path_not_same_file(out_path, news_events_csv, "output path")
        # **Fixed, 2026-07-22 Codex review finding:** an output written
        # INSIDE journal_dir (even under a different name) could later be
        # picked up by a SUBSEQUENT run's "decisions_*.jsonl" glob as if
        # it were a real journal input, folding a derived output into its
        # own future dataset hash. Any real journal file is also checked
        # directly (hard-link-safe), catching a hard link to one from
        # anywhere on disk, not only a direct child of journal_dir.
        for journal_file in journal_dir.glob("decisions_*.jsonl"):
            assert_path_not_same_file(out_path, journal_file, "output path")
    assert_output_paths_distinct([output_csv, summary_json, errors_json])

    # **Fixed, 2026-07-22 Codex review finding (fifth round): the previous
    # "hash, then parse, then re-hash and compare" pattern (rounds 3-4)
    # was a race DETECTOR, not proof the parsed content equals the
    # reported hash -- an ABA-mutation probe changed a file, had it
    # parsed with the CHANGED bytes, then restored the ORIGINAL bytes
    # before the post-parse rehash ran, which matched the ORIGINAL hash
    # despite the changed content being what was actually analyzed.
    # read_journal_directory (below) accumulates its own dataset_hash
    # INLINE from the exact same single-pass read that produces
    # valid_records; read_csv_with_required_columns_and_hash (further
    # below, for news_events_csv) does the same for a single CSV. Neither
    # has a second read, so neither has a window for this race. The two
    # ABA-safe hashes are combined into one dataset identity via the same
    # sorted-manifest scheme compute_dataset_hash itself uses, so the
    # combined shape is unchanged even though neither component was
    # produced by re-reading a path a second time. Passing the
    # pre-enumerated 'journal_files' list to read_journal_directory still
    # closes the separate ENUMERATION race (a file added between two
    # independent globs) the fourth round fixed.**
    journal_files = sorted(journal_dir.glob("decisions_*.jsonl"))
    read_result = read_journal_directory(journal_dir, files=journal_files)
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

    # **Fixed, 2026-07-22 Codex review finding (fifth round): 'event_id'
    # was previously read with generic pandas numeric inference despite
    # NewsManager.mqh's SNewsEvent defining it as a durable STRING --
    # "001" was silently re-emitted as "1", and "001"/"1" then collapsed
    # into a false duplicate (the same identifier class of bug already
    # fixed for order_id/deal_id/trade_id in join_signal_to_outcome.py).**
    news, news_file_hash = read_csv_with_required_columns_and_hash(
        news_events_csv, REQUIRED_NEWS_COLUMNS, dtype={"event_id": str}
    )
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

    # Combines the journal directory's own inline hash (from
    # read_journal_directory, accumulated during the single pass that
    # produced 'decisions_df' above) with the news CSV's own inline hash
    # (from read_csv_with_required_columns_and_hash, accumulated during
    # the single pass that produced 'news' above) -- both ABA-safe by
    # construction, so there is no post-parse rehash left to run: neither
    # component hash could ever have drifted from what was actually
    # parsed, since neither involved a second read of anything.
    dataset_paths_for_metadata = [news_events_csv, *journal_files]
    # **Fixed, 2026-07-22 Codex review finding (seventh round, P1 finding
    # 16): the news_events_csv side's label was previously the bare
    # basename -- role-qualified now, matching the already-role-qualified
    # "journal_directory" label on the other side.**
    combined_hash = combine_labeled_hashes(
        [
            (f"news_events_csv:{news_events_csv.name}", news_file_hash),
            ("journal_directory", read_result.dataset_hash),
        ]
    )
    metadata = build_report_metadata(
        dataset_paths_for_metadata,
        currency=currency,
        random_seed=seed,
        spread_note=spread_note,
        slippage_note=slippage_note,
        repo_path=repo_path,
        dataset_hash_override=combined_hash,
    )

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

    safe_joined = None
    if output_csv is not None:
        # Sanitize caller-controlled journal strings against spreadsheet-
        # formula injection before export -- same fix as join_trade_journal.py.
        safe_joined = joined.copy()
        for col in safe_joined.select_dtypes(include=["object", "str"]).columns:
            safe_joined[col] = safe_joined[col].map(sanitize_for_csv)

    payload = None
    if summary_json is not None:
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

    # **Fixed, 2026-07-22 Codex review finding (third round): row-level
    # invalid-journal details were previously persisted ONLY if the
    # caller happened to request errors_json explicitly -- otherwise an
    # all-invalid run could write an empty output_csv, exit nonzero, and
    # retain no reviewable error artifact anywhere on disk. errors_json is
    # now auto-derived at the top of this function (before the collision
    # check -- fourth-round finding), whenever any other output is
    # requested, matching join_trade_journal.py's own fix for the
    # identical gap.**
    error_payload = None
    if errors_json is not None:
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

    # **Fixed, 2026-07-22 Codex review finding (eighth round, P1 finding
    # 16): output_csv/summary_json/errors_json were previously written as
    # three separate calls, each individually atomic but NOT atomic as a
    # GROUP -- a fault injected during summary_json or errors_json left
    # output_csv genuinely present on disk with no (or only partial)
    # provenance.
    #
    # **Rewritten, 2026-07-27 Codex review finding (ninth round, P1 finding
    # 12):** see join_trade_journal.py's own identical fix comment -- the
    # "unlink whatever this call already wrote" rollback was itself
    # unsound on a REPUBLISH (it destroyed a pre-existing valid file the
    # moment ITS OWN write in the group succeeded before a LATER write
    # failed). Every requested file is now written fully to a temp
    # location first; only once every temp write has succeeded are they
    # renamed into place. If any temp write raises, every temp file this
    # call created is removed and no final path is ever touched.**
    csv_tmp: Optional[Path] = None
    summary_json_tmp: Optional[Path] = None
    errors_json_tmp: Optional[Path] = None
    try:
        if output_csv is not None:
            csv_tmp = write_dataframe_csv_to_temp(safe_joined, output_csv)

        if summary_json is not None:
            summary_json_tmp = write_text_to_temp(
                summary_json, json.dumps(payload, indent=2, default=str, allow_nan=False)
            )

        if errors_json is not None:
            errors_json_tmp = write_text_to_temp(
                errors_json, json.dumps(error_payload, indent=2, default=str, allow_nan=False)
            )

        if summary_json_tmp is not None and summary_json is not None:
            os.replace(summary_json_tmp, summary_json)
            summary_json_tmp = None
        if errors_json_tmp is not None and errors_json is not None:
            os.replace(errors_json_tmp, errors_json)
            errors_json_tmp = None
        if csv_tmp is not None and output_csv is not None:
            os.replace(csv_tmp, output_csv)
            csv_tmp = None
    finally:
        for tmp_path in (csv_tmp, summary_json_tmp, errors_json_tmp):
            if tmp_path is not None:
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass

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
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
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
            spread_note=args.spread_note,
            slippage_note=args.slippage_note,
        )
    # **Fixed, 2026-07-22 Codex review finding (fourth round):** the
    # hash-race check (RuntimeError) and JournalReaderLimitError (a
    # RuntimeError subclass) were previously uncaught here -- an expected
    # input-integrity failure surfaced as an unhandled traceback instead
    # of a controlled ERROR exit.
    except (
        FileNotFoundError,
        CsvSchemaError,
        TimezoneValidationError,
        ValueError,
        RuntimeError,
    ) as exc:
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
