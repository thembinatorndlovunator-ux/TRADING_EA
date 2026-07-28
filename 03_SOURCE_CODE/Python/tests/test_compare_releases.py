from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.compare_releases import (
    MAX_N_RESAMPLES,
    MIN_N_PER_GROUP,
    MIN_N_RESAMPLES,
    main,
    two_sample_bootstrap_diff,
)
from analysis.compare_releases import run as _real_run
from analysis.csv_io import CsvSchemaError
from analysis.metrics import InsufficientSampleError

REPO_ROOT = Path(__file__).resolve().parents[3]

# **Added, 2026-07-22 Codex review finding (fourth round): period_start/
# period_end are now required run() parameters -- a wide default window
# covering every fixture's default 2026-07-21 entry/exit timestamps below.**
DEFAULT_PERIOD_START = "2026-01-01T00:00:00Z"
DEFAULT_PERIOD_END = "2026-12-31T23:59:59Z"

# **Added, 2026-07-22 Codex review finding (fifth round): broker/
# timeframe/modelling_mode/set_file/market_data_id/spread_note/
# slippage_note are now REQUIRED, role-specific run() parameters (see
# that module's own docstring). Every test below goes through this
# wrapper so it doesn't need its own boilerplate default for all seven
# pairs -- a test that cares about a SPECIFIC field (e.g. testing a
# mismatch) passes that field explicitly, which overrides the default.**
_DEFAULT_MANIFEST_KWARGS = dict(
    baseline_broker="Deriv",
    candidate_broker="Deriv",
    baseline_timeframe="M5",
    candidate_timeframe="M5",
    baseline_modelling_mode="every_tick",
    candidate_modelling_mode="every_tick",
    baseline_set_file="default.set",
    candidate_set_file="default.set",
    baseline_market_data_id="synthetic-fixture-v1",
    candidate_market_data_id="synthetic-fixture-v1",
    baseline_spread_note="2-pip fixed spread assumed",
    candidate_spread_note="2-pip fixed spread assumed",
    baseline_slippage_note="no slippage modelled",
    candidate_slippage_note="no slippage modelled",
    # **Added, 2026-07-22 Codex review finding (sixth round): ea_version/
    # data_source are now REQUIRED, not optional -- see run()'s own
    # docstring.**
    baseline_ea_version="v6.37",
    candidate_ea_version="v6.37",
    baseline_data_source="synthetic-fixture",
    candidate_data_source="synthetic-fixture",
)


def run(*args, **kwargs):
    return _real_run(*args, **{**_DEFAULT_MANIFEST_KWARGS, **kwargs})


def _write_trades(
    path: Path, exits: list[float], profits: list[float], symbol: str = "XAUUSD"
) -> None:
    rows = []
    for i, (exit_price, profit) in enumerate(zip(exits, profits)):
        rows.append(
            {
                "trade_id": f"t{i}",
                "symbol": symbol,
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": exit_price,
                "stop_price": 98.0,
                "profit": profit,
            }
        )
    pd.DataFrame(rows).to_csv(path, index=False)


# --- two_sample_bootstrap_diff -------------------------------------------------


def test_insufficient_sample_below_min_n_per_group_raises():
    """Regression for a Codex review finding: previously only required
    n>=2 per group, which let a degenerate 2-observation sample "bless"
    a fake significant result (see test below)."""

    with pytest.raises(InsufficientSampleError):
        two_sample_bootstrap_diff(
            [1.0] * (MIN_N_PER_GROUP - 1),
            [1.0] * MIN_N_PER_GROUP,
            n_resamples=MIN_N_RESAMPLES,
            seed=1,
        )


def test_degenerate_two_observation_sample_no_longer_blessed_as_significant():
    """Regression for a Codex review finding: two constant observations
    per group (e.g. [0,1] vs [0,1]) previously passed straight through and
    could report a spurious `likely_significant=True` result from a
    single resample. This must now be rejected outright as too small."""

    with pytest.raises(InsufficientSampleError):
        two_sample_bootstrap_diff([0.0, 1.0], [0.0, 1.0], n_resamples=1, seed=42)


