"""join_trade_journal.py -- reads, validates, and cleans ThembaEA's
DecisionJournal ``.jsonl`` output into one reviewable CSV/JSON pair, plus a
separate error report. The first of the nine required scripts named in
``TASK-028_PYTHON_STATISTICAL_LAB.md``.

Per the reproducibility contract, this is a plain function (``run``) with
explicit input/output paths -- no hidden kernel state, no reliance on the
current working directory -- with a thin CLI wrapper (``main``) around it,
so a notebook or a test can call ``run`` directly without going through
subprocess/argv at all.

This script does ONE job: clean and validate the trade journal. Joining
against news events is a SEPARATE required script (``join_news_events.py``,
not yet built -- see TASK-028_PYTHON_STATISTICAL_LAB.md's own backlog
list) precisely so this script's output is independently useful and
independently testable without a news-event dependency.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from analysis.report_metadata import PIPELINE_VERSION, ReportMetadata, build_report_metadata
from data_collection.journal_reader import (
    JournalReadResult,
    find_duplicate_signal_ids,
    find_duplicate_timestamp_symbol,
    read_journal_directory,
    to_dataframe,
)


@dataclass(frozen=True)
class JoinTradeJournalResult:
    read_result: JournalReadResult
    n_duplicate_signal_id_rows: int
    n_duplicate_timestamp_symbol_rows: int
    metadata: ReportMetadata


def run(
    input_dir: Path,
    output_csv: Optional[Path] = None,
    output_json: Optional[Path] = None,
    errors_json: Optional[Path] = None,
    *,
    symbol: Optional[str] = None,
    broker: Optional[str] = None,
    seed: Optional[int] = None,
    repo_path: Optional[Path] = None,
) -> JoinTradeJournalResult:
    """Reads every ``decisions_*.jsonl`` file in 'input_dir', validates
    every record, and (if the corresponding output path is given) writes
    the valid records to CSV/JSON and a combined error report (parse
    errors + schema-validation errors + duplicate rows) to 'errors_json'.

    All three output paths are optional independently, so a caller (e.g. a
    notebook, or a test) can call this purely for the in-memory
    JoinTradeJournalResult without touching disk at all.

    Raises FileNotFoundError if 'input_dir' does not exist (propagated
    from read_journal_directory) -- never silently returns an empty
    result for a typo'd path.
    """

    read_result = read_journal_directory(input_dir)
    df = to_dataframe(read_result.valid_records)

    dup_signal_id = find_duplicate_signal_ids(df)
    dup_timestamp_symbol = find_duplicate_timestamp_symbol(df)

    journal_files = sorted(input_dir.glob("decisions_*.jsonl"))
    if journal_files:
        metadata = build_report_metadata(
            journal_files, symbol=symbol, broker=broker, random_seed=seed, repo_path=repo_path
        )
    else:
        # No journal files at all is a legitimate (if unusual) input state
        # -- e.g. a brand-new EA that has not run yet -- not a script
        # failure, but there is no dataset to hash, so metadata is built
        # with an empty dataset reference rather than crashing.
        metadata = ReportMetadata(
            git_commit="",
            git_dirty=False,
            dataset_paths=(),
            dataset_hash="",
            symbol=symbol,
            broker=broker,
            period_start=None,
            period_end=None,
            timezone="UTC",
            random_seed=seed,
            pipeline_version=PIPELINE_VERSION,
            generated_at_utc=datetime.now(timezone.utc).isoformat(timespec="seconds"),
        )

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(output_csv, index=False)

    if output_json is not None:
        output_json.parent.mkdir(parents=True, exist_ok=True)
        output_json.write_text(
            json.dumps([r.model_dump(mode="json") for r in read_result.valid_records], indent=2),
            encoding="utf-8",
        )

    if errors_json is not None:
        errors_json.parent.mkdir(parents=True, exist_ok=True)
        error_report = {
            "metadata": metadata.to_dict(),
            "summary": {
                "total_lines_seen": read_result.total_lines,
                "valid_records": len(read_result.valid_records),
                "parse_errors": len(read_result.parse_errors),
                "validation_errors": len(read_result.validation_errors),
                "duplicate_signal_id_rows": len(dup_signal_id),
                "duplicate_timestamp_symbol_rows": len(dup_timestamp_symbol),
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
        errors_json.write_text(json.dumps(error_report, indent=2, default=str), encoding="utf-8")

    return JoinTradeJournalResult(
        read_result=read_result,
        n_duplicate_signal_id_rows=len(dup_signal_id),
        n_duplicate_timestamp_symbol_rows=len(dup_timestamp_symbol),
        metadata=metadata,
    )


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--output-json", type=Path, default=None)
    parser.add_argument("--errors-json", type=Path, default=None)
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--broker", default=None)
    parser.add_argument("--seed", type=int, default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)

    try:
        result = run(
            input_dir=args.input_dir,
            output_csv=args.output_csv,
            output_json=args.output_json,
            errors_json=args.errors_json,
            symbol=args.symbol,
            broker=args.broker,
            seed=args.seed,
        )
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"join_trade_journal: {len(result.read_result.valid_records)} valid, "
        f"{len(result.read_result.parse_errors)} parse errors, "
        f"{len(result.read_result.validation_errors)} validation errors, "
        f"{result.n_duplicate_signal_id_rows} duplicate-signal-id rows, "
        f"{result.n_duplicate_timestamp_symbol_rows} duplicate-timestamp-symbol rows."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
