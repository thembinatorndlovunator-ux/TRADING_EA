"""performance_breakdown.py -- performance (win rate, expectancy, profit
factor) grouped by any combination of strategy, setup, regime, session,
symbol, direction, hour-of-day, day-of-week, and news-blackout window --
the full breakdown master-prompt section 19 requires (previously only
partially covered, inline, by non-paired notebook logic; see this
script's own Codex review provenance below).

**Provenance (Codex review finding, 2026-07-22):** notebooks 03 and 04
previously computed a strategy/regime/session breakdown directly inside
the notebook (a made-up fixed-UTC-hour ``session_for_hour`` function for
"session", and a bare regime-only groupby with no strategy/setup
dimension for "strategy performance") instead of calling a paired `.py`
pipeline -- a violation of this project's own reproducibility contract
rule 1. This script is the real, paired, tested replacement.

**Why this is NOT built on invented session-hour buckets:**
``SessionManager.mqh`` has no fixed Asia/London/New-York UTC-hour concept
at all -- it only ever computes session-time-remaining from the BROKER'S
OWN per-symbol session calendar (``SymbolInfoSessionTrade``, a live-MT5
API this Python layer cannot call offline). Inventing a fixed-UTC-hour
substitute would not be "porting the broker-session logic" as required;
it would be re-fabricating a different, un-validated one. This script
instead consumes the journal schema's own ``session_state`` field
(``analysis.schema.TradeDecision.session_state``) -- the authoritative,
already-defined session categorization this project actually has, once
the live EA populates it (tracked under a numbered follow-up; see the
module-level "not yet real-data-capable" note below).

Required input format -- ONE unified, already-joined CSV combining both
a trade's dimensional attributes (from its journal decision) and its
outcome (profit, r_multiple), columns: ``trade_id, symbol, direction,
strategy, setup, regime, session_state, entry_time, profit,
r_multiple``. ``direction`` is ``BUY``/``SELL`` (matching
``TradeDecision.direction``, not the trades.csv schema's ``is_long``
boolean, since this pipeline's natural input is a JOINED
journal-decision + outcome record, not a raw MT5 export).

**Real-data run: PENDING.** Producing this unified CSV requires joining
a journal decision to its eventual trade outcome by a durable
signal/order/deal identity -- **the join pipeline itself now exists and
is tested** (``analysis/join_signal_to_outcome.py``, 2026-07-22), but it
is still blocked on the live EA actually POPULATING `order_id`/`deal_id`
(tracked as `TASK-036_JOURNAL_PRODUCER_COMPLETION.md`). Every dimension
this script groups by is genuinely optional except ``profit`` -- a
caller with only SOME dimensions populated (e.g. symbol/direction but
not strategy/session) still gets a real, correct breakdown over
whichever dimensions it has.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Optional, Sequence

import pandas as pd

from analysis.csv_io import (
    CsvSchemaError,
    assert_finite_columns,
    assert_output_paths_distinct,
    assert_path_not_same_file,
    assert_unique_ids,
    atomic_write_dataframe_csv,
    read_csv_with_required_columns,
    sanitize_dataframe_for_csv,
)
from analysis.metrics import InsufficientSampleError, expectancy, profit_factor, win_rate
from analysis.report_metadata import atomic_write_text, build_report_metadata
from analysis.time_utils import parse_utc_series

REQUIRED_COLUMNS = {"trade_id", "profit"}
NUMERIC_COLUMNS = ("profit",)
# Every dimension a caller MAY group by -- present/absent independently.
# **Extended, 2026-07-22 Codex review finding (third round): 'intraday_mode'
# and 'news_state'/'in_news_blackout' were missing entirely, despite the
# master prompt naming mode and news-window explicitly among the required
# breakdown dimensions.**
OPTIONAL_DIMENSIONS = (
    "symbol",
    "direction",
    "strategy",
    "setup",
    "regime",
    "session_state",
    "intraday_mode",
    "news_state",
    "in_news_blackout",
    "hour_of_day",
    "day_of_week",
)


def _derive_time_dimensions(df: pd.DataFrame) -> pd.DataFrame:
    """If 'entry_time' is present, derives 'hour_of_day' (UTC, 0-23) and
    'day_of_week' (Monday..Sunday) columns from it -- real, derived
    dimensions, not invented session buckets. A caller that already
    supplies these columns directly is left untouched."""

    if "entry_time" not in df.columns:
        return df
    df = df.copy()
    parsed = parse_utc_series(df["entry_time"])
    if "hour_of_day" not in df.columns:
        df["hour_of_day"] = parsed.dt.hour
    if "day_of_week" not in df.columns:
        df["day_of_week"] = parsed.dt.day_name()
    return df


def compute_breakdown(df: pd.DataFrame, dimensions: Sequence[str], seed: int = 42) -> pd.DataFrame:
    """Groups 'df' by 'dimensions' (each one MUST be a member of
    OPTIONAL_DIMENSIONS -- **fixed, 2026-07-22 Codex review finding
    (third round): this previously accepted ANY column present in 'df',
    including 'trade_id' or 'profit' themselves, as long as it existed --
    not the documented restricted dimension set**) and computes win_rate
    (+ Wilson CI), expectancy in dollars (+ bootstrap CI where n>=2), and
    -- when 'df' has an 'r_multiple' column -- R-expectancy too
    (**fixed, 2026-07-22 Codex review finding (third round): the
    documented r_multiple input was previously accepted but never used,
    so only dollar expectancy was ever reported**), and profit_factor per
    group. Raises ValueError if 'dimensions' is empty, contains a column
    not in OPTIONAL_DIMENSIONS, or a named dimension is not actually
    present in 'df'.

    'seed' feeds every per-group expectancy bootstrap -- **fixed,
    2026-07-22 Codex review finding (third round): this function
    previously ignored the caller's seed entirely and always used
    expectancy()'s own hidden default.**

    A group with n==0 cannot occur (groupby only yields groups with at
    least one row); a group of n==1 still reports a point expectancy with
    std_dev/CI as None, per metrics.expectancy's own convention -- never
    a false-precision number.
    """

    if not dimensions:
        raise ValueError("compute_breakdown: at least one dimension is required")
    not_allowed = [d for d in dimensions if d not in OPTIONAL_DIMENSIONS]
    if not_allowed:
        raise ValueError(
            f"compute_breakdown: dimension(s) not in OPTIONAL_DIMENSIONS: {not_allowed}"
        )
    missing = [d for d in dimensions if d not in df.columns]
    if missing:
        raise ValueError(f"compute_breakdown: dimension(s) not present in data: {missing}")

    has_r_multiple = "r_multiple" in df.columns

    rows = []
    for group_key, group_df in df.groupby(list(dimensions), dropna=False):
        key_values = group_key if isinstance(group_key, tuple) else (group_key,)
        profits = group_df["profit"].tolist()

        row: dict = dict(zip(dimensions, key_values))
        row["n_trades"] = len(group_df)

        wr = win_rate([p > 0 for p in profits])
        row["win_rate"] = wr.win_rate
        row["win_rate_ci_lower"] = wr.ci_lower
        row["win_rate_ci_upper"] = wr.ci_upper

        exp = expectancy(profits, seed=seed)
        row["expectancy_dollars"] = exp.expectancy
        row["expectancy_ci_lower"] = exp.ci_lower
        row["expectancy_ci_upper"] = exp.ci_upper

        if has_r_multiple:
            exp_r = expectancy(group_df["r_multiple"].tolist(), seed=seed)
            row["expectancy_r"] = exp_r.expectancy
            row["expectancy_r_ci_lower"] = exp_r.ci_lower
            row["expectancy_r_ci_upper"] = exp_r.ci_upper
        else:
            row["expectancy_r"] = None
            row["expectancy_r_ci_lower"] = None
            row["expectancy_r_ci_upper"] = None

        pf = profit_factor(profits)
        row["profit_factor"] = pf.profit_factor

        rows.append(row)

    columns = list(dimensions) + [
        "n_trades",
        "win_rate",
        "win_rate_ci_lower",
        "win_rate_ci_upper",
        "expectancy_dollars",
        "expectancy_ci_lower",
        "expectancy_ci_upper",
        "expectancy_r",
        "expectancy_r_ci_lower",
        "expectancy_r_ci_upper",
        "profit_factor",
    ]
    result = pd.DataFrame(rows, columns=columns)
    return result.sort_values(list(dimensions)).reset_index(drop=True)


def run(
    trades_csv: Path,
    dimensions: Sequence[str],
    output_csv: Optional[Path] = None,
    summary_json: Optional[Path] = None,
    *,
    symbol: Optional[str] = None,
    seed: int = 42,
    repo_path: Optional[Path] = None,
) -> pd.DataFrame:
    """Reads 'trades_csv' (the unified joined schema -- see module
    docstring) and computes a breakdown over 'dimensions'. Raises
    CsvSchemaError if a required column is missing/duplicate/non-finite,
    or if 'dimensions' contains a column not present in the file.
    Raises InsufficientSampleError if the file has zero rows.

    'seed' is threaded to every per-group expectancy bootstrap -- **fixed,
    2026-07-22 Codex review finding (third round): this recorded the
    supplied seed in metadata but never actually passed it to
    compute_breakdown(), which always used a hidden default instead.**
    """

    # Uses OS-level file-identity (not just Path.resolve()) so a hard
    # link to an input is also caught -- Codex review finding, third round.
    for out_path in (output_csv, summary_json):
        assert_path_not_same_file(out_path, trades_csv, "output path")
    assert_output_paths_distinct([output_csv, summary_json])

    trades = read_csv_with_required_columns(trades_csv, REQUIRED_COLUMNS)
    if trades.empty:
        raise InsufficientSampleError(f"{trades_csv}: zero trade rows")
    assert_unique_ids(trades, "trade_id", trades_csv)
    assert_finite_columns(trades, NUMERIC_COLUMNS, trades_csv)
    if "r_multiple" in trades.columns:
        assert_finite_columns(trades, ["r_multiple"], trades_csv)

    trades = _derive_time_dimensions(trades)
    result = compute_breakdown(trades, dimensions, seed=seed)

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        # Dimension values (strategy, setup, regime, session_state, etc.)
        # are caller/journal-controlled strings -- sanitized against
        # spreadsheet-formula injection before export (Codex review
        # finding, 2026-07-22, third round).
        atomic_write_dataframe_csv(sanitize_dataframe_for_csv(result), output_csv)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [trades_csv], symbol=symbol, random_seed=seed, repo_path=repo_path
        )
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "dimensions": list(dimensions),
                "n_groups": len(result),
                "n_trades_total": int(trades["trade_id"].nunique()),
            },
        }
        atomic_write_text(summary_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return result


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--dimensions", required=True, nargs="+", help="e.g. strategy regime")
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--summary-json", type=Path, default=None)
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--seed", type=int, default=42)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        result = run(
            trades_csv=args.trades_csv,
            dimensions=args.dimensions,
            output_csv=args.output_csv,
            summary_json=args.summary_json,
            symbol=args.symbol,
            seed=args.seed,
        )
    except (FileNotFoundError, CsvSchemaError, InsufficientSampleError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"performance_breakdown: {len(result)} groups over dimensions {args.dimensions}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
