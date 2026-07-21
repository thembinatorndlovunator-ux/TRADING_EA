from __future__ import annotations

import pandas as pd
import pytest

from analysis.csv_io import CsvSchemaError
from analysis.metrics import InsufficientSampleError
from analysis.performance_breakdown import compute_breakdown, run


def _fixture_df() -> pd.DataFrame:
    # Hand-computable: strategy A has 2 trades (1 win +50, 1 loss -20) ->
    # win_rate=0.5, expectancy=15.0. Strategy B has 2 trades (both wins
    # +10, +30) -> win_rate=1.0, expectancy=20.0.
    return pd.DataFrame(
        {
            "trade_id": ["t1", "t2", "t3", "t4"],
            "strategy": ["A", "A", "B", "B"],
            "regime": [
                "REGIME_TRENDING_UP",
                "REGIME_RANGING",
                "REGIME_TRENDING_UP",
                "REGIME_RANGING",
            ],
            "profit": [50.0, -20.0, 10.0, 30.0],
        }
    )


def test_compute_breakdown_hand_computed_single_dimension():
    result = compute_breakdown(_fixture_df(), ["strategy"])
    assert len(result) == 2

    row_a = result[result["strategy"] == "A"].iloc[0]
    assert row_a["n_trades"] == 2
    assert row_a["win_rate"] == pytest.approx(0.5)
    assert row_a["expectancy_dollars"] == pytest.approx(15.0)

    row_b = result[result["strategy"] == "B"].iloc[0]
    assert row_b["n_trades"] == 2
    assert row_b["win_rate"] == pytest.approx(1.0)
    assert row_b["expectancy_dollars"] == pytest.approx(20.0)


def test_compute_breakdown_multi_dimension_hand_computed():
    result = compute_breakdown(_fixture_df(), ["strategy", "regime"])
    assert len(result) == 4  # every (strategy, regime) combination present

    row = result[(result["strategy"] == "A") & (result["regime"] == "REGIME_TRENDING_UP")].iloc[0]
    assert row["n_trades"] == 1
    assert row["expectancy_dollars"] == pytest.approx(50.0)
    # n=1 -> std_dev/CI genuinely unestimable, propagated as None, not a
    # false-precision number (see metrics.expectancy's own convention).
    assert pd.isna(row["expectancy_ci_lower"])


def test_compute_breakdown_empty_dimensions_raises():
    with pytest.raises(ValueError):
        compute_breakdown(_fixture_df(), [])


def test_compute_breakdown_unknown_dimension_raises():
    with pytest.raises(ValueError):
        compute_breakdown(_fixture_df(), ["nonexistent_column"])


def test_compute_breakdown_rejects_dimension_outside_whitelist():
    """Regression for a Codex review finding (2026-07-22, third round):
    this previously accepted ANY column present in the data as a
    dimension, including 'trade_id' or 'profit' themselves, rather than
    enforcing the documented OPTIONAL_DIMENSIONS restriction."""

    df = _fixture_df()
    assert "profit" in df.columns  # a real column, but not an allowed dimension
    with pytest.raises(ValueError):
        compute_breakdown(df, ["profit"])
    with pytest.raises(ValueError):
        compute_breakdown(df, ["trade_id"])


def test_compute_breakdown_reports_r_multiple_expectancy_when_present():
    """Regression for a Codex review finding (2026-07-22, third round):
    the documented r_multiple input was accepted but never used -- only
    dollar expectancy was ever reported."""

    df = _fixture_df()  # trade_id t1-t4: strategy A (t1,t2), strategy B (t3,t4)
    df["r_multiple"] = [2.0, -0.5, 0.5, 1.0]
    result = compute_breakdown(df, ["strategy"])
    row_a = result[result["strategy"] == "A"].iloc[0]
    assert row_a["expectancy_r"] == pytest.approx(0.75)  # mean(2.0, -0.5)


def test_compute_breakdown_seed_actually_used():
    """Regression for a Codex review finding (2026-07-22, third round):
    compute_breakdown ignored the caller's seed entirely and always used
    expectancy()'s own hidden default. A group of only 2 values has too
    small a bootstrap support for the seed to visibly change percentile
    bounds (min/max dominate regardless of seed), so this uses a
    skewed 6-value group where the seed's effect is actually detectable."""

    df = pd.DataFrame(
        {
            "trade_id": [f"t{i}" for i in range(6)],
            "strategy": ["A"] * 6,
            "profit": [1.0, 2.0, 3.0, 4.0, 5.0, 100.0],
        }
    )
    result_a = compute_breakdown(df, ["strategy"], seed=1)
    result_b = compute_breakdown(df, ["strategy"], seed=1)
    result_c = compute_breakdown(df, ["strategy"], seed=2)
    pd.testing.assert_frame_equal(result_a, result_b)
    assert not result_a["expectancy_ci_lower"].equals(
        result_c["expectancy_ci_lower"]
    ) or not result_a["expectancy_ci_upper"].equals(result_c["expectancy_ci_upper"])


def test_derive_time_dimensions_hand_computed(tmp_path):
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame(
        {
            "trade_id": ["t1", "t2"],
            "profit": [10.0, -5.0],
            "entry_time": ["2026-07-20T14:30:00Z", "2026-07-21T09:00:00Z"],  # Mon, Tue
        }
    ).to_csv(trades_csv, index=False)

    result = run(trades_csv, ["hour_of_day"])
    assert set(result["hour_of_day"]) == {14, 9}


def test_run_zero_rows_raises(tmp_path):
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame(columns=["trade_id", "profit"]).to_csv(trades_csv, index=False)
    with pytest.raises(InsufficientSampleError):
        run(trades_csv, ["strategy"])


def test_run_sanitizes_csv_formula_injection(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    sanitize_for_csv was previously applied only in the two "journal"
    scripts -- this pipeline exported caller/journal-derived dimension
    values (e.g. strategy) directly, unsanitized."""

    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame({"trade_id": ["t1"], "profit": [10.0], "strategy": ["=1+1"]}).to_csv(
        trades_csv, index=False
    )
    output_csv = tmp_path / "out.csv"

    run(trades_csv, ["strategy"], output_csv=output_csv)

    raw = output_csv.read_text(encoding="utf-8")
    assert "'=1+1" in raw


def test_run_output_paths_must_be_distinct(tmp_path):
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame({"trade_id": ["t1"], "profit": [10.0], "strategy": ["A"]}).to_csv(
        trades_csv, index=False
    )
    same_path = tmp_path / "out.json"
    with pytest.raises(CsvSchemaError):
        run(trades_csv, ["strategy"], output_csv=same_path, summary_json=same_path)
