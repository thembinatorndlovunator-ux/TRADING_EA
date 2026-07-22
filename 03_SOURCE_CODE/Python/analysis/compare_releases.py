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

**Comparability manifest now REQUIRED and fully cross-checked, 2026-07-22
Codex review finding (fifth round): broker/timeframe/modelling_mode/
set_file/market_data_id/spread_note/slippage_note were previously either
optional (compared "only when both sides happen to be supplied" -- a
baseline broker with a missing candidate broker previously passed
outright) or a single value shared between both sides (costs).** All
seven are now REQUIRED, role-specific (baseline_*/candidate_*), and
unconditionally cross-checked for equality -- ``run()`` raises
``ValueError`` the moment any one differs. ``market_data_id`` is new: a
caller-asserted identifier for the raw market-data segment both runs
were replayed against (this cannot be derived from the trade CSVs
themselves -- role-specific trade-file hashes prove only that the two
TRADE files differ, never that their SOURCE market data matched).
'period_start'/'period_end' still bound containment, not coverage or
raw-data identity -- a baseline trading only near the start of the
claimed period and a candidate only near its end still both pass; this
script does not (and, from trade timestamps alone, cannot) prove actual
temporal coverage. Different OBSERVED trade envelopes between baseline
and candidate can be entirely legitimate (e.g. a stricter candidate
simply took fewer setups) -- equality of first/last trade timestamps is
deliberately not required or checked.

**Named explicitly, not silently left implicit, 2026-07-22 Codex review
finding (sixth round): a caller could previously claim an arbitrarily
broad 'period_start'/'period_end' (e.g. a full year) for a dataset whose
trades actually span a tiny fraction of it, with nothing in the returned
summary making that gap visible** -- the returned 'baseline_period'/
'candidate_period' fields (the OBSERVED entry/exit envelope, always
computed regardless of the claim) exist precisely so a caller can
compare them against the CLAIMED period and see this for themselves;
they are not a coverage proof, only the evidence a coverage check would
need. A caller presenting this comparison MUST show both the claimed and
observed periods side by side, not the claimed period alone -- see
notebook 10's own fix for this exact gap.
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
    TRADE_ID_DTYPE,
    CsvSchemaError,
    assert_chronological_order,
    assert_finite_columns,
    assert_path_not_same_file,
    assert_unique_ids,
    assert_valid_stop_geometry,
    parse_is_long,
    read_csv_with_required_columns_and_hash,
)
from analysis.metrics import InsufficientSampleError, wilson_diff_confidence_interval
from analysis.report_metadata import (
    atomic_write_text,
    build_report_metadata,
    combine_labeled_hashes,
)
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


