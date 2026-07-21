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

from analysis.csv_io import CsvSchemaError, read_csv_with_required_columns
from analysis.report_metadata import build_report_metadata
from data_collection.journal_reader import read_journal_directory, to_dataframe

REQUIRED_NEWS_COLUMNS = {"event_id", "event_name", "currency", "importance", "scheduled_utc"}


@dataclass(frozen=True)
class NewsJoinResult:
    joined: pd.DataFrame  # one row per decision, + in_blackout / triggering_event_id
    n_decisions: int
    n_news_events_considered: int
    n_in_blackout: int


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
    currency whenever it's known)."""

    read_result = read_journal_directory(journal_dir)
    decisions_df = to_dataframe(read_result.valid_records)

    news = read_csv_with_required_columns(news_events_csv, REQUIRED_NEWS_COLUMNS)
    news = news.copy()
    news["scheduled_utc"] = pd.to_datetime(news["scheduled_utc"], utc=True, errors="raise")
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
        joined.to_csv(output_csv, index=False)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [news_events_csv], symbol=currency, random_seed=seed, repo_path=repo_path
        )
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
        summary_json.write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")

    return NewsJoinResult(
        joined=joined,
        n_decisions=len(decisions_df),
        n_news_events_considered=len(news),
        n_in_blackout=int(sum(in_blackout_flags)),
    )


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal-dir", required=True, type=Path)
    parser.add_argument("--news-events-csv", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--summary-json", type=Path, default=None)
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
            currency=args.currency,
            before_minutes=args.before_minutes,
            after_minutes=args.after_minutes,
            min_importance=args.min_importance,
            seed=args.seed,
        )
    except (FileNotFoundError, CsvSchemaError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"join_news_events: {result.n_decisions} decisions, "
        f"{result.n_news_events_considered} news events considered, "
        f"{result.n_in_blackout} in blackout."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