def test_below_minimum_n_resamples_rejected():
    with pytest.raises(ValueError):
        two_sample_bootstrap_diff(
            [1.0] * MIN_N_PER_GROUP,
            [1.0] * MIN_N_PER_GROUP,
            n_resamples=MIN_N_RESAMPLES - 1,
            seed=1,
        )


def test_above_maximum_n_resamples_rejected():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    no upper bound previously existed on n_resamples anywhere in this
    project, permitting an accidental unbounded memory/time request."""

    with pytest.raises(ValueError):
        two_sample_bootstrap_diff(
            [1.0] * MIN_N_PER_GROUP,
            [1.0] * MIN_N_PER_GROUP,
            n_resamples=MAX_N_RESAMPLES + 1,
            seed=1,
        )


def test_two_sample_bootstrap_diff_rejects_non_finite_values():
    """Regression for a Codex review finding (2026-07-22, third round):
    a non-finite value in either sample previously silently produced NaN
    point/interval fields instead of a visible error."""

    good = [1.0] * 10
    bad = [1.0] * 9 + [float("nan")]
    with pytest.raises(ValueError):
        two_sample_bootstrap_diff(bad, good, MIN_N_RESAMPLES, seed=1)
    with pytest.raises(ValueError):
        two_sample_bootstrap_diff(good, bad, MIN_N_RESAMPLES, seed=1)


def test_two_sample_bootstrap_diff_rejects_overflow_to_non_finite_from_finite_inputs():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    every individual value is finite, but the mean/difference of finite
    values can still overflow -- the exact reproduced counterexample, two
    ten-value samples at opposite 1e308 magnitudes, previously returned an
    observed difference of -inf and a CI of [nan, nan] instead of
    raising."""

    high = [1e308] * 10
    low = [-1e308] * 10
    with pytest.raises(ValueError):
        two_sample_bootstrap_diff(high, low, MIN_N_RESAMPLES, seed=1)


def test_confidence_out_of_range_rejected():
    with pytest.raises(ValueError):
        two_sample_bootstrap_diff(
            [1.0] * MIN_N_PER_GROUP,
            [1.0] * MIN_N_PER_GROUP,
            n_resamples=MIN_N_RESAMPLES,
            seed=1,
            confidence=1.5,
        )


def test_observed_diff_is_the_actual_difference_not_a_resampled_mean():
    """Regression for a Codex review finding (2026-07-21): the point
    estimate was previously mean(diffs across resamples) -- a RANDOM
    quantity -- rather than the actual observed difference on the real
    data. Constant data makes both quantities identical, so this alone
    would not have caught the bug; the key assertion is that observed_diff
    is deterministic and matches the exact arithmetic difference of means,
    independent of n_resamples/seed (see the next test)."""

    baseline = [1.0] * MIN_N_PER_GROUP
    candidate = [2.0] * MIN_N_PER_GROUP
    result = two_sample_bootstrap_diff(baseline, candidate, n_resamples=MIN_N_RESAMPLES, seed=1)
    assert result.observed_diff == pytest.approx(1.0)  # 2.0 - 1.0, exactly
    assert result.ci_lower == pytest.approx(1.0)
    assert result.ci_upper == pytest.approx(1.0)


def test_observed_diff_is_seed_and_resample_count_invariant():
    """The critical property the bug violated: the OBSERVED difference
    must not depend on the seed or n_resamples -- only the CI bounds
    (uncertainty around it) may."""

    baseline = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    candidate = [4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0]
    expected_diff = (sum(candidate) / len(candidate)) - (sum(baseline) / len(baseline))

    result_a = two_sample_bootstrap_diff(baseline, candidate, n_resamples=100, seed=1)
    result_b = two_sample_bootstrap_diff(baseline, candidate, n_resamples=5000, seed=999)

    assert result_a.observed_diff == pytest.approx(expected_diff)
    assert result_b.observed_diff == pytest.approx(expected_diff)
    assert result_a.observed_diff == result_b.observed_diff


