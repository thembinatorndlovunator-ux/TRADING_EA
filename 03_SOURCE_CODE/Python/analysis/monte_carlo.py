"""monte_carlo.py -- seeded bootstrap resampling of a trade P/L sequence
to characterize the distribution of balance-curve outcomes (final
balance, max drawdown, probability of hitting a ruin threshold) beyond
the single historical ORDER those trades actually happened in.

**Scope, stated explicitly (Codex review finding, 2026-07-21): this is a
FIXED-CASH model, not a percentage-of-equity compounding model.** Each
resample reorders the same historical dollar P/L values and adds them
UNCHANGED to a running balance. That is only a faithful simulation for a
system that risks a fixed dollar/lot amount per trade regardless of
account size. This project's own risk model (RiskManager.mqh,
OrderManager.mqh) sizes risk as a PERCENTAGE of current equity, which
means a real reordering of trades would compound differently (a loss
early in a reordered path reduces the equity base every subsequent trade
sizes from, and vice versa for a gain) -- this module does NOT model
that. Do not present this tool's output as evidence for a percentage-risk
system's real ruin probability; it is only valid for a fixed-cash/
fixed-lot reading of the same P/L history. A percentage-compounding
variant is a reasonable future enhancement, not attempted here.

**Balance, not equity** -- same distinction as analyse_baseline.py: this
is built from closed-trade P/L only, no mark-to-market of open positions.

Uses the SAME trades.csv schema as analyse_baseline.py (this script only
needs ``trade_id``/``profit``, but accepts the full schema so one dataset
file works across every script in this layer).
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np

from analysis.csv_io import CsvSchemaError, assert_finite_columns, assert_unique_ids, read_csv_with_required_columns
from analysis.metrics import InsufficientSampleError, compute_max_drawdown, wilson_confidence_interval
from analysis.report_metadata import build_report_metadata
from analysis.resampling import seeded_bootstrap_indices

REQUIRED_COLUMNS = {"trade_id", "profit"}
MIN_N_RESAMPLES = 100  # below this a percentile CI is not a defensible estimate


@dataclass(frozen=True)
class MonteCarloResult:
    n_trades: int
    n_resamples: int
    seed: int
    starting_balance: float
    confidence: float
    final_balance_mean: float
    final_balance_ci_lower: float
    final_balance_ci_upper: float
    max_drawdown_pct_mean: float
    max_drawdown_pct_ci_lower: float
    max_drawdown_pct_ci_upper: float
    ruin_threshold: Optional[float]
    prob_ruin: Optional[float]
    prob_ruin_ci_lower: Optional[float]
    prob_ruin_ci_upper: Optional[float]


def run_monte_carlo(
    pnl: list[float],
    n_resamples: int,
    seed: int,
    starting_balance: float = 1000.0,
    ruin_threshold: Optional[float] = None,
    confidence: float = 0.95,
) -> MonteCarloResult:
    """Runs 'n_resamples' bootstrap resamples of 'pnl' (each a full-length
    resample WITH replacement of the trade sequence, deterministic given
    'seed' via resampling.seeded_bootstrap_indices), and summarizes the
    resulting distribution of final balance and max drawdown. See the
    module docstring for the fixed-cash modelling scope.

    Raises InsufficientSampleError if 'pnl' is empty or 'starting_balance'
    is not strictly positive (percentage drawdown is undefined otherwise
    -- see metrics.compute_max_drawdown). Raises ValueError if
    n_resamples < MIN_N_RESAMPLES or confidence is out of (0, 1).
    """

    if not pnl:
        raise InsufficientSampleError("run_monte_carlo: empty pnl sequence")
    if starting_balance <= 0:
        raise InsufficientSampleError(
            f"run_monte_carlo: starting_balance must be > 0, got {starting_balance}"
        )
    if n_resamples < MIN_N_RESAMPLES:
        raise ValueError(f"n_resamples must be >= {MIN_N_RESAMPLES} for a defensible CI, got {n_resamples}")
    if not (0.0 < confidence < 1.0):
        raise ValueError(f"confidence must be in (0, 1), got {confidence}")

    n = len(pnl)
    pnl_arr = np.asarray(pnl, dtype=float)

    final_balances = np.empty(n_resamples, dtype=float)
    max_dd_pcts = np.empty(n_resamples, dtype=float)
    ruin_hits = 0

    for i, idx in enumerate(seeded_bootstrap_indices(n, n_resamples, seed)):
        path_pnl = pnl_arr[idx]
        balance_curve = [starting_balance]
        balance = starting_balance
        for p in path_pnl:
            balance += float(p)
            balance_curve.append(balance)

        final_balances[i] = balance_curve[-1]
        max_dd_pcts[i] = compute_max_drawdown(balance_curve).max_drawdown_pct

        if ruin_threshold is not None and min(balance_curve) <= ruin_threshold:
            ruin_hits += 1

    alpha = 1.0 - confidence
    if ruin_threshold is not None:
        prob_ruin = ruin_hits / n_resamples
        ruin_ci_lower, ruin_ci_upper = wilson_confidence_interval(ruin_hits, n_resamples, confidence)
    else:
        prob_ruin = None
        ruin_ci_lower = None
        ruin_ci_upper = None

    return MonteCarloResult(
        n_trades=n,
        n_resamples=n_resamples,
        seed=seed,
        starting_balance=starting_balance,
        confidence=confidence,
        final_balance_mean=float(np.mean(final_balances)),
        final_balance_ci_lower=float(np.quantile(final_balances, alpha / 2)),
        final_balance_ci_upper=float(np.quantile(final_balances, 1.0 - alpha / 2)),
        max_drawdown_pct_mean=float(np.mean(max_dd_pcts)),
        max_drawdown_pct_ci_lower=float(np.quantile(max_dd_pcts, alpha / 2)),
        max_drawdown_pct_ci_upper=float(np.quantile(max_dd_pcts, 1.0 - alpha / 2)),
        ruin_threshold=ruin_threshold,
        prob_ruin=prob_ruin,
        prob_ruin_ci_lower=ruin_ci_lower,
        prob_ruin_ci_upper=ruin_ci_upper,
    )


def run(
    trades_csv: Path,
    n_resamples: int,
    seed: int,
    output_json: Optional[Path] = None,
    *,
    starting_balance: float = 1000.0,
    ruin_threshold: Optional[float] = None,
    confidence: float = 0.95,
    symbol: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> MonteCarloResult:
    if output_json is not None and output_json.resolve() == trades_csv.resolve():
        raise CsvSchemaError(f"output_json {output_json} must not be the same as the input trades_csv")

    trades = read_csv_with_required_columns(trades_csv, REQUIRED_COLUMNS)
    if trades.empty:
        raise InsufficientSampleError(f"{trades_csv}: zero trade rows")
    assert_unique_ids(trades, "trade_id", trades_csv)
    assert_finite_columns(trades, ["profit"], trades_csv)

    result = run_monte_carlo(
        trades["profit"].tolist(),
        n_resamples=n_resamples,
        seed=seed,
        starting_balance=starting_balance,
        ruin_threshold=ruin_threshold,
        confidence=confidence,
    )

    if output_json is not None:
        output_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [trades_csv], symbol=symbol, random_seed=seed, repo_path=repo_path
        )
        payload = {"metadata": metadata.to_dict(), "result": result.__dict__}
        output_json.write_text(json.dumps(payload, indent=2, default=str, allow_nan=False), encoding="utf-8")

    return result


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--n-resamples", type=int, default=2000)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--output-json", type=Path, default=None)
    parser.add_argument("--starting-balance", type=float, default=1000.0)
    parser.add_argument("--ruin-threshold", type=float, default=None)
    parser.add_argument("--confidence", type=float, default=0.95)
    parser.add_argument("--symbol", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        result = run(
            trades_csv=args.trades_csv,
            n_resamples=args.n_resamples,
            seed=args.seed,
            output_json=args.output_json,
            starting_balance=args.starting_balance,
            ruin_threshold=args.ruin_threshold,
            confidence=args.confidence,
            symbol=args.symbol,
        )
    except (FileNotFoundError, CsvSchemaError, InsufficientSampleError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"monte_carlo: n_trades={result.n_trades} n_resamples={result.n_resamples} seed={result.seed} "
        f"final_balance_mean={result.final_balance_mean:.2f} "
        f"max_dd_pct_mean={result.max_drawdown_pct_mean:.4f} prob_ruin={result.prob_ruin}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
