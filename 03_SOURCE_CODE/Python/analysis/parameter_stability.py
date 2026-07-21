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
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence

import pandas as pd

from analysis.csv_io import assert_output_paths_distinct
from analysis.exit_simulation import simulate_giveback_path
from analysis.metrics import bootstrap_confidence_interval
from analysis.report_metadata import atomic_write_text, capture_git_commit, default_repo_root


@dataclass(frozen=True)
class StabilityRow:
    giveback_percent: float
    n_paths: int
    n_triggered: int
    mean_r_diff_over_all_paths: float
    r_diff_ci_lower: Optional[float]
    r_diff_ci_upper: Optional[float]


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

    Raises ValueError if 'r_paths' or 'giveback_percents' is empty, or any
    path is empty.
    """

    if not r_paths:
        raise ValueError("sweep_giveback_percent: r_paths must not be empty")
    if not giveback_percents:
        raise ValueError("sweep_giveback_percent: giveback_percents must not be empty")
    if any(not p for p in r_paths):
        raise ValueError("sweep_giveback_percent: every path in r_paths must be non-empty")

    rows: list[StabilityRow] = []
    for pct in giveback_percents:
        r_diffs: list[float] = []
        n_triggered = 0
        for path in r_paths:
            actual_final_r = path[-1]
            triggered = simulate_giveback_path(
                path, "v637", arm_rr=arm_rr, giveback_percent=pct, close_trigger_floor_r=close_trigger_floor_r,
            )
            if triggered is not None:
                n_triggered += 1
                _, trigger_r = triggered
                r_diffs.append(trigger_r - actual_final_r)
            else:
                r_diffs.append(0.0)  # same "no effect" convention as analyse_giveback.py

        mean_r_diff = sum(r_diffs) / len(r_diffs)
        ci_lower = ci_upper = None
        if len(r_diffs) >= 2 and len(set(r_diffs)) > 1:
            boot = bootstrap_confidence_interval(r_diffs, statistic="mean", seed=seed)
            ci_lower, ci_upper = boot.ci_lower, boot.ci_upper

        rows.append(
            StabilityRow(
                giveback_percent=pct, n_paths=len(r_paths), n_triggered=n_triggered,
                mean_r_diff_over_all_paths=mean_r_diff, r_diff_ci_lower=ci_lower, r_diff_ci_upper=ci_upper,
            )
        )
    return rows


def run(
    r_paths: Sequence[Sequence[float]],
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
    assert_output_paths_distinct([output_csv, summary_json])

    rows = sweep_giveback_percent(
        r_paths, giveback_percents, arm_rr=arm_rr, close_trigger_floor_r=close_trigger_floor_r, seed=seed
    )
    result = pd.DataFrame([r.__dict__ for r in rows])

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        result.to_csv(output_csv, index=False)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        # No file dataset to hash here (r_paths is caller-supplied
        # in-memory data, not a CSV) -- git commit/dirty-state provenance
        # is still captured, matching every other pipeline's discipline.
        root = repo_path if repo_path is not None else default_repo_root()
        commit, dirty = capture_git_commit(root)
        payload = {
            "metadata": {"git_commit": commit, "git_dirty": dirty, "symbol": symbol},
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
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--summary-json", type=Path, default=None)
    parser.add_argument("--giveback-percents", type=float, nargs="+", default=[40.0, 60.0, 80.0])
    parser.add_argument("--seed", type=int, default=42)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    # No CLI-level real-R-path input source exists yet (this pipeline is
    # designed to be called with real historical R-paths once available,
    # or from a notebook/test with synthetic ones) -- the CLI form here
    # exists for interface completeness/consistency, not as the primary
    # calling convention.
    print("parameter_stability: no CLI-level R-path input source exists yet; call run() directly.",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
