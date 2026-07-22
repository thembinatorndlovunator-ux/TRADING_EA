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

**Individual trades are resampled WITH REPLACEMENT (an i.i.d. empirical
bootstrap), reiterated here since it is easy to lose sight of (Codex
review finding, 2026-07-22): this is not merely reordering the historical
sequence -- it DESTROYS any streak/autocorrelation structure, day-level
caps, and cooldown behavior the real trade sequence had. A real account
subject to (for example) a three-loss cooldown (see TASK-034) cannot
actually produce every resampled path this tool generates. Do not read
this tool's ruin/drawdown probabilities as evidence about a system that
has streak-dependent risk controls; it only characterizes what an i.i.d.
reshuffling of the SAME historical P/L values would look like.**

**``final_balance_ci_*``/``max_drawdown_pct_ci_*`` are PERCENTILE SCENARIO
BOUNDS conditional on the empirical i.i.d. resampling model above, not a
conventional statistical confidence interval for a future balance or
drawdown (Codex review finding, 2026-07-22) -- they describe the spread
of outcomes this specific reshuffling procedure produces from this
specific historical sample, not an inference about the true underlying
process. The ruin Wilson interval measures finite-simulation error (how
precisely ``n_resamples`` estimates the resampling procedure's own ruin
rate), not uncertainty in the small historical P/L distribution itself.

**Balance, not equity** -- same distinction as analyse_baseline.py: this
is built from closed-trade P/L only, no mark-to-market of open positions.

Uses the SAME trades.csv schema as analyse_baseline.py (this script only
needs ``trade_id``/``profit``, but accepts the full schema so one dataset
file works across every script in this layer).
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

from analysis.csv_io import (
    CsvSchemaError,
    assert_finite_columns,
    assert_path_not_same_file,
    assert_unique_ids,
    read_csv_with_required_columns_and_hash,
)
from analysis.metrics import (
    InsufficientSampleError,
    compute_max_drawdown,
    wilson_confidence_interval,
)
from analysis.report_metadata import atomic_write_text, build_report_metadata
from analysis.resampling import seeded_bootstrap_indices

REQUIRED_COLUMNS = {"trade_id", "profit"}
MIN_N_RESAMPLES = 100  # below this a percentile scenario-bound estimate is not defensible
# **Added, 2026-07-22 Codex review finding (fifth round): no upper bound
# previously existed on n_resamples, permitting an accidental unbounded
# memory/time request.**
MAX_N_RESAMPLES = 100_000
MIN_N_TRADES = 20  # **Added, 2026-07-22 Codex review finding:** below this, resampling
# manufactures apparent precision the underlying sample cannot support
# -- a direct probe with a single historical trade previously returned
# a suspiciously "precise" [1010.0, 1010.0] final-balance bound and a
# [0.0, 0.0] drawdown bound; more simulations cannot create sample
# information that was never there.


