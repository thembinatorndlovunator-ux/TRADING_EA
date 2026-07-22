"""pattern_validation.py -- Python ports of a SUBSET of
``CandlestickPatternEngine.mqh``'s pattern predicates (bullish/bearish pin
bar including TASK-017's wick-to-body ratio fix, bullish/bearish
engulfing), validated against hand-constructed synthetic OHLC fixtures, for
independent cross-checking against the MQL5 source.

**Explicitly NOT a full port.** ``CandlestickPatternEngine.mqh`` defines
**19** ``CP_Is*Array`` boolean pattern predicates PLUS one non-boolean
helper, ``CP_DetectHaramiArray`` -- **20 detector/predicate functions
total** (corrected count, 2026-07-22 Codex review finding, third round:
this docstring previously said "18 total/14 remaining", which does not
match the actual MQL5 source -- see ``TASK-033_PATTERN_VALIDATION_COMPLETION.md``
for the full, verified enumeration). This module ports the 4 named above
(kept algebraically identical to the MQL5 source, not re-derived) as a
first slice -- the remaining 15 ``CP_Is*Array`` predicates (dragonfly/
gravestone rejection, marubozu, doji, spinning top, inside/outside bar,
tweezer top/bottom, harami-confirmed, morning/evening star, three white
soldiers/three black crows, three-bar reversal) PLUS the
``CP_DetectHaramiArray`` helper (16 functions total) are explicitly NOT
ported here, left for TASK-033.

**Array convention, stated explicitly (a common point of confusion this
project has flagged before):** these functions use the SAME "logical
index" convention as the MQL5 side -- index 0 is the MOST RECENTLY
completed bar, increasing index is OLDER (opposite of a typical
chronologically-ascending pandas DataFrame). A caller building these
arrays from ascending-time OHLC data must reverse it first.

**Cross-check against a real MQL5-exported detector-results CSV is NOT YET
POSSIBLE** -- no MQL5 module in this project exports pattern-detection
results to a file (``CandlestickPatternEngine.mqh`` has no CSV/export
function). ``compare_to_mql5_export`` is provided as a generic join/diff
utility for when such an export exists, explicitly marked pending real
data per the reproducibility contract's rule 7.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence

import pandas as pd

from analysis.csv_io import (
    CsvSchemaError,
    assert_finite_columns,
    assert_high_low_geometry,
    assert_output_paths_distinct,
    assert_path_not_same_file,
    assert_unique_ids,
    atomic_write_dataframe_csv,
    read_csv_with_required_columns,
    read_csv_with_required_columns_and_hash,
)
from analysis.report_metadata import atomic_write_text, build_report_metadata

CP_BODY_EPSILON = 0.00001
CP_PIN_BAR_MIN_WICK_TO_BODY = 2.0

REQUIRED_OHLC_COLUMNS = {"open", "high", "low", "close"}


@dataclass(frozen=True)
class CandleRatios:
    body: float
    range: float
    upper_wick: float
    lower_wick: float
    body_ratio: float
    upper_wick_ratio: float
    lower_wick_ratio: float
    upper_wick_to_body: float
    lower_wick_to_body: float
    valid: bool


def measure_ratios(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
) -> CandleRatios:
    """Direct port of CP_MeasureRatiosArray. A zero-range bar (high==low)
    never qualifies for any pattern, per section 5 -- 'valid' is False in
    that case, matching the MQL5 source's own early return."""

    n = len(closes)
    invalid = CandleRatios(0, 0, 0, 0, 0, 0, 0, 0, 0, False)
    if k < 0 or k >= n:
        return invalid

    o, h, low, c = opens[k], highs[k], lows[k], closes[k]
    candle_range = h - low
    if candle_range <= 0.0:
        return invalid

    body = abs(c - o)
    upper_wick = h - max(o, c)
    lower_wick = min(o, c) - low

    return CandleRatios(
        body=body,
        range=candle_range,
        upper_wick=upper_wick,
        lower_wick=lower_wick,
        body_ratio=body / candle_range,
        upper_wick_ratio=upper_wick / candle_range,
        lower_wick_ratio=lower_wick / candle_range,
        upper_wick_to_body=upper_wick / max(body, CP_BODY_EPSILON),
        lower_wick_to_body=lower_wick / max(body, CP_BODY_EPSILON),
        valid=True,
    )


