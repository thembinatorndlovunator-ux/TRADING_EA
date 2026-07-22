"""calculate_mfe_mae.py -- per-trade maximum favorable/adverse excursion.

Required input format (documented here since no real MT5 export exists yet
to derive it from -- a future task bridging a real MT5 "Deals" export into
this shape is separate work, not attempted here):

``trades.csv`` columns: ``trade_id, symbol, is_long, entry_time, exit_time,
entry_price, stop_price`` (``is_long`` accepts "True"/"False"/"1"/"0",
case-insensitive; ``entry_time``/``exit_time`` must be ISO-8601 UTC, same
convention as ``DJ_FormatIso8601Utc``).

``bars.csv`` columns: ``symbol, timestamp, high, low`` (``timestamp``
ISO-8601 UTC) -- one row per completed bar, any SINGLE timeframe, covering
at least every trade's [entry_time, exit_time] window.

A trade whose window has no matching bars, or whose input row is malformed,
is recorded in the error report -- never silently dropped or defaulted to
a zero excursion (see ``trade_math.NoBarsInWindowError``'s own docstring
for why those two situations must not be conflated).

**Required ``expected_cadence_minutes``, added 2026-07-22 (Codex review
finding, fifth round):** endpoint alignment (entry_time/exit_time each
matching SOME bar) does not guarantee every bar IN BETWEEN is also
present -- a trade from 00:00 to 03:00 with bars only at 00:00 and 03:00
previously completed and reported ONE measured bar, silently ignoring
the missing 01:00/02:00 exposure. ``run()`` now requires the caller to
declare the bars' own cadence (e.g. 1.0 for M1), and a trade whose window
is not a complete, gap-free sequence at that exact cadence is now a row
error (``trade_math.IncompleteBarCoverageError``), not silently-accepted
partial evidence.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import pandas as pd

from analysis.csv_io import (
    TRADE_ID_DTYPE,
    CsvSchemaError,
    assert_finite_columns,
    assert_high_low_geometry,
    assert_output_paths_distinct,
    assert_path_not_same_file,
    assert_unique_composite_key,
    assert_unique_ids,
    atomic_write_dataframe_csv,
    parse_is_long,
    read_csv_with_required_columns_and_hash,
    sanitize_dataframe_for_csv,
)
from analysis.report_metadata import (
    atomic_write_text,
    build_report_metadata,
    combine_labeled_hashes,
)
from analysis.time_utils import parse_iso8601_utc, parse_utc_series
from analysis.trade_math import (
    BarAlignmentError,
    IncompleteBarCoverageError,
    MfeMaeResult,
    NoBarsInWindowError,
    compute_mfe_mae,
)

TradesSchemaError = CsvSchemaError  # kept as a local alias for readability
# at this script's own call sites

REQUIRED_TRADE_COLUMNS = {
    "trade_id",
    "symbol",
    "is_long",
    "entry_time",
    "exit_time",
    "entry_price",
    "stop_price",
}
REQUIRED_BAR_COLUMNS = {"symbol", "timestamp", "high", "low"}


@dataclass(frozen=True)
class MfeMaeRunResult:
    results: list[MfeMaeResult]
    row_errors: list[dict]


def run(
    trades_csv: Path,
    bars_csv: Path,
    output_csv: Optional[Path] = None,
    errors_json: Optional[Path] = None,
    *,
    # **Added, 2026-07-22 Codex review finding (fifth round): REQUIRED
    # (not optional) -- see IncompleteBarCoverageError's own docstring
    # for the exact counterexample this closes (a trade whose window has
    # its two ENDPOINTS bar-aligned but is missing bars in between,
    # silently accepted as complete evidence before this fix). A caller
    # must state what cadence bars_csv is actually supposed to be at.
    expected_cadence_minutes: float,
    symbol: Optional[str] = None,
    seed: Optional[int] = None,
    # **Added, 2026-07-22 Codex review finding (fourth round): spread_note/
    # slippage_note exist on ReportMetadata but no analysis caller exposed
    # or populated them.**
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> MfeMaeRunResult:
    """Reads 'trades_csv' and 'bars_csv', computes MFE/MAE per trade.
    Raises TradesSchemaError/FileNotFoundError for structural problems
    (missing file, missing required column) -- those are script-level
    failures, distinct from a per-ROW problem (malformed timestamp, no
    bars in window, incomplete bar coverage within an otherwise-aligned
    window), which is instead collected into 'row_errors' so one bad
    trade never hides every other trade's valid result.
    """

    # **Added, 2026-07-22 Codex review finding (sixth round): a caller
    # requesting output_csv without errors_json previously got a CSV
    # with NO accompanying provenance metadata anywhere. An implicit
    # sidecar path is now derived (matching join_trade_journal.py/
    # join_news_events.py/join_signal_to_outcome.py's own pattern),
    # derived FIRST so the collision checks below cover it too.**
    if errors_json is None and output_csv is not None:
        errors_json = output_csv.parent / f"{output_csv.stem}.errors.json"

    # Uses OS-level file-identity (not just Path.resolve()) so a hard
    # link to an input is also caught -- Codex review finding, third round.
    for out_path in (output_csv, errors_json):
        assert_path_not_same_file(out_path, trades_csv, "output path")
        assert_path_not_same_file(out_path, bars_csv, "output path")
    assert_output_paths_distinct([output_csv, errors_json])

    # **Fixed, 2026-07-22 Codex review finding (sixth round): both files
    # were previously read via the plain (non-hashing) helper, and
    # 'build_report_metadata' below then re-read them a SECOND time to
    # compute their hash -- the same ABA-mutation race round 5 already
    # closed for join_trade_journal.py/join_news_events.py/
    # analyse_baseline.py but left open here. Reading once and hashing
    # from that same pass, then combining both files' hashes below,
    # closes the race structurally.**
    # **Fixed, 2026-07-22 Codex review finding (sixth round): 'trade_id'
    # was previously read via plain pandas type inference -- see
    # csv_io.TRADE_ID_DTYPE's own docstring for the exact counterexample
    # this closes.**
    trades, trades_csv_hash = read_csv_with_required_columns_and_hash(
        trades_csv, REQUIRED_TRADE_COLUMNS, dtype=TRADE_ID_DTYPE
    )
    bars, bars_csv_hash = read_csv_with_required_columns_and_hash(bars_csv, REQUIRED_BAR_COLUMNS)
    # **Fixed, 2026-07-22 Codex review finding:** a header-only (zero-row)
    # trades.csv previously produced a "successful" empty run (0 results,
    # 0 row errors) instead of a visible insufficient-sample failure --
    # indistinguishable from "every trade was valid and none had errors".
    if trades.empty:
        raise CsvSchemaError(f"{trades_csv}: zero trade rows (header-only input)")
    assert_unique_ids(trades, "trade_id", trades_csv)
    assert_finite_columns(trades, ["entry_price", "stop_price"], trades_csv)
    assert_finite_columns(bars, ["high", "low"], bars_csv)
    assert_high_low_geometry(bars, "high", "low", bars_csv)

    # **Fixed, 2026-07-22 Codex review finding (fourth round): the
    # duplicate-(symbol, timestamp) check previously ran on the RAW
    # string timestamp column, BEFORE UTC normalization -- two raw
    # spellings of the same instant ("...Z" and "...+00:00") pass as
    # distinct strings, then become the same instant once parsed, so a
    # direct probe with two such rows was accepted with both conflicting
    # bars silently entering the measurement. Parse first, then enforce
    # canonical-time uniqueness.**
    bars = bars.copy()
    bars["timestamp"] = parse_utc_series(bars["timestamp"])
    assert_unique_composite_key(bars, ["symbol", "timestamp"], bars_csv)

    results: list[MfeMaeResult] = []
    row_errors: list[dict] = []

    for _, row in trades.iterrows():
        trade_id = str(row["trade_id"])
        try:
            is_long = parse_is_long(row["is_long"])
            entry_time = parse_iso8601_utc(str(row["entry_time"]))
            exit_time = parse_iso8601_utc(str(row["exit_time"]))
            entry_price = float(row["entry_price"])
            stop_price = float(row["stop_price"])
            # **Fixed, 2026-07-22 Codex review finding:** compute_r_multiple's
            # (used inside compute_mfe_mae) live fail-safe silently returns
            # 0R for malformed stop geometry rather than rejecting it --
            # appropriate for a live guard, not for evidence cleaning.
            if is_long and stop_price >= entry_price:
                raise ValueError(
                    f"trade_id={trade_id}: long trade stop_price ({stop_price}) must be below "
                    f"entry_price ({entry_price})"
                )
            if not is_long and stop_price <= entry_price:
                raise ValueError(
                    f"trade_id={trade_id}: short trade stop_price ({stop_price}) must be above "
                    f"entry_price ({entry_price})"
                )
            symbol_bars = bars[bars["symbol"] == row["symbol"]]

            result = compute_mfe_mae(
                trade_id=trade_id,
                is_long=is_long,
                entry_price=entry_price,
                stop_price=stop_price,
                entry_time=entry_time,
                exit_time=exit_time,
                bars=symbol_bars,
                expected_cadence_minutes=expected_cadence_minutes,
            )
            results.append(result)
        except (
            ValueError,
            NoBarsInWindowError,
            BarAlignmentError,
            IncompleteBarCoverageError,
            KeyError,
        ) as exc:
            row_errors.append({"trade_id": trade_id, "error": str(exc)})

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        out_df = pd.DataFrame(
            [
                {
                    "trade_id": r.trade_id,
                    "mfe_price": r.mfe_price,
                    "mae_price": r.mae_price,
                    "mfe_r": r.mfe_r,
                    "mae_r": r.mae_r,
                    "n_bars": r.n_bars,
                }
                for r in results
            ]
        )
        # trade_id is a caller-controlled string -- sanitized against
        # spreadsheet-formula injection (Codex review finding,
        # 2026-07-22, third round).
        atomic_write_dataframe_csv(sanitize_dataframe_for_csv(out_df), output_csv)

    if errors_json is not None:
        errors_json.parent.mkdir(parents=True, exist_ok=True)
        combined_hash = combine_labeled_hashes(
            [(trades_csv.name, trades_csv_hash), (bars_csv.name, bars_csv_hash)]
        )
        metadata = build_report_metadata(
            [trades_csv, bars_csv],
            symbol=symbol,
            random_seed=seed,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=repo_path,
            dataset_hash_override=combined_hash,
        )
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_trades_input": len(trades),
                "n_results": len(results),
                "n_row_errors": len(row_errors),
            },
            "row_errors": row_errors,
        }
        atomic_write_text(errors_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return MfeMaeRunResult(results=results, row_errors=row_errors)


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--bars-csv", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--errors-json", type=Path, default=None)
    # **Added, 2026-07-22 Codex review finding (fifth round): required --
    # see run()'s own comment.**
    parser.add_argument("--expected-cadence-minutes", type=float, required=True)
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        result = run(
            trades_csv=args.trades_csv,
            bars_csv=args.bars_csv,
            output_csv=args.output_csv,
            errors_json=args.errors_json,
            expected_cadence_minutes=args.expected_cadence_minutes,
            symbol=args.symbol,
            seed=args.seed,
            spread_note=args.spread_note,
            slippage_note=args.slippage_note,
        )
    except (FileNotFoundError, TradesSchemaError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"calculate_mfe_mae: {len(result.results)} computed, {len(result.row_errors)} row errors."
    )
    return 1 if result.row_errors else 0


if __name__ == "__main__":
    sys.exit(main())