@dataclass(frozen=True)
class MonteCarloResult:
    """**Field-naming note (Codex review finding, 2026-07-22):**
    ``final_balance_ci_*`` and ``max_drawdown_pct_ci_*`` are PERCENTILE
    SCENARIO BOUNDS from the i.i.d. empirical-bootstrap resampling
    procedure described in the module docstring, not a conventional
    statistical confidence interval for a future balance or drawdown --
    every caller/notebook presenting these MUST use that framing (e.g.
    "percentile scenario bounds"), not bare "95% CI" language, which
    overstates what this tool can establish from a small, streak-
    destroyed, i.i.d.-resampled trade history.
    """

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

    Raises InsufficientSampleError if 'pnl' has fewer than MIN_N_TRADES
    observations (see that constant's own comment), or 'starting_balance'
    is not strictly positive/finite (percentage drawdown is undefined
    otherwise -- see metrics.compute_max_drawdown). Raises ValueError if
    n_resamples < MIN_N_RESAMPLES, confidence is out of (0, 1), 'pnl'
    contains a non-finite value, or 'ruin_threshold' is given and
    non-finite.
    """

    if len(pnl) < MIN_N_TRADES:
        raise InsufficientSampleError(
            f"run_monte_carlo: need >= {MIN_N_TRADES} historical trades for a defensible "
            f"resampling distribution, got {len(pnl)}"
        )
    if not math.isfinite(starting_balance) or starting_balance <= 0:
        raise InsufficientSampleError(
            f"run_monte_carlo: starting_balance must be a finite number > 0, got {starting_balance}"
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
    if not (0.0 < confidence < 1.0):
        raise ValueError(f"confidence must be in (0, 1), got {confidence}")
    if not all(math.isfinite(p) for p in pnl):
        raise ValueError("run_monte_carlo: pnl contains a non-finite (NaN/inf) value")
    if ruin_threshold is not None and not math.isfinite(ruin_threshold):
        raise ValueError(f"run_monte_carlo: ruin_threshold must be finite, got {ruin_threshold}")

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
        ruin_ci_lower, ruin_ci_upper = wilson_confidence_interval(
            ruin_hits, n_resamples, confidence
        )
    else:
        prob_ruin = None
        ruin_ci_lower = None
        ruin_ci_upper = None

    final_balance_mean = float(np.mean(final_balances))
    final_balance_ci_lower = float(np.quantile(final_balances, alpha / 2))
    final_balance_ci_upper = float(np.quantile(final_balances, 1.0 - alpha / 2))
    max_drawdown_pct_mean = float(np.mean(max_dd_pcts))
    max_drawdown_pct_ci_lower = float(np.quantile(max_dd_pcts, alpha / 2))
    max_drawdown_pct_ci_upper = float(np.quantile(max_dd_pcts, 1.0 - alpha / 2))
    # **Added, 2026-07-22 Codex review finding (fifth round):** each
    # individual resampled final balance is finite (accumulated one trade
    # at a time from finite pnl values), but AGGREGATING many large-but-
    # finite values across 'n_resamples' resamples (mean/quantile) can
    # still overflow -- a probe with pnl=[5e306]*20, n_resamples=100
    # produced an infinite final_balance_mean even though every individual
    # resampled final balance was finite.
    if not all(
        math.isfinite(v)
        for v in (
            final_balance_mean,
            final_balance_ci_lower,
            final_balance_ci_upper,
            max_drawdown_pct_mean,
            max_drawdown_pct_ci_lower,
            max_drawdown_pct_ci_upper,
        )
    ):
        raise ValueError(
            "run_monte_carlo: an aggregate statistic (mean/CI) over the resampled distribution "
            "overflowed to a non-finite value -- individual resampled outcomes are finite but "
            f"their aggregate is not (final_balance_mean={final_balance_mean}, "
            f"max_drawdown_pct_mean={max_drawdown_pct_mean})"
        )

    return MonteCarloResult(
        n_trades=n,
        n_resamples=n_resamples,
        seed=seed,
        starting_balance=starting_balance,
        confidence=confidence,
        final_balance_mean=final_balance_mean,
        final_balance_ci_lower=final_balance_ci_lower,
        final_balance_ci_upper=final_balance_ci_upper,
        max_drawdown_pct_mean=max_drawdown_pct_mean,
        max_drawdown_pct_ci_lower=max_drawdown_pct_ci_lower,
        max_drawdown_pct_ci_upper=max_drawdown_pct_ci_upper,
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
    # **Added, 2026-07-22 Codex review finding (fourth round): spread_note/
    # slippage_note exist on ReportMetadata but no analysis caller exposed
    # or populated them.**
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> MonteCarloResult:
    # Uses OS-level file-identity (not just Path.resolve()) so a hard
    # link to an input is also caught -- Codex review finding, third round.
    assert_path_not_same_file(output_json, trades_csv, "output_json")

    # **Fixed, 2026-07-22 Codex review finding (sixth round): previously
    # read via the plain (non-hashing) helper, then re-read a second time
    # inside build_report_metadata below to compute its hash -- the same
    # ABA-mutation race round 5 already closed for
    # join_trade_journal.py/join_news_events.py/analyse_baseline.py but
    # left open here.**
    trades, trades_csv_hash = read_csv_with_required_columns_and_hash(trades_csv, REQUIRED_COLUMNS)
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
            [trades_csv],
            symbol=symbol,
            random_seed=seed,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=repo_path,
            dataset_hash_override=trades_csv_hash,
        )
        # **Added, 2026-07-22 Codex review finding (third round):** the
        # module docstring and dataclass docstring already explained that
        # ``final_balance_ci_*``/``max_drawdown_pct_ci_*`` are percentile
        # scenario bounds from an i.i.d. fixed-cash resampling model, not
        # a conventional statistical CI -- but that caveat lived only in
        # PROSE, never in the machine-readable JSON artifact itself. A
        # tool or reader consuming only the JSON (not this source file)
        # had no way to know the field names overstate what they mean.
        # ``bound_type``/``model``/``caveat`` are now serialized directly
        # alongside the result so the artifact is self-describing.
        payload = {
            "metadata": metadata.to_dict(),
            "bound_type": "percentile_scenario_bound",
            "model": "fixed_cash_iid_empirical_bootstrap",
            "caveat": (
                "final_balance_ci_* and max_drawdown_pct_ci_* are percentile scenario "
                "bounds conditional on an i.i.d. empirical-bootstrap reshuffling of this "
                "fixed-cash historical P/L sample -- NOT a conventional statistical "
                "confidence interval for a future balance or drawdown, and not valid "
                "evidence for a percentage-of-equity compounding system or for a system "
                "with streak-dependent risk controls (e.g. a loss-streak cooldown). "
                "prob_ruin_ci_* is a Wilson interval on finite-simulation error only. "
                "See analysis/monte_carlo.py module docstring for the full scope."
            ),
            "result": result.__dict__,
        }
        atomic_write_text(output_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

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
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
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
            spread_note=args.spread_note,
            slippage_note=args.slippage_note,
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