def size_percentile(highs: Sequence[float], lows: Sequence[float], k: int, window: int) -> float:
    """Direct port of CP_SizePercentileArray (average-rank percentile of
    range[k] against the trailing 'window' OLDER candles, k+1..k+window)."""

    n = len(highs)
    if k < 0 or k >= n:
        return 0.0

    end = min(k + window, n - 1)
    total = end - k
    if total <= 0:
        return 1.0  # no comparison history -- cannot be disproven as large

    range_k = highs[k] - lows[k]
    less_count = 0.0
    for i in range(k + 1, end + 1):
        r = highs[i] - lows[i]
        if r < range_k:
            less_count += 1.0
        elif r == range_k:
            less_count += 0.5
    return less_count / total


def is_bullish_pin_bar(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    trend_lookback: int,
    min_lower_wick_ratio: float = 0.60,
    max_body_ratio: float = 0.30,
    max_opposite_wick_ratio: float = 0.15,
) -> bool:
    """Direct port of CP_IsBullishPinBarArray, including TASK-017's
    wick-to-body ratio fix (CP_PIN_BAR_MIN_WICK_TO_BODY)."""

    n = len(closes)
    if k < 0 or k + trend_lookback >= n:
        return False

    m = measure_ratios(opens, highs, lows, closes, k)
    if not m.valid:
        return False
    if m.lower_wick_ratio < min_lower_wick_ratio:
        return False
    if m.body_ratio > max_body_ratio:
        return False
    if m.upper_wick_ratio > max_opposite_wick_ratio:
        return False
    if m.lower_wick_to_body < CP_PIN_BAR_MIN_WICK_TO_BODY:
        return False

    close_position = (closes[k] - lows[k]) / (highs[k] - lows[k])
    if close_position < 0.60:
        return False

    return closes[k + trend_lookback] > closes[k]  # preceding down-move


def is_bearish_pin_bar(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    trend_lookback: int,
    min_upper_wick_ratio: float = 0.60,
    max_body_ratio: float = 0.30,
    max_opposite_wick_ratio: float = 0.15,
) -> bool:
    """Direct port of CP_IsBearishPinBarArray (mirror of the bullish case)."""

    n = len(closes)
    if k < 0 or k + trend_lookback >= n:
        return False

    m = measure_ratios(opens, highs, lows, closes, k)
    if not m.valid:
        return False
    if m.upper_wick_ratio < min_upper_wick_ratio:
        return False
    if m.body_ratio > max_body_ratio:
        return False
    if m.lower_wick_ratio > max_opposite_wick_ratio:
        return False
    if m.upper_wick_to_body < CP_PIN_BAR_MIN_WICK_TO_BODY:
        return False

    close_position = (closes[k] - lows[k]) / (highs[k] - lows[k])
    if close_position > 0.40:  # lower 40% of range
        return False

    return closes[k + trend_lookback] < closes[k]  # preceding up-move


def is_bullish_engulfing(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    size_window: int = 20,
    min_size_percentile: float = 0.50,
) -> bool:
    """Direct port of CP_IsBullishEngulfingArray."""

    n = len(closes)
    if k < 0 or k + 1 >= n:
        return False

    cond = (
        closes[k] > opens[k + 1]
        and opens[k] < closes[k + 1]
        and abs(closes[k] - opens[k]) > abs(closes[k + 1] - opens[k + 1])
        and closes[k + 1] < opens[k + 1]
    )
    if not cond:
        return False

    return size_percentile(highs, lows, k, size_window) >= min_size_percentile


def is_bearish_engulfing(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    k: int,
    size_window: int = 20,
    min_size_percentile: float = 0.50,
) -> bool:
    """Direct port of CP_IsBearishEngulfingArray."""

    n = len(closes)
    if k < 0 or k + 1 >= n:
        return False

    cond = (
        closes[k] < opens[k + 1]
        and opens[k] > closes[k + 1]
        and abs(closes[k] - opens[k]) > abs(closes[k + 1] - opens[k + 1])
        and closes[k + 1] > opens[k + 1]
    )
    if not cond:
        return False

    return size_percentile(highs, lows, k, size_window) >= min_size_percentile


