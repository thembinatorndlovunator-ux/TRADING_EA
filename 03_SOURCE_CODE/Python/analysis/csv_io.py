"""Shared CSV-reading helper: every script in this analysis layer takes
explicit CSV input paths (per the reproducibility contract, "pipelines
accept explicit input/output paths"), and every one of them must fail
loudly, not silently, on a missing required column -- this is the one
place that check is implemented."""

from __future__ import annotations

import csv
import os
import tempfile
from pathlib import Path
from typing import Optional, Sequence

import numpy as np
import pandas as pd


class CsvSchemaError(ValueError):
    """Raised when a CSV is missing one or more required columns, contains
    a duplicate durable ID, a non-finite/missing numeric value, or invalid
    OHLC geometry -- every one of these is a reportable data-integrity
    problem per the reproducibility contract's "visible failures, never
    silently coerced" rule, not something a caller should filter out
    quietly."""


def read_csv_with_required_columns(
    path: Path, required_columns: set[str], dtype: Optional[dict] = None
) -> pd.DataFrame:
    """Reads 'path' as CSV and raises CsvSchemaError if any of
    'required_columns' is absent, OR if the raw header row contains a
    duplicate column name. Raises FileNotFoundError (pandas' own,
    propagated) if 'path' does not exist -- a caller must distinguish "the
    file is missing" from "the file exists but has the wrong shape", since
    they call for different remediation.

    **Fixed, 2026-07-22 Codex review finding:** pandas silently renames a
    duplicate header (e.g. two ``trade_id`` columns become ``trade_id``
    and ``trade_id.1``) before the required-column check ever sees it, so
    a genuinely malformed CSV with a repeated column name previously
    passed this check outright. The raw header row is now read and
    checked for duplicates FIRST, independently of pandas' own parsing.

    **Fixed, 2026-07-22 Codex review finding (third round): reading only
    the first PHYSICAL line (``fh.readline()``) missed a header row that
    itself spans multiple physical lines due to CSV quoting** (a quoted
    field containing an embedded newline) -- a quoted multiline duplicate
    header previously bypassed this check entirely. ``csv.reader`` is now
    used directly on the file handle so the first LOGICAL row is read
    correctly regardless of embedded newlines within quoted fields.

    **Added, 2026-07-22 Codex review finding (fourth round): 'dtype', if
    given, is passed straight through to ``pandas.read_csv``** -- durable
    identifier columns (order_id, deal_id, trade_id) must be read as
    ``str``, never pandas' own inferred numeric type: an in-memory probe
    of ``9007199254740992``/``9007199254740993``/a blank ID loaded the
    column as ``float64`` and collapsed the first two IDs to the SAME
    value (float64 cannot represent every int64 exactly), and leading
    zeroes (``"001"``) were silently discarded by numeric inference.
    """

    with path.open("r", newline="", encoding="utf-8-sig") as fh:
        raw_headers = next(csv.reader(fh), [])
    seen: set[str] = set()
    dupe_set: set[str] = set()
    for h in raw_headers:
        if h in seen:
            dupe_set.add(h)
        seen.add(h)
    dupes = sorted(dupe_set)
    if dupes:
        raise CsvSchemaError(f"{path}: duplicate column header(s) in raw file: {dupes}")

    df = pd.read_csv(path, dtype=dtype)
    missing = required_columns - set(df.columns)
    if missing:
        raise CsvSchemaError(f"{path}: missing required columns: {sorted(missing)}")
    return df


def _same_file_identity(a: Path, b: Path) -> bool:
    """True if 'a' and 'b' resolve to the same path OR (when both already
    exist) refer to the same underlying file via OS-level identity
    (inode/device on POSIX, file index on Windows) -- catches a hard
    link, which has a DIFFERENT resolved path but is the SAME file on
    disk.

    **Added, 2026-07-22 Codex review finding (third round): path guards
    previously compared only Path.resolve(), which a hard link to an
    existing input trivially bypasses (different resolved name, identical
    underlying file) -- a direct probe used a hard-linked output path to
    overwrite an input's own inode.**
    """

    if a.resolve() == b.resolve():
        return True
    try:
        return a.exists() and b.exists() and os.path.samestat(a.stat(), b.stat())
    except OSError:
        return False