def test_identical_distributions_not_significant():
    values = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    result = two_sample_bootstrap_diff(values, values, n_resamples=1000, seed=1)
    assert result.observed_diff == pytest.approx(0.0)
    assert result.likely_significant is False


def test_deterministic_given_same_seed():
    a = two_sample_bootstrap_diff([1.0, 2.0, 3.0] * 4, [4.0, 5.0, 6.0] * 4, n_resamples=200, seed=7)
    b = two_sample_bootstrap_diff([1.0, 2.0, 3.0] * 4, [4.0, 5.0, 6.0] * 4, n_resamples=200, seed=7)
    assert a == b


# --- run() ---------------------------------------------------------------------


def test_missing_column_raises(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    pd.DataFrame({"trade_id": ["t1"]}).to_csv(baseline_path, index=False)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_empty_dataset_raises(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    pd.DataFrame(
        columns=[
            "trade_id",
            "symbol",
            "is_long",
            "entry_time",
            "exit_time",
            "entry_price",
            "exit_price",
            "stop_price",
            "profit",
        ]
    ).to_csv(baseline_path, index=False)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(InsufficientSampleError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_n_resamples_and_confidence_forwarded_into_nested_summaries(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round):
    n_resamples/confidence were previously used for the TOP-LEVEL
    win_rate_diff/expectancy_r_diff inference but never forwarded into
    baseline_summary/candidate_summary -- a probe with n_resamples=100,
    confidence=0.9 returned those values at the top level while the
    nested summaries silently kept compute_trade_summary's own defaults
    (2000/0.95), reporting internally DIFFERENT inferential
    configurations inside one JSON artifact."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 15 + [105.0] * 5, [-10.0] * 15 + [10.0] * 5)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 15 + [95.0] * 5, [10.0] * 15 + [-10.0] * 5)

    summary = run(
        baseline_path,
        candidate_path,
        n_resamples=100,
        confidence=0.90,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
    )
    assert summary["expectancy_r_diff"]["n_resamples"] == 100
    assert summary["baseline_summary"]["expectancy_dollars"]["n_resamples"] == 100
    assert summary["baseline_summary"]["expectancy_dollars"]["confidence"] == 0.90
    assert summary["candidate_summary"]["expectancy_dollars"]["n_resamples"] == 100
    assert summary["candidate_summary"]["expectancy_dollars"]["confidence"] == 0.90


def test_surface_diff_net_profit_overflow_is_a_visible_error(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round):
    two individually finite baseline/candidate net_profit summary values
    at opposite extreme magnitudes previously produced
    surface_diff.net_profit == inf with no error raised anywhere --
    _point_diff never checked its own DIFFERENCE for finiteness."""

    def _extreme_rows(profit: float) -> list[dict]:
        return [
            {
                "trade_id": f"t{i}",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": profit,
            }
            for i in range(10)
        ]

    baseline_path = tmp_path / "baseline.csv"
    pd.DataFrame(_extreme_rows(1.5e307)).to_csv(baseline_path, index=False)
    candidate_path = tmp_path / "candidate.csv"
    pd.DataFrame(_extreme_rows(-1.5e307)).to_csv(candidate_path, index=False)

    with pytest.raises(ValueError, match="net_profit"):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_leading_zero_trade_id_not_collapsed_by_numeric_inference(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round):
    'trade_id' was previously read via plain pandas type inference -- a
    CSV containing IDs "001" and "1" loaded as integer values 1, 1 and
    was rejected as a false duplicate."""

    baseline_path = tmp_path / "baseline.csv"
    rows = []
    for trade_id in ["001", "1"] + [f"t{i}" for i in range(2, 10)]:
        rows.append(
            {
                "trade_id": trade_id,
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 10.0,
            }
        )
    pd.DataFrame(rows).to_csv(baseline_path, index=False)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 10, [10.0] * 10)

    summary = run(
        baseline_path,
        candidate_path,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
    )
    assert summary["n_baseline_trades"] == 10


def test_duplicate_trade_id_rejected(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    pd.DataFrame(
        [
            {
                "trade_id": "dup",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 102.0,
                "stop_price": 98.0,
                "profit": 10.0,
            },
            {
                "trade_id": "dup",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 99.0,
                "stop_price": 98.0,
                "profit": -5.0,
            },
        ]
    ).to_csv(baseline_path, index=False)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_symbol_filter_rejects_mismatched_rows(tmp_path):
    """Regression for a Codex review finding: the `symbol` parameter
    previously only labelled metadata and did not validate either input,
    so arbitrary/incomparable datasets could be silently compared."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12, symbol="EURUSD")
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12, symbol="XAUUSD")

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            symbol="XAUUSD",
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_no_symbol_filter_still_rejects_datasets_covering_different_symbols(tmp_path):
    """Regression for a Codex review finding (2026-07-22): with NO
    'symbol' filter supplied at all, the two datasets' own symbol sets
    were never checked against EACH OTHER -- an EURUSD baseline vs. an
    XAUUSD candidate was accepted and compared as if they were the same
    instrument. This must be rejected even when the caller never passes
    'symbol'."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12, symbol="EURUSD")
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12, symbol="XAUUSD")

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )  # no symbol= at all


def test_impossible_chronology_rejected(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    rows = []
    for i in range(12):
        rows.append(
            {
                "trade_id": f"t{i}",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-22T00:00:00Z",
                "exit_time": "2026-07-21T00:00:00Z",  # entry after exit
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 10.0,
            }
        )
    pd.DataFrame(rows).to_csv(candidate_path, index=False)

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_disjoint_trade_periods_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    only symbol sets were checked -- a same-symbol January-2026 baseline
    vs. January-2025 candidate was still accepted and compared as if the
    two experiments covered the same market period.

    **Corrected, 2026-07-22 Codex review finding (fourth round): the old
    mechanism (checking whether the two datasets' own observed ranges
    overlap) let a baseline spanning Jan 1-31 and a candidate spanning
    Jan 31-Feb 28 pass because the ranges touch at one instant --
    period_start/period_end are now a mandatory, caller-claimed window
    that every trade in BOTH datasets must fall inside. This test now
    proves the 2025 baseline is rejected against a claimed 2026-only
    comparison window, which subsumes the old disjoint-ranges case.**"""

    baseline_path = tmp_path / "baseline.csv"
    rows_2025 = []
    for i in range(12):
        rows_2025.append(
            {
                "trade_id": f"t{i}",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2025-01-01T00:00:00Z",
                "exit_time": "2025-01-01T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 10.0,
            }
        )
    pd.DataFrame(rows_2025).to_csv(baseline_path, index=False)

    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)  # 2026-07-21, per _write_trades

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_trade_touching_period_boundary_still_rejected_if_outside(tmp_path):
    """Regression for the exact reproduced counterexample (2026-07-22,
    fourth round): a baseline spanning Jan 1-31 and a candidate spanning
    Jan 31-Feb 28 previously passed the old overlap check because the
    ranges touch at one instant. Claiming a Jan-only comparison period
    must reject the candidate's February trade."""

    baseline_path = tmp_path / "baseline.csv"
    rows = []
    for i in range(12):
        rows.append(
            {
                "trade_id": f"t{i}",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-01-01T00:00:00Z",
                "exit_time": "2026-01-01T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 10.0,
            }
        )
    pd.DataFrame(rows).to_csv(baseline_path, index=False)

    candidate_path = tmp_path / "candidate.csv"
    rows2 = []
    for i in range(12):
        rows2.append(
            {
                "trade_id": f"t{i}",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-02-27T00:00:00Z",
                "exit_time": "2026-02-27T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 10.0,
            }
        )
    pd.DataFrame(rows2).to_csv(candidate_path, index=False)

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            period_start="2026-01-01T00:00:00Z",
            period_end="2026-01-31T23:59:59Z",
        )


def test_manifest_field_mismatch_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    broker/timeframe/modelling_mode/set_file were a single shared,
    optional, caller-trusted assertion -- not two compared manifests.
    Supplying mismatched baseline/candidate values for the same field
    must now be rejected."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(ValueError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
            baseline_broker="Deriv",
            candidate_broker="IC Markets",
        )


