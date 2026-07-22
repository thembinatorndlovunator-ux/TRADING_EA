"""analyse_giveback.py -- offline simulation of ExitManager.mqh's (TASK-030)
two giveback-guard models (V6.37-style percent-of-peak, V8.11-style
absolute-R-floor) against historical bar data, to gather the "Phase 8
evidence" ExitManager.mqh's own header says is required before either
model is ever enabled live. **This script never controls, and cannot be
wired to, any live trading action -- it only answers "if this guard had
been active, would it have closed each trade earlier, and would that have
helped or hurt".**

Required input format (same rationale as calculate_mfe_mae.py -- no real
MT5 export exists yet to derive this from):

``trades.csv`` columns: ``trade_id, symbol, is_long, entry_time, exit_time,
entry_price, stop_price`` and OPTIONALLY ``exit_price`` (if present and
non-null, used as the actual close R instead of the last bar's close --
the more accurate figure when available).

``bars.csv`` columns: ``symbol, timestamp, close`` -- note this is
CLOSE-price-based (a documented simplification: the live guard would check
current bid/ask every tick; a bar-close proxy is what offline analysis at
bar granularity can reasonably provide) -- distinct from
calculate_mfe_mae.py's high/low-based bars.csv.

**Bar-timestamp convention, declared explicitly (Codex review finding,
2026-07-22, third round): 'timestamp' is the bar's CLOSE time** -- the
natural convention here since the R-path is built by walking bar CLOSE
prices one at a time (each close represents "the R multiple as of this
bar closing"), unlike calculate_mfe_mae.py's bar-OPEN convention (which
walks high/low RANGES, not point-in-time closes). entry_time/exit_time
must each exactly match a bar timestamp for that trade's symbol --
without this, a trade like 00:30-01:30 with only a 01:00 bar previously
completed with ZERO row errors despite neither endpoint being covered by
any real bar, silently treating an arbitrary sub-bar-resolution timestamp
as if it aligned with actual price data.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import pandas as pd

from analysis.csv_io import (
    TRADE_ID_DTYPE,
    CsvSchemaError,
    assert_finite_columns,
    assert_output_paths_distinct,
    assert_path_not_same_file,
    assert_unique_composite_key,
    assert_unique_ids,
    atomic_write_dataframe_csv,
    parse_is_long,
    read_csv_with_required_columns_and_hash,
    sanitize_dataframe_for_csv,
)
from analysis.exit_simulation import simulate_giveback_path
from analysis.metrics import (
    MAX_N_RESAMPLES,
    MIN_N_RESAMPLES,
    InsufficientSampleError,
    bootstrap_confidence_interval,
    win_rate,
)
from analysis.report_metadata import (
    atomic_write_text,
    build_report_metadata,
    combine_labeled_hashes,
)
from analysis.time_utils import parse_iso8601_utc, parse_utc_series
from analysis.trade_math import (
    assert_complete_bar_coverage,
    compute_r_multiple,
)

REQUIRED_TRADE_COLUMNS = {
    "trade_id",
    "symbol",
    "is_long",
    "entry_time",
    "exit_time",
    "entry_price",
    "stop_price",
}
REQUIRED_BAR_COLUMNS = {"symbol", "timestamp", "close"}


@dataclass(frozen=True)
class TradeGivebackComparison:
    trade_id: str
    actual_final_r: float
    v637_trigger_bar: Optional[int]
    v637_trigger_r: Optional[float]
    v637_r_diff: float  # trigger_r - actual_final_r: positive means the
    # guard would have closed at a BETTER R than the
    # trade actually ended with (guard would have
    # helped); negative means it would have closed
    # early and hurt. 0.0 if the guard never triggered.
    v811_trigger_bar: Optional[int]
    v811_trigger_r: Optional[float]
    v811_r_diff: float


@dataclass(frozen=True)
class GivebackRunResult:
    comparisons: list[TradeGivebackComparison]
    row_errors: list[dict]


def run(
    trades_csv: Path,
    bars_csv: Path,
    output_csv: Optional[Path] = None,
    summary_json: Optional[Path] = None,
    *,
    v637_arm_rr: float = 1.25,
    v637_giveback_percent: float = 60.0,
    v637_floor_r: float = 0.05,
    v811_arm_r: float = 0.8,
    v811_floor_r: float = 0.1,
    # **Added, 2026-07-22 Codex review finding (fifth round): REQUIRED --
    # see trade_math.IncompleteBarCoverageError's own docstring. Endpoint
    # alignment of entry_time/exit_time to SOME bar does not guarantee
    # every bar in between is also present; a caller must declare what
    # cadence bars_csv is actually supposed to be at so a gap can be
    # detected instead of silently accepted as a sparse-but-complete path.
    expected_cadence_minutes: float,
    symbol: Optional[str] = None,
    # **Fixed, 2026-07-22 Codex review finding (third round): this was
    # 'Optional[int] = None', combined with a call site using
    # 'seed or 42' -- an explicit seed=0 is falsy in Python, so it was
    # silently replaced by 42 while metadata still reported the caller's
    # real seed of 0, a real reproducibility-breaking mismatch. Always an
    # explicit int now, matching monte_carlo.py/compare_releases.py.**
    seed: int = 42,
    # **Added, 2026-07-22 Codex review finding (fifth round): the two
    # bootstrap calls below previously hard-coded n_resamples=2000/
    # confidence=0.95 (matching bootstrap_confidence_interval's own
    # defaults) with no way for a caller to override or even discover
    # what was actually used -- the persisted summary independently
    # hard-coded the SAME two literals rather than reporting the real
    # values.**
    n_resamples: int = 2000,
    confidence: float = 0.95,
    # **Added, 2026-07-22 Codex review finding (fourth round): spread_note/
    # slippage_note exist on ReportMetadata but no analysis caller exposed
    # or populated them.**
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> GivebackRunResult:
    # **Added, 2026-07-22 Codex review finding (fourth round):** none of
    # the five giveback-model parameters were validated or persisted --
    # passing NaN for all five previously produced "valid" comparisons
    # with zero row errors, because should_giveback_close_v637/v811's own
    # max()/min() clamps silently select an effective value from a NaN
    # input (Python's max(a, nan) returns 'a', since 'nan > a' is False).
    # A caller-supplied NaN/inf is not a legitimate model configuration
    # (unlike a merely out-of-range-but-finite value, which mirrors the
    # live guard's own deliberate clamp behavior) and must be rejected
    # outright rather than silently substituted.
    model_params = {
        "v637_arm_rr": v637_arm_rr,
        "v637_giveback_percent": v637_giveback_percent,
        "v637_floor_r": v637_floor_r,
        "v811_arm_r": v811_arm_r,
        "v811_floor_r": v811_floor_r,
    }
    non_finite_params = {
        name: value for name, value in model_params.items() if not math.isfinite(value)
    }
    if non_finite_params:
        raise ValueError(
            f"analyse_giveback: model parameters must be finite, got non-finite: {non_finite_params}"
        )
    # **Added, 2026-07-22 Codex review finding (fifth round): n_resamples/
    # confidence were previously validated only INSIDE the two
    # bootstrap_confidence_interval calls below, each gated on its own
    # subset having >= 2 observations -- a caller passing n_resamples=0
    # was silently accepted whenever both subsets were too small to ever
    # reach either call. Validated here UNCONDITIONALLY, independent of
    # how many trades/triggers the data actually produces.**
    if not (0.0 < confidence < 1.0):
        raise ValueError(f"confidence must be in (0, 1), got {confidence}")
    if not (MIN_N_RESAMPLES <= n_resamples <= MAX_N_RESAMPLES):
        raise ValueError(
            f"n_resamples must be in [{MIN_N_RESAMPLES}, {MAX_N_RESAMPLES}], got {n_resamples}"
        )
    # The effective (post-clamp) values applied by exit_simulation.py's own
    # should_giveback_close_v637/v811 -- mirrored here (not re-derived) so
    # the requested vs. effective distinction can be disclosed in the
    # summary artifact even when a caller passes an out-of-range-but-finite
    # setting that gets silently clamped downstream.
    effective_params = {
        "v637_arm_rr": max(0.25, v637_arm_rr),
        "v637_giveback_percent": max(10.0, min(90.0, v637_giveback_percent)),
        "v637_floor_r": v637_floor_r,
        "v811_arm_r": max(0.3, v811_arm_r),
        "v811_floor_r": max(0.0, v811_floor_r),
    }

    # **Added, 2026-07-22 Codex review finding (sixth round): a caller
    # requesting output_csv without summary_json previously got a CSV
    # with NO accompanying provenance metadata anywhere -- "mandatory,
    # reproducible provenance" was actually separable from the result.
    # An implicit sidecar path is now derived (matching the same pattern
    # already used by join_trade_journal.py/join_news_events.py/
    # join_signal_to_outcome.py) so requesting output_csv alone still
    # gets its metadata written, derived FIRST so the collision checks
    # below cover it too.**
    if summary_json is None and output_csv is not None:
        summary_json = output_csv.parent / f"{output_csv.stem}.summary.json"

    # Uses OS-level file-identity (not just Path.resolve()) so a hard
    # link to an input is also caught -- Codex review finding, third round.
    for out_path in (output_csv, summary_json):
        assert_path_not_same_file(out_path, trades_csv, "output path")
        assert_path_not_same_file(out_path, bars_csv, "output path")
    assert_output_paths_distinct([output_csv, summary_json])

    # **Fixed, 2026-07-22 Codex review finding (sixth round): both files
    # were previously read via the plain (non-hashing) helper, and
    # 'build_report_metadata' below then re-read them a SECOND time to
    # compute their hash -- the exact ABA-mutation race round 5 already
    # closed for join_trade_journal.py/join_news_events.py/
    # analyse_baseline.py but left open here. A deterministic probe
    # (mutate between reads, restore, rehash-matches-original) previously
    # produced a summary whose metadata hash did not correspond to the
    # rows actually analyzed. Reading once and hashing from that same
    # pass, then combining both files' hashes below, closes the race
    # structurally rather than merely detecting it.**
    # **Fixed, 2026-07-22 Codex review finding (sixth round): 'trade_id'
    # was previously read via plain pandas type inference -- see
    # csv_io.TRADE_ID_DTYPE's own docstring for the exact counterexample
    # this closes.**
    trades, trades_csv_hash = read_csv_with_required_columns_and_hash(
        trades_csv, REQUIRED_TRADE_COLUMNS, dtype=TRADE_ID_DTYPE
    )
    bars, bars_csv_hash = read_csv_with_required_columns_and_hash(bars_csv, REQUIRED_BAR_COLUMNS)
    # **Fixed, 2026-07-22 Codex review finding:** a header-only (zero-row)
    # trades.csv previously produced a "successful" empty run instead of a
    # visible insufficient-sample failure.
    if trades.empty:
        raise CsvSchemaError(f"{trades_csv}: zero trade rows (header-only input)")
    assert_unique_ids(trades, "trade_id", trades_csv)
    assert_finite_columns(trades, ["entry_price", "stop_price"], trades_csv)
    assert_finite_columns(bars, ["close"], bars_csv)

    # **Fixed, 2026-07-22 Codex review finding (fourth round): the
    # duplicate-(symbol, timestamp) check previously ran on the RAW
    # string timestamp column, BEFORE UTC normalization -- two raw
    # spellings of the same instant ("...Z" and "...+00:00") pass as
    # distinct strings, then become the same instant once parsed. Parse
    # first, then enforce canonical-time uniqueness.**
    bars = bars.copy()
    bars["timestamp"] = parse_utc_series(bars["timestamp"])
    assert_unique_composite_key(bars, ["symbol", "timestamp"], bars_csv)

    comparisons: list[TradeGivebackComparison] = []
    row_errors: list[dict] = []

    for _, row in trades.iterrows():
        trade_id = str(row["trade_id"])
        try:
            is_long = parse_is_long(row["is_long"])
            entry_time = parse_iso8601_utc(str(row["entry_time"]))
            exit_time = parse_iso8601_utc(str(row["exit_time"]))
            entry_price = float(row["entry_price"])
            stop_price = float(row["stop_price"])
            if is_long and stop_price >= entry_price:
                raise ValueError(
                    f"trade_id={trade_id}: long trade stop_price ({stop_price}) must be below "
                    f"entry_price ({entry_price})"
                )
            if not is_long and stop_price <= entry_price:
                raise ValueError(
                    f"trade_id={trade_id}: short trade stop_price ({stop_price}) must be above "
                    f"entry_price ({entry_price})"
                )

            symbol_all_bars = bars[bars["symbol"] == row["symbol"]]
            symbol_bar_timestamps = set(symbol_all_bars["timestamp"])
            if entry_time not in symbol_bar_timestamps:
                row_errors.append(
                    {
                        "trade_id": trade_id,
                        "error": f"entry_time ({entry_time}) does not match any bar timestamp for "
                        f"symbol {row['symbol']!r} (bar timestamps are bar-CLOSE times)",
                    }
                )
                continue
            if exit_time not in symbol_bar_timestamps:
                row_errors.append(
                    {
                        "trade_id": trade_id,
                        "error": f"exit_time ({exit_time}) does not match any bar timestamp for "
                        f"symbol {row['symbol']!r} (bar timestamps are bar-CLOSE times)",
                    }
                )
                continue

            symbol_bars = symbol_all_bars[
                (symbol_all_bars["timestamp"] >= entry_time)
                & (symbol_all_bars["timestamp"] <= exit_time)
            ].sort_values("timestamp")

            if symbol_bars.empty:
                row_errors.append({"trade_id": trade_id, "error": "no bars found in trade window"})
                continue

            # **Added, 2026-07-22 Codex review finding (fifth round):**
            # endpoint alignment (checked above) does not guarantee every
            # bar IN BETWEEN is also present -- see
            # trade_math.IncompleteBarCoverageError's own docstring for
            # the exact reproduced counterexample
            # (calculate_mfe_mae.py's, but the same gap existed here).
            # This window is INCLUSIVE of exit_time (bar-CLOSE
            # convention, unlike calculate_mfe_mae.py's half-open one) --
            # shifting the end by one cadence makes the same
            # half-open-window coverage math apply without changing it.
            assert_complete_bar_coverage(
                symbol_bars["timestamp"],
                entry_time,
                exit_time + pd.Timedelta(minutes=expected_cadence_minutes),
                expected_cadence_minutes,
                trade_id,
            )

            r_path = [
                compute_r_multiple(is_long, entry_price, stop_price, close)
                for close in symbol_bars["close"]
            ]

            has_exit_price = "exit_price" in trades.columns and pd.notna(row.get("exit_price"))
            if has_exit_price:
                # **Fixed, 2026-07-22 Codex review finding:** the optional
                # exit_price column was never checked for finiteness when
                # populated -- `pd.notna(inf)` is True, so an infinite
                # exit_price could reach compute_r_multiple and produce an
                # infinite actual_final_r.
                exit_price_val = float(row["exit_price"])
                if not math.isfinite(exit_price_val):
                    raise ValueError(
                        f"trade_id={trade_id}: exit_price ({exit_price_val}) is not finite"
                    )
                actual_final_r = compute_r_multiple(
                    is_long, entry_price, stop_price, exit_price_val
                )
            else:
                actual_final_r = r_path[-1]

            v637_result = simulate_giveback_path(
                r_path,
                "v637",
                arm_rr=v637_arm_rr,
                giveback_percent=v637_giveback_percent,
                close_trigger_floor_r=v637_floor_r,
            )
            v811_result = simulate_giveback_path(
                r_path, "v811", arm_r=v811_arm_r, floor_r=v811_floor_r
            )

            v637_bar, v637_r = v637_result if v637_result else (None, None)
            v811_bar, v811_r = v811_result if v811_result else (None, None)

            comparisons.append(
                TradeGivebackComparison(
                    trade_id=trade_id,
                    actual_final_r=actual_final_r,
                    v637_trigger_bar=v637_bar,
                    v637_trigger_r=v637_r,
                    v637_r_diff=(v637_r - actual_final_r) if v637_r is not None else 0.0,
                    v811_trigger_bar=v811_bar,
                    v811_trigger_r=v811_r,
                    v811_r_diff=(v811_r - actual_final_r) if v811_r is not None else 0.0,
                )
            )
        except (ValueError, KeyError) as exc:
            row_errors.append({"trade_id": trade_id, "error": str(exc)})

    if output_csv is not None:
        # trade_id is a caller-controlled string -- sanitized against
        # spreadsheet-formula injection (Codex review finding,
        # 2026-07-22, third round). Written atomically (temp-then-rename).
        atomic_write_dataframe_csv(
            sanitize_dataframe_for_csv(pd.DataFrame([c.__dict__ for c in comparisons])), output_csv
        )

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        combined_hash = combine_labeled_hashes(
            [(trades_csv.name, trades_csv_hash), (bars_csv.name, bars_csv_hash)]
        )
        metadata = build_report_metadata(
            [trades_csv, bars_csv],
            symbol=symbol,
            random_seed=seed,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=repo_path,
            dataset_hash_override=combined_hash,
        )
        summary = {
            "metadata": metadata.to_dict(),
            "n_trades_compared": len(comparisons),
            "n_row_errors": len(row_errors),
            "row_errors": row_errors,
            # **Added, 2026-07-22 Codex review finding (fourth round):**
            # requested vs. effective (post-clamp) model parameters are
            # both persisted, so an out-of-range-but-finite setting's
            # silent clamp is disclosed in the artifact rather than
            # hidden.
            "requested_model_params": model_params,
            "effective_model_params": effective_params,
        }
        for model in ("v637", "v811"):
            triggered = [c for c in comparisons if getattr(c, f"{model}_trigger_r") is not None]
            # **Note (Codex review finding, 2026-07-22):** this mean is
            # CONDITIONAL on this model's own trigger subset -- v637's and
            # v811's triggered subsets are generally different trades, so
            # this figure must never be read as a like-for-like comparison
            # between the two models without accounting for that.
            mean_r_diff = None
            r_diff_ci_lower = None
            r_diff_ci_upper = None
            if triggered:
                mean_r_diff = sum(getattr(c, f"{model}_r_diff") for c in triggered) / len(triggered)
                # A bootstrap CI needs >= 2 observations; below that the
                # mean is reported alone, per metrics.expectancy's own
                # None-uncertainty convention for n < 2 (Codex review
                # finding: this mean previously had NO interval at all).
                if len(triggered) >= 2:
                    r_diffs = [getattr(c, f"{model}_r_diff") for c in triggered]
                    boot = bootstrap_confidence_interval(
                        r_diffs,
                        statistic="mean",
                        seed=seed,
                        n_resamples=n_resamples,
                        confidence=confidence,
                    )
                    r_diff_ci_lower = boot.ci_lower
                    r_diff_ci_upper = boot.ci_upper
            # **Added, 2026-07-22 Codex review finding (fourth round):**
            # the conditional mean above cannot be compared like-for-like
            # between v637 and v811 (their triggered subsets are
            # generally different trades of different sizes) -- a
            # full-cohort mean effect magnitude, using the SAME
            # denominator (every comparison) and r_diff's own documented
            # 0.0-when-never-triggered convention for both models, is the
            # actual like-for-like comparison figure.
            full_cohort_r_diffs = [getattr(c, f"{model}_r_diff") for c in comparisons]
            mean_r_diff_full_cohort = (
                sum(full_cohort_r_diffs) / len(full_cohort_r_diffs) if full_cohort_r_diffs else None
            )
            full_cohort_ci_lower = None
            full_cohort_ci_upper = None
            if len(full_cohort_r_diffs) >= 2:
                boot_full = bootstrap_confidence_interval(
                    full_cohort_r_diffs,
                    statistic="mean",
                    seed=seed,
                    n_resamples=n_resamples,
                    confidence=confidence,
                )
                full_cohort_ci_lower = boot_full.ci_lower
                full_cohort_ci_upper = boot_full.ci_upper
            model_summary: dict = {
                "n_triggered": len(triggered),
                "n_not_triggered": len(comparisons) - len(triggered),
                "mean_r_diff_when_triggered": mean_r_diff,
                "mean_r_diff_when_triggered_ci_lower": r_diff_ci_lower,
                "mean_r_diff_when_triggered_ci_upper": r_diff_ci_upper,
                # **Added, 2026-07-22 Codex review finding (third round):**
                # confidence/resample count were previously omitted from
                # the persisted output entirely. **Fixed, 2026-07-22 Codex
                # review finding (fifth round): these previously hard-coded
                # the LITERALS 0.95/2000 (matching bootstrap_confidence_
                # interval's own defaults) instead of the caller's actual
                # 'confidence'/'n_resamples' arguments -- a caller who
                # overrode either got a report that silently lied about
                # what was actually used.**
                "mean_r_diff_confidence": confidence if len(triggered) >= 2 else None,
                "mean_r_diff_n_resamples": n_resamples if len(triggered) >= 2 else None,
                "mean_r_diff_seed": seed if len(triggered) >= 2 else None,
                "mean_r_diff_full_cohort": mean_r_diff_full_cohort,
                "mean_r_diff_full_cohort_ci_lower": full_cohort_ci_lower,
                "mean_r_diff_full_cohort_ci_upper": full_cohort_ci_upper,
                "mean_r_diff_full_cohort_confidence": (
                    confidence if len(full_cohort_r_diffs) >= 2 else None
                ),
                "mean_r_diff_full_cohort_n_resamples": (
                    n_resamples if len(full_cohort_r_diffs) >= 2 else None
                ),
                "mean_r_diff_full_cohort_seed": seed if len(full_cohort_r_diffs) >= 2 else None,
            }
            if triggered:
                # **Renamed, 2026-07-22 Codex review finding (third
                # round):** the old name "guard_helped_rate" read as a
                # full-cohort policy rate but was silently conditional on
                # this model's own triggered subset -- one helpful trigger
                # among 100 total trades would be reported as 100%, not
                # 1%. The `_when_triggered` suffix makes that scope
                # explicit, and a full-cohort rate is now also reported
                # alongside it so both questions ("how often does the
                # guard help when it fires?" vs. "how often does the
                # guard help across every trade?") are answerable.
                try:
                    wr = win_rate(
                        [getattr(c, f"{model}_r_diff") > 0.0 for c in triggered],
                        confidence=confidence,
                    )
                    model_summary["guard_helped_rate_when_triggered"] = wr.win_rate
                    model_summary["guard_helped_rate_when_triggered_ci"] = [
                        wr.ci_lower,
                        wr.ci_upper,
                    ]
                    model_summary["guard_helped_rate_when_triggered_n"] = wr.n
                    # **Added, 2026-07-22 Codex review finding (fourth
                    # round): the Wilson confidence level used for this
                    # interval was never persisted, unlike the
                    # mean_r_diff_confidence field above.**
                    model_summary["guard_helped_rate_when_triggered_confidence"] = wr.confidence
                except InsufficientSampleError:
                    pass
            try:
                full_cohort_outcomes = [
                    getattr(c, f"{model}_trigger_r") is not None
                    and getattr(c, f"{model}_r_diff") > 0.0
                    for c in comparisons
                ]
                wr_full = win_rate(full_cohort_outcomes, confidence=confidence)
                model_summary["guard_helped_rate_full_cohort"] = wr_full.win_rate
                model_summary["guard_helped_rate_full_cohort_ci"] = [
                    wr_full.ci_lower,
                    wr_full.ci_upper,
                ]
                model_summary["guard_helped_rate_full_cohort_n"] = wr_full.n
                model_summary["guard_helped_rate_full_cohort_confidence"] = wr_full.confidence
            except InsufficientSampleError:
                pass
            summary[model] = model_summary
        atomic_write_text(summary_json, json.dumps(summary, indent=2, default=str, allow_nan=False))

    return GivebackRunResult(comparisons=comparisons, row_errors=row_errors)


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--bars-csv", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--summary-json", type=Path, default=None)
    parser.add_argument("--v637-arm-rr", type=float, default=1.25)
    parser.add_argument("--v637-giveback-percent", type=float, default=60.0)
    parser.add_argument("--v637-floor-r", type=float, default=0.05)
    parser.add_argument("--v811-arm-r", type=float, default=0.8)
    parser.add_argument("--v811-floor-r", type=float, default=0.1)
    # **Added, 2026-07-22 Codex review finding (fifth round): required --
    # see run()'s own comment.**
    parser.add_argument("--expected-cadence-minutes", type=float, required=True)
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--n-resamples", type=int, default=2000)
    parser.add_argument("--confidence", type=float, default=0.95)
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        result = run(
            trades_csv=args.trades_csv,
            bars_csv=args.bars_csv,
            output_csv=args.output_csv,
            summary_json=args.summary_json,
            v637_arm_rr=args.v637_arm_rr,
            v637_giveback_percent=args.v637_giveback_percent,
            v637_floor_r=args.v637_floor_r,
            v811_arm_r=args.v811_arm_r,
            v811_floor_r=args.v811_floor_r,
            expected_cadence_minutes=args.expected_cadence_minutes,
            symbol=args.symbol,
            seed=args.seed,
            n_resamples=args.n_resamples,
            confidence=args.confidence,
            spread_note=args.spread_note,
            slippage_note=args.slippage_note,
        )
    except (FileNotFoundError, CsvSchemaError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"analyse_giveback: {len(result.comparisons)} compared, {len(result.row_errors)} row errors."
    )
    return 1 if result.row_errors else 0


if __name__ == "__main__":
    sys.exit(main())
