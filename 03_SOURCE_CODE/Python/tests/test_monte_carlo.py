from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.csv_io import CsvSchemaError
from analysis.metrics import InsufficientSampleError
from analysis.monte_carlo import MIN_N_RESAMPLES, MIN_N_TRADES, main, run, run_monte_carlo

REPO_ROOT = Path(__file__).resolve().parents[3]

# A >= MIN_N_TRADES pnl fixture used by every test that isn't specifically
# about the MIN_N_TRADES floor itself -- 20 trades alternating small
# wins/losses, net positive.
VALID_PNL_20 = [10.0, -5.0, 20.0, -15.0, 8.0] * 4


# --- run_monte_carlo ---------------------------------------------------------


def test_empty_pnl_raises():
    with pytest.raises(InsufficientSampleError):
        run_monte_carlo([], n_resamples=100, seed=1)


def test_below_minimum_n_trades_rejected():
    """Regression for a Codex review finding (2026-07-22): resampling a
    single historical trade 2000 times previously returned a suspiciously
    "precise" degenerate interval -- more simulations cannot manufacture
    sample information a tiny underlying history never had."""

    with pytest.raises(InsufficientSampleError):
        run_monte_carlo([10.0], n_resamples=100, seed=1)
    assert MIN_N_TRADES > 1


def test_non_positive_starting_balance_rejected():
    """Regression for a Codex review finding: a zero starting balance
    (the old default) made ruin_threshold=0 trigger immediately for every
    path, and percentage drawdown became meaningless."""

    with pytest.raises(InsufficientSampleError):
        run_monte_carlo(VALID_PNL_20, n_resamples=100, seed=1, starting_balance=0.0)
    with pytest.raises(InsufficientSampleError):
        run_monte_carlo(VALID_PNL_20, n_resamples=100, seed=1, starting_balance=-500.0)


def test_non_finite_starting_balance_rejected():
    """Regression for a Codex review finding: `starting_balance <= 0` is
    False for NaN (every comparison against NaN is False in Python), so a
    NaN starting_balance previously slipped past that check entirely."""

    with pytest.raises(InsufficientSampleError):
        run_monte_carlo(VALID_PNL_20, n_resamples=100, seed=1, starting_balance=float("nan"))


def test_non_finite_pnl_rejected():
    with pytest.raises(ValueError):
        run_monte_carlo(VALID_PNL_20[:-1] + [float("nan")], n_resamples=100, seed=1)


def test_non_finite_ruin_threshold_rejected():
    with pytest.raises(ValueError):
        run_monte_carlo(VALID_PNL_20, n_resamples=100, seed=1, ruin_threshold=float("inf"))


def test_below_minimum_n_resamples_rejected():
    """Regression for a Codex review finding: no minimum n_resamples was
    enforced, allowing a meaningless single-resample "confidence interval"."""

    with pytest.raises(ValueError):
        run_monte_carlo(VALID_PNL_20, n_resamples=1, seed=1)
    assert MIN_N_RESAMPLES > 1


def test_confidence_out_of_range_raises():
    with pytest.raises(ValueError):
        run_monte_carlo(VALID_PNL_20, n_resamples=100, seed=1, confidence=1.5)


def test_zero_variance_pnl_collapses_exactly():
    """Every resample of identical P/L values produces the exact same
    balance curve regardless of draw order -- an exact, deterministic-by-
    construction property, not a randomized coincidence."""

    result = run_monte_carlo([10.0] * 20, n_resamples=100, seed=7, starting_balance=100.0)
    assert result.final_balance_mean == pytest.approx(300.0)  # 100 + 20*10
    assert result.final_balance_ci_lower == pytest.approx(300.0)
    assert result.final_balance_ci_upper == pytest.approx(300.0)
    assert result.max_drawdown_pct_mean == pytest.approx(0.0)
    assert result.n_trades == 20
    assert result.n_resamples == 100
    assert result.seed == 7


def test_deterministic_given_same_seed():
    a = run_monte_carlo(VALID_PNL_20, n_resamples=300, seed=42, starting_balance=100.0)
    b = run_monte_carlo(VALID_PNL_20, n_resamples=300, seed=42, starting_balance=100.0)
    assert a == b