def test_manifest_field_match_accepted(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    summary = run(
        baseline_path,
        candidate_path,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
        baseline_broker="Deriv",
        candidate_broker="Deriv",
    )
    assert summary["baseline_broker"] == "Deriv"
    assert summary["candidate_broker"] == "Deriv"


def test_role_preserving_dataset_hashes_differ_by_role(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    the one combined, order-independent dataset hash is not
    role-preserving -- swapping which physical file is baseline vs.
    candidate could retain the same combined hash. Separate per-role
    hashes must differ whenever the two files' content differs."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 12, [-10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)
    output_json = tmp_path / "compare.json"

    run(
        baseline_path,
        candidate_path,
        output_json=output_json,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
        repo_path=REPO_ROOT,
    )
    payload = json.loads(output_json.read_text(encoding="utf-8"))
    assert (
        payload["summary"]["baseline_dataset_hash"] != payload["summary"]["candidate_dataset_hash"]
    )


def test_baseline_and_candidate_ea_version_recorded_separately(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round): a
    single shared ea_version/data_source value is insufficient to
    identify TWO releases."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    summary = run(
        baseline_path,
        candidate_path,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
        baseline_ea_version="v6.37",
        candidate_ea_version="v8.11",
        baseline_data_source="mt5_export_a",
        candidate_data_source="mt5_export_b",
    )
    assert summary["baseline_ea_version"] == "v6.37"
    assert summary["candidate_ea_version"] == "v8.11"
    assert summary["baseline_data_source"] == "mt5_export_a"
    assert summary["candidate_data_source"] == "mt5_export_b"


@pytest.mark.parametrize(
    "field",
    [
        "baseline_broker",
        "candidate_broker",
        "baseline_timeframe",
        "candidate_timeframe",
        "baseline_modelling_mode",
        "candidate_modelling_mode",
        "baseline_set_file",
        "candidate_set_file",
        "baseline_market_data_id",
        "candidate_market_data_id",
        "baseline_spread_note",
        "candidate_spread_note",
        "baseline_slippage_note",
        "candidate_slippage_note",
    ],
)
def test_blank_manifest_pair_rejected_even_when_both_sides_agree(tmp_path, field):
    """Regression for a Codex review finding (2026-07-22, sixth round):
    all seven role-manifest pairs were checked ONLY for equality, never
    for nonblank content -- a direct probe with every pair blank on both
    sides ("" == "") previously succeeded outright."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(ValueError, match="nonblank"):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
            **{field: ""},
        )


def test_blank_ea_version_or_data_source_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round):
    ea_version/data_source remained optional and were persisted as null
    with no check at all."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(ValueError, match="nonblank"):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
            baseline_ea_version="",
        )


def test_naive_timestamp_rejected(tmp_path):
    """Regression for a Codex review finding: this script previously did
    not parse or validate entry/exit timestamps at all."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    rows = []
    for i in range(12):
        rows.append(
            {
                "trade_id": f"t{i}",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00",
                "exit_time": "2026-07-21T01:00:00",  # naive
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 10.0,
            }
        )
    pd.DataFrame(rows).to_csv(candidate_path, index=False)

    with pytest.raises(ValueError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_win_rate_diff_uses_newcombe_wilson_not_bootstrap(tmp_path):
    """Regression for a Codex review finding: bootstrapping raw 0/1
    win-rate outcomes collapses to a degenerate [1.0, 1.0] interval for
    an all-loss-vs-all-win boundary sample. This must now be a real,
    non-degenerate interval via the Newcombe-Wilson method."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 10, [-10.0] * 10)  # 10 losses
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 10, [10.0] * 10)  # 10 wins

    summary = run(
        baseline_path,
        candidate_path,
        n_resamples=2000,
        seed=1,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
    )
    win_rate_diff = summary["win_rate_diff"]
    assert win_rate_diff["method"] == "newcombe_wilson"
    assert win_rate_diff["observed_diff"] == pytest.approx(1.0)
    assert win_rate_diff["ci_upper"] == pytest.approx(1.0)
    assert win_rate_diff["ci_lower"] < win_rate_diff["ci_upper"]  # NOT degenerate


def test_output_path_colliding_with_input_rejected(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            output_json=baseline_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_stark_difference_detected(tmp_path):
    # 20 trades per dataset (well above MIN_N_PER_GROUP) -- large enough
    # for the bootstrap CI to actually resolve a 0.25 vs 0.75 win-rate gap.
    baseline_exits = [95.0] * 15 + [105.0] * 5
    baseline_profits = [-10.0] * 15 + [10.0] * 5
    candidate_exits = [105.0] * 15 + [95.0] * 5
    candidate_profits = [10.0] * 15 + [-10.0] * 5

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, baseline_exits, baseline_profits)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, candidate_exits, candidate_profits)

    summary = run(
        baseline_path,
        candidate_path,
        n_resamples=2000,
        seed=1,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
    )

    assert summary["baseline_win_rate"] == pytest.approx(0.25)
    assert summary["candidate_win_rate"] == pytest.approx(0.75)
    assert summary["baseline_expectancy_r"] == pytest.approx(-1.25)
    assert summary["candidate_expectancy_r"] == pytest.approx(1.25)
    assert summary["win_rate_diff"]["observed_diff"] == pytest.approx(
        0.5
    )  # EXACT, not resample-dependent
    assert summary["win_rate_diff"]["likely_significant"] is True


def test_writes_output_json(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 12, [-10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)
    output_json = tmp_path / "out" / "compare.json"

    run(
        baseline_path,
        candidate_path,
        output_json=output_json,
        n_resamples=100,
        seed=1,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
        repo_path=REPO_ROOT,
    )

    payload = json.loads(output_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_baseline_trades"] == 12
    assert payload["summary"]["n_candidate_trades"] == 12
    assert "metadata" in payload


def test_period_coverage_ratio_flags_a_barely_sampled_claim(tmp_path):
    """Regression for a Codex review finding (2026-07-22, seventh round,
    P1 finding 17): period_start/period_end were verified only for
    containment (every trade falls within the claimed window), and the
    full claimed duration was reported with nothing computing how much
    of it the observed data actually covers -- a one-hour sample can be
    truthfully claimed to fall "within" a full-year window. This test's
    own DEFAULT_PERIOD_START/END already span a full year while
    _write_trades' own fixture entries all fall within a single hour --
    exactly that counterexample -- so the computed coverage ratio must
    be tiny, not silently absent."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 12, [-10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)
    output_json = tmp_path / "out" / "compare.json"

    run(
        baseline_path,
        candidate_path,
        output_json=output_json,
        n_resamples=100,
        seed=1,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
        repo_path=REPO_ROOT,
    )

    payload = json.loads(output_json.read_text(encoding="utf-8"))
    summary = payload["summary"]
    assert summary["claimed_period_days"] == pytest.approx(365.0, abs=0.01)
    assert summary["baseline_observed_days"] == pytest.approx(1.0 / 24.0, abs=1e-6)
    assert summary["candidate_observed_days"] == pytest.approx(1.0 / 24.0, abs=1e-6)
    # A 1-hour sample inside a claimed 365-day window -- a genuinely tiny,
    # explicitly-visible coverage ratio, not silently reported as if the
    # full claimed duration were authenticated.
    assert summary["baseline_period_coverage_ratio"] < 0.001
    assert summary["candidate_period_coverage_ratio"] < 0.001


def test_spread_and_slippage_note_persisted(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    spread_note/slippage_note exist on ReportMetadata but no analysis
    caller exposed or populated them -- this module's own docstring
    already claimed the caller could assert cost identity, but no
    parameter existed to do so."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 12, [-10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)
    output_json = tmp_path / "out" / "compare.json"

    run(
        baseline_path,
        candidate_path,
        output_json=output_json,
        n_resamples=100,
        seed=1,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
        baseline_spread_note="2-pip fixed spread assumed",
        candidate_spread_note="2-pip fixed spread assumed",
        baseline_slippage_note="no slippage modelled",
        candidate_slippage_note="no slippage modelled",
        repo_path=REPO_ROOT,
    )

    payload = json.loads(output_json.read_text(encoding="utf-8"))
    assert payload["metadata"]["spread_note"] == "2-pip fixed spread assumed"
    assert payload["metadata"]["slippage_note"] == "no slippage modelled"


def test_role_specific_cost_notes_mismatch_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    costs were previously a single shared spread_note/slippage_note pair
    -- "a shared trusted note", not a verified comparability check.
    Mismatched baseline/candidate cost notes must now be rejected the
    same way a mismatched broker/timeframe/modelling_mode/set_file is."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(ValueError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
            baseline_spread_note="2-pip fixed spread assumed",
            candidate_spread_note="0-pip fixed spread assumed",
        )


def test_market_data_id_mismatch_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    nothing previously asserted the two runs used the SAME underlying raw
    market-data segment -- role-specific output hashes only prove the two
    TRADE files differ, not that their SOURCE data matched. A caller-
    asserted market_data_id mismatch must now be rejected."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(ValueError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
            baseline_market_data_id="vendor-export-2026-07-a",
            candidate_market_data_id="vendor-export-2026-07-b",
        )


# **Added, 2026-07-22 Codex review finding (fifth round): the CLI's own
# seven required manifest pairs (see _build_arg_parser), as a shared
# argv fragment every CLI test below appends to its own args.**
_DEFAULT_MANIFEST_ARGV = [
    "--baseline-broker",
    "Deriv",
    "--candidate-broker",
    "Deriv",
    "--baseline-timeframe",
    "M5",
    "--candidate-timeframe",
    "M5",
    "--baseline-modelling-mode",
    "every_tick",
    "--candidate-modelling-mode",
    "every_tick",
    "--baseline-set-file",
    "default.set",
    "--candidate-set-file",
    "default.set",
    "--baseline-market-data-id",
    "synthetic-fixture-v1",
    "--candidate-market-data-id",
    "synthetic-fixture-v1",
    "--baseline-spread-note",
    "2-pip fixed spread assumed",
    "--candidate-spread-note",
    "2-pip fixed spread assumed",
    "--baseline-slippage-note",
    "no slippage modelled",
    "--candidate-slippage-note",
    "no slippage modelled",
    # **Added, 2026-07-22 Codex review finding (sixth round): ea_version/
    # data_source are now REQUIRED, not optional -- see run()'s own
    # docstring.**
    "--baseline-ea-version",
    "v6.37",
    "--candidate-ea-version",
    "v6.37",
    "--baseline-data-source",
    "synthetic-fixture",
    "--candidate-data-source",
    "synthetic-fixture",
]


def test_cli_main_success(tmp_path, capsys):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 12, [-10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    exit_code = main(
        [
            "--baseline-csv",
            str(baseline_path),
            "--candidate-csv",
            str(candidate_path),
            "--n-resamples",
            "100",
            "--period-start",
            DEFAULT_PERIOD_START,
            "--period-end",
            DEFAULT_PERIOD_END,
        ]
        + _DEFAULT_MANIFEST_ARGV
    )
    assert exit_code == 0
    assert "baseline_n=12" in capsys.readouterr().out


def test_cli_main_missing_file(tmp_path, capsys):
    exit_code = main(
        [
            "--baseline-csv",
            str(tmp_path / "nope.csv"),
            "--candidate-csv",
            str(tmp_path / "nope2.csv"),
            "--period-start",
            DEFAULT_PERIOD_START,
            "--period-end",
            DEFAULT_PERIOD_END,
        ]
        + _DEFAULT_MANIFEST_ARGV
    )
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err


# --- required side-by-side comparison surface (Codex review finding, ---------
# --- 2026-07-22, fifth round) -------------------------------------------------


def test_surface_diff_hand_computed_all_winners_vs_all_losers(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    this script previously compared ONLY win rate and R-expectancy --
    TEST_PLAN.md's required side-by-side surface (profit, profit factor,
    drawdowns, recovery, giveback, streaks, duration, frequency) is now
    computed for both datasets and diffed. Hand-traced: baseline is 12
    trades all winning $10 (all same entry/exit instant, so they collapse
    into ONE balance step each); candidate is 12 trades all losing $5."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [95.0] * 12, [-5.0] * 12)

    summary = run(
        baseline_path,
        candidate_path,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
    )

    baseline_summary = summary["baseline_summary"]
    candidate_summary = summary["candidate_summary"]
    diff = summary["surface_diff"]

    # baseline: balance_curve=[1000, 1120] (12*10 summed into one step,
    # all same exit instant) -- monotonically rising, no drawdown, no
    # losers, so profit_factor/recovery_factor/avg_loser are all None.
    assert baseline_summary["net_profit"] == pytest.approx(120.0)
    assert baseline_summary["profit_factor"] is None
    assert baseline_summary["max_balance_drawdown_pct"] == pytest.approx(0.0)
    assert baseline_summary["recovery_factor"] is None
    assert baseline_summary["longest_losing_balance_step_streak"] == 0
    assert baseline_summary["avg_winner_dollars"] == pytest.approx(10.0)
    assert baseline_summary["avg_loser_dollars"] is None

    # candidate: balance_curve=[1000, 940] -- one 6% drawdown, all losers,
    # so profit_factor is defined (0.0, gross_profit=0) but
    # avg_winner/None since there are no winners. All 12 trades share the
    # SAME exit_time instant, so per the order-independent streak fix
    # (Codex review finding, 2026-07-22, fifth round) they collapse into
    # ONE balance step -- the streak is 1, not 12 (one loss STEP, not one
    # per row).
    assert candidate_summary["net_profit"] == pytest.approx(-60.0)
    assert candidate_summary["profit_factor"] == pytest.approx(0.0)
    assert candidate_summary["max_balance_drawdown_pct"] == pytest.approx(60.0 / 1000.0)
    assert candidate_summary["recovery_factor"] == pytest.approx(-1.0)
    assert candidate_summary["longest_losing_balance_step_streak"] == 1
    assert candidate_summary["avg_winner_dollars"] is None
    assert candidate_summary["avg_loser_dollars"] == pytest.approx(-5.0)

    # surface_diff: candidate - baseline, None whenever either side is
    # undefined (not fabricated as 0 or silently dropped).
    assert diff["net_profit"] == pytest.approx(-180.0)
    assert diff["profit_factor"] is None  # baseline's is None
    assert diff["max_balance_drawdown_pct"] == pytest.approx(60.0 / 1000.0)
    assert diff["recovery_factor"] is None  # baseline's is None
    assert diff["longest_losing_balance_step_streak"] == 1
    assert diff["avg_winner_dollars"] is None  # candidate's is None
    assert diff["avg_loser_dollars"] is None  # baseline's is None
    assert diff["avg_trade_duration_minutes"] == pytest.approx(0.0)


def test_surface_not_covered_present_in_real_summary(tmp_path):
    """Every comparison-surface gap this script does not (yet) close --
    MFE/MAE, dimensional breakdowns, cost sensitivity, and a genuine
    equity-based (not balance-based) peak giveback -- must have a
    concrete, non-empty explanation naming what still needs to happen,
    not a silent absence."""
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    summary = run(
        baseline_path,
        candidate_path,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
    )
    gaps = summary["surface_not_covered"]
    for key in (
        "mfe_mae",
        "dimensional_breakdowns",
        "cost_sensitivity",
        "account_or_daily_equity_peak_giveback",
    ):
        assert key in gaps
        assert isinstance(gaps[key], str) and len(gaps[key]) > 0
