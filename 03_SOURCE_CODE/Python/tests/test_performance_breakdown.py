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


def _session_mode_news_fixture_df() -> pd.DataFrame:
    # Same 8-row synthetic fixture as notebook 04's session/mode/news
    # outcome breakdown section (Codex review finding, 2026-07-22, fourth
    # round) -- hand-computable: OPEN=[10,10,-5,10] (n=4, win_rate=0.75,
    # expectancy=6.25), CLOSING_SOON=[-5,-5,-5,10] (n=4, win_rate=0.25,
    # expectancy=-1.25); NFP_NEARBY==in_news_blackout True=[-5,-5,-5]
    # (n=3, win_rate=0.0, expectancy=-5.0), NONE==in_news_blackout
    # False=[10,10,-5,10,10] (n=5, win_rate=0.8, expectancy=7.0).
    rows = [
        (10.0, "OPEN", "SCALP", "NONE", False),
        (10.0, "OPEN", "SCALP", "NONE", False),
        (-5.0, "OPEN", "DAY_TRADE", "NONE", False),
        (10.0, "OPEN", "DAY_TRADE", "NONE", False),
        (-5.0, "CLOSING_SOON", "SCALP", "NFP_NEARBY", True),
        (-5.0, "CLOSING_SOON", "SCALP", "NFP_NEARBY", True),
        (-5.0, "CLOSING_SOON", "DAY_TRADE", "NFP_NEARBY", True),
        (10.0, "CLOSING_SOON", "DAY_TRADE", "NONE", False),
    ]
    df = pd.DataFrame(
        rows, columns=["profit", "session_state", "intraday_mode", "news_state", "in_news_blackout"]
    )
    df.insert(0, "trade_id", [f"su{i}" for i in range(len(df))])
    return df


def test_compute_breakdown_session_state_hand_computed():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    notebook 04 previously never reported trade outcomes broken down by
    session_state/intraday_mode/news_state/in_news_blackout at all,
    despite this module already supporting all four dimensions."""

    result = compute_breakdown(_session_mode_news_fixture_df(), ["session_state"])
    open_row = result[result["session_state"] == "OPEN"].iloc[0]
    assert open_row["n_trades"] == 4
    assert open_row["win_rate"] == pytest.approx(0.75)
    assert open_row["expectancy_dollars"] == pytest.approx(6.25)
    closing_row = result[result["session_state"] == "CLOSING_SOON"].iloc[0]
    assert closing_row["n_trades"] == 4
    assert closing_row["win_rate"] == pytest.approx(0.25)
    assert closing_row["expectancy_dollars"] == pytest.approx(-1.25)


def test_compute_breakdown_intraday_mode_hand_computed():
    result = compute_breakdown(_session_mode_news_fixture_df(), ["intraday_mode"])
    scalp_row = result[result["intraday_mode"] == "SCALP"].iloc[0]
    assert scalp_row["n_trades"] == 4
    assert scalp_row["win_rate"] == pytest.approx(0.5)
    assert scalp_row["expectancy_dollars"] == pytest.approx(2.5)


def test_compute_breakdown_news_state_and_in_news_blackout_hand_computed():
    by_news = compute_breakdown(_session_mode_news_fixture_df(), ["news_state"])
    nfp_row = by_news[by_news["news_state"] == "NFP_NEARBY"].iloc[0]
    assert nfp_row["n_trades"] == 3
    assert nfp_row["win_rate"] == pytest.approx(0.0)
    assert nfp_row["expectancy_dollars"] == pytest.approx(-5.0)

    by_blackout = compute_breakdown(_session_mode_news_fixture_df(), ["in_news_blackout"])
    blackout_row = by_blackout[by_blackout["in_news_blackout"] == True].iloc[0]  # noqa: E712
    assert blackout_row["n_trades"] == 3
    assert blackout_row["expectancy_dollars"] == pytest.approx(-5.0)
    no_blackout_row = by_blackout[by_blackout["in_news_blackout"] == False].iloc[0]  # noqa: E712
    assert no_blackout_row["n_trades"] == 5
    assert no_blackout_row["win_rate"] == pytest.approx(0.8)
    assert no_blackout_row["expectancy_dollars"] == pytest.approx(7.0)


def test_compute_breakdown_rejects_news_state_in_news_blackout_contradiction():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    no cross-field validation previously existed between news_state and
    in_news_blackout -- a row with news_state="CLEAR" and
    in_news_blackout=True was silently accepted and grouped."""

    df = pd.DataFrame(
        {
            "trade_id": ["t1", "t2"],
            "profit": [10.0, -5.0],
            "news_state": ["CLEAR", "BLACKOUT"],
            "in_news_blackout": [True, False],  # both contradict news_state
        }
    )
    with pytest.raises(CsvSchemaError):
        compute_breakdown(df, ["in_news_blackout"])


def test_compute_breakdown_accepts_consistent_news_state_and_in_news_blackout():
    df = pd.DataFrame(
        {
            "trade_id": ["t1", "t2"],
            "profit": [10.0, -5.0],
            "news_state": ["CLEAR", "BLACKOUT"],
            "in_news_blackout": [False, True],  # consistent
        }
    )
    result = compute_breakdown(df, ["in_news_blackout"])
    assert len(result) == 2