def assert_output_paths_distinct(paths: Sequence[Optional[Path]]) -> None:
    """Raises CsvSchemaError if any two non-None paths in 'paths' are the
    same file -- e.g. the same path (or a hard link to it) passed for
    both a CSV and a JSON output.

    **Added, 2026-07-22 Codex review finding:** most two-output pipelines
    in this project previously compared each output only against its
    INPUT paths, never against each other -- passing the same path for
    two different outputs was silently accepted, and the later write
    replaced the earlier artifact with no warning.
    """

    present = [p for p in paths if p is not None]
    for i in range(len(present)):
        for j in range(i + 1, len(present)):
            if _same_file_identity(present[i], present[j]):
                raise CsvSchemaError(
                    f"output paths must all be distinct, got a collision between "
                    f"{present[i]} and {present[j]}"
                )


def assert_path_not_same_file(
    output_path: Optional[Path], input_path: Path, context: str = "output path"
) -> None:
    """Raises CsvSchemaError if 'output_path' refers to the same
    underlying file as 'input_path' -- via ``_same_file_identity``, so a
    hard link is caught even though its resolved path differs.
    """

    if output_path is not None and _same_file_identity(output_path, input_path):
        raise CsvSchemaError(
            f"{context} {output_path} must not be the same file as input {input_path}"
        )


def assert_path_not_direct_child_of_directory(
    output_path: Optional[Path], directory: Path, context: str = "output path"
) -> None:
    """Raises CsvSchemaError if 'output_path' is 'directory' itself, or a
    DIRECT child of it (matching what a non-recursive
    ``directory.glob("decisions_*.jsonl")``-style scan could pick up on a
    later run) -- writing an output directly inside a directory this
    pipeline treats as read-only INPUT risks a stray CSV/JSON later being
    misread as a real source file. Deliberately does NOT reject a deeper
    subdirectory (e.g. ``directory/out/result.csv``) -- that is this
    project's own established, intentional pattern for colocating outputs
    near their input directory in their own subfolder, and a non-recursive
    glob never descends into it anyway.

    **Fixed, 2026-07-22 Codex review finding (fifth round): the two call
    sites this replaces (``join_trade_journal.py``, ``join_news_events.py``)
    previously each hand-rolled an ad hoc
    ``output_path.resolve().parent == directory.resolve()`` check using
    plain resolved-STRING comparison rather than this shared helper.**
    """

    if output_path is None:
        return
    resolved_output = output_path.resolve()
    resolved_directory = directory.resolve()
    if resolved_output == resolved_directory or resolved_output.parent == resolved_directory:
        raise CsvSchemaError(f"{context} {output_path} must not be written inside {directory}")


def parse_is_long(value: object) -> bool:
    """Parses a CSV 'is_long' field -- accepts "True"/"False"/"1"/"0"/
    "yes"/"no"/"long"/"short", case-insensitive. Raises ValueError (never
    silently defaults to a direction) for anything else, since a wrongly-
    guessed trade direction would silently invert every downstream R
    computation for that row."""

    text = str(value).strip().lower()
    if text in ("true", "1", "yes", "long"):
        return True
    if text in ("false", "0", "no", "short"):
        return False
    raise ValueError(f"cannot parse is_long value: {value!r}")


def assert_unique_ids(df: pd.DataFrame, id_column: str, path: Path) -> None:
    """Raises CsvSchemaError if 'id_column' contains any duplicate,
    non-null value, OR any null/blank value -- per the reproducibility
    contract, duplicate durable IDs (trade_id, event_id, etc.) must be a
    visible failure, never silently deduplicated or averaged over, and a
    missing ID is not a valid identity either.

    **Fixed, 2026-07-22 Codex review finding:** this previously excluded
    null IDs from the check entirely (to avoid every row trivially
    "duplicating" every other while the live EA's signal_id is
    universally empty -- see journal_reader.py's own docstring), which
    let a blank event_id/trade_id pass silently; one was later observed
    written out as the literal string ``"nan"``. Blank/null IDs are now
    rejected outright as their own distinct error, not merely excluded
    from duplicate detection.
    """

    blank_mask = df[id_column].isna() | (df[id_column].astype(str).str.strip() == "")
    if blank_mask.any():
        raise CsvSchemaError(
            f"{path}: {int(blank_mask.sum())} row(s) have a null/blank {id_column}: "
            f"rows {df.index[blank_mask].tolist()}"
        )

    duplicated = df[df.duplicated(subset=[id_column], keep=False)]
    if not duplicated.empty:
        dup_ids = sorted(duplicated[id_column].astype(str).unique())
        raise CsvSchemaError(f"{path}: duplicate {id_column} values found: {dup_ids}")