def test_different_seed_can_differ():
    a = run_monte_carlo(VALID_PNL_20, n_resamples=300, seed=1, starting_balance=100.0)
    b = run_monte_carlo(VALID_PNL_20, n_resamples=300, seed=2, starting_balance=100.0)
    assert a != b


def test_ruin_threshold_none_gives_none_prob_ruin():
    result = run_monte_carlo(VALID_PNL_20, n_resamples=100, seed=1, starting_balance=100.0, ruin_threshold=None)
    assert result.prob_ruin is None
    assert result.prob_ruin_ci_lower is None
    assert result.prob_ruin_ci_upper is None
    assert result.ruin_threshold is None


def test_ruin_threshold_reachable_gives_positive_probability_with_ci():
    # A big enough loss relative to starting balance makes ruin reachable
    # on any resample that draws it early; with 500 resamples of a
    # 20-element pool containing one large loss, the chance of NEVER
    # drawing it in a way that triggers ruin is negligible.
    pnl = [-100.0] + [50.0] * 19
    result = run_monte_carlo(pnl, n_resamples=500, seed=3, starting_balance=60.0, ruin_threshold=0.0)
    assert result.prob_ruin is not None
    assert 0.0 < result.prob_ruin <= 1.0
    assert result.prob_ruin_ci_lower <= result.prob_ruin <= result.prob_ruin_ci_upper


def test_ruin_threshold_unreachable_gives_zero_probability():
    pnl = [10.0, 20.0, 30.0] * 7  # 21 trades, all positive
    result = run_monte_carlo(
        pnl, n_resamples=100, seed=1, starting_balance=1000.0, ruin_threshold=-1000.0
    )
    assert result.prob_ruin == 0.0


# --- run() (CSV wrapper) ------------------------------------------------------


def test_missing_column_raises(tmp_path):
    path = tmp_path / "trades.csv"
    pd.DataFrame({"trade_id": ["t1"]}).to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        run(path, n_resamples=100, seed=1)


def test_empty_trades_csv_raises(tmp_path):
    path = tmp_path / "trades.csv"
    pd.DataFrame(columns=["trade_id", "profit"]).to_csv(path, index=False)
    with pytest.raises(InsufficientSampleError):
        run(path, n_resamples=100, seed=1)


def test_duplicate_trade_id_rejected(tmp_path):
    path = tmp_path / "trades.csv"
    pd.DataFrame({"trade_id": ["dup", "dup"], "profit": [10.0, -5.0]}).to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        run(path, n_resamples=100, seed=1)


def test_non_finite_profit_rejected(tmp_path):
    path = tmp_path / "trades.csv"
    pd.DataFrame({"trade_id": ["t1"], "profit": [float("nan")]}).to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        run(path, n_resamples=100, seed=1)


def test_output_path_colliding_with_input_rejected(tmp_path):
    path = tmp_path / "trades.csv"
    pd.DataFrame({"trade_id": ["t1", "t2"], "profit": [10.0, -5.0]}).to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        run(path, n_resamples=100, seed=1, output_json=path)


def test_run_writes_output_json(tmp_path):
    path = tmp_path / "trades.csv"
    pd.DataFrame(
        {"trade_id": [f"t{i}" for i in range(20)], "profit": VALID_PNL_20}
    ).to_csv(path, index=False)
    output_json = tmp_path / "out" / "mc.json"

    result = run(
        path, n_resamples=100, seed=1, output_json=output_json, symbol="XAUUSD", repo_path=REPO_ROOT
    )

    assert output_json.exists()
    payload = json.loads(output_json.read_text(encoding="utf-8"))
    assert payload["result"]["n_trades"] == 20
    assert payload["metadata"]["symbol"] == "XAUUSD"
    assert result.n_trades == 20


def test_cli_main_success(tmp_path, capsys):
    path = tmp_path / "trades.csv"
    pd.DataFrame(
        {"trade_id": [f"t{i}" for i in range(20)], "profit": VALID_PNL_20}
    ).to_csv(path, index=False)
    exit_code = main(["--trades-csv", str(path), "--seed", "1", "--n-resamples", "100"])
    assert exit_code == 0
    assert "n_trades=20" in capsys.readouterr().out


def test_cli_main_missing_file(tmp_path, capsys):
    exit_code = main(["--trades-csv", str(tmp_path / "nope.csv"), "--seed", "1"])
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err
