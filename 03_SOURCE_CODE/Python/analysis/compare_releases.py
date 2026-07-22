"""compare_releases.py -- statistically compares two trade datasets (e.g.
a baseline release vs. a candidate release) using the SAME normalized
trade-export schema as analyse_baseline.py, reusing that script's own
schema (not re-derived) for each dataset.

**Corrected, 2026-07-22 Codex review finding (fourth round): this
docstring previously said BOTH win rate and R-expectancy use a two-sample
bootstrap CI on their difference -- only R-expectancy actually does.**
The win-rate difference uses the Newcombe-Wilson hybrid interval
(``metrics.wilson_diff_confidence_interval``), not a bootstrap, since
bootstrapping a binary 0/1 outcome collapses to a degenerate interval at
boundary samples (see that function's own docstring). R-expectancy uses
``two_sample_bootstrap_diff``, a genuine two-sample bootstrap CI on the
difference in means.

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

**Extended, 2026-07-22 Codex review finding (fifth round): this script
previously compared ONLY win rate and R-expectancy** -- TEST_PLAN.md's
required minimum side-by-side surface (profit, profit factor, drawdowns,
recovery, giveback, streaks, duration, frequency) is now computed for
BOTH datasets via ``analyse_baseline.compute_trade_summary`` (the exact
function ``analyse_baseline.py`` itself uses) and returned as
``baseline_summary``/``candidate_summary``, with a ``surface_diff`` point
comparison for the key scalars. MFE/MAE, dimensional (session/regime/
news) breakdowns, and cost sensitivity are explicitly NOT included --
see the returned ``surface_not_covered`` field for exactly why and which
task/pipeline owns closing each gap; they are not silently absent.
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

from analysis.analyse_baseline import REQUIRED_COLUMNS, compute_trade_summary
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
from analysis.report_metadata import atomic_write_text, build_report_metadata, compute_dataset_hash
from analysis.resampling import seeded_bootstrap_indices
from analysis.time_utils import parse_iso8601_utc, parse_utc_series
from analysis.trade_math import compute_r_multiple

NUMERIC_COLUMNS = ("entry_price", "exit_price", "stop_price", "profit")
MIN_N_PER_GROUP = 10  # below this, a bootstrap CI cannot represent real uncertainty
MIN_N_RESAMPLES = 100
# **Added, 2026-07-22 Codex review finding (fifth round): no upper bound
# previously existed on n_resamples, permitting an accidental unbounded
# memory/time request.**
MAX_N_RESAMPLES = 100_000


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
    # **Added, 2026-07-22 Codex review finding (fifth round): no upper
    # bound previously existed, permitting an accidental unbounded
    # memory/time request.**
    if n_resamples > MAX_N_RESAMPLES:
        raise ValueError(f"n_resamples must be <= {MAX_N_RESAMPLES}, got {n_resamples}")
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
    # **Added, 2026-07-22 Codex review finding (fourth round):** every
    # individual value is checked finite above, but the MEAN/DIFFERENCE of
    # finite values can still overflow -- an independent probe with two
    # ten-value samples at opposite 1e308 magnitudes produced an observed
    # difference of -inf and a CI of [nan, nan]. A pipeline must fail
    # visibly rather than persist non-finite statistical evidence.
    if not (math.isfinite(observed_diff) and math.isfinite(lower) and math.isfinite(upper)):
        raise ValueError(
            f"two_sample_bootstrap_diff: computed statistic overflowed to a non-finite value "
            f"(observed_diff={observed_diff}, ci=[{lower}, {upper}]) -- the input values are "
            "finite individually but their mean/difference is not"
        )
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
    # **Added, 2026-07-22 Codex review finding (fifth round): this script
    # previously reported ONLY win-rate/R-expectancy differences --
    # TEST_PLAN.md's required side-by-side surface (profit, profit
    # factor, drawdowns, recovery, giveback, streaks, duration,
    # frequency) is now computed for BOTH datasets via
    # analyse_baseline.compute_trade_summary (the same function
    # analyse_baseline.py itself uses), so a fix or new field there
    # reaches this comparison automatically. 'starting_balance'/
    # 'giveback_arm_percent'/'giveback_floor_percent' feed that shared
    # computation; defaults match analyse_baseline.py's own.**
    starting_balance: float = 1000.0,
    giveback_arm_percent: float = 1.0,
    giveback_floor_percent: float = 0.5,
    # **Fixed, 2026-07-22 Codex review finding (fourth round): period_start/
    # period_end are now REQUIRED, not optional -- the comparability
    # contract ("use identical symbols, periods, data, costs, and broker
    # settings", TEST_PLAN.md) means ONE claimed comparison period both
    # datasets must be constrained to, not two independently-observed
    # ranges checked only for any overlap (a baseline spanning Jan 1-31
    # and a candidate spanning Jan 31-Feb 28 previously passed because the
    # ranges touch at one instant). Every trade in BOTH datasets must now
    # fall entirely within [period_start, period_end].**
    period_start: str,
    period_end: str,
    # **Added, 2026-07-22 Codex review finding (fourth round): broker/
    # timeframe/modelling_mode/set_file were previously a single shared,
    # optional, caller-trusted assertion -- not "two compared manifests".
    # Unlike ea_version/data_source (which are SUPPOSED to differ between
    # baseline and candidate), these facts are supposed to be IDENTICAL
    # between the two sides of a fair comparison; role-specific fields are
    # now cross-checked for equality whenever both sides are supplied,
    # catching a human mistake (e.g. mistyping the candidate's broker)
    # instead of silently trusting one shared value.**
    baseline_broker: Optional[str] = None,
    candidate_broker: Optional[str] = None,
    baseline_timeframe: Optional[str] = None,
    candidate_timeframe: Optional[str] = None,
    baseline_modelling_mode: Optional[str] = None,
    candidate_modelling_mode: Optional[str] = None,
    baseline_set_file: Optional[str] = None,
    candidate_set_file: Optional[str] = None,
    # **Fixed, 2026-07-22 Codex review finding (third round): a single
    # shared ea_version/data_source value is insufficient to identify TWO
    # releases -- a caller could only ever record one version for both
    # sides of the comparison. Separate baseline/candidate fields now.**
    baseline_ea_version: Optional[str] = None,
    candidate_ea_version: Optional[str] = None,
    baseline_data_source: Optional[str] = None,
    candidate_data_source: Optional[str] = None,
    # **Added, 2026-07-22 Codex review finding (fourth round): spread_note/
    # slippage_note exist on ReportMetadata but no analysis caller exposed
    # or populated them -- this docstring already claimed the caller could
    # assert cost identity, but no parameter existed to do so.**
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> dict:
    """Costs, spread, and slippage identity remain the CALLER's own
    responsibility to assert consistently (no CSV column carries them) --
    'spread_note'/'slippage_note' are recorded verbatim as provenance, not
    verified against either dataset. 'period_start'/'period_end' and the
    four role-specific manifest pairs above are now either enforced
    against the actual data or cross-checked for equality (see their own
    parameter comments) rather than accepted as unverified assertions.

    Raises ValueError if a baseline/candidate manifest pair (broker,
    timeframe, modelling_mode, set_file) is supplied on both sides but the
    two values differ. Raises CsvSchemaError if any trade in either
    dataset falls outside [period_start, period_end].
    """

    for label, base_val, cand_val in (
        ("broker", baseline_broker, candidate_broker),
        ("timeframe", baseline_timeframe, candidate_timeframe),
        ("modelling_mode", baseline_modelling_mode, candidate_modelling_mode),
        ("set_file", baseline_set_file, candidate_set_file),
    ):
        if base_val is not None and cand_val is not None and base_val != cand_val:
            raise ValueError(
                f"compare_releases: baseline_{label} ({base_val!r}) != "
                f"candidate_{label} ({cand_val!r}) -- the comparability contract requires "
                f"identical {label} between baseline and candidate"
            )

    # Uses OS-level file-identity (not just Path.resolve()) so a hard
    # link to an input is also caught -- Codex review finding, third round.
    assert_path_not_same_file(output_json, baseline_csv, "output_json")
    assert_path_not_same_file(output_json, candidate_csv, "output_json")

    parsed_period_start = pd.Timestamp(parse_iso8601_utc(period_start))
    parsed_period_end = pd.Timestamp(parse_iso8601_utc(period_end))
    if parsed_period_start > parsed_period_end:
        raise ValueError(
            f"compare_releases: period_start ({period_start}) must not be after "
            f"period_end ({period_end})"
        )

    baseline = _load_trades_with_r_multiple(baseline_csv, symbol)
    candidate = _load_trades_with_r_multiple(candidate_csv, symbol)

    for label, df, csv_path in (
        ("baseline", baseline, baseline_csv),
        ("candidate", candidate, candidate_csv),
    ):
        outside = df[
            (df["entry_time"] < parsed_period_start) | (df["exit_time"] > parsed_period_end)
        ]
        if not outside.empty:
            raise CsvSchemaError(
                f"{csv_path}: {len(outside)} {label} trade(s) fall outside the claimed "
                f"comparison period [{period_start}, {period_end}] -- "
                "identical periods are required for a fair comparison"
            )

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

    # Data-driven periods each dataset actually covers -- purely
    # descriptive now that both are already ENFORCED to fall within the
    # caller-claimed [period_start, period_end] window above (Codex review
    # finding, fourth round: the old "do the observed ranges overlap"
    # check let a Jan 1-31 baseline vs. a Jan 31-Feb 28 candidate pass
    # because the ranges touch at one instant -- replaced by the stronger
    # per-trade window enforcement above).
    baseline_period = (baseline["entry_time"].min(), baseline["exit_time"].max())
    candidate_period = (candidate["entry_time"].min(), candidate["exit_time"].max())

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

    # **Added, 2026-07-22 Codex review finding (fifth round): the required
    # side-by-side comparison surface (profit, profit factor, drawdowns,
    # recovery, giveback, streaks, duration, frequency) -- computed via
    # the SAME function analyse_baseline.py itself uses, so this and that
    # module can never silently diverge on what these numbers mean.
    # 'trades_per_day' uses the CLAIMED comparison period (already the
    # authenticated window both datasets are required to fall within,
    # see the period_start/period_end enforcement above) as its
    # denominator, not each dataset's own active trade envelope -- the
    # exact fix finding 11 required, and compare_releases.py already had
    # the one input (a caller-asserted period) analyse_baseline.py alone
    # never has.**
    claimed_period_days = (parsed_period_end - parsed_period_start).total_seconds() / 86400.0
    baseline_summary = compute_trade_summary(
        baseline.sort_values("exit_time"),
        starting_balance=starting_balance,
        seed=seed,
        giveback_arm_percent=giveback_arm_percent,
        giveback_floor_percent=giveback_floor_percent,
        evaluation_period_days=claimed_period_days,
    )
    candidate_summary = compute_trade_summary(
        candidate.sort_values("exit_time"),
        starting_balance=starting_balance,
        seed=seed,
        giveback_arm_percent=giveback_arm_percent,
        giveback_floor_percent=giveback_floor_percent,
        evaluation_period_days=claimed_period_days,
    )

    def _point_diff(
        candidate_val: Optional[float], baseline_val: Optional[float]
    ) -> Optional[float]:
        # Point difference only (no CI) -- these are single-run
        # descriptive statistics, not resampled distributions; None
        # propagates when either side has an undefined statistic (e.g.
        # profit_factor with zero losses, recovery_factor with zero
        # drawdown) rather than a misleading fabricated number.
        if candidate_val is None or baseline_val is None:
            return None
        return candidate_val - baseline_val

    surface_diff = {
        "net_profit": _point_diff(candidate_summary["net_profit"], baseline_summary["net_profit"]),
        "profit_factor": _point_diff(
            candidate_summary["profit_factor"], baseline_summary["profit_factor"]
        ),
        "max_balance_drawdown_pct": _point_diff(
            candidate_summary["max_balance_drawdown_pct"],
            baseline_summary["max_balance_drawdown_pct"],
        ),
        "recovery_factor": _point_diff(
            candidate_summary["recovery_factor"], baseline_summary["recovery_factor"]
        ),
        "balance_peak_giveback_n_trigger_events": _point_diff(
            candidate_summary["balance_peak_giveback"]["n_trigger_events"],
            baseline_summary["balance_peak_giveback"]["n_trigger_events"],
        ),
        "balance_peak_giveback_max_giveback_pct": _point_diff(
            candidate_summary["balance_peak_giveback"]["max_giveback_pct"],
            baseline_summary["balance_peak_giveback"]["max_giveback_pct"],
        ),
        "longest_losing_streak": _point_diff(
            candidate_summary["longest_losing_streak"], baseline_summary["longest_losing_streak"]
        ),
        "avg_winner_dollars": _point_diff(
            candidate_summary["avg_winner_dollars"], baseline_summary["avg_winner_dollars"]
        ),
        "avg_loser_dollars": _point_diff(
            candidate_summary["avg_loser_dollars"], baseline_summary["avg_loser_dollars"]
        ),
        "avg_trade_duration_minutes": _point_diff(
            candidate_summary["avg_trade_duration_minutes"],
            baseline_summary["avg_trade_duration_minutes"],
        ),
        "trades_per_day": _point_diff(
            candidate_summary["trades_per_day"], baseline_summary["trades_per_day"]
        ),
    }

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
        "baseline_summary": baseline_summary,
        "candidate_summary": candidate_summary,
        "surface_diff": surface_diff,
        # **Added, 2026-07-22 Codex review finding (fifth round): names
        # exactly what this comparison surface still cannot cover and why
        # -- every gap has a concrete numbered owner rather than being
        # silently absent.** MFE/MAE and dimensional (session/regime/
        # news/hour) breakdowns need calculate_mfe_mae.py's bars.csv and
        # performance_breakdown.py's joined dimensional CSV respectively
        # -- both are separate, already-implemented pipelines a caller
        # can run against the same baseline_csv/candidate_csv once those
        # additional inputs exist; they are not duplicated here. Cost-
        # sensitivity (the SAME trades run through multiple assumed
        # spread/slippage scenarios) and a genuine account/daily equity-
        # peak-giveback (needs real intratrade equity ticks) both require
        # inputs TASK-037_MT5_EXPORT_BRIDGE.md does not export yet (see
        # that task's Files-affected list).
        "surface_not_covered": {
            "mfe_mae": "run calculate_mfe_mae.py separately once bars.csv exists for both releases",
            "dimensional_breakdowns": (
                "run performance_breakdown.py separately once a joined signal/outcome/session/"
                "news CSV exists for both releases"
            ),
            "cost_sensitivity": (
                "not implemented -- needs TASK-037 to export multiple cost scenarios per release, "
                "not just spread_note/slippage_note provenance"
            ),
            "account_or_daily_equity_peak_giveback": (
                "not implemented -- needs TASK-037 to export an intratrade equity-tick series; "
                "balance_peak_giveback in baseline_summary/candidate_summary is a different, "
                "balance-based proxy, see analysis.metrics.compute_balance_peak_giveback"
            ),
        },
        "n_resamples": n_resamples,
        "seed": seed,
        "confidence": confidence,
        "baseline_period": [str(baseline_period[0]), str(baseline_period[1])],
        "candidate_period": [str(candidate_period[0]), str(candidate_period[1])],
        "claimed_comparison_period": [period_start, period_end],
        "baseline_ea_version": baseline_ea_version,
        "candidate_ea_version": candidate_ea_version,
        "baseline_data_source": baseline_data_source,
        "candidate_data_source": candidate_data_source,
        # **Added, 2026-07-22 Codex review finding (fourth round):** each
        # pair is EQUALITY-VERIFIED above whenever both sides are supplied
        # (raising ValueError on mismatch), so recording both role-specific
        # values here documents what was actually checked, not just what
        # was asserted.
        "baseline_broker": baseline_broker,
        "candidate_broker": candidate_broker,
        "baseline_timeframe": baseline_timeframe,
        "candidate_timeframe": candidate_timeframe,
        "baseline_modelling_mode": baseline_modelling_mode,
        "candidate_modelling_mode": candidate_modelling_mode,
        "baseline_set_file": baseline_set_file,
        "candidate_set_file": candidate_set_file,
    }

    if output_json is not None:
        output_json.parent.mkdir(parents=True, exist_ok=True)
        # **Fixed, 2026-07-22 Codex review finding (fourth round): the one
        # combined, order-independent dataset hash is not role-preserving
        # -- two outside-repo inputs sharing a filename receive
        # indistinguishable labels in compute_dataset_hash's own portable-
        # label manifest, so swapping which physical file is baseline vs.
        # candidate could retain the SAME combined hash while reversing
        # the comparison. Separate per-role hashes close that gap.**
        summary["baseline_dataset_hash"] = compute_dataset_hash([baseline_csv], repo_root=repo_path)
        summary["candidate_dataset_hash"] = compute_dataset_hash(
            [candidate_csv], repo_root=repo_path
        )
        metadata = build_report_metadata(
            [baseline_csv, candidate_csv],
            symbol=symbol,
            period_start=period_start,
            period_end=period_end,
            random_seed=seed,
            spread_note=spread_note,
            slippage_note=slippage_note,
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
    parser.add_argument("--starting-balance", type=float, default=1000.0)
    parser.add_argument("--giveback-arm-percent", type=float, default=1.0)
    parser.add_argument("--giveback-floor-percent", type=float, default=0.5)
    # **Fixed, 2026-07-22 Codex review finding (fourth round): period-start/
    # period-end are now required, not optional -- see run()'s own comment.**
    parser.add_argument("--period-start", required=True)
    parser.add_argument("--period-end", required=True)
    parser.add_argument("--baseline-broker", default=None)
    parser.add_argument("--candidate-broker", default=None)
    parser.add_argument("--baseline-timeframe", default=None)
    parser.add_argument("--candidate-timeframe", default=None)
    parser.add_argument("--baseline-modelling-mode", default=None)
    parser.add_argument("--candidate-modelling-mode", default=None)
    parser.add_argument("--baseline-set-file", default=None)
    parser.add_argument("--candidate-set-file", default=None)
    parser.add_argument("--baseline-ea-version", default=None)
    parser.add_argument("--candidate-ea-version", default=None)
    parser.add_argument("--baseline-data-source", default=None)
    parser.add_argument("--candidate-data-source", default=None)
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
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
            starting_balance=args.starting_balance,
            giveback_arm_percent=args.giveback_arm_percent,
            giveback_floor_percent=args.giveback_floor_percent,
            period_start=args.period_start,
            period_end=args.period_end,
            baseline_broker=args.baseline_broker,
            candidate_broker=args.candidate_broker,
            baseline_timeframe=args.baseline_timeframe,
            candidate_timeframe=args.candidate_timeframe,
            baseline_modelling_mode=args.baseline_modelling_mode,
            candidate_modelling_mode=args.candidate_modelling_mode,
            baseline_set_file=args.baseline_set_file,
            candidate_set_file=args.candidate_set_file,
            baseline_ea_version=args.baseline_ea_version,
            candidate_ea_version=args.candidate_ea_version,
            baseline_data_source=args.baseline_data_source,
            candidate_data_source=args.candidate_data_source,
            spread_note=args.spread_note,
            slippage_note=args.slippage_note,
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