def test_compute_breakdown_rejects_string_valued_in_news_blackout():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    a string-valued blackout flag (e.g. the literal text "False") was
    previously accepted -- every non-empty Python string is truthy, so it
    would silently behave as blackout=True downstream."""

    df = pd.DataFrame(
        {
            "trade_id": ["t1", "t2"],
            "profit": [10.0, -5.0],
            "in_news_blackout": ["True", "False"],  # strings, not real booleans
        }
    )
    with pytest.raises(CsvSchemaError):
        compute_breakdown(df, ["in_news_blackout"])


def test_compute_breakdown_unrelated_news_state_values_not_cross_checked():
    """news_state values outside the CLEAR/BLACKOUT vocabulary this
    project's own pipeline actually produces are not cross-checked --
    no full vocabulary is defined yet (see the module's own note)."""

    df = pd.DataFrame(
        {
            "trade_id": ["t1"],
            "profit": [10.0],
            "news_state": ["SOME_LEGACY_VALUE"],
            "in_news_blackout": [True],
        }
    )
    result = compute_breakdown(df, ["news_state"])
    assert len(result) == 1


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


def test_compute_breakdown_rejects_n_resamples_unconditionally_when_every_group_is_singleton():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    n_resamples/confidence were previously validated only INSIDE
    expectancy()'s own bootstrap branch (n>=2 per group) -- a caller
    passing n_resamples=0 was silently accepted whenever every group
    happened to be a singleton (n==1), since the bootstrap call, and the
    validation inside it, was never reached. Must now raise regardless of
    the data's actual group sizes."""

    df = pd.DataFrame({"trade_id": ["t1", "t2"], "strategy": ["A", "B"], "profit": [10.0, 20.0]})
    with pytest.raises(ValueError):
        compute_breakdown(df, ["strategy"], n_resamples=0)
    with pytest.raises(ValueError):
        compute_breakdown(df, ["strategy"], confidence=1.5)
    with pytest.raises(ValueError):
        compute_breakdown(df, ["strategy"], n_resamples=10_000_000)


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


def test_run_persists_n_resamples_and_confidence(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    n_resamples/confidence were hard-wired to expectancy()'s/win_rate()'s
    own hidden defaults and never exposed at the run()/CLI boundary or
    persisted in the report."""

    import json

    trades_csv = tmp_path / "trades.csv"
    _fixture_df().to_csv(trades_csv, index=False)
    summary_json = tmp_path / "out" / "summary.json"
    run(trades_csv, ["strategy"], summary_json=summary_json, n_resamples=500, confidence=0.90)
    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_resamples"] == 500
    assert payload["summary"]["confidence"] == 0.90


def test_summary_json_auto_derived_when_omitted(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round): a
    caller requesting output_csv without summary_json previously got a
    CSV with NO accompanying provenance metadata anywhere. An implicit
    sidecar path is now derived from output_csv."""

    import json

    trades_csv = tmp_path / "trades.csv"
    _fixture_df().to_csv(trades_csv, index=False)
    output_csv = tmp_path / "out" / "breakdown.csv"
    run(trades_csv, ["strategy"], output_csv=output_csv)

    derived_summary_json = tmp_path / "out" / "breakdown.summary.json"
    assert derived_summary_json.exists()
    payload = json.loads(derived_summary_json.read_text(encoding="utf-8"))
    assert payload["metadata"]["dataset_hash"]


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


def test_caller_supplied_hour_of_day_is_recomputed_not_trusted(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    a caller-supplied hour_of_day/day_of_week was previously trusted
    unconditionally -- the exact reproduced counterexample: a row at
    2026-01-01T02:00:00Z (a Thursday, true UTC hour 2) carrying
    hour_of_day=15/day_of_week="Sunday" was accepted and grouped under
    those WRONG values instead of being recomputed from entry_time."""

    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame(
        {
            "trade_id": ["t1"],
            "profit": [10.0],
            "entry_time": ["2026-01-01T02:00:00Z"],
            "hour_of_day": [15],
            "day_of_week": ["Sunday"],
        }
    ).to_csv(trades_csv, index=False)

    result = run(trades_csv, ["hour_of_day"])
    assert result.iloc[0]["hour_of_day"] == 2

    result_dow = run(trades_csv, ["day_of_week"])
    assert result_dow.iloc[0]["day_of_week"] == "Thursday"


def test_leading_zero_trade_id_not_collapsed_by_numeric_inference(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round):
    'trade_id' was previously read via plain pandas type inference -- a
    CSV containing IDs "001" and "1" loaded as integer values 1, 1 and
    was rejected as a false duplicate."""

    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame(
        {
            "trade_id": ["001", "1"],
            "strategy": ["A", "A"],
            "profit": [10.0, -5.0],
        }
    ).to_csv(trades_csv, index=False)

    result = run(trades_csv, ["strategy"])
    assert result["n_trades"].iloc[0] == 2


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
