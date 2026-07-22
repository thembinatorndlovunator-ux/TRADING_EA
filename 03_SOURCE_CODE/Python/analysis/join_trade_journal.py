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
now built -- see that module) precisely so this script's output is
independently useful and independently testable without a news-event
dependency.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from analysis.csv_io import atomic_write_dataframe_csv, sanitize_for_csv
from analysis.report_metadata import (
    PIPELINE_VERSION,
    ReportMetadata,
    atomic_write_text,
    build_report_metadata,
    capture_git_commit,
    compute_dataset_hash,
    default_repo_root,
)
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
    # **Added, 2026-07-22 Codex review finding (fourth round): spread_note/
    # slippage_note exist on ReportMetadata but no analysis caller exposed
    # or populated them.**
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
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
    result for a typo'd path. Raises ValueError if any output path
    coincides with 'input_dir' or with another output path.
    """

    # **Fixed, 2026-07-22 Codex review finding (fourth round):** the
    # errors_json sidecar used to be derived from output_csv/output_json
    # AFTER this collision check already ran -- a probe requesting
    # output_csv=foo.csv, output_json=foo.provenance.json, errors_json=None
    # had the derived sidecar path collide with (and silently overwrite)
    # the explicitly requested output_json. Every implicit path is now
    # derived FIRST, then the complete final path set is validated once.
    if errors_json is None:
        base = output_csv if output_csv is not None else output_json
        if base is not None:
            errors_json = base.parent / f"{base.stem}.provenance.json"

    output_paths = [p for p in (output_csv, output_json, errors_json) if p is not None]
    resolved_outputs = [p.resolve() for p in output_paths]
    if len(set(resolved_outputs)) != len(resolved_outputs):
        raise ValueError("output_csv, output_json, and errors_json must all be distinct paths")
    if any(p == input_dir.resolve() for p in resolved_outputs):
        raise ValueError("an output path must not be the same as input_dir")
    # **Fixed, 2026-07-22 Codex review finding:** this previously checked
    # output paths only against input_dir ITSELF, not against the actual
    # decisions_*.jsonl files inside it -- a direct probe used a journal
    # source file as output_csv and overwrote the source evidence. Any
    # output written INSIDE input_dir (regardless of filename) is now
    # rejected outright, both to prevent overwriting a real journal file
    # and to prevent a derived output later being picked up by a
    # SUBSEQUENT run's own journal glob.
    resolved_input_dir = input_dir.resolve()
    if any(p.parent == resolved_input_dir for p in resolved_outputs):
        raise ValueError(f"an output path must not be written inside input_dir ({input_dir})")

    # **Fixed, 2026-07-22 Codex review finding:** the dataset hash was
    # previously computed AFTER read_journal_directory had already parsed
    # every file -- a concurrent append or a torn final line completing
    # between the two reads could make the reported hash describe
    # different bytes than the ones actually analyzed. Hashing first
    # narrows (does not perfectly eliminate, absent a single atomic read)
    # that window.
    journal_files = sorted(input_dir.glob("decisions_*.jsonl"))
    root = repo_path if repo_path is not None else default_repo_root()
    if journal_files:
        metadata = build_report_metadata(
            journal_files,
            symbol=symbol,
            broker=broker,
            random_seed=seed,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=root,
        )
    else:
        # No journal files at all is a legitimate (if unusual) input state
        # -- e.g. a brand-new EA that has not run yet -- not a script
        # failure. There is no DATASET to hash, but the CODE provenance
        # (git commit) is always determinable regardless of whether any
        # input data exists, so it is captured for real here too rather
        # than special-cased to an empty string (a Codex review finding:
        # the previous code silently reported an empty commit/hash pair
        # here instead of the still-knowable commit).
        commit, dirty = capture_git_commit(root)
        metadata = ReportMetadata(
            git_commit=commit,
            git_dirty=dirty,
            dataset_paths=(),
            dataset_hash="",
            symbol=symbol,
            currency=None,
            broker=broker,
            period_start=None,
            period_end=None,
            timeframe=None,
            modelling_mode=None,
            costs_note=None,
            set_file=None,
            timezone="UTC",
            random_seed=seed,
            pipeline_version=PIPELINE_VERSION,
            spread_note=spread_note,
            slippage_note=slippage_note,
        )

    # **Fixed, 2026-07-22 Codex review finding (fourth round):** previously
    # this passed only 'input_dir' to read_journal_directory, which
    # re-globbed the directory independently of the 'journal_files' list
    # already hashed above -- a probe added a second decisions_*.jsonl
    # file after the initial glob/hash; both files got analyzed here, but
    # 'metadata'/the post-parse re-hash below both still only knew about
    # the first file, so the mismatch went undetected. Passing the SAME
    # pre-enumerated 'journal_files' list closes the enumeration race
    # entirely (no second glob can see a new file); the post-parse re-hash
    # of that same fixed list still catches a concurrent CONTENT mutation.
    read_result = read_journal_directory(input_dir, files=journal_files)

    # **Fixed, 2026-07-22 Codex review finding (third round): hashing
    # before parsing narrows, but does NOT eliminate, the race a
    # concurrent writer creates -- a probe changed a journal file AFTER
    # metadata hashing but BEFORE parsing, and the result analyzed the
    # NEW record while retaining the OLD hash. Re-hashing after parsing
    # and comparing catches exactly that case (this is a detection, not
    # a full transactional guarantee -- a change occurring in the tiny
    # window during this second hash computation itself remains
    # possible, though vanishingly unlikely for local files).**
    if journal_files:
        post_parse_hash = compute_dataset_hash(journal_files, repo_root=root)
        if post_parse_hash != metadata.dataset_hash:
            raise RuntimeError(
                f"{input_dir}: journal files changed between hashing and parsing -- "
                "the analyzed content and the reported dataset_hash would not match. "
                "Re-run against a stable snapshot."
            )

    df = to_dataframe(read_result.valid_records)

    dup_signal_id = find_duplicate_signal_ids(df)
    dup_timestamp_symbol = find_duplicate_timestamp_symbol(df)

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        # **Fixed, 2026-07-22 Codex review finding:** caller-controlled
        # journal strings (strategy/setup/pattern names, etc.) were
        # written directly to CSV; a value like "=CMD(...)" could become
        # a live spreadsheet formula the moment a reviewer opened the
        # exported CSV. Every string (object-dtype) column is sanitized
        # before export.
        safe_df = df.copy()
        for col in safe_df.select_dtypes(include=["object", "str"]).columns:
            safe_df[col] = safe_df[col].map(sanitize_for_csv)
        atomic_write_dataframe_csv(safe_df, output_csv)

    if output_json is not None:
        output_json.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_text(
            output_json,
            json.dumps(
                [r.model_dump(mode="json") for r in read_result.valid_records],
                indent=2,
                allow_nan=False,
            ),
        )

    # **Fixed, 2026-07-22 Codex review finding (third round): provenance
    # was previously written ONLY into the optional errors_json report --
    # a caller who requested output_csv/output_json but not errors_json
    # got a data file with zero provenance record anywhere. A provenance
    # sidecar is now auto-derived (see the top of this function, before
    # the collision check -- fourth-round finding) and always written
    # whenever ANY output is requested, even if the caller never asks for
    # errors_json explicitly.**
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
            # Duplicate rows are identified explicitly (not just counted)
            # -- a Codex review finding: this report previously promised
            # duplicate detection but wrote only the COUNT, losing which
            # records were actually affected.
            "duplicate_signal_id_records": dup_signal_id.to_dict(orient="records"),
            "duplicate_timestamp_symbol_records": dup_timestamp_symbol.to_dict(orient="records"),
        }
        atomic_write_text(
            errors_json, json.dumps(error_report, indent=2, default=str, allow_nan=False)
        )

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
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
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
            spread_note=args.spread_note,
            slippage_note=args.slippage_note,
        )
    # **Fixed, 2026-07-22 Codex review finding (fourth round):** the
    # hash-race check (RuntimeError) and JournalReaderLimitError (a
    # RuntimeError subclass) were previously uncaught here -- an expected
    # input-integrity failure surfaced as an unhandled traceback instead
    # of a controlled ERROR exit, unlike every FileNotFoundError/
    # ValueError this CLI already handles gracefully.
    except (FileNotFoundError, ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"join_trade_journal: {len(result.read_result.valid_records)} valid, "
        f"{len(result.read_result.parse_errors)} parse errors, "
        f"{len(result.read_result.validation_errors)} validation errors, "
        f"{result.n_duplicate_signal_id_rows} duplicate-signal-id rows, "
        f"{result.n_duplicate_timestamp_symbol_rows} duplicate-timestamp-symbol rows."
    )
    has_problems = (
        result.read_result.parse_errors
        or result.read_result.validation_errors
        or result.n_duplicate_signal_id_rows
        or result.n_duplicate_timestamp_symbol_rows
    )
    return 1 if has_problems else 0


if __name__ == "__main__":
    sys.exit(main())