def assert_finite_columns(df: pd.DataFrame, columns: Sequence[str], path: Path) -> None:
    """Raises CsvSchemaError if any of 'columns' contains a missing,
    non-numeric, or non-finite (NaN/inf) value in any row. Column values
    are coerced via pandas' own numeric parser first, so a string like
    "abc" is treated identically to a missing/NaN cell -- both are
    reportable data problems, not silently-different failure modes."""

    for col in columns:
        parsed = pd.to_numeric(df[col], errors="coerce")
        bad_mask = ~np.isfinite(parsed.to_numpy(dtype=float))
        if bad_mask.any():
            bad_rows = df.index[bad_mask].tolist()
            raise CsvSchemaError(
                f"{path}: column '{col}' has non-finite/missing/non-numeric values at rows {bad_rows}"
            )


def assert_high_low_geometry(
    df: pd.DataFrame,
    high_column: str,
    low_column: str,
    path: Path,
    open_column: Optional[str] = None,
    close_column: Optional[str] = None,
) -> None:
    """Raises CsvSchemaError if any row has high < low -- an impossible
    bar that would otherwise silently corrupt any MFE/MAE or pattern
    calculation built on it. If 'open_column'/'close_column' are also
    given, ALSO requires low <= open, close <= high for every row.

    **Fixed, 2026-07-22 Codex review finding:** this previously checked
    only high >= low, which admits a bar where open or close falls
    outside the [low, high] range entirely -- an equally impossible bar
    geometry that silently corrupted downstream candle-ratio and
    MFE/MAE math. Callers that only have high/low (no open/close, e.g.
    calculate_mfe_mae.py's bars.csv) omit the two optional columns and
    get the original high>=low check only.
    """

    bad = df[df[high_column] < df[low_column]]
    if not bad.empty:
        raise CsvSchemaError(
            f"{path}: {len(bad)} row(s) have {high_column} < {low_column} (impossible bar geometry): "
            f"rows {bad.index.tolist()}"
        )

    if open_column is not None and close_column is not None:
        out_of_range = df[
            (df[open_column] < df[low_column])
            | (df[open_column] > df[high_column])
            | (df[close_column] < df[low_column])
            | (df[close_column] > df[high_column])
        ]
        if not out_of_range.empty:
            raise CsvSchemaError(
                f"{path}: {len(out_of_range)} row(s) have {open_column}/{close_column} outside "
                f"[{low_column}, {high_column}] (impossible bar geometry): rows {out_of_range.index.tolist()}"
            )


def assert_unique_composite_key(df: pd.DataFrame, columns: Sequence[str], path: Path) -> None:
    """Raises CsvSchemaError if the combination of 'columns' is not
    unique per row -- e.g. duplicate (symbol, timestamp) bars, which
    would silently make MFE/MAE or giveback R-path construction
    ambiguous about which row's high/low/close applies at that instant.

    **Added, 2026-07-22 Codex review finding (third round):** neither
    calculate_mfe_mae.py nor analyse_giveback.py rejected duplicate
    (symbol, timestamp) bars before this.
    """

    duplicated = df[df.duplicated(subset=list(columns), keep=False)]
    if not duplicated.empty:
        raise CsvSchemaError(
            f"{path}: duplicate rows for key {list(columns)}: "
            f"{duplicated[list(columns)].drop_duplicates().to_dict(orient='records')}"
        )


def assert_chronological_order(entry_time: pd.Series, exit_time: pd.Series, path: Path) -> None:
    """Raises CsvSchemaError if any row has entry_time strictly after
    exit_time -- an impossible trade chronology.

    **Added, 2026-07-22 Codex review finding (third round):**
    analyse_baseline.py, compare_releases.py, and walk_forward.py all
    strictly parsed both timestamps but never checked their relative
    order -- a baseline trade whose entry was one day AFTER its exit was
    previously accepted and reported as one valid trade.
    """

    bad = entry_time > exit_time
    if bad.any():
        raise CsvSchemaError(
            f"{path}: {int(bad.sum())} row(s) have entry_time after exit_time (impossible "
            f"chronology): rows {entry_time.index[bad].tolist()}"
        )


