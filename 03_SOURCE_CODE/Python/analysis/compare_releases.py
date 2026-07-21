"""compare_releases.py -- statistically compares two trade datasets (e.g.
a baseline release vs. a candidate release) using the SAME normalized
trade-export schema as analyse_baseline.py, reusing that script's own
schema (not re-derived) for each dataset, plus a two-sample bootstrap
confidence interval on the DIFFERENCE in win rate and R-expectancy between
them.

Per the reproducibility contract's "tiny samples cannot drive automatic
live parameter changes" rule: this script never declares a release
"better" -- it reports the OBSERVED difference and a bootstrap CI around
it; a CI that excludes zero is flagged as ``likely_significant``, but the
actual go/no-go judgment remains a human decision informed by this, not an
automatic one.

**Assumes INDEPENDENT (unpaired) samples.** The two datasets are treated
as two independent collections of trades -- there is no assumption that
row *i* of the baseline corresponds to row *i* of the candidate (e.g. "the
same market period, replayed twice"). If a future caller has genuinely
PAIRED data (the same underlying market periods/trades re-evaluated under
two configurations), a paired-difference test would be more powerful and
is NOT implemented here -- using this unpaired test on paired data would
discard the pairing and understate the true precision.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd

from analysis.analyse_baseline import REQUIRED_COLUMNS
from analysis.csv_io import (
    CsvSchemaError,
    assert_chronological_order,
    assert_finite_columns,
    assert_path_not_same_file,
    assert_unique_ids,
    assert_valid_stop_geometry,
    parse_is_long,
    read_csv_with_required_columns,
)
from analysis.metrics import InsufficientSampleError, wilson_diff_confidence_interval
from analysis.report_metadata import atomic_write_text, build_report_metadata
from analysis.resampling import seeded_bootstrap_indices
from analysis.time_utils import parse_utc_series
from analysis.trade_math import compute_r_multiple

NUMERIC_COLUMNS = ("entry_price", "exit_price", "stop_price", "profit")
MIN_N_PER_GROUP = 10  # below this, a bootstrap CI cannot represent real uncertainty
MIN_N_RESAMPLES = 100


def _load_trades_with_r_multiple(trades_csv: Path, symbol_filter: Optional[str]) -> pd.DataFrame:
    trades = read_csv_with_required_columns(trades_csv, REQUIRED_COLUMNS)
    if trades.empty:
        raise InsufficientSampleError(f"{trades_csv}: zero trade rows")
    assert_unique_ids(trades, "trade_id", trades_csv)
    assert_finite_columns(trades, NUMERIC_COLUMNS, trades_csv)

    if symbol_filter is not None:
        mismatched = trades[trades["symbol"] != symbol_filter]
        if not mismatched.empty:
            raise CsvSchemaError(
                f"{trades_csv}: {len(mismatched)} row(s) have symbol != {symbol_filter!r} "
                f"(found: {sorted(mismatched['symbol'].unique())})"
            )

    trades = trades.copy()
    trades["is_long"] = trades["is_long"].apply(parse_is_long)
    # **Fixed, 2026-07-22 Codex review finding:** entry_time/exit_time were
    # never parsed or validated at all in this script (unlike every other
    # trades.csv consumer), so a naive/malformed timestamp passed through
    # silently. Parsed here even though this script's own statistics don't
    # currently use the parsed columns, so a schema problem is still a
    # visible failure rather than a silent no-op.
    trades["entry_time"] = parse_utc_series(trades["entry_time"])
    trades["exit_time"] = parse_utc_series(trades["exit_time"])
    assert_chronological_order(trades["entry_time"], trades["exit_time"], trades_csv)
    assert_valid_stop_geometry(
        trades["is_long"], trades["entry_price"], trades["stop_price"], trades_csv
    )
    trades["r_multiple"] = trades.apply(
        lambda row: compute_r_multiple(
            row["is_long"],
            float(row["entry_price"]),
            float(row["stop_price"]),
            float(row["exit_price"]),
        ),
        axis=1,
    )
    return trades


@dataclass(frozen=True)
class DiffCiResult:
    observed_diff: float  # mean(candidate) - mean(baseline) on the ACTUAL data
    ci_lower: float
    ci_upper: float
    likely_significant: bool  # True iff the CI excludes 0.0
    n_baseline: int
    n_candidate: int
    n_resamples: int
    seed: int


def two_sample_bootstrap_diff(
    baseline_values: list[float],
    candidate_values: list[float],
    n_resamples: int,
    seed: int,
    confidence: float = 0.95,
) -> DiffCiResult:
    """Reports the OBSERVED difference (mean(candidate) - mean(baseline)
    on the actual, un-resampled data) with a bootstrap confidence interval
    around it, resampling each dataset independently.

    **Fixed, 2026-07-21 Codex review finding:** the point estimate
    previously returned was ``mean(diffs across resamples)`` -- i.e. a
    RANDOM quantity that moves with the seed -- rather than the actual
    observed difference on the real data. A reproduced counterexample:
    identical observed samples [0,1] and [0,1] (a TRUE difference of
    exactly 0) with n_resamples=1 and seed=42 previously returned +0.5 as
    "the" difference, with a degenerate CI of [0.5, 0.5], and
    ``likely_significant=True`` -- while the real, observed difference
    was exactly zero.

    The candidate stream uses 'seed + 1' (deterministically derived from
    'seed', not a second independent random choice) so the two streams
    never share draws while the whole result stays fully reproducible
    given one seed value.

    Raises InsufficientSampleError if either input has fewer than
    MIN_N_PER_GROUP values -- below that, a bootstrap CI cannot represent
    real uncertainty (a degenerate 2-observation-per-group sample can
    only ever resample to that same tiny set of possible means). Raises
    ValueError if n_resamples < MIN_N_RESAMPLES, confidence is out of
    (0, 1), or either input contains a non-finite value -- **fixed,
    2026-07-22 Codex review finding (third round): this previously
    accepted a non-finite sample and silently returned NaN point/interval
    fields.**
    """

    if len(baseline_values) < MIN_N_PER_GROUP or len(candidate_values) < MIN_N_PER_GROUP:
        raise InsufficientSampleError(
            f"two_sample_bootstrap_diff: need >= {MIN_N_PER_GROUP} values in both samples, "
            f"got baseline={len(baseline_values)} candidate={len(candidate_values)}"
        )
    if n_resamples < MIN_N_RESAMPLES:
        raise ValueError(
            f"n_resamples must be >= {MIN_N_RESAMPLES} for a defensible CI, got {n_resamples}"
        )
    if not all(math.isfinite(v) for v in baseline_values) or not all(
        math.isfinite(v) for v in candidate_values
    ):
        raise ValueError("two_sample_bootstrap_diff: baseline/candidate values must all be finite")
    if not (0.0 < confidence < 1.0):
        raise ValueError(f"confidence must be in (0, 1), got {confidence}")

    baseline_arr = np.asarray(baseline_values, dtype=float)
    candidate_arr = np.asarray(candidate_values, dtype=float)
    observed_diff = float(candidate_arr.mean() - baseline_arr.mean())

    diffs = np.empty(n_resamples, dtype=float)
    baseline_iter = seeded_bootstrap_indices(len(baseline_arr), n_resamples, seed)
    candidate_iter = seeded_bootstrap_indices(len(candidate_arr), n_resamples, seed + 1)
    for i, (b_idx, c_idx) in enumerate(zip(baseline_iter, candidate_iter)):
        diffs[i] = candidate_arr[c_idx].mean() - baseline_arr[b_idx].mean()

    alpha = 1.0 - confidence
    lower = float(np.quantile(diffs, alpha / 2))
    upper = float(np.quantile(diffs, 1.0 - alpha / 2))
    return DiffCiResult(
        observed_diff=observed_diff,
        ci_lower=lower,
        ci_upper=upper,
        likely_significant=(lower > 0.0 or upper < 0.0),
        n_baseline=len(baseline_values),
        n_candidate=len(candidate_values),
        n_resamples=n_resamples,
        seed=seed,
    )


def run(
    baseline_csv: Path,
    candidate_csv: Path,
    output_json: Optional[Path] = None,
    *,
    n_resamples: int = 2000,
    seed: int = 42,
    confidence: float = 0.95,
    symbol: Optional[str] = None,
    broker: Optional[str] = None,
    period_start: Optional[str] = None,
    period_end: Optional[str] = None,
    # **Fixed, 2026-07-22 Codex review finding (third round): a single
    # shared ea_version/data_source value is insufficient to identify TWO
    # releases -- a caller could only ever record one version for both
    # sides of the comparison. Separate baseline/candidate fields now.**
    baseline_ea_version: Optional[str] = None,
    candidate_ea_version: Optional[str] = None,
    baseline_data_source: Optional[str] = None,
    candidate_data_source: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> dict:
    """'broker'/'period_start'/'period_end' are recorded in the report's
    provenance metadata and are the CALLER's responsibility to ensure are
    actually identical between the two datasets -- this script can only
    verify what is present IN the CSVs themselves (symbol and, now, the
    data-driven trade period -- see below), not facts (broker, costs,
    modelling mode, set file) that live outside them. Always state these
    explicitly when calling this comparison."""

    # Uses OS-level file-identity (not just Path.resolve()) so a hard
    # link to an input is also caught -- Codex review finding, third round.
    assert_path_not_same_file(output_json, baseline_csv, "output_json")
    assert_path_not_same_file(output_json, candidate_csv, "output_json")

    baseline = _load_trades_with_r_multiple(baseline_csv, symbol)
    candidate = _load_trades_with_r_multiple(candidate_csv, symbol)

    # **Fixed, 2026-07-22 Codex review finding:** with no 'symbol' filter
    # supplied, the two datasets' own symbol sets were never checked
    # against EACH OTHER at all -- an EURUSD baseline vs. an XAUUSD
    # candidate was accepted and compared as if they were the same
    # instrument. A CI comparing two genuinely different symbols answers
    # the wrong question regardless of its arithmetic correctness.
    baseline_symbols = set(baseline["symbol"].unique())
    candidate_symbols = set(candidate["symbol"].unique())
    if baseline_symbols != candidate_symbols:
        raise CsvSchemaError(
            f"compare_releases: baseline and candidate cover different symbols -- "
            f"baseline={sorted(baseline_symbols)}, candidate={sorted(candidate_symbols)}. "
            "A release comparison requires both datasets to cover the same instrument(s)."
        )

    # **Added, 2026-07-22 Codex review finding (third round): only symbol
    # sets were checked -- a same-symbol January-2026 baseline vs.
    # January-2025 candidate was still accepted. broker/period/costs/
    # modelling-mode/set-file identity cannot be verified from the CSVs
    # themselves (they are caller-asserted facts, documented above), but
    # the DATA-DRIVEN trade period each dataset actually covers can be,
    # and a wholly disjoint period is a defensible, data-driven rejection
    # (not exhaustive comparability, but a real check, not zero checks).**
    baseline_period = (baseline["entry_time"].min(), baseline["exit_time"].max())
    candidate_period = (candidate["entry_time"].min(), candidate["exit_time"].max())
    periods_overlap = (
        baseline_period[0] <= candidate_period[1] and candidate_period[0] <= baseline_period[1]
    )
    if not periods_overlap:
        raise CsvSchemaError(
            f"compare_releases: baseline period {baseline_period} and candidate period "
            f"{candidate_period} do not overlap at all -- these do not look like comparable "
            "experiments over the same market period."
        )

    # Win-rate difference: a proper two-proportion interval (Newcombe-
    # Wilson), not a bootstrap over raw 0/1 outcomes -- **fixed, 2026-07-22
    # Codex review finding:** bootstrapping binary outcomes collapses to a
    # degenerate [1.0, 1.0] or [0.0, 0.0] at boundary samples (e.g. all-win
    # vs. all-loss groups), which is not a defensible sampling-uncertainty
    # statement for a proportion.
    baseline_wins = int((baseline["profit"] > 0).sum())
    candidate_wins = int((candidate["profit"] > 0).sum())
    win_rate_diff = wilson_diff_confidence_interval(
        candidate_wins, len(candidate), baseline_wins, len(baseline), confidence
    )
    # Continuous R-expectancy difference remains a bootstrap -- appropriate
    # for a continuous statistic, unlike the binary win-rate case above.
    expectancy_r_diff = two_sample_bootstrap_diff(
        baseline["r_multiple"].tolist(),
        candidate["r_multiple"].tolist(),
        n_resamples,
        seed,
        confidence,
    )

    summary = {
        "n_baseline_trades": len(baseline),
        "n_candidate_trades": len(candidate),
        "baseline_win_rate": float((baseline["profit"] > 0).mean()),
        "candidate_win_rate": float((candidate["profit"] > 0).mean()),
        "baseline_expectancy_r": float(baseline["r_multiple"].mean()),
        "candidate_expectancy_r": float(candidate["r_multiple"].mean()),
        "win_rate_diff": {
            "observed_diff": win_rate_diff.diff,
            "ci_lower": win_rate_diff.ci_lower,
            "ci_upper": win_rate_diff.ci_upper,
            "likely_significant": win_rate_diff.likely_significant,
            "method": "newcombe_wilson",
            "n_baseline": win_rate_diff.n_b,
            "n_candidate": win_rate_diff.n_a,
            "confidence": win_rate_diff.confidence,
        },
        "expectancy_r_diff": expectancy_r_diff.__dict__,
        "n_resamples": n_resamples,
        "seed": seed,
        "confidence": confidence,
        "baseline_period": [str(baseline_period[0]), str(baseline_period[1])],
        "candidate_period": [str(candidate_period[0]), str(candidate_period[1])],
        "baseline_ea_version": baseline_ea_version,
        "candidate_ea_version": candidate_ea_version,
        "baseline_data_source": baseline_data_source,
        "candidate_data_source": candidate_data_source,
    }

    if output_json is not None:
        output_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [baseline_csv, candidate_csv],
            symbol=symbol,
            broker=broker,
            period_start=period_start,
            period_end=period_end,
            random_seed=seed,
            repo_path=repo_path,
        )
        payload = {"metadata": metadata.to_dict(), "summary": summary}
        atomic_write_text(output_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return summary


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-csv", required=True, type=Path)
    parser.add_argument("--candidate-csv", required=True, type=Path)
    parser.add_argument("--output-json", type=Path, default=None)
    parser.add_argument("--n-resamples", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--confidence", type=float, default=0.95)
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--broker", default=None)
    parser.add_argument("--period-start", default=None)
    parser.add_argument("--period-end", default=None)
    parser.add_argument("--baseline-ea-version", default=None)
    parser.add_argument("--candidate-ea-version", default=None)
    parser.add_argument("--baseline-data-source", default=None)
    parser.add_argument("--candidate-data-source", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        summary = run(
            baseline_csv=args.baseline_csv,
            candidate_csv=args.candidate_csv,
            output_json=args.output_json,
            n_resamples=args.n_resamples,
            seed=args.seed,
            confidence=args.confidence,
            symbol=args.symbol,
            broker=args.broker,
            period_start=args.period_start,
            period_end=args.period_end,
            baseline_ea_version=args.baseline_ea_version,
            candidate_ea_version=args.candidate_ea_version,
            baseline_data_source=args.baseline_data_source,
            candidate_data_source=args.candidate_data_source,
        )
    except (FileNotFoundError, CsvSchemaError, InsufficientSampleError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"compare_releases: baseline_n={summary['n_baseline_trades']} "
        f"candidate_n={summary['n_candidate_trades']} "
        f"win_rate_diff={summary['win_rate_diff']['observed_diff']:.4f} "
        f"(significant={summary['win_rate_diff']['likely_significant']})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