def detect_all_patterns(
    opens: Sequence[float],
    highs: Sequence[float],
    lows: Sequence[float],
    closes: Sequence[float],
    trend_lookback: int = 5,
    size_window: int = 20,
) -> pd.DataFrame:
    """Runs every ported pattern at every valid logical index k, returning
    a DataFrame with one row per k and one boolean column per pattern.

    Raises ValueError if trend_lookback/size_window is not a positive
    integer -- **added, 2026-07-22 Codex review finding (fourth round):**
    neither was previously validated. A negative size_window makes
    size_percentile's own "total <= 0" branch return 1.0 ("no comparison
    history -- cannot be disproven as large"), silently turning ANY bar
    into an automatic 100th-percentile pass regardless of its real size.
    A negative trend_lookback bypasses the `k + trend_lookback >= n`
    upper-bound guard while still being used as a list index, so
    `closes[k + trend_lookback]` can silently wrap around to the END of
    the array (Python negative-index semantics) and compare against an
    unrelated bar instead of raising.
    """

    if trend_lookback < 1:
        raise ValueError(f"trend_lookback must be a positive integer, got {trend_lookback}")
    if size_window < 1:
        raise ValueError(f"size_window must be a positive integer, got {size_window}")

    n = len(closes)
    rows = []
    for k in range(n):
        rows.append(
            {
                "k": k,
                "bullish_pin_bar": is_bullish_pin_bar(
                    opens, highs, lows, closes, k, trend_lookback
                ),
                "bearish_pin_bar": is_bearish_pin_bar(
                    opens, highs, lows, closes, k, trend_lookback
                ),
                "bullish_engulfing": is_bullish_engulfing(
                    opens, highs, lows, closes, k, size_window
                ),
                "bearish_engulfing": is_bearish_engulfing(
                    opens, highs, lows, closes, k, size_window
                ),
            }
        )
    return pd.DataFrame(rows)


def compare_to_mql5_export(python_results: pd.DataFrame, mql5_export_csv: Path) -> pd.DataFrame:
    """Joins this module's own detect_all_patterns() output against a
    real MQL5-exported detector-results CSV (columns: k, <same pattern
    names as booleans>) and reports every row where they disagree.

    **Fixed, 2026-07-21 Codex review finding:** previously used an INNER
    merge, which silently drops any 'k' present in only one side --
    reproduced counterexample: Python results at k=1 and an MQL5 export at
    k=0 (i.e. the two datasets never actually overlap at all) returned an
    EMPTY disagreement DataFrame, the strongest possible false "pass". A
    duplicate 'k' on either side could also silently fan out into a
    Cartesian join. Now requires exact, unique key coverage on both sides
    (via an outer merge with an indicator column) and raises
    CsvSchemaError -- not a silent comparison -- if either side has a key
    the other lacks, or if either side has a duplicate key.

    **Not yet exercisable against real data** -- no MQL5 module in this
    project currently exports pattern results to a file. Also raises
    CsvSchemaError if the export is missing the 'k' column or any pattern
    column present in 'python_results'.
    """

    pattern_columns = [c for c in python_results.columns if c != "k"]
    if python_results["k"].duplicated().any():
        raise CsvSchemaError("compare_to_mql5_export: python_results has duplicate 'k' values")

    mql5_results = read_csv_with_required_columns(mql5_export_csv, {"k", *pattern_columns})
    assert_unique_ids(mql5_results, "k", mql5_export_csv)

    merged = python_results.merge(
        mql5_results, on="k", how="outer", suffixes=("_python", "_mql5"), indicator=True
    )

    left_only = merged[merged["_merge"] == "left_only"]
    right_only = merged[merged["_merge"] == "right_only"]
    if not left_only.empty or not right_only.empty:
        raise CsvSchemaError(
            f"compare_to_mql5_export: key coverage mismatch -- "
            f"{len(left_only)} k value(s) only in python_results ({sorted(left_only['k'].tolist())}), "
            f"{len(right_only)} k value(s) only in {mql5_export_csv} ({sorted(right_only['k'].tolist())})"
        )

    both = merged[merged["_merge"] == "both"]
    disagreement_mask = pd.Series(False, index=both.index)
    for col in pattern_columns:
        disagreement_mask |= both[f"{col}_python"] != both[f"{col}_mql5"]

    return both[disagreement_mask].drop(columns=["_merge"])


