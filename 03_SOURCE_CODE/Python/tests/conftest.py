"""Shared pytest fixtures -- synthetic data only, per the reproducibility
contract ("if real evidence data is unavailable, tests use clearly labelled
synthetic fixtures... rather than fabricate results"). No file under
01_BASELINE/ or any real account export is read by any test here."""

from __future__ import annotations

import json
from pathlib import Path

import pytest


def make_valid_record(**overrides) -> dict:
    """A schema-valid TradeDecision dict, matching TRADE_DECISION_SCHEMA.json
    exactly -- and, as of TASK-040 (2026-07-22), the shape the live EA
    build actually produces (market_family/intraday_mode are both
    populated on every real journal line; see schema.py's docstring)."""

    record = {
        "signal_id": "sig-0001",
        "timestamp_utc": "2026-07-21T14:05:30Z",
        "symbol": "XAUUSD",
        "market_family": "METAL",
        "intraday_mode": "SCALP",
        "regime": "REGIME_TRENDING_UP",
        "regime_confidence": 72.5,
        "direction": "BUY",
        "strategy": "TrendFollowingStrategy",
        "setup": "TrendlinePullback",
        "candlestick_pattern": "BullishEngulfing",
        "chart_pattern": None,
        "score": 68.0,
        "score_breakdown": {"base": 68.0},
        "entry": 2350.55,
        "stop": 2345.10,
        "targets": [2361.45],
        "risk_percent": 0.3,
        "news_state": "CLEAR",
        "session_state": "SESSION_TIME_REMAINING_HIGH",
        "reasons_passed": ["daily_weekly_loss_caps_clear"],
        "reasons_rejected": [],
        "ea_version": "1.01-task027-order-submission-optional",
        "git_commit": "ddcee10",
    }
    record.update(overrides)
    return record


def make_schema_invalid_record(**overrides) -> dict:
    """A generically schema-INVALID record (blank signal_id/market_family/
    intraday_mode) -- used by several tests below purely as a known-bad
    fixture to prove invalid-record handling (rejection, error surfacing,
    row-error reporting), not as a claim about any particular EA build's
    real output. **Renamed, 2026-07-22 (Codex review finding, seventh
    round, P1 finding 18): this was previously named
    make_current_ea_record and documented as "what the live EA actually
    emits today" -- TASK-040 has since wired market_family/intraday_mode
    into the live journal, so that claim is no longer true; this fixture
    is now honestly framed as a synthetic invalid-record generator, not a
    live-behavior snapshot.**"""

    record = make_valid_record(signal_id="", market_family="", intraday_mode="")
    record.update(overrides)
    return record


@pytest.fixture
def valid_record() -> dict:
    return make_valid_record()


@pytest.fixture
def schema_invalid_record() -> dict:
    return make_schema_invalid_record()


@pytest.fixture
def journal_dir_factory(tmp_path):
    """Returns a function that writes a decisions_YYYYMMDD.jsonl file with
    the given list of already-JSON-serializable dict/str lines, and returns
    the containing directory."""

    def _write(filename: str, lines: list) -> Path:
        path = tmp_path / filename
        with path.open("w", encoding="utf-8") as fh:
            for line in lines:
                if isinstance(line, str):
                    fh.write(line + "\n")
                else:
                    fh.write(json.dumps(line) + "\n")
        return tmp_path

    return _write
