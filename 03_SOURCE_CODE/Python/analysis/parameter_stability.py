"""parameter_stability.py -- sweeps ExitManager.mqh's (TASK-030) V6.37-style
giveback-guard ``giveback_percent`` parameter across a set of historical (or
clearly-labelled synthetic) R-paths, reporting how the guard's effect on
mean R changes as the parameter varies.

**Provenance (Codex review finding, 2026-07-22):** this sweep previously
lived entirely inline inside notebook 06, in violation of this project's
own reproducibility contract rule 1 (every notebook needs a paired `.py`
pipeline). It also had a real statistical defect: it compared
``mean_r_diff_when_triggered`` across different ``giveback_percent``
settings, but each setting triggers on a DIFFERENT subset of paths (a
higher giveback_percent triggers later, or not at all, on some paths) --
averaging only over each setting's own triggered subset and then
comparing those means across settings is not a like-for-like comparison.

**Fixed here:** the mean R-diff is computed over the SAME FULL set of
paths for every parameter setting (a path where the guard never
triggers contributes an r_diff of 0.0 -- the same "no effect" convention
`analyse_giveback.py` already uses), so every row of the output table is
comparable to every other row.

**Fixed, 2026-07-22 Codex review finding (third round): this was NOT an
explicit-input reproducible pipeline** -- ``run()`` accepted only
caller-created in-memory R paths, the CLI accepted no input path at all
(always printed an error and exited 1), and hand-built metadata had no
dataset identity/hash. This module now reads R-paths from an explicit
CSV file (documented schema below), hashes it via the same
``build_report_metadata`` every other pipeline uses, and has a real,
functioning CLI.

Required input format: ``r_paths.csv`` columns: ``path_id, bar_index,
r_value`` -- one row per bar of one trade's chronological R-multiple
sequence (bar_index 0 = entry, increasing = later bars; the final
bar_index per path_id is that path's own "actual final R", matching
`analyse_giveback.py`'s own R-path convention). Rows are grouped by
path_id and sorted by bar_index to reconstruct each path.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence

import pandas as pd

from analysis.csv_io import (
    CsvSchemaError,
    assert_finite_columns,
    assert_output_paths_distinct,
    atomic_write_dataframe_csv,
    read_csv_with_required_columns,
)
from analysis.exit_simulation import simulate_giveback_path
from analysis.metrics import bootstrap_confidence_interval
from analysis.report_metadata import atomic_write_text, build_report_metadata

REQUIRED_COLUMNS = {"path_id", "bar_index", "r_value"}
# ExitManager.mqh's EM_ShouldGivebackCloseV637 silently clamps giveback_percent
# to this range -- **fixed, 2026-07-22 Codex review finding (third round):
# a value outside this range was previously reported under the caller's own
# out-of-range label while actually executing the clamped value, so distinct
# reported settings could silently execute the identical effective setting.**
# Rejected outright now rather than silently clamped-and-mislabelled.
MIN_GIVEBACK_PERCENT = 10.0
MAX_GIVEBACK_PERCENT = 90.0


@dataclass(frozen=True)
class StabilityRow:
    giveback_percent: float
    n_paths: int
    n_triggered: int
    mean_r_diff_over_all_paths: float
    r_diff_ci_lower: Optional[float]
    r_diff_ci_upper: Optional[float]


def _load_r_paths_from_csv(path: Path) -> list[list[float]]:
    df = read_csv_with_required_columns(path, REQUIRED_COLUMNS)
    if df.empty:
        raise CsvSchemaError(f"{path}: zero rows")
    assert_finite_columns(df, ["bar_index", "r_value"], path)

    paths: list[list[float]] = []
    for _, group in df.sort_values(["path_id", "bar_index"]).groupby("path_id", sort=False):
        paths.append(group["r_value"].tolist())
    return paths


def sweep_giveback_percent(
    r_paths: Sequence[Sequence[float]],
    giveback_percents: Sequence[float],
    *,
    arm_rr: float = 1.25,
    close_trigger_floor_r: float = 0.05,
    seed: int = 42,
) -> list[StabilityRow]:
    """For each value in 'giveback_percents', simulates the V6.37 giveback
    guard against every path in 'r_paths' (each path's actual final R is
    its own last value -- these are already-completed historical/synthetic
    R sequences, not live trades), and computes the mean R-diff over the
    FULL set of paths (0.0 contribution for any path the guard never
    triggers on) -- see module docstring for why this differs from
    averaging only the triggered subset.

    Raises ValueError if 'r_paths' or 'giveback_percents' is empty, any
    path is empty or contains a non-finite value, or any percent is
    non-finite or outside [10, 90] (the range
    ``EM_ShouldGivebackCloseV637`` actually honors without silently
    clamping to a different effective value).
    """

    if not r_paths:
        raise ValueError("sweep_giveback_percent: r_paths must not be empty")
    if not giveback_percents:
        raise ValueError("sweep_giveback_percent: giveback_percents must not be empty")
    if any(not p for p in r_paths):
        raise ValueError("sweep_giveback_percent: every path in r_paths must be non-empty")
    if any(not math.isfinite(v) for p in r_paths for v in p):
        raise ValueError("sweep_giveback_percent: every r_path value must be finite")
    for pct in giveback_percents:
        if not math.isfinite(pct):
            raise ValueError(f"sweep_giveback_percent: giveback_percent must be finite, got {pct}")
        if not (MIN_GIVEBACK_PERCENT <= pct <= MAX_GIVEBACK_PERCENT):
            raise ValueError(
                f"sweep_giveback_percent: giveback_percent {pct} outside "
                f"[{MIN_GIVEBACK_PERCENT}, {MAX_GIVEBACK_PERCENT}] -- EM_ShouldGivebackCloseV637 "
                "would silently clamp it to a different EFFECTIVE value, so an out-of-range "
                "setting must be rejected rather than reported under its own requested label"
            )

    rows: list[StabilityRow] = []
    for pct in giveback_percents:
        r_diffs: list[float] = []
        n_triggered = 0
        for path in r_paths:
            actual_final_r = path[-1]
            triggered = simulate_giveback_path(
                path,
                "v637",
                arm_rr=arm_rr,
                giveback_percent=pct,
                close_trigger_floor_r=close_trigger_floor_r,
            )
            if triggered is not None:
                n_triggered += 1
                _, trigger_r = triggered
                r_diffs.append(trigger_r - actual_final_r)
            else:
                r_diffs.append(0.0)  # same "no effect" convention as analyse_giveback.py

        mean_r_diff = sum(r_diffs) / len(r_diffs)
        ci_lower = ci_upper = None
        # **Fixed, 2026-07-22 Codex review finding (third round): a
        # constant-r_diffs sample (e.g. the guard never triggers on any
        # path) previously SUPPRESSED its own bootstrap CI entirely
        # instead of reporting the exact (degenerate but valid) interval
        # bootstrap_confidence_interval already computes correctly for
        # zero-variance data -- see its own test coverage.**
        if len(r_diffs) >= 2:
            boot = bootstrap_confidence_interval(r_diffs, statistic="mean", seed=seed)
            ci_lower, ci_upper = boot.ci_lower, boot.ci_upper

        rows.append(
            StabilityRow(
                giveback_percent=pct,
                n_paths=len(r_paths),
                n_triggered=n_triggered,
                mean_r_diff_over_all_paths=mean_r_diff,
                r_diff_ci_lower=ci_lower,
                r_diff_ci_upper=ci_upper,
            )
        )
    return rows


def run(
    r_paths_csv: Path,
    giveback_percents: Sequence[float],
    output_csv: Optional[Path] = None,
    summary_json: Optional[Path] = None,
    *,
    arm_rr: float = 1.25,
    close_trigger_floor_r: float = 0.05,
    seed: int = 42,
    symbol: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> pd.DataFrame:
    """Reads R-paths from 'r_paths_csv' (see module docstring for the
    schema) and sweeps 'giveback_percents' against them. Raises
    CsvSchemaError for structural input problems, ValueError for
    invalid parameter values (see sweep_giveback_percent's docstring).
    """

    for out_path in (output_csv, summary_json):
        if out_path is not None and out_path.resolve() == r_paths_csv.resolve():
            raise CsvSchemaError(
                f"output path {out_path} must not be the same as the input r_paths_csv"
            )
    assert_output_paths_distinct([output_csv, summary_json])

    r_paths = _load_r_paths_from_csv(r_paths_csv)
    rows = sweep_giveback_percent(
        r_paths,
        giveback_percents,
        arm_rr=arm_rr,
        close_trigger_floor_r=close_trigger_floor_r,
        seed=seed,
    )
    result = pd.DataFrame([r.__dict__ for r in rows])

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_dataframe_csv(result, output_csv)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [r_paths_csv], symbol=symbol, random_seed=seed, repo_path=repo_path
        )
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_paths": len(r_paths),
                "giveback_percents_swept": list(giveback_percents),
                "seed": seed,
            },
        }
        atomic_write_text(summary_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return result


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--r-paths-csv", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--summary-json", type=Path, default=None)
    parser.add_argument("--giveback-percents", type=float, nargs="+", default=[40.0, 60.0, 80.0])
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--symbol", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        result = run(
            r_paths_csv=args.r_paths_csv,
            giveback_percents=args.giveback_percents,
            output_csv=args.output_csv,
            summary_json=args.summary_json,
            seed=args.seed,
            symbol=args.symbol,
        )
    except (FileNotFoundError, CsvSchemaError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"parameter_stability: {len(result)} settings swept.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