def _load_trades_with_r_multiple(
    trades_csv: Path, symbol_filter: Optional[str]
) -> tuple[pd.DataFrame, str]:
    # **Fixed, 2026-07-22 Codex review finding (sixth round): this was
    # previously read via the plain (non-hashing) helper, and the caller
    # then re-read the same path (twice more -- once for its own
    # role-specific 'baseline_dataset_hash'/'candidate_dataset_hash', once
    # more inside build_report_metadata's combined hash) -- the same
    # ABA-mutation race round 5 already closed for
    # join_trade_journal.py/join_news_events.py/analyse_baseline.py but
    # left open here. Returns the hash from this single read so every
    # downstream use (role-specific and combined) shares it.**
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
    return trades, trades_csv_hash


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
    # **Fixed, 2026-07-22 Codex review finding (fifth round): broker/
    # timeframe/modelling_mode/set_file were previously OPTIONAL and
    # compared "only when both sides are supplied" -- a baseline
    # broker="Deriv" with a missing candidate broker previously PASSED
    # (nothing to compare against). TEST_PLAN.md's comparability contract
    # ("use identical symbols, periods, data, costs, and broker settings")
    # requires a COMPLETE manifest on both sides, not an optional
    # best-effort assertion. All four pairs are now REQUIRED and always
    # cross-checked for equality.**
    baseline_broker: str,
    candidate_broker: str,
    baseline_timeframe: str,
    candidate_timeframe: str,
    baseline_modelling_mode: str,
    candidate_modelling_mode: str,
    baseline_set_file: str,
    candidate_set_file: str,
    # **Added, 2026-07-22 Codex review finding (fifth round): nothing
    # previously asserted the two runs used the SAME underlying raw
    # market-data segment -- role-specific output hashes only prove the
    # two TRADE files differ, not that their SOURCE data matched. A
    # caller must supply a stable identifier for the raw market-data
    # segment each run was replayed against (e.g. a vendor/export hash,
    # a tick-data file's own dataset hash, or a fixed named dataset
    # version) -- required and cross-checked for equality, same
    # discipline as broker/timeframe/modelling_mode/set_file above.**
    baseline_market_data_id: str,
    candidate_market_data_id: str,
    # **Fixed, 2026-07-22 Codex review finding (third round): a single
    # shared ea_version/data_source value is insufficient to identify TWO
    # releases -- a caller could only ever record one version for both
    # sides of the comparison. Separate baseline/candidate fields now.**
    #
    # **Fixed, 2026-07-22 Codex review finding (sixth round): these four
    # remained OPTIONAL and were persisted as null with no check at all
    # -- the master prompt names EA version and data source among the
    # facts every result must record (00_MASTER_PROMPT_FOR_CLAUDE.md's
    # required-provenance list), yet a comparison could previously
    # "pass" with both entirely absent. Now REQUIRED and cross-checked
    # for equality/non-blank alongside the other manifest pairs below.**
    baseline_ea_version: str,
    candidate_ea_version: str,
    baseline_data_source: str,
    candidate_data_source: str,
    # **Fixed, 2026-07-22 Codex review finding (fifth round): costs were
    # previously a SINGLE shared spread_note/slippage_note pair -- "a
    # shared trusted note", not two compared manifests. TEST_PLAN.md's
    # comparability contract requires identical costs between baseline
    # and candidate; these are now role-specific and cross-checked for
    # equality like broker/timeframe/modelling_mode/set_file above.**
    baseline_spread_note: str,
    candidate_spread_note: str,
    baseline_slippage_note: str,
    candidate_slippage_note: str,
    repo_path: Optional[Path] = None,
) -> dict:
    """'period_start'/'period_end' and the seven role-specific manifest
    pairs (broker, timeframe, modelling_mode, set_file, market_data_id,
    cost notes) are all REQUIRED and either enforced against the actual
    data or cross-checked for equality AND non-blank content (see their
    own parameter comments) -- a complete comparability manifest, not an
    optional best-effort assertion a caller could silently omit or
    satisfy with two equal empty strings. EA version and data source are
    likewise now REQUIRED (never silently null) but, unlike those seven,
    are deliberately NOT cross-checked for equality -- a baseline/
    candidate comparison's entire premise is that the two releases (and
    often their export source) legitimately differ.

    **Disclosed, not closed, 2026-07-22 Codex review finding (sixth
    round): set_file/market_data_id/cost notes remain caller-asserted
    free-text labels, not bound to a manifest or source-file hash** --
    genuinely authenticating them (e.g. hashing the real .set file, or
    a real market-data export) needs inputs this project does not have
    yet (TASK-037_MT5_EXPORT_BRIDGE.md); non-blank/equality checking is
    what is actually enforceable from a string label alone.

    Raises ValueError if any required baseline/candidate manifest pair
    (broker, timeframe, modelling_mode, set_file, market_data_id, spread
    note, slippage note) is blank or differs between the two sides, or if
    EA version/data source is blank on either side. Raises
    CsvSchemaError if any trade in either dataset falls outside
    [period_start, period_end].
    """

    for label, base_val, cand_val in (
        ("broker", baseline_broker, candidate_broker),
        ("timeframe", baseline_timeframe, candidate_timeframe),
        ("modelling_mode", baseline_modelling_mode, candidate_modelling_mode),
        ("set_file", baseline_set_file, candidate_set_file),
        ("market_data_id", baseline_market_data_id, candidate_market_data_id),
        ("spread_note", baseline_spread_note, candidate_spread_note),
        ("slippage_note", baseline_slippage_note, candidate_slippage_note),
    ):
        # **Added, 2026-07-22 Codex review finding (sixth round): all
        # seven pairs above were checked ONLY for equality, never for
        # nonblank content -- a direct probe with every pair blank on
        # both sides ("" == "") previously succeeded outright.**
        if not isinstance(base_val, str) or not base_val.strip():
            raise ValueError(
                f"compare_releases: baseline_{label} must be a nonblank string, got {base_val!r}"
            )
        if not isinstance(cand_val, str) or not cand_val.strip():
            raise ValueError(
                f"compare_releases: candidate_{label} must be a nonblank string, got {cand_val!r}"
            )
        if base_val != cand_val:
            raise ValueError(
                f"compare_releases: baseline_{label} ({base_val!r}) != "
                f"candidate_{label} ({cand_val!r}) -- the comparability contract requires "
                f"identical {label} between baseline and candidate"
            )

    # **Added, 2026-07-22 Codex review finding (sixth round): ea_version/
    # data_source are now REQUIRED (never silently null) -- but, UNLIKE
    # the seven pairs above, they are deliberately NOT required to be
    # EQUAL between baseline and candidate: a baseline/candidate
    # comparison's entire premise is that the two releases (and often
    # their export source) legitimately DIFFER, which is exactly what
    # test_baseline_and_candidate_ea_version_recorded_separately already
    # exercises.**
    for label, value in (
        ("baseline_ea_version", baseline_ea_version),
        ("candidate_ea_version", candidate_ea_version),
        ("baseline_data_source", baseline_data_source),
        ("candidate_data_source", candidate_data_source),
    ):
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"compare_releases: {label} must be a nonblank string, got {value!r}")

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

    baseline, baseline_csv_hash = _load_trades_with_r_multiple(baseline_csv, symbol)
    candidate, candidate_csv_hash = _load_trades_with_r_multiple(candidate_csv, symbol)

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
    # **Fixed, 2026-07-22 Codex review finding (sixth round): this
    # function's own n_resamples/confidence (already used for the
    # TOP-LEVEL win_rate_diff/expectancy_r_diff below) were previously
    # never forwarded into either nested summary -- a probe with
    # n_resamples=100, confidence=0.9 returned those values at the top
    # level while baseline_summary/candidate_summary silently kept
    # compute_trade_summary's own defaults (2000/0.95), reporting
    # internally DIFFERENT inferential configurations inside one JSON
    # artifact.**
    baseline_summary = compute_trade_summary(
        baseline.sort_values("exit_time"),
        starting_balance=starting_balance,
        seed=seed,
        n_resamples=n_resamples,
        confidence=confidence,
        giveback_arm_percent=giveback_arm_percent,
        giveback_floor_percent=giveback_floor_percent,
        evaluation_period_days=claimed_period_days,
    )
    candidate_summary = compute_trade_summary(
        candidate.sort_values("exit_time"),
        starting_balance=starting_balance,
        seed=seed,
        n_resamples=n_resamples,
        confidence=confidence,
        giveback_arm_percent=giveback_arm_percent,
        giveback_floor_percent=giveback_floor_percent,
        evaluation_period_days=claimed_period_days,
    )

    def _point_diff(
        candidate_val: Optional[float], baseline_val: Optional[float], label: str
    ) -> Optional[float]:
        # Point difference only (no CI) -- these are single-run
        # descriptive statistics, not resampled distributions; None
        # propagates when either side has an undefined statistic (e.g.
        # profit_factor with zero losses, recovery_factor with zero
        # drawdown) rather than a misleading fabricated number.
        if candidate_val is None or baseline_val is None:
            return None
        diff = candidate_val - baseline_val
        # **Added, 2026-07-22 Codex review finding (sixth round): two
        # individually finite summary values (e.g. net_profit at opposite
        # extreme magnitudes) can still overflow to a non-finite
        # DIFFERENCE -- a reproduced probe produced surface_diff.
        # net_profit == inf from finite baseline/candidate summaries with
        # no error raised anywhere.**
        if not math.isfinite(diff):
            raise ValueError(
                f"compare_releases: surface_diff.{label} overflowed to a non-finite value "
                f"({diff!r}) from candidate={candidate_val!r}, baseline={baseline_val!r}"
            )
        return diff

    _SURFACE_DIFF_FIELDS: tuple[tuple[str, Optional[float], Optional[float]], ...] = (
        ("net_profit", candidate_summary["net_profit"], baseline_summary["net_profit"]),
        ("profit_factor", candidate_summary["profit_factor"], baseline_summary["profit_factor"]),
        (
            "max_balance_drawdown_pct",
            candidate_summary["max_balance_drawdown_pct"],
            baseline_summary["max_balance_drawdown_pct"],
        ),
        (
            "recovery_factor",
            candidate_summary["recovery_factor"],
            baseline_summary["recovery_factor"],
        ),
        (
            "balance_peak_giveback_n_trigger_events",
            candidate_summary["balance_peak_giveback"]["n_trigger_events"],
            baseline_summary["balance_peak_giveback"]["n_trigger_events"],
        ),
        (
            "balance_peak_giveback_max_giveback_pct",
            candidate_summary["balance_peak_giveback"]["max_giveback_pct"],
            baseline_summary["balance_peak_giveback"]["max_giveback_pct"],
        ),
        (
            "longest_losing_streak",
            candidate_summary["longest_losing_streak"],
            baseline_summary["longest_losing_streak"],
        ),
        (
            "avg_winner_dollars",
            candidate_summary["avg_winner_dollars"],
            baseline_summary["avg_winner_dollars"],
        ),
        (
            "avg_loser_dollars",
            candidate_summary["avg_loser_dollars"],
            baseline_summary["avg_loser_dollars"],
        ),
        (
            "avg_trade_duration_minutes",
            candidate_summary["avg_trade_duration_minutes"],
            baseline_summary["avg_trade_duration_minutes"],
        ),
        ("trades_per_day", candidate_summary["trades_per_day"], baseline_summary["trades_per_day"]),
    )
    surface_diff = {
        label: _point_diff(cand_val, base_val, label)
        for label, cand_val, base_val in _SURFACE_DIFF_FIELDS
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
        # **Fixed, 2026-07-22 Codex review finding (fifth round):** every
        # pair below is now REQUIRED and EQUALITY-VERIFIED above (raising
        # ValueError on mismatch, not just "when both sides happen to be
        # supplied") -- recording both role-specific values here documents
        # a complete, actually-checked comparability manifest, not a
        # best-effort optional assertion.
        "baseline_broker": baseline_broker,
        "candidate_broker": candidate_broker,
        "baseline_timeframe": baseline_timeframe,
        "candidate_timeframe": candidate_timeframe,
        "baseline_modelling_mode": baseline_modelling_mode,
        "candidate_modelling_mode": candidate_modelling_mode,
        "baseline_set_file": baseline_set_file,
        "candidate_set_file": candidate_set_file,
        # **Added, 2026-07-22 Codex review finding (fifth round):** proves
        # (as an asserted, cross-checked identifier -- not derived from
        # the trade files themselves, which cannot establish this) that
        # both runs were replayed against the SAME underlying raw
        # market-data segment. Role-specific output trade-file hashes
        # above prove only that the two TRADE files differ; they say
        # nothing about whether the source market data matched.
        "baseline_market_data_id": baseline_market_data_id,
        "candidate_market_data_id": candidate_market_data_id,
        # **Added, 2026-07-22 Codex review finding (fifth round):** costs
        # were previously a single shared spread_note/slippage_note pair
        # -- "a shared trusted note", not a verified comparability check.
        "spread_note": baseline_spread_note,
        "slippage_note": baseline_slippage_note,
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
        # **Fixed, 2026-07-22 Codex review finding (sixth round): both
        # role-specific hashes above, AND the combined hash passed to
        # build_report_metadata below, were previously each a SEPARATE
        # re-read of baseline_csv/candidate_csv -- independent of the
        # single read '_load_trades_with_r_multiple' already did to
        # produce 'baseline'/'candidate' above. All three now reuse the
        # exact hash computed during that one read.**
        summary["baseline_dataset_hash"] = baseline_csv_hash
        summary["candidate_dataset_hash"] = candidate_csv_hash
        combined_hash = combine_labeled_hashes(
            [(baseline_csv.name, baseline_csv_hash), (candidate_csv.name, candidate_csv_hash)]
        )
        metadata = build_report_metadata(
            [baseline_csv, candidate_csv],
            symbol=symbol,
            broker=baseline_broker,
            period_start=period_start,
            period_end=period_end,
            timeframe=baseline_timeframe,
            modelling_mode=baseline_modelling_mode,
            set_file=baseline_set_file,
            random_seed=seed,
            # Cross-checked equal to candidate's own above -- either side
            # is an equally valid value to persist here.
            spread_note=baseline_spread_note,
            slippage_note=baseline_slippage_note,
            repo_path=repo_path,
            dataset_hash_override=combined_hash,
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
    # **Fixed, 2026-07-22 Codex review finding (fifth round): these were
    # previously optional and compared only when both sides were
    # supplied -- now required, matching run()'s own signature.**
    parser.add_argument("--baseline-broker", required=True)
    parser.add_argument("--candidate-broker", required=True)
    parser.add_argument("--baseline-timeframe", required=True)
    parser.add_argument("--candidate-timeframe", required=True)
    parser.add_argument("--baseline-modelling-mode", required=True)
    parser.add_argument("--candidate-modelling-mode", required=True)
    parser.add_argument("--baseline-set-file", required=True)
    parser.add_argument("--candidate-set-file", required=True)
    # **Added, 2026-07-22 Codex review finding (fifth round): asserts both
    # runs were replayed against the SAME underlying raw market-data
    # segment -- see run()'s own comment for why this cannot be derived
    # from the trade files themselves.**
    parser.add_argument("--baseline-market-data-id", required=True)
    parser.add_argument("--candidate-market-data-id", required=True)
    parser.add_argument("--baseline-ea-version", required=True)
    parser.add_argument("--candidate-ea-version", required=True)
    parser.add_argument("--baseline-data-source", required=True)
    parser.add_argument("--candidate-data-source", required=True)
    # **Fixed, 2026-07-22 Codex review finding (fifth round): costs were
    # previously a single shared --spread-note/--slippage-note pair --
    # now role-specific and required, matching run()'s own signature.**
    parser.add_argument("--baseline-spread-note", required=True)
    parser.add_argument("--candidate-spread-note", required=True)
    parser.add_argument("--baseline-slippage-note", required=True)
    parser.add_argument("--candidate-slippage-note", required=True)
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
            baseline_market_data_id=args.baseline_market_data_id,
            candidate_market_data_id=args.candidate_market_data_id,
            baseline_ea_version=args.baseline_ea_version,
            candidate_ea_version=args.candidate_ea_version,
            baseline_data_source=args.baseline_data_source,
            candidate_data_source=args.candidate_data_source,
            baseline_spread_note=args.baseline_spread_note,
            candidate_spread_note=args.candidate_spread_note,
            baseline_slippage_note=args.baseline_slippage_note,
            candidate_slippage_note=args.candidate_slippage_note,
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
