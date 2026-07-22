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

from analysis.csv_io import (
    assert_output_paths_distinct,
    assert_path_not_direct_child_of_directory,
    assert_path_not_same_file,
    atomic_write_dataframe_csv,
    sanitize_for_csv,
)
from analysis.report_metadata import (
    ReportMetadata,
    atomic_write_text,
    build_report_metadata,
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

    # **Fixed, 2026-07-22 Codex review finding (fifth round): these
    # collision checks previously hand-rolled ad hoc resolved-STRING
    # comparisons instead of the shared hard-link-aware helpers every
    # other pipeline in this layer uses, and the "outside input_dir"
    # check tested only the IMMEDIATE parent -- a nested
    # ``input_dir/subdir/out.csv`` output silently bypassed it despite
    # genuinely living inside the input directory.**
    assert_output_paths_distinct([output_csv, output_json, errors_json])
    for out_path in (output_csv, output_json, errors_json):
        assert_path_not_direct_child_of_directory(out_path, input_dir, "output path")
    # **Fixed, 2026-07-22 Codex review finding:** this previously checked
    # output paths only against input_dir ITSELF, not against the actual
    # decisions_*.jsonl files inside it -- a direct probe used a journal
    # source file as output_csv and overwrote the source evidence.
    # **Extended, 2026-07-22 Codex review finding (fifth round):** now
    # hard-link-safe (``assert_path_not_same_file``, not resolved-string
    # equality) and checked against every actual journal file directly,
    # not just "is it a direct child of input_dir" -- catching a hard
    # link to a real journal file from anywhere on disk, not only one
    # sitting next to it.
    for out_path in (output_csv, output_json, errors_json):
        for journal_file in input_dir.glob("decisions_*.jsonl"):
            assert_path_not_same_file(out_path, journal_file, "output path")

    # **Fixed, 2026-07-22 Codex review finding (fifth round): the previous
    # "hash, then parse, then re-hash and compare" pattern (rounds 3-4)
    # was a race DETECTOR, not proof the parsed content equals the
    # reported hash -- an ABA-mutation probe changed a journal file,
    # had this parse the changed bytes, then restored the original bytes
    # before the post-parse rehash ran; the rehash matched the ORIGINAL
    # hash despite the changed content being what was actually analyzed.
    # read_journal_directory now accumulates its own dataset_hash INLINE,
    # one line at a time, from the exact same single-pass read that
    # produces valid_records/parse_errors/validation_errors below -- there
    # is no second read and therefore no window for this exact race.
    # Passing the pre-enumerated 'journal_files' list still closes the
    # separate ENUMERATION race (a file added between two independent
    # globs) the fourth round fixed.**
    journal_files = sorted(input_dir.glob("decisions_*.jsonl"))
    root = repo_path if repo_path is not None else default_repo_root()
    read_result = read_journal_directory(input_dir, files=journal_files)

    # **Fixed, 2026-07-22 Codex review finding: the empty-journal path
    # previously wrote dataset_hash="" (not a real SHA-256 identity) via a
    # special-cased manual ReportMetadata construction. read_result.dataset_hash
    # is always a genuine SHA-256 digest (the hash of zero files' worth of
    # bytes when 'journal_files' is empty, per read_journal_directory's own
    # definition), so build_report_metadata can now be called unconditionally
    # -- no more empty-vs-nonempty branch needed.**
    metadata = build_report_metadata(
        journal_files,
        symbol=symbol,
        broker=broker,
        random_seed=seed,
        spread_note=spread_note,
        slippage_note=slippage_note,
        repo_path=root,
        dataset_hash_override=read_result.dataset_hash,
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