def assert_valid_stop_geometry(
    is_long: pd.Series,
    entry: pd.Series,
    stop: pd.Series,
    path: Path,
) -> None:
    """Raises CsvSchemaError if any row's initial stop is on the wrong
    side of (or exactly equal to) its entry price given its direction --
    for a long, stop must be strictly below entry; for a short, strictly
    above.

    **Fixed, 2026-07-22 Codex review finding:** ``trade_math.compute_r_multiple``
    deliberately mirrors ``ExitManager.mqh``'s live fail-safe of returning
    0R for a non-positive risk distance -- correct for a LIVE guard, but
    wrong for evidence cleaning: a malformed row (e.g. a long with entry
    100 and stop 101) was silently reported as a plausible 0R trade
    instead of being rejected as bad input. This check runs BEFORE
    compute_r_multiple in every analysis pipeline so malformed geometry
    is a visible schema failure, not a silently-plausible statistic.
    'is_long' must already be a parsed boolean Series (see
    csv_io.parse_is_long).
    """

    entry_f = pd.to_numeric(entry, errors="coerce")
    stop_f = pd.to_numeric(stop, errors="coerce")
    bad_long = is_long & (stop_f >= entry_f)
    bad_short = (~is_long) & (stop_f <= entry_f)
    bad = bad_long | bad_short
    if bad.any():
        raise CsvSchemaError(
            f"{path}: {int(bad.sum())} row(s) have an initial stop on the wrong side of "
            f"(or equal to) entry given direction: rows {is_long.index[bad].tolist()}"
        )


_CSV_FORMULA_PREFIXES = ("=", "+", "-", "@", "\t", "\r")


def sanitize_for_csv(value: object) -> object:
    """Neutralizes spreadsheet-formula injection: if 'value' is a string
    starting with a character a spreadsheet application (Excel, Google
    Sheets, LibreOffice) would interpret as a formula prefix, prepends a
    single quote so it opens as inert text instead of executing as a
    formula. Non-string values pass through unchanged.

    **Added, 2026-07-22 Codex review finding:** caller-controlled journal
    strings (strategy/setup names, rejection reasons, etc.) were written
    directly to CSV; a value like ``=CMD(...)`` could become a live
    formula the moment a reviewer opened the exported CSV in a
    spreadsheet application. Apply this to every free-text/journal-
    derived field before writing to CSV.
    """

    if isinstance(value, str) and value.startswith(_CSV_FORMULA_PREFIXES):
        return "'" + value
    return value


def atomic_write_dataframe_csv(df: pd.DataFrame, path: Path) -> None:
    """Writes 'df' to 'path' as CSV via write-to-temp-then-rename, so an
    interrupted write (crash, kill, disk full) never leaves a partially
    -written CSV at 'path'.

    **Added, 2026-07-22 Codex review finding (third round): JSON writes
    already use this discipline (``report_metadata.atomic_write_text``),
    but every CSV writer in this project remained a direct
    ``df.to_csv(path)`` call.**
    """

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp")
    try:
        # **Fixed, 2026-07-22 Codex review finding (fourth round):** no
        # explicit encoding was given here, so this defaulted to the
        # active locale's code page (cp1252 on the tested Windows
        # environment) -- writing "Café" produced byte 0xE9 and reopening
        # the result as UTF-8 raised UnicodeDecodeError. Every reader in
        # this project (journal_reader.py, pandas.read_csv elsewhere)
        # assumes UTF-8; this writer must match that contract explicitly
        # rather than depend on the runtime's locale.
        with os.fdopen(fd, "w", newline="", encoding="utf-8") as fh:
            df.to_csv(fh, index=False)
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.remove(tmp_name)
        except OSError:
            pass
        raise


def sanitize_dataframe_for_csv(df: pd.DataFrame) -> pd.DataFrame:
    """Returns a copy of 'df' with every string (object/str-dtype) column
    passed through ``sanitize_for_csv``.

    **Added, 2026-07-22 Codex review finding (third round):**
    ``sanitize_for_csv`` was previously applied only in the two "journal"
    scripts -- ``performance_breakdown.py``, ``analyse_baseline.py``,
    ``analyse_giveback.py``, and ``calculate_mfe_mae.py`` all export
    caller-controlled strings (dimension values, symbol, trade_id)
    directly; a strategy name of ``=1+1`` was reproduced emitted
    unchanged. This helper is the one place that fix now lives, applied
    at every CSV-writing call site carrying caller-controlled text.
    """

    safe_df = df.copy()
    for col in safe_df.select_dtypes(include=["object", "str"]).columns:
        safe_df[col] = safe_df[col].map(sanitize_for_csv)
    return safe_df
