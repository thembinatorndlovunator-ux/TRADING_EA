"""analyse_baseline.py -- aggregate performance summary over a normalized
trade-export CSV: win rate (with Wilson CI), expectancy ($  and R), profit
factor, max drawdown, net profit, recovery factor, equity-peak giveback,
longest losing streak, average winner/loser, average trade duration, and
trades-per-day on the resulting BALANCE curve -- **extended, 2026-07-22
Codex review finding (fourth round): every one of these except win rate/
expectancy/profit factor/max drawdown was previously absent, despite
TEST_PLAN.md naming all of them as the minimum baseline-comparison
surface.** Spread/slippage SENSITIVITY (running the same trades through
multiple assumed cost scenarios) remains a separate, larger deliverable
-- not attempted here; ``spread_note``/``slippage_note`` record a single
caller-asserted cost assumption as provenance, they do not vary it.

**Balance, not equity, and stated explicitly (Codex review finding,
2026-07-21):** the curve this module builds is cumulative CLOSED-TRADE
P/L only -- it contains no mark-to-market value for any still-open
position, so it is a balance curve, not an equity curve. `TEST_PLAN.md`
requires both a max BALANCE drawdown and a max EQUITY drawdown as
separate figures; this module only ever produces the former. A true
equity curve needs an actual time series of account equity (including
floating P/L), which this project does not have yet (see
TASK-028_PYTHON_STATISTICAL_LAB.md's Risks section).

Required input format (documented here since neither baseline EA has a
committed real trade export yet -- 01_BASELINE/ contains only source code,
screenshots, and set files, no trade history):

``trades.csv`` columns: ``trade_id, symbol, is_long, entry_time, exit_time,
entry_price, exit_price, stop_price, profit`` -- ``profit`` is the NET
account-currency P/L (commission and swap already netted in, matching how
an MT5 "Deals" export's own profit column normally already nets these in
per deal); a future task bridging a real MT5 HTML/XLSX statement export
into this CSV shape is separate work, not attempted here.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Optional

from analysis.csv_io import (
    CsvSchemaError,
    assert_chronological_order,
    assert_finite_columns,
    assert_output_paths_distinct,
    assert_path_not_same_file,
    assert_unique_ids,
    assert_valid_stop_geometry,
    atomic_write_dataframe_csv,
    parse_is_long,
    read_csv_with_required_columns,
    sanitize_dataframe_for_csv,
)
from analysis.metrics import (
    InsufficientSampleError,
    compute_equity_peak_giveback,
    compute_max_drawdown,
    expectancy,
    profit_factor,
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
NUMERIC_COLUMNS = ("entry_price", "exit_price", "stop_price", "profit")


def run(
    trades_csv: Path,
    output_json: Optional[Path] = None,
    per_trade_csv: Optional[Path] = None,
    *,
    starting_balance: float = 1000.0,
    symbol: Optional[str] = None,
    broker: Optional[str] = None,
    # **Fixed, 2026-07-22 Codex review finding (third round): this was
    # never forwarded to the expectancy() bootstrap calls below at all --
    # they always silently used expectancy()'s own default seed 42
    # regardless of what a caller passed here. Always an explicit int
    # now, matching monte_carlo.py/compare_releases.py.**
    seed: int = 42,
    ea_version: Optional[str] = None,
    data_source: Optional[str] = None,
    # **Added, 2026-07-22 Codex review finding (fourth round): the
    # master-prompt-required "Equity-peak giveback" metric -- see
    # metrics.compute_equity_peak_giveback's own docstring for the ported
    # formula. Defaults match TASK-002_PHASE2_SPECIFICATION.md's own
    # "Daily equity-peak giveback" defaults (InpDailyGivebackArmPercent/
    # InpDailyGivebackFloorPercent), reused here for the ACCOUNT-scope
    # variant since the spec gives no separate default for it.
    giveback_arm_percent: float = 1.0,
    giveback_floor_percent: float = 0.5,
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> dict:
    """Reads 'trades_csv', computes the aggregate summary, and (if given)
    writes it to 'output_json' plus a per-trade CSV (with the computed
    r_multiple column added) to 'per_trade_csv'. Returns the summary dict
    unconditionally so a caller (test or notebook) can inspect it without
    touching disk.

    Raises CsvSchemaError if a required column is missing, a duplicate
    trade_id exists, a numeric column has a non-finite/missing value, or
    an output path collides with the input path. Raises
    InsufficientSampleError if the file has zero trade rows, or if
    'starting_balance' is not strictly positive (percentage drawdown is
    undefined otherwise -- see metrics.compute_max_drawdown).
    """

    # **Fixed, 2026-07-22 Codex review finding:** `starting_balance <= 0`
    # is False for NaN (every comparison against NaN is False in Python),
    # so a NaN starting_balance previously passed this check and produced
    # a NaN final balance with a plausible-looking 0.0 drawdown in memory
    # instead of a visible error.
    if not math.isfinite(starting_balance) or starting_balance <= 0:
        raise InsufficientSampleError(
            f"analyse_baseline.run: starting_balance must be a finite number > 0, got {starting_balance}"
        )
    # **Fixed, 2026-07-22 Codex review finding (third round): comparing
    # only Path.resolve() let a hard link to trades_csv pass this check
    # (different resolved name, identical underlying file) -- a direct
    # probe used a hard-linked output path to overwrite trades_csv's own
    # inode. assert_path_not_same_file also checks OS-level file identity.
    for out_path in (output_json, per_trade_csv):
        assert_path_not_same_file(out_path, trades_csv, "output path")
    assert_output_paths_distinct([output_json, per_trade_csv])

    trades = read_csv_with_required_columns(trades_csv, REQUIRED_COLUMNS)
    if trades.empty:
        raise InsufficientSampleError(f"{trades_csv}: zero trade rows")
    assert_unique_ids(trades, "trade_id", trades_csv)
    assert_finite_columns(trades, NUMERIC_COLUMNS, trades_csv)

    trades = trades.copy()
    trades["is_long"] = trades["is_long"].apply(parse_is_long)
    # **Fixed, 2026-07-22 Codex review finding:** `pd.to_datetime(...,
    # utc=True)` silently treats a naive string (no "Z"/offset) as if it
    # were already UTC -- a direct probe with no "Z" or offset was
    # accepted as a valid trade. `parse_utc_series` rejects any naive or
    # non-UTC timestamp instead (already used by every other pipeline in
    # this layer; this script had been missed).
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

    trades_sorted = trades.sort_values("exit_time")

    # **Fixed, 2026-07-22 Codex review finding:** sorting only by
    # exit_time leaves ties (multiple trades closing at the identical
    # instant) in an ARBITRARY order (pandas' sort is stable against
    # input row order, which is itself just CSV row order -- not a
    # durable deal sequence). Reversing two same-time win/loss rows
    # changed the independently observed max drawdown from 10.0% to
    # ~9.09% with identical timestamps and net P/L. Since this schema has
    # no durable intra-timestamp deal sequence field, same-instant P/L is
    # now SUMMED into one balance step before computing drawdown -- the
    # drawdown calculation no longer depends on an arbitrary tie-break
    # order, though per-trade win-rate/expectancy below still use every
    # individual row (order-independent statistics).
    balance_steps = trades_sorted.groupby("exit_time", sort=True)["profit"].sum()
    balance_curve = [starting_balance] + list(starting_balance + balance_steps.cumsum())

    profits = trades_sorted["profit"].tolist()
    r_multiples = trades_sorted["r_multiple"].tolist()

    wr = win_rate([p > 0 for p in profits])
    exp_dollars = expectancy(profits, seed=seed)
    exp_r = expectancy(r_multiples, seed=seed)
    pf = profit_factor(profits)
    dd = compute_max_drawdown(balance_curve)
    # **Added, 2026-07-22 Codex review finding (fourth round): TEST_PLAN.md's
    # required minimum comparability surface (recovery factor, longest
    # losing streak, average winner/loser, duration, trades/day) was
    # computable from this schema but never reported by any pipeline.**
    giveback = compute_equity_peak_giveback(
        balance_curve, arm_percent=giveback_arm_percent, floor_percent=giveback_floor_percent
    )
    net_profit = balance_curve[-1] - starting_balance
    recovery_factor = net_profit / dd.max_drawdown_abs if dd.max_drawdown_abs > 0 else None

    longest_losing_streak = 0
    current_losing_streak = 0
    for p in profits:
        if p < 0:
            current_losing_streak += 1
            longest_losing_streak = max(longest_losing_streak, current_losing_streak)
        else:
            current_losing_streak = 0

    winners = [p for p in profits if p > 0]
    losers = [p for p in profits if p < 0]
    avg_winner = sum(winners) / len(winners) if winners else None
    avg_loser = sum(losers) / len(losers) if losers else None

    durations_minutes = (
        trades_sorted["exit_time"] - trades_sorted["entry_time"]
    ).dt.total_seconds() / 60.0
    avg_trade_duration_minutes = float(durations_minutes.mean())

    period_days = (
        trades_sorted["exit_time"].max() - trades_sorted["entry_time"].min()
    ).total_seconds() / 86400.0
    trades_per_day = (len(trades_sorted) / period_days) if period_days > 0 else None

    summary = {
        "n_trades": len(trades_sorted),
        "win_rate": {
            "value": wr.win_rate,
            "ci_lower": wr.ci_lower,
            "ci_upper": wr.ci_upper,
            "confidence": wr.confidence,
            "n": wr.n,
        },
        "expectancy_dollars": {
            "value": exp_dollars.expectancy,
            "std_dev": exp_dollars.std_dev,
            "n": exp_dollars.n,
            # **Added, 2026-07-22 Codex review finding (third round):**
            # the expectancy CI/confidence/resample-count/seed were
            # computed by expectancy() but discarded before reaching this
            # summary.
            "ci_lower": exp_dollars.ci_lower,
            "ci_upper": exp_dollars.ci_upper,
            "confidence": exp_dollars.confidence,
            "n_resamples": exp_dollars.n_resamples,
            "seed": exp_dollars.seed,
        },
        "expectancy_r": {
            "value": exp_r.expectancy,
            "std_dev": exp_r.std_dev,
            "n": exp_r.n,
            "ci_lower": exp_r.ci_lower,
            "ci_upper": exp_r.ci_upper,
            "confidence": exp_r.confidence,
            "n_resamples": exp_r.n_resamples,
            "seed": exp_r.seed,
        },
        "profit_factor": pf.profit_factor,
        "gross_profit": pf.gross_profit,
        "gross_loss": pf.gross_loss,
        "max_balance_drawdown_abs": dd.max_drawdown_abs,
        "max_balance_drawdown_pct": dd.max_drawdown_pct,
        "max_balance_drawdown_abs_peak_index": dd.max_drawdown_abs_peak_index,
        "max_balance_drawdown_abs_trough_index": dd.max_drawdown_abs_trough_index,
        "max_balance_drawdown_pct_peak_index": dd.max_drawdown_pct_peak_index,
        "max_balance_drawdown_pct_trough_index": dd.max_drawdown_pct_trough_index,
        "max_equity_drawdown": None,  # not computable -- see module docstring
        "final_balance": balance_curve[-1],
        "starting_balance": starting_balance,
        # **Added, 2026-07-22 Codex review finding (fourth round): the
        # remaining minimum comparability surface TEST_PLAN.md requires.**
        "net_profit": net_profit,
        "recovery_factor": recovery_factor,
        "equity_peak_giveback": {
            "arm_percent": giveback.arm_percent,
            "floor_percent": giveback.floor_percent,
            "armed": giveback.armed,
            "n_trigger_events": giveback.n_trigger_events,
            "trigger_indices": giveback.trigger_indices,
            "max_giveback_pct": giveback.max_giveback_pct,
            "max_giveback_pct_index": giveback.max_giveback_pct_index,
            "note": "BALANCE-based (not equity), same disclosed limitation as the rest of this module",
        },
        "longest_losing_streak": longest_losing_streak,
        "avg_winner_dollars": avg_winner,
        "avg_loser_dollars": avg_loser,
        "avg_trade_duration_minutes": avg_trade_duration_minutes,
        "trades_per_day": trades_per_day,
    }

    if output_json is not None:
        output_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [trades_csv],
            symbol=symbol,
            broker=broker,
            random_seed=seed,
            ea_version=ea_version,
            data_source=data_source,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=repo_path,
        )
        payload = {"metadata": metadata.to_dict(), "summary": summary}
        atomic_write_text(output_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    if per_trade_csv is not None:
        per_trade_csv.parent.mkdir(parents=True, exist_ok=True)
        # symbol/trade_id are caller-controlled strings -- sanitized
        # against spreadsheet-formula injection (Codex review finding,
        # 2026-07-22, third round).
        atomic_write_dataframe_csv(sanitize_dataframe_for_csv(trades_sorted), per_trade_csv)

    return summary


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--output-json", type=Path, default=None)
    parser.add_argument("--per-trade-csv", type=Path, default=None)
    parser.add_argument("--starting-balance", type=float, default=1000.0)
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--broker", default=None)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--ea-version", default=None)
    parser.add_argument("--data-source", default=None)
    parser.add_argument("--giveback-arm-percent", type=float, default=1.0)
    parser.add_argument("--giveback-floor-percent", type=float, default=0.5)
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        summary = run(
            trades_csv=args.trades_csv,
            output_json=args.output_json,
            per_trade_csv=args.per_trade_csv,
            starting_balance=args.starting_balance,
            symbol=args.symbol,
            broker=args.broker,
            seed=args.seed,
            ea_version=args.ea_version,
            data_source=args.data_source,
            giveback_arm_percent=args.giveback_arm_percent,
            giveback_floor_percent=args.giveback_floor_percent,
            spread_note=args.spread_note,
            slippage_note=args.slippage_note,
        )
    except (FileNotFoundError, CsvSchemaError, InsufficientSampleError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"analyse_baseline: n={summary['n_trades']} win_rate={summary['win_rate']['value']:.4f} "
        f"expectancy=${summary['expectancy_dollars']['value']:.2f} "
        f"profit_factor={summary['profit_factor']} "
        f"max_balance_dd_pct={summary['max_balance_drawdown_pct']:.4f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
