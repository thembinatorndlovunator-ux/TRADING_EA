"""walk_forward.py -- rolling train/test window stability analysis over a
time-ordered trade series, using the SAME normalized trade-export schema as
``analyse_baseline.py`` (``trade_id, symbol, is_long, entry_time, exit_time,
entry_price, exit_price, stop_price, profit``).

Window boundaries are entirely deterministic given
(``train_days``, ``test_days``, ``step_days``) and the dataset's own first/
last ``exit_time`` -- window GENERATION itself uses no randomization.

**Correction, 2026-07-22 Codex review finding (third round): this module
DOES need and accept a seed.** The claim above ("no seed is needed or
accepted") became false once ``metrics.expectancy`` started computing a
bootstrap confidence interval internally (a separate, later fix) --
every non-singleton per-window expectancy now invokes a seeded bootstrap.
``run()`` accepts an explicit ``seed`` (default 42, matching this
project's other seed defaults), threads it to every ``expectancy()``
call, and the report exposes it -- a hidden default seed would otherwise
make the reported expectancy CIs look reproducible while actually
depending on an unexposed constant.

**Scope, stated explicitly (Codex review finding, 2026-07-21): this is a
descriptive rolling-window STABILITY report, not a walk-forward
OPTIMIZATION procedure.** It computes win-rate/expectancy for each
train/test window pair; it does NOT select any parameter on the train
window and freeze it for the test window (the standard definition of
"walk-forward" in a trading-strategy-development sense). A genuine
parameter-selection walk-forward harness (accepting a pluggable
train-window optimizer and a frozen-parameter test evaluator) is a
reasonable future enhancement, not attempted here.

**Purged boundaries, fixed 2026-07-21:** a trade is assigned to a window
only if BOTH its entry_time and exit_time fall inside that window's own
[start, end) range. A trade whose entry precedes a window's start (or
whose exit follows a window's end) is excluded from that window entirely
rather than assigned by exit_time alone -- the previous exit-time-only
partitioning could let a trade whose ENTRY (and thus whatever information
the trade's own decision used) preceded a test window's start still count
as a "test" observation, which is a temporal-leakage route for any
parameter genuinely selected on the train window.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import pandas as pd

from analysis.csv_io import (
    TRADE_ID_DTYPE,
    CsvSchemaError,
    assert_chronological_order,
    assert_finite_columns,
    assert_output_paths_distinct,
    assert_path_not_same_file,
    assert_unique_ids,
    assert_valid_stop_geometry,
    atomic_write_dataframe_csv,
    parse_is_long,
    read_csv_with_required_columns_and_hash,
)
from analysis.metrics import (
    MAX_N_RESAMPLES,
    MIN_N_RESAMPLES,
    InsufficientSampleError,
    expectancy,
    win_rate,
)
from analysis.report_metadata import atomic_write_text, build_report_metadata
from analysis.time_utils import parse_utc_series
from analysis.trade_math import compute_r_multiple

REQUIRED_COLUMNS = {
    "trade_id",
    "symbol",
    "is_long",
    "entry_time",
    "exit_time",
    "entry_price",
    "exit_price",
    "stop_price",
    "profit",
}
# **Fixed, 2026-07-22 Codex review finding:** 'profit' was missing from
# this validated set. A missing/NaN profit reaches `profit > 0`, where
# pandas returns False for NaN, silently counting an unknown-P/L row as
# a LOSS rather than raising a visible schema failure -- reproduced via a
# direct three-row probe that returned train_win_rate=0.0 with the
# legitimate earliest trade discarded (see the window-anchor fix below)
# and the remaining NaN-profit row counted as a loss.
NUMERIC_COLUMNS = ("entry_price", "exit_price", "stop_price", "profit")

SUMMARY_COLUMNS = [
    "window_index",
    "train_start",
    "train_end",
    "test_start",
    "test_end",
    "train_n",
    "train_win_rate",
    "train_win_rate_ci_lower",
    "train_win_rate_ci_upper",
    "train_expectancy_r",
    "train_expectancy_r_ci_lower",
    "train_expectancy_r_ci_upper",
    "test_n",
    "test_win_rate",
    "test_win_rate_ci_lower",
    "test_win_rate_ci_upper",
    "test_expectancy_r",
    "test_expectancy_r_ci_lower",
    "test_expectancy_r_ci_upper",
]


def generate_windows(
    first_time: pd.Timestamp,
    last_time: pd.Timestamp,
    train_days: int,
    test_days: int,
    step_days: int,
) -> list[tuple[pd.Timestamp, pd.Timestamp, pd.Timestamp, pd.Timestamp]]:
    """Generates (train_start, train_end, test_start, test_end) tuples,
    rolling forward by 'step_days' each time, stopping once a window's
    test_start would fall after 'last_time' (no window is generated that
    starts entirely beyond the available data). Raises ValueError if any
    of the three day counts is non-positive."""

    if train_days <= 0 or test_days <= 0 or step_days <= 0:
        raise ValueError("train_days, test_days, and step_days must all be > 0")
    if first_time > last_time:
        raise ValueError(f"first_time ({first_time}) must not be after last_time ({last_time})")

    windows = []
    train_start = first_time
    while True:
        train_end = train_start + pd.Timedelta(days=train_days)
        test_start = train_end
        test_end = test_start + pd.Timedelta(days=test_days)
        if test_start > last_time:
            break
        windows.append((train_start, train_end, test_start, test_end))
        train_start = train_start + pd.Timedelta(days=step_days)

    return windows


@dataclass(frozen=True)
class WindowMetrics:
    n: int
    win_rate: Optional[float]
    win_rate_ci_lower: Optional[float]
    win_rate_ci_upper: Optional[float]
    expectancy_r: Optional[float]
    expectancy_r_ci_lower: Optional[float]
    expectancy_r_ci_upper: Optional[float]


def _slice_metrics(
    slice_df: pd.DataFrame, seed: int, n_resamples: int = 2000, confidence: float = 0.95
) -> WindowMetrics:
    n = len(slice_df)
    if n == 0:
        return WindowMetrics(0, None, None, None, None, None, None)

    wr = None
    try:
        wr = win_rate((slice_df["profit"] > 0).tolist(), confidence=confidence)
    except InsufficientSampleError:
        pass

    exp = None
    try:
        # **Fixed, 2026-07-22 Codex review finding (fourth round):**
        # n_resamples/confidence were previously hard-wired to
        # expectancy()'s own hidden defaults and never exposed in the
        # persisted report at all.
        exp = expectancy(
            slice_df["r_multiple"].tolist(),
            n_resamples=n_resamples,
            seed=seed,
            confidence=confidence,
        )
    except InsufficientSampleError:
        pass

    return WindowMetrics(
        n=n,
        win_rate=wr.win_rate if wr else None,
        win_rate_ci_lower=wr.ci_lower if wr else None,
        win_rate_ci_upper=wr.ci_upper if wr else None,
        expectancy_r=exp.expectancy if exp else None,
        # exp.ci_lower/ci_upper are themselves None when exp.n < 2 (see
        # metrics.expectancy's own docstring) -- propagated as-is, not
        # coerced to a false-precision number.
        expectancy_r_ci_lower=exp.ci_lower if exp else None,
        expectancy_r_ci_upper=exp.ci_upper if exp else None,
    )


def _slice_window(trades: pd.DataFrame, start: pd.Timestamp, end: pd.Timestamp) -> pd.DataFrame:
    """A trade belongs to [start, end) only if BOTH its entry_time and
    exit_time fall inside that range -- see module docstring's "purged
    boundaries" note. A trade spanning the boundary is excluded from both
    the window it starts in and the window it ends in, rather than
    silently assigned to one by exit_time alone."""

    return trades[
        (trades["entry_time"] >= start)
        & (trades["entry_time"] < end)
        & (trades["exit_time"] >= start)
        & (trades["exit_time"] < end)
    ]


def run(
    trades_csv: Path,
    train_days: int,
    test_days: int,
    step_days: int,
    output_csv: Optional[Path] = None,
    summary_json: Optional[Path] = None,
    *,
    seed: int = 42,
    # **Added, 2026-07-22 Codex review finding (fourth round): these were
    # previously hard-wired to expectancy()'s/win_rate()'s own hidden
    # defaults and never exposed at the run()/CLI boundary or persisted
    # in the report, despite every per-window metric depending on them.**
    n_resamples: int = 2000,
    confidence: float = 0.95,
    symbol: Optional[str] = None,
    # **Added, 2026-07-22 Codex review finding (fourth round): spread_note/
    # slippage_note exist on ReportMetadata but no analysis caller exposed
    # or populated them.**
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> pd.DataFrame:
    """Returns a DataFrame with one row per window (train/test metrics
    both included, SUMMARY_COLUMNS in shape even when zero windows are
    generated). Raises CsvSchemaError/InsufficientSampleError the same
    way analyse_baseline.run does for structural input problems.

    'seed'/'n_resamples'/'confidence' feed every per-window expectancy
    bootstrap and win_rate Wilson interval (see module docstring's
    2026-07-22 correction) -- always explicit, never hidden."""

    # **Added, 2026-07-22 Codex review finding (fifth round): n_resamples/
    # confidence were previously validated only INSIDE _slice_metrics's
    # bootstrap call -- if zero windows were generated (or every window's
    # slice was too small to reach the bootstrap branch), that call, and
    # therefore the validation inside it, was never reached, silently
    # accepting e.g. n_resamples=0. Validated here UNCONDITIONALLY,
    # independent of how many windows the data actually produces.**
    if not (0.0 < confidence < 1.0):
        raise ValueError(f"confidence must be in (0, 1), got {confidence}")
    if not (MIN_N_RESAMPLES <= n_resamples <= MAX_N_RESAMPLES):
        raise ValueError(
            f"n_resamples must be in [{MIN_N_RESAMPLES}, {MAX_N_RESAMPLES}], got {n_resamples}"
        )

    # **Added, 2026-07-22 Codex review finding (sixth round): a caller
    # requesting output_csv without summary_json previously got a CSV
    # with NO accompanying provenance metadata anywhere. An implicit
    # sidecar path is now derived (matching join_trade_journal.py/
    # join_news_events.py/join_signal_to_outcome.py's own pattern),
    # derived FIRST so the collision checks below cover it too.**
    if summary_json is None and output_csv is not None:
        summary_json = output_csv.parent / f"{output_csv.stem}.summary.json"

    # Uses OS-level file-identity (not just Path.resolve()) so a hard
    # link to an input is also caught -- Codex review finding, third round.
    for out_path in (output_csv, summary_json):
        assert_path_not_same_file(out_path, trades_csv, "output path")
    assert_output_paths_distinct([output_csv, summary_json])

    # **Fixed, 2026-07-22 Codex review finding (sixth round): previously
    # read via the plain (non-hashing) helper, then re-read a second time
    # inside build_report_metadata below to compute its hash -- the same
    # ABA-mutation race round 5 already closed for
    # join_trade_journal.py/join_news_events.py/analyse_baseline.py but
    # left open here.**
    # **Fixed, 2026-07-22 Codex review finding (sixth round): 'trade_id'
    # was previously read via plain pandas type inference -- see
    # csv_io.TRADE_ID_DTYPE's own docstring for the exact counterexample
    # this closes.**
    trades, trades_csv_hash = read_csv_with_required_columns_and_hash(
        trades_csv, REQUIRED_COLUMNS, dtype=TRADE_ID_DTYPE
    )
    if trades.empty:
        raise InsufficientSampleError(f"{trades_csv}: zero trade rows")
    assert_unique_ids(trades, "trade_id", trades_csv)
    assert_finite_columns(trades, NUMERIC_COLUMNS, trades_csv)

    trades = trades.copy()
    trades["is_long"] = trades["is_long"].apply(parse_is_long)
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
    trades = trades.sort_values("exit_time")

    # **Fixed, 2026-07-22 Codex review finding:** window 0 was previously
    # anchored at the earliest EXIT time, while _slice_window requires
    # BOTH entry_time and exit_time to be at or after the window start.
    # Every positive-duration trade with the earliest exit necessarily
    # ENTERED before that anchor, so it could never appear in any window
    # -- the test suite had mislabelled this permanent exclusion as
    # "correct purged behavior". The overall analysis period now starts
    # at the earliest eligible ENTRY instead, so the earliest trade is at
    # least reachable by window 0 (still subject to the normal purging
    # rule if its exit falls outside that window).
    last_time = trades["exit_time"].max()
    windows = generate_windows(
        trades["entry_time"].min(), last_time, train_days, test_days, step_days
    )

    rows = []
    for i, (train_start, train_end, test_start, test_end) in enumerate(windows):
        train_slice = _slice_window(trades, train_start, train_end)
        test_slice = _slice_window(trades, test_start, test_end)

        train_m = _slice_metrics(train_slice, seed, n_resamples=n_resamples, confidence=confidence)
        test_m = _slice_metrics(test_slice, seed, n_resamples=n_resamples, confidence=confidence)

        rows.append(
            {
                "window_index": i,
                "train_start": train_start,
                "train_end": train_end,
                "test_start": test_start,
                "test_end": test_end,
                "train_n": train_m.n,
                "train_win_rate": train_m.win_rate,
                "train_win_rate_ci_lower": train_m.win_rate_ci_lower,
                "train_win_rate_ci_upper": train_m.win_rate_ci_upper,
                "train_expectancy_r": train_m.expectancy_r,
                "train_expectancy_r_ci_lower": train_m.expectancy_r_ci_lower,
                "train_expectancy_r_ci_upper": train_m.expectancy_r_ci_upper,
                "test_n": test_m.n,
                "test_win_rate": test_m.win_rate,
                "test_win_rate_ci_lower": test_m.win_rate_ci_lower,
                "test_win_rate_ci_upper": test_m.win_rate_ci_upper,
                "test_expectancy_r": test_m.expectancy_r,
                "test_expectancy_r_ci_lower": test_m.expectancy_r_ci_lower,
                "test_expectancy_r_ci_upper": test_m.expectancy_r_ci_upper,
            }
        )

    # Explicit column set even when 'rows' is empty (zero windows generated,
    # e.g. the data span is shorter than train_days+test_days) -- a Codex
    # review finding: pd.DataFrame([]) previously produced a DataFrame with
    # NO columns at all, and the summary_json block below then raised a
    # bare KeyError trying to access "test_expectancy_r" on it.
    result_df = pd.DataFrame(rows, columns=SUMMARY_COLUMNS)

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_dataframe_csv(result_df, output_csv)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [trades_csv],
            symbol=symbol,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=repo_path,
            dataset_hash_override=trades_csv_hash,
        )
        # pandas stores the "no test trades" case as NaN (float), not the
        # Python None _slice_metrics returned -- `r is not None` does NOT
        # filter NaN out (a Codex review finding, reproduced on this
        # module's own 5-trade test fixture: it silently wrote
        # `mean_test_expectancy_r: NaN`, a non-standard JSON token, instead
        # of the mean over the genuinely-valid windows). Use pd.notna().
        valid_test_expectancies = result_df["test_expectancy_r"][
            result_df["test_expectancy_r"].notna()
        ]
        # **Added, 2026-07-22 Codex review finding (fourth round):**
        # 'mean_test_expectancy_r' is an UNWEIGHTED mean of per-window
        # means (each window contributes equally regardless of its own
        # trade count) -- previously undocumented as such. Test windows
        # OVERLAP in time whenever step_days < test_days (a trade can
        # then appear in more than one window's test set, receiving
        # unequal effective weight across the whole report), and the
        # FINAL window's test period can be PARTIAL (shorter than
        # test_days) when the data span ends before that window's test
        # period would otherwise close -- both facts are now persisted
        # explicitly rather than left for a reader to infer.
        test_windows_overlap = step_days < test_days
        final_window_test_period_is_partial = bool(windows) and windows[-1][3] > last_time
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_windows": len(result_df),
                "train_days": train_days,
                "test_days": test_days,
                "step_days": step_days,
                "n_windows_with_test_data": int((result_df["test_n"] > 0).sum()),
                "mean_test_expectancy_r": (
                    float(valid_test_expectancies.mean()) if len(valid_test_expectancies) else None
                ),
                "mean_test_expectancy_r_estimand": (
                    "unweighted mean of per-window test_expectancy_r means "
                    "(NOT trade-count-weighted; a trade in an overlapping "
                    "window can be double-counted across windows -- see "
                    "test_windows_overlap)"
                ),
                "test_windows_overlap": test_windows_overlap,
                "final_window_test_period_is_partial": final_window_test_period_is_partial,
                # **Added, 2026-07-22 Codex review finding (third round):**
                # every per-window expectancy CI is a seeded bootstrap;
                # the seed must be reported, not left implicit.
                "seed": seed,
                # **Added, 2026-07-22 Codex review finding (fourth round):**
                # n_resamples/confidence were previously omitted from the
                # persisted report despite every per-window win_rate/
                # expectancy interval depending on them.
                "n_resamples": n_resamples,
                "confidence": confidence,
            },
        }
        atomic_write_text(summary_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return result_df


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--train-days", type=int, required=True)
    parser.add_argument("--test-days", type=int, required=True)
    parser.add_argument("--step-days", type=int, required=True)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--summary-json", type=Path, default=None)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--n-resamples", type=int, default=2000)
    parser.add_argument("--confidence", type=float, default=0.95)
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        result_df = run(
            trades_csv=args.trades_csv,
            train_days=args.train_days,
            test_days=args.test_days,
            step_days=args.step_days,
            output_csv=args.output_csv,
            summary_json=args.summary_json,
            seed=args.seed,
            n_resamples=args.n_resamples,
            confidence=args.confidence,
            symbol=args.symbol,
            spread_note=args.spread_note,
            slippage_note=args.slippage_note,
        )
    except (FileNotFoundError, CsvSchemaError, InsufficientSampleError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"walk_forward: {len(result_df)} windows generated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