def run(
    ohlc_csv: Path,
    output_csv: Optional[Path] = None,
    summary_json: Optional[Path] = None,
    *,
    trend_lookback: int = 5,
    size_window: int = 20,
    ascending_input: bool = False,
    symbol: Optional[str] = None,
    seed: Optional[int] = None,
    # **Added, 2026-07-22 Codex review finding (fourth round): spread_note/
    # slippage_note exist on ReportMetadata but no analysis caller exposed
    # or populated them.**
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> pd.DataFrame:
    """Reads 'ohlc_csv' (columns open/high/low/close) and detects every
    ported pattern at every valid index.

    'ascending_input' makes the required array convention an explicit,
    caller-declared choice instead of a silent assumption (a Codex review
    finding: there is no timestamp/order column in this CSV shape with
    which to verify the convention from the data alone, so a normal
    chronologically-ascending export could otherwise be silently analyzed
    backwards). Default False means 'ohlc_csv' is ALREADY in the MQL5
    logical-index convention (row 0 = most recent bar); pass True if
    'ohlc_csv' is in the more common chronologically-ascending order
    (row 0 = oldest bar) and this function will reverse it first.

    'summary_json', if given, records this pipeline's provenance --
    **added, 2026-07-22 Codex review finding (third round): this script
    previously emitted an entirely unprovenanced CSV, unlike every other
    pipeline in this layer.**
    """

    # **Added, 2026-07-22 Codex review finding (sixth round): a caller
    # requesting output_csv without summary_json previously got a CSV
    # with NO accompanying provenance metadata anywhere. An implicit
    # sidecar path is now derived (matching join_trade_journal.py/
    # join_news_events.py/join_signal_to_outcome.py's own pattern),
    # derived FIRST so the collision checks below cover it too.**
    if summary_json is None and output_csv is not None:
        summary_json = output_csv.parent / f"{output_csv.stem}.summary.json"

    # **Fixed, 2026-07-22 Codex review finding:** this script had no
    # input/output collision guard at all -- unlike every other pipeline
    # in this layer. **Fixed, 2026-07-22 Codex review finding (fourth
    # round): the guard used a bare Path.resolve() == comparison, which a
    # hard link to ohlc_csv (different resolved name, identical
    # underlying file) would bypass -- every other pipeline in this
    # layer already uses the OS-level file-identity check.**
    assert_path_not_same_file(output_csv, ohlc_csv, "output_csv")
    assert_path_not_same_file(summary_json, ohlc_csv, "summary_json")
    assert_output_paths_distinct([output_csv, summary_json])

    # **Fixed, 2026-07-22 Codex review finding (sixth round): previously
    # read via the plain (non-hashing) helper, then re-read a second time
    # inside build_report_metadata below to compute its hash -- the same
    # ABA-mutation race round 5 already closed for
    # join_trade_journal.py/join_news_events.py/analyse_baseline.py but
    # left open here.**
    ohlc, ohlc_csv_hash = read_csv_with_required_columns_and_hash(ohlc_csv, REQUIRED_OHLC_COLUMNS)
    assert_finite_columns(ohlc, ["open", "high", "low", "close"], ohlc_csv)
    # Full OHLC geometry (open/close must also fall within [low, high]),
    # not just high >= low -- see assert_high_low_geometry's own
    # docstring for the Codex review finding this closes.
    assert_high_low_geometry(
        ohlc, "high", "low", ohlc_csv, open_column="open", close_column="close"
    )
    if ascending_input:
        ohlc = ohlc.iloc[::-1].reset_index(drop=True)

    result = detect_all_patterns(
        ohlc["open"].tolist(),
        ohlc["high"].tolist(),
        ohlc["low"].tolist(),
        ohlc["close"].tolist(),
        trend_lookback=trend_lookback,
        size_window=size_window,
    )

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_dataframe_csv(result, output_csv)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [ohlc_csv],
            symbol=symbol,
            random_seed=seed,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=repo_path,
            dataset_hash_override=ohlc_csv_hash,
        )
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_bars": len(ohlc),
                "trend_lookback": trend_lookback,
                "size_window": size_window,
                "ascending_input": ascending_input,
                "n_detections": int(result.drop(columns=["k"]).sum().sum()),
            },
        }
        atomic_write_text(summary_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return result


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ohlc-csv", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--summary-json", type=Path, default=None)
    parser.add_argument("--trend-lookback", type=int, default=5)
    parser.add_argument("--size-window", type=int, default=20)
    parser.add_argument(
        "--ascending-input",
        action="store_true",
        help="Set if ohlc_csv is chronologically ascending (row 0 = oldest); "
        "default assumes it is already in the MQL5 logical-index convention (row 0 = newest).",
    )
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        result = run(
            args.ohlc_csv,
            args.output_csv,
            args.summary_json,
            trend_lookback=args.trend_lookback,
            size_window=args.size_window,
            ascending_input=args.ascending_input,
            symbol=args.symbol,
            seed=args.seed,
            spread_note=args.spread_note,
            slippage_note=args.slippage_note,
        )
    except (FileNotFoundError, CsvSchemaError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    n_detections = int(result.drop(columns=["k"]).sum().sum())
    print(
        f"pattern_validation: {len(result)} bars scanned, {n_detections} total pattern detections."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
