"""analyse_baseline.py -- aggregate performance summary over a normalized
trade-export CSV: win rate (with Wilson CI), expectancy ($  and R), profit
factor, max drawdown, net profit, recovery factor, a BALANCE-based peak-
giveback proxy (**not** the master-prompt equity-peak-giveback metric --
see below), longest losing BALANCE-STEP streak (**renamed, 2026-07-22
Codex review finding, sixth round: NOT "longest run of consecutive
losing trades" -- see compute_trade_summary's own comment for exactly
why**), average winner/loser, average trade duration, and trades-per-day
on the resulting BALANCE curve --
**extended, 2026-07-22 Codex review finding (fourth round): every one of
these except win rate/expectancy/profit factor/max drawdown was
previously absent, despite TEST_PLAN.md naming all of them as the
minimum baseline-comparison surface.** Spread/slippage SENSITIVITY
(running the same trades through multiple assumed cost scenarios)
remains a separate, larger deliverable -- not attempted here;
``spread_note``/``slippage_note`` record a single caller-asserted cost
assumption as provenance, they do not vary it.

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
entry_price, exit_price, stop_price, profit`` -- ``profit`` MUST be the
NET account-currency P/L (commission, swap, and any other fees already
netted in). **Corrected, 2026-07-22 Codex review finding (fifth round):
this previously ASSERTED, as if verified, that an MT5 "Deals" export's
own profit column normally already nets commission/swap in per deal --
`TASK-037_MT5_EXPORT_BRIDGE.md` explicitly says that exact net-vs-gross
behavior is UNVERIFIED against real MT5 history fields and must not be
assumed.** This is therefore a REQUIREMENT on whatever produces
'trades_csv' (a real MT5 bridge or a synthetic fixture), not a factual
claim about MT5's own export format -- TASK-037 (Specification item 1)
must define and test the actual netting formula (profit + commission +
swap + fees, verified field-by-field against a real MT5 Deals export)
before its bridge is accepted as satisfying this contract; every dollar
metric in this module is silently wrong if that formula is assumed
rather than verified.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Optional, Sequence

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
    parse_is_long,
    read_csv_with_required_columns_and_hash,
    sanitize_dataframe_for_csv,
)
from analysis.metrics import (
    InsufficientSampleError,
    bootstrap_confidence_interval,
    compute_balance_peak_giveback,
    compute_max_drawdown,
    expectancy,
    profit_factor,
    win_rate,
)
from analysis.report_metadata import build_report_metadata, publish_dataframe_csv_and_json
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


def _mean_with_ci(
    values: Sequence[float], *, n_resamples: int, seed: int, confidence: float
) -> tuple[Optional[float], Optional[float], Optional[float]]:
    """Mean of 'values' plus a bootstrap CI on that mean -- returns
    (mean, ci_lower, ci_upper), with the CI as ``None`` (never a
    false-precision degenerate interval) when fewer than 2 observations
    exist, same "no estimable uncertainty" convention ``expectancy``
    already uses for n==1.

    **Added, 2026-07-22 Codex review finding (sixth round): avg_winner_
    dollars/avg_loser_dollars/avg_trade_duration_minutes previously
    carried a sample size (added round 5) but no uncertainty at all,
    despite round 5's own finding/test commentary naming BOTH as
    required -- a caller could not tell whether e.g. an average winner
    of $45 over 2 trades was anywhere near as reliable as one over 200.**
    """

    if not values:
        return None, None, None
    mean = sum(values) / len(values)
    if len(values) < 2:
        return mean, None, None
    boot = bootstrap_confidence_interval(
        values, statistic="mean", n_resamples=n_resamples, confidence=confidence, seed=seed
    )
    return mean, boot.ci_lower, boot.ci_upper


def compute_trade_summary(
    trades_sorted: pd.DataFrame,
    *,
    starting_balance: float = 1000.0,
    seed: int = 42,
    # **Added, 2026-07-22 Codex review finding (sixth round): this
    # function previously exposed 'seed' but hard-wired every
    # win_rate()/expectancy() call to their own default n_resamples/
    # confidence (2000/0.95), regardless of what a caller (e.g.
    # compare_releases.run, which already exposes its own n_resamples/
    # confidence for its TOP-LEVEL win_rate_diff/expectancy_r_diff
    # inference) actually wanted -- a probe with n_resamples=100,
    # confidence=0.9 previously returned those values at the top level
    # while the NESTED baseline_summary/candidate_summary silently kept
    # 2000/0.95, reporting internally DIFFERENT inferential
    # configurations inside one JSON artifact.**
    n_resamples: int = 2000,
    confidence: float = 0.95,
    giveback_arm_percent: float = 1.0,
    giveback_floor_percent: float = 0.5,
    # **Added, 2026-07-22 Codex review finding (fifth round): 'trades_per_day'
    # previously always divided by the ACTIVE trade envelope (earliest
    # entry to latest exit), silently misrepresenting a short burst of
    # trades within a much longer authenticated backtest/evaluation
    # period as a much higher daily rate. A caller who knows the real
    # evaluation window can supply it explicitly here; when omitted, the
    # active envelope is still used but the summary now discloses which
    # denominator was actually applied (see 'trades_per_day_denominator_source').
    evaluation_period_days: Optional[float] = None,
) -> dict:
    """Computes the full baseline summary dict (win rate, expectancy,
    profit factor, drawdown, net profit, recovery factor, balance-peak
    giveback, longest losing BALANCE-STEP streak, avg winner/loser, avg
    trade duration, trades-per-day) from an ALREADY-VALIDATED, already-parsed
    trades DataFrame: 'is_long' parsed to bool, 'entry_time'/'exit_time'
    parsed to UTC timestamps, 'r_multiple' column already computed --
    exactly what ``run()`` below and
    ``compare_releases._load_trades_with_r_multiple`` each independently
    prepare.

    **Factored out of ``run()``, 2026-07-22 Codex review finding (fifth
    round):** this was previously inline in ``run()`` only, so
    ``compare_releases.py`` could not report this same side-by-side
    profit/profit-factor/drawdown/recovery/giveback/streak/duration/
    frequency surface for two datasets -- it only ever compared win rate
    and R-expectancy. Both callers now share this one implementation, so
    a fix here (or a new field) reaches both automatically.

    'trades_sorted' must already be sorted by 'exit_time' (this function
    does not re-sort). Raises InsufficientSampleError if 'trades_sorted'
    is empty or 'starting_balance' is not finite/positive.
    """

    if trades_sorted.empty:
        raise InsufficientSampleError("compute_trade_summary: zero trade rows")
    if not math.isfinite(starting_balance) or starting_balance <= 0:
        raise InsufficientSampleError(
            f"compute_trade_summary: starting_balance must be a finite number > 0, "
            f"got {starting_balance}"
        )
    if evaluation_period_days is not None and (
        not math.isfinite(evaluation_period_days) or evaluation_period_days <= 0
    ):
        raise ValueError(
            f"compute_trade_summary: evaluation_period_days must be a finite number > 0 if "
            f"given, got {evaluation_period_days}"
        )

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

    wr = win_rate([p > 0 for p in profits], confidence=confidence)
    exp_dollars = expectancy(profits, n_resamples=n_resamples, seed=seed, confidence=confidence)
    exp_r = expectancy(r_multiples, n_resamples=n_resamples, seed=seed, confidence=confidence)
    pf = profit_factor(profits)
    dd = compute_max_drawdown(balance_curve)
    giveback = compute_balance_peak_giveback(
        balance_curve, arm_percent=giveback_arm_percent, floor_percent=giveback_floor_percent
    )
    net_profit = balance_curve[-1] - starting_balance
    recovery_factor = net_profit / dd.max_drawdown_abs if dd.max_drawdown_abs > 0 else None

    # **Fixed, 2026-07-22 Codex review finding (fifth round): this
    # previously iterated 'profits' in trades_sorted's own row order,
    # which is ARBITRARY among trades sharing the same exit_time (the
    # same tie-break problem the drawdown calculation above already
    # solves by summing same-instant P/L into one balance step).
    # Reordering three simultaneous outcomes from loss/win/loss to
    # loss/loss/win changed the reported streak from 1 to 2 with
    # identical timestamps and net P/L. The streak is now computed over
    # the SAME order-independent 'balance_steps' series drawdown uses --
    # one outcome per DISTINCT exit_time (summed), not one per row.**
    #
    # **Renamed, 2026-07-22 Codex review finding (sixth round): computing
    # this over summed-per-exit-time balance steps (the round-5 fix
    # above) is not the SAME metric as "longest run of consecutive
    # LOSING TRADES" -- it changed what is measured, not just how it is
    # computed. Reproduced counterexample: simultaneous profits
    # [-1, -1, +10] at one exit_time sum to a single +8 balance step,
    # reporting a losing streak of 0 despite two individual losing
    # trades; three simultaneous losses sum to one negative step,
    # reporting 1 instead of 3. This schema has no durable intra-
    # timestamp deal sequence field, so there is no principled way to
    # recover a genuine per-TRADE ordering among same-instant trades --
    # renamed to describe exactly what is measured (consecutive negative
    # BALANCE STEPS, i.e. distinct exit-time instants, not individual
    # trades) rather than silently redefining the old, differently-named
    # field.**
    longest_losing_balance_step_streak = 0
    current_losing_streak = 0
    for step_pnl in balance_steps:
        if step_pnl < 0:
            current_losing_streak += 1
            longest_losing_balance_step_streak = max(
                longest_losing_balance_step_streak, current_losing_streak
            )
        else:
            current_losing_streak = 0

    winners = [p for p in profits if p > 0]
    losers = [p for p in profits if p < 0]
    # **Added, 2026-07-22 Codex review finding (sixth round): a bootstrap
    # CI alongside each mean -- see _mean_with_ci's own docstring.**
    avg_winner, avg_winner_ci_lower, avg_winner_ci_upper = _mean_with_ci(
        winners, n_resamples=n_resamples, seed=seed, confidence=confidence
    )
    avg_loser, avg_loser_ci_lower, avg_loser_ci_upper = _mean_with_ci(
        losers, n_resamples=n_resamples, seed=seed, confidence=confidence
    )

    durations_minutes = (
        trades_sorted["exit_time"] - trades_sorted["entry_time"]
    ).dt.total_seconds() / 60.0
    (
        avg_trade_duration_minutes,
        avg_trade_duration_minutes_ci_lower,
        avg_trade_duration_minutes_ci_upper,
    ) = _mean_with_ci(
        durations_minutes.tolist(), n_resamples=n_resamples, seed=seed, confidence=confidence
    )

    # **Fixed, 2026-07-22 Codex review finding (fifth round): this
    # previously ALWAYS divided by the active trade envelope (earliest
    # entry to latest exit) -- a data-derived span that can be far
    # shorter than the actual backtest/evaluation period a caller ran
    # (e.g. 4 trades clustered in one week of a month-long run
    # previously inflated to a misleading "trades/day" figure for the
    # whole month). When 'evaluation_period_days' is supplied, it is now
    # used as the authenticated denominator instead; the summary always
    # discloses which source was actually used.**
    if evaluation_period_days is not None:
        period_days = evaluation_period_days
        trades_per_day_source = "authenticated_evaluation_period"
    else:
        period_days = (
            trades_sorted["exit_time"].max() - trades_sorted["entry_time"].min()
        ).total_seconds() / 86400.0
        trades_per_day_source = "active_trade_envelope"
    trades_per_day = (len(trades_sorted) / period_days) if period_days > 0 else None

    return {
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
        "net_profit": net_profit,
        "recovery_factor": recovery_factor,
        "balance_peak_giveback": {
            "arm_percent": giveback.arm_percent,
            "floor_percent": giveback.floor_percent,
            "armed": giveback.armed,
            "n_trigger_events": giveback.n_trigger_events,
            "trigger_indices": giveback.trigger_indices,
            "max_giveback_pct": giveback.max_giveback_pct,
            "max_giveback_pct_index": giveback.max_giveback_pct_index,
            "note": (
                "BALANCE-based, non-daily-resetting proxy -- NOT the master-prompt-required "
                "account or daily equity-peak-giveback metric (both need a real intratrade "
                "equity-tick series this project does not have yet); also distinct from "
                "analyse_giveback.py's per-trade R-path guard simulation"
            ),
        },
        "longest_losing_balance_step_streak": longest_losing_balance_step_streak,
        # **Added, 2026-07-22 Codex review finding (fifth round): these
        # carried neither a subgroup sample size nor uncertainty, despite
        # the task's sample-size/uncertainty contract -- a caller could
        # not tell a well-supported average from one based on a single
        # observation.**
        # **Added, 2026-07-22 Codex review finding (sixth round): a
        # bootstrap CI on each mean, closing the "sample size but no
        # uncertainty" gap round 5's own commentary named but did not
        # actually add -- ``None`` when fewer than 2 observations exist
        # (no estimable uncertainty from a single point), never a
        # false-precision degenerate interval.**
        "avg_winner_dollars": avg_winner,
        "avg_winner_dollars_n": len(winners),
        "avg_winner_dollars_ci_lower": avg_winner_ci_lower,
        "avg_winner_dollars_ci_upper": avg_winner_ci_upper,
        "avg_loser_dollars": avg_loser,
        "avg_loser_dollars_n": len(losers),
        "avg_loser_dollars_ci_lower": avg_loser_ci_lower,
        "avg_loser_dollars_ci_upper": avg_loser_ci_upper,
        "avg_trade_duration_minutes": avg_trade_duration_minutes,
        "avg_trade_duration_minutes_n": len(trades_sorted),
        "avg_trade_duration_minutes_ci_lower": avg_trade_duration_minutes_ci_lower,
        "avg_trade_duration_minutes_ci_upper": avg_trade_duration_minutes_ci_upper,
        "trades_per_day": trades_per_day,
        "trades_per_day_denominator_days": period_days,
        "trades_per_day_denominator_source": trades_per_day_source,
    }


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
    # **Added, 2026-07-22 Codex review finding (sixth round): this
    # script previously had NO CLI/API control over n_resamples/
    # confidence at all, unlike every other pipeline in this layer --
    # see compute_trade_summary's own comment for the exact inconsistency
    # this closes.**
    n_resamples: int = 2000,
    confidence: float = 0.95,
    ea_version: Optional[str] = None,
    data_source: Optional[str] = None,
    # **Added, 2026-07-22 Codex review finding (fourth round), renamed
    # and re-scoped 2026-07-22 (fifth round): NOT the master-prompt-
    # required "Equity-peak giveback" metric -- see
    # metrics.compute_balance_peak_giveback's own docstring for exactly
    # why (balance-based, no daily reset) and for what a real equity-
    # based measurement still needs. Defaults match
    # TASK-002_PHASE2_SPECIFICATION.md's own "Daily equity-peak giveback"
    # defaults (InpDailyGivebackArmPercent/InpDailyGivebackFloorPercent)
    # purely as a starting point for this distinct balance-based proxy.
    giveback_arm_percent: float = 1.0,
    giveback_floor_percent: float = 0.5,
    # **Added, 2026-07-22 Codex review finding (fifth round): see
    # compute_trade_summary's own docstring/comment -- when omitted,
    # 'trades_per_day' still falls back to the active trade envelope, but
    # the summary now discloses that fact rather than reporting the same
    # figure under an unqualified label.**
    evaluation_period_days: Optional[float] = None,
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
    # **Added, 2026-07-22 Codex review finding (sixth round): a caller
    # requesting per_trade_csv without output_json previously got a CSV
    # with NO accompanying provenance metadata anywhere -- this pipeline's
    # summary/metadata payload lives entirely in output_json, so omitting
    # it left the per-trade CSV completely unprovenanced. An implicit
    # path is now derived (matching join_trade_journal.py/
    # join_news_events.py/join_signal_to_outcome.py's own pattern),
    # derived FIRST so the collision checks below cover it too.**
    if output_json is None and per_trade_csv is not None:
        output_json = per_trade_csv.parent / f"{per_trade_csv.stem}.summary.json"

    # **Fixed, 2026-07-22 Codex review finding (third round): comparing
    # only Path.resolve() let a hard link to trades_csv pass this check
    # (different resolved name, identical underlying file) -- a direct
    # probe used a hard-linked output path to overwrite trades_csv's own
    # inode. assert_path_not_same_file also checks OS-level file identity.
    for out_path in (output_json, per_trade_csv):
        assert_path_not_same_file(out_path, trades_csv, "output path")
    assert_output_paths_distinct([output_json, per_trade_csv])

    # **Fixed, 2026-07-22 Codex review finding (fifth round): 'trades_csv'
    # was previously parsed here, then SEPARATELY re-read and hashed by
    # build_report_metadata() far below -- a mutation landing in that gap
    # (after parsing, before hashing) produced a result computed from the
    # OLD content while the persisted dataset_hash described the NEW
    # file. read_csv_with_required_columns_and_hash reads the file exactly
    # ONCE and derives both the parsed DataFrame and the hash from that
    # same byte buffer, so the two can never desync.**
    # **Fixed, 2026-07-22 Codex review finding (sixth round): 'trade_id'
    # was previously read via plain pandas type inference -- a CSV
    # containing IDs "001"/"1" loaded as integer values 1, 1 and was
    # rejected as a false duplicate (the same identifier-corruption class
    # already fixed in the specialized signal/news joins).**
    trades, trades_csv_hash = read_csv_with_required_columns_and_hash(
        trades_csv, REQUIRED_COLUMNS, dtype=TRADE_ID_DTYPE
    )
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

    summary = compute_trade_summary(
        trades_sorted,
        starting_balance=starting_balance,
        seed=seed,
        n_resamples=n_resamples,
        confidence=confidence,
        giveback_arm_percent=giveback_arm_percent,
        giveback_floor_percent=giveback_floor_percent,
        evaluation_period_days=evaluation_period_days,
    )

    payload = None
    if output_json is not None:
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
            dataset_hash_override=trades_csv_hash,
        )
        payload = {"metadata": metadata.to_dict(), "summary": summary}

    # symbol/trade_id are caller-controlled strings -- sanitized against
    # spreadsheet-formula injection (Codex review finding, 2026-07-22,
    # third round).
    # **Fixed, 2026-07-22 Codex review finding (eighth round, P1 finding
    # 16): writing output_json then per_trade_csv as two separate calls
    # was each individually atomic but NOT atomic as a PAIR -- see
    # publish_dataframe_csv_and_json's own docstring.**
    publish_dataframe_csv_and_json(
        sanitize_dataframe_for_csv(trades_sorted) if per_trade_csv is not None else None,
        per_trade_csv,
        payload,
        output_json,
    )

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
    # **Added, 2026-07-22 Codex review finding (sixth round): this script
    # previously had NO CLI control over n_resamples/confidence at all.**
    parser.add_argument("--n-resamples", type=int, default=2000)
    parser.add_argument("--confidence", type=float, default=0.95)
    parser.add_argument("--ea-version", default=None)
    parser.add_argument("--data-source", default=None)
    parser.add_argument("--giveback-arm-percent", type=float, default=1.0)
    parser.add_argument("--giveback-floor-percent", type=float, default=0.5)
    parser.add_argument("--evaluation-period-days", type=float, default=None)
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
            n_resamples=args.n_resamples,
            confidence=args.confidence,
            ea_version=args.ea_version,
            data_source=args.data_source,
            giveback_arm_percent=args.giveback_arm_percent,
            giveback_floor_percent=args.giveback_floor_percent,
            evaluation_period_days=args.evaluation_period_days,
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
