"""monte_carlo.py -- seeded bootstrap resampling of a trade P/L sequence
to characterize the distribution of equity-curve outcomes (final equity,
max drawdown, probability of hitting a ruin threshold) beyond the single
historical ORDER those trades actually happened in.

**Explicit, stated simplification:** this resamples trades WITH
replacement and independently at each position (an i.i.d. bootstrap of the
trade sequence), which assumes trade outcomes are exchangeable -- it does
NOT preserve any real autocorrelation between consecutive trades (e.g. a
losing streak triggering the daily-loss-cap gate, or the three-loss
cooldown named in section 8 of TASK-002_PHASE2_SPECIFICATION.md but not
yet built as a module -- see TASK-027's Scope Boundary). A block-bootstrap
variant preserving short-run sequential structure is a reasonable future
enhancement, not attempted here.

Uses the SAME trades.csv schema as analyse_baseline.py (this script only
needs the ``profit`` column, but accepts the full schema so one dataset
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
import pandas as pd

from analysis.csv_io import CsvSchemaError, read_csv_with_required_columns
from analysis.metrics import InsufficientSampleError, compute_max_drawdown
from analysis.report_metadata import build_report_metadata
from analysis.resampling import seeded_bootstrap_indices

REQUIRED_COLUMNS = {"trade_id", "profit"}


@dataclass(frozen=True)
class MonteCarloResult:
    n_trades: int
    n_resamples: int
    seed: int
    starting_equity: float
    confidence: float
    final_equity_mean: float
    final_equity_ci_lower: float
    final_equity_ci_upper: float
    max_drawdown_pct_mean: float
    max_drawdown_pct_ci_lower: float
    max_drawdown_pct_ci_upper: float
    ruin_threshold: Optional[float]
    prob_ruin: Optional[float]


def run_monte_carlo(
    pnl: list[float],
    n_resamples: int,
    seed: int,
    starting_equity: float = 0.0,
    ruin_threshold: Optional[float] = None,
    confidence: float = 0.95,
) -> MonteCarloResult:
    """Runs 'n_resamples' bootstrap resamples of 'pnl' (each a full-length
    resample WITH replacement of the trade sequence, deterministic given
    'seed' via resampling.seeded_bootstrap_indices), and summarizes the
    resulting distribution of final equity and max drawdown.

    Raises InsufficientSampleError if 'pnl' is empty, ValueError if
    n_resamples <= 0 or confidence is out of (0, 1).
    """

    if not pnl:
        raise InsufficientSampleError("run_monte_carlo: empty pnl sequence")
    if n_resamples <= 0:
        raise ValueError(f"n_resamples must be > 0, got {n_resamples}")
    if not (0.0 < confidence < 1.0):
        raise ValueError(f"confidence must be in (0, 1), got {confidence}")

    n = len(pnl)
    pnl_arr = np.asarray(pnl, dtype=float)

    final_equities = np.empty(n_resamples, dtype=float)
    max_dd_pcts = np.empty(n_resamples, dtype=float)
    ruin_hits = 0

    for i, idx in enumerate(seeded_bootstrap_indices(n, n_resamples, seed)):
        path_pnl = pnl_arr[idx]
        equity_curve = [starting_equity]
        eq = starting_equity
        for p in path_pnl:
            eq += float(p)
            equity_curve.append(eq)

        final_equities[i] = equity_curve[-1]
        max_dd_pcts[i] = compute_max_drawdown(equity_curve).max_drawdown_pct

        if ruin_threshold is not None and min(equity_curve) <= ruin_threshold:
            ruin_hits += 1

    alpha = 1.0 - confidence
    return MonteCarloResult(
        n_trades=n,
        n_resamples=n_resamples,
        seed=seed,
        starting_equity=starting_equity,
        confidence=confidence,
        final_equity_mean=float(np.mean(final_equities)),
        final_equity_ci_lower=float(np.quantile(final_equities, alpha / 2)),
        final_equity_ci_upper=float(np.quantile(final_equities, 1.0 - alpha / 2)),
        max_drawdown_pct_mean=float(np.mean(max_dd_pcts)),
        max_drawdown_pct_ci_lower=float(np.quantile(max_dd_pcts, alpha / 2)),
        max_drawdown_pct_ci_upper=float(np.quantile(max_dd_pcts, 1.0 - alpha / 2)),
        ruin_threshold=ruin_threshold,
        prob_ruin=(ruin_hits / n_resamples) if ruin_threshold is not None else None,
    )


def run(
    trades_csv: Path,
    n_resamples: int,
    seed: int,
    output_json: Optional[Path] = None,
    *,
    starting_equity: float = 0.0,
    ruin_threshold: Optional[float] = None,
    confidence: float = 0.95,
    symbol: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> MonteCarloResult:
    trades = read_csv_with_required_columns(trades_csv, REQUIRED_COLUMNS)
    if trades.empty:
        raise InsufficientSampleError(f"{trades_csv}: zero trade rows")

    result = run_monte_carlo(
        trades["profit"].tolist(),
        n_resamples=n_resamples,
        seed=seed,
        starting_equity=starting_equity,
        ruin_threshold=ruin_threshold,
        confidence=confidence,
    )

    if output_json is not None:
        output_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [trades_csv], symbol=symbol, random_seed=seed, repo_path=repo_path
        )
        payload = {"metadata": metadata.to_dict(), "result": result.__dict__}
        output_json.write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")

    return result


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--n-resamples", type=int, default=2000)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--output-json", type=Path, default=None)
    parser.add_argument("--starting-equity", type=float, default=0.0)
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
            starting_equity=args.starting_equity,
            ruin_threshold=args.ruin_threshold,
            confidence=args.confidence,
            symbol=args.symbol,
        )
    except (FileNotFoundError, CsvSchemaError, InsufficientSampleError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"monte_carlo: n_trades={result.n_trades} n_resamples={result.n_resamples} seed={result.seed} "
        f"final_equity_mean={result.final_equity_mean:.2f} "
        f"max_dd_pct_mean={result.max_drawdown_pct_mean:.4f} prob_ruin={result.prob_ruin}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
