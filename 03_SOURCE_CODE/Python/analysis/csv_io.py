"""Shared CSV-reading helper: every script in this analysis layer takes
explicit CSV input paths (per the reproducibility contract, "pipelines
accept explicit input/output paths"), and every one of them must fail
loudly, not silently, on a missing required column -- this is the one
place that check is implemented."""

from __future__ import annotations

import csv
import hashlib
import io
import os
import tempfile
from pathlib import Path
from typing import Optional, Sequence

import numpy as np
import pandas as pd


class CsvSchemaError(ValueError):
    """Raised when a CSV is missing one or more required columns, contains
    a duplicate durable ID, a non-finite/missing numeric value, invalid
    OHLC geometry, or exceeds a resource ceiling (file size) -- every one
    of these is a reportable data-integrity problem per the
    reproducibility contract's "visible failures, never silently coerced"
    rule, not something a caller should filter out quietly."""


# **Added, 2026-07-22 Codex review finding (sixth round): 'trade_id' was
# already read as a durable, never-numerically-inferred string in the
# specialized signal/news joins (see join_signal_to_outcome.py's own
# IDENTITY_DTYPE), but every OTHER trades.csv consumer in this layer
# (analyse_baseline.py, analyse_giveback.py, calculate_mfe_mae.py,
# compare_releases.py, monte_carlo.py, performance_breakdown.py,
# walk_forward.py) read it via plain pandas type inference -- a CSV
# containing IDs "001" and "1" loaded as integer values 1, 1 and was
# rejected as a false duplicate; a sufficiently large ticket-style ID
# could lose precision under float64 inference. One shared constant, not
# a call-site-specific dtype literal repeated seven times, so a future
# trades.csv consumer inherits the same durable-ID discipline by
# construction.**
TRADE_ID_DTYPE = {"trade_id": str}


# **Added, 2026-07-22 Codex review finding (sixth round): this helper
# previously read an entire caller-controlled file into bytes, decoded
# text, and a DataFrame with no size ceiling at all -- unlike
# journal_reader.py's own per-file/per-directory byte budgets. A
# generously large but genuinely bounded ceiling, checked via a cheap
# stat() BEFORE the unbounded read_bytes() call below.**
MAX_CSV_FILE_BYTES = 500_000_000  # 500 MB

# **Added, 2026-07-22 Codex review finding (eighth round, P1 finding 15):
# the read below previously issued ONE fh.read(MAX_CSV_FILE_BYTES + 1) call
# regardless of the file's actual size -- CPython's BufferedReader.read(n)
# for an explicit positive n attempts to size its buffer to n upfront, so
# even a genuinely tiny CSV triggered an allocation attempt near the full
# 500,000,001-byte ceiling (the review's own probe measured ~500,008,794
# bytes for a one-byte file), producing MemoryError nondeterministically
# under constrained available memory -- confirmed by two independent full
# pytest runs in the pinned environment, both with real MemoryError
# failures at this exact line, directly falsifying a prior "0 failed"
# claim. Reading in bounded chunks (never allocating anywhere near the
# full ceiling for an ordinary small file) closes this.**
CSV_READ_CHUNK_BYTES = 1_048_576  # 1 MiB per chunk


def _read_csv_bytes_checked(
    path: Path, required_columns: set[str], dtype: Optional[dict]
) -> tuple[pd.DataFrame, str]:
    """Shared core of ``read_csv_with_required_columns``/
    ``read_csv_with_required_columns_and_hash``: reads 'path' exactly
    ONCE as a byte stream, then performs every check (duplicate header,
    parse, required columns) against that SAME data -- never a second
    file open. Returns (df, file_sha256_hex), the hex SHA-256 digest
    guaranteed by construction to be of the exact bytes 'df' was parsed
    from.

    **Added, 2026-07-22 Codex review finding (fifth round): every prior
    caller of this module computed a dataset hash via a SEPARATE, LATER
    (or earlier) file open (``report_metadata.compute_file_sha256``/
    ``compute_dataset_hash``) -- a race DETECTOR at best (a before/after
    rehash comparison), not proof the hashed bytes equal the parsed ones.
    A deterministic ABA-mutation probe changed a file, had it parsed with
    the changed bytes, then restored the original bytes before a caller's
    own post-parse rehash ran -- the rehash matched the ORIGINAL hash
    despite the changed content being what was actually analyzed. Reading
    once and hashing/parsing that same data makes this structurally
    impossible: there is only one read, so there is no window for the
    file to change in between.**

    Raises CsvSchemaError if 'path' exceeds MAX_CSV_FILE_BYTES. A stat()
    call BEFORE the read is a fast-path rejection for an obviously
    oversized file, but is NOT the enforcement mechanism by itself --
    **fixed, 2026-07-22 Codex review finding (seventh round, P1 finding
    16): the previous version checked stat() size, then called
    path.read_bytes() (unbounded) -- a concurrently growing file could
    exceed the ceiling in the window between the two calls (a classic
    TOCTOU race), and read_bytes() itself has no cap regardless.

    **Fixed again, 2026-07-22 Codex review finding (eighth round, P1
    finding 15): the seventh-round fix's own single fh.read(
    MAX_CSV_FILE_BYTES + 1) call requested a huge buffer up front
    regardless of the file's real size, triggering a large allocation
    attempt (and real, reproducible MemoryError failures under pytest) for
    even a tiny CSV. Reading in bounded CSV_READ_CHUNK_BYTES (1 MiB)
    chunks, checked against the ceiling after EVERY chunk, closed that.**

    **Rewritten, 2026-07-27 Codex review finding (ninth round, P1 finding
    19): a permitted near-500-MB file previously survived the chunked
    ceiling check above only to then be held SIMULTANEOUSLY as a list of
    chunks (never cleared), the joined ``raw_bytes``, a decoded Unicode
    string, and one or more ``StringIO`` readers -- several live,
    full-size copies of the same ~500 MB content at once, several times
    the advertised ceiling, before pandas' own parser storage and the
    resulting DataFrame are even counted. Every chunk is now written
    directly into a ``tempfile.SpooledTemporaryFile`` (in-memory only up
    to CSV_READ_CHUNK_BYTES; anything larger spills to a real temp file
    on disk, per Python's own stdlib) while a SHA-256 hash is updated
    INCREMENTALLY from the same chunk -- neither the raw bytes nor a
    decoded string is ever materialized as one contiguous in-memory
    object. pandas then reads directly from the spool (through one
    ``TextIOWrapper``, reused for both the header-duplicate check and the
    actual parse, never a separate ``StringIO`` copy of the text) --
    pandas' own C parser streams from that file-like object incrementally,
    the same way it would from a real file. The only remaining resident
    copies are the spool itself (bounded, mostly on disk beyond 1 MiB) and
    pandas' own DataFrame -- inherent to using pandas at all, not
    duplicated by this function.**
    """

    file_size = path.stat().st_size
    if file_size > MAX_CSV_FILE_BYTES:
        raise CsvSchemaError(
            f"{path}: file size {file_size} bytes exceeds MAX_CSV_FILE_BYTES ceiling of "
            f"{MAX_CSV_FILE_BYTES} bytes -- refusing to load the whole file into memory"
        )

    hasher = hashlib.sha256()
    spool = tempfile.SpooledTemporaryFile(max_size=CSV_READ_CHUNK_BYTES, mode="w+b")
    try:
        total_read = 0
        with path.open("rb") as fh:
            while True:
                chunk = fh.read(CSV_READ_CHUNK_BYTES)
                if not chunk:
                    break
                total_read += len(chunk)
                if total_read > MAX_CSV_FILE_BYTES:
                    raise CsvSchemaError(
                        f"{path}: file size (observed while reading) exceeds "
                        f"MAX_CSV_FILE_BYTES ceiling of {MAX_CSV_FILE_BYTES} bytes -- refusing "
                        f"to load the rest into memory"
                    )
                hasher.update(chunk)
                spool.write(chunk)

        spool.seek(0)
        # Mirrors "utf-8-sig" text-mode decoding (transparently strips a
        # leading BOM, identical to plain "utf-8" otherwise) -- one
        # TextIOWrapper reused for both checks below, never a second
        # in-memory text copy.
        text_stream = io.TextIOWrapper(spool, encoding="utf-8-sig", newline="")

        raw_headers = next(csv.reader(text_stream), [])
        seen: set[str] = set()
        dupe_set: set[str] = set()
        for h in raw_headers:
            if h in seen:
                dupe_set.add(h)
            seen.add(h)
        dupes = sorted(dupe_set)
        if dupes:
            raise CsvSchemaError(f"{path}: duplicate column header(s) in raw file: {dupes}")

        text_stream.seek(0)
        df = pd.read_csv(text_stream, dtype=dtype)
        missing = required_columns - set(df.columns)
        if missing:
            raise CsvSchemaError(f"{path}: missing required columns: {sorted(missing)}")
        return df, hasher.hexdigest()
    finally:
        # Closes the TextIOWrapper (if created) and, through it, the
        # underlying spool -- a bare spool.close() after text_stream
        # already closed it would be a harmless no-op either way.
        spool.close()


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

    See ``read_csv_with_required_columns_and_hash`` for a variant that
    also returns an ABA-safe dataset-identity hash of the exact bytes
    this was parsed from.
    """

    df, _file_sha256_hex = _read_csv_bytes_checked(path, required_columns, dtype)
    return df


def read_csv_with_required_columns_and_hash(
    path: Path, required_columns: set[str], dtype: Optional[dict] = None
) -> tuple[pd.DataFrame, str]:
    """As ``read_csv_with_required_columns``, but also returns a hex
    SHA-256 digest of the exact bytes 'df' was parsed from -- computed
    from the SAME single read, never a separate later/earlier file open
    (see ``_read_csv_bytes_checked``'s own docstring for why that
    structurally closes the ABA-mutation race a caller's own before/after
    rehash comparison cannot). A caller previously hashing this same path
    via ``report_metadata.compute_file_sha256``/``compute_dataset_hash``
    (a second, independent file open) should switch to this hash instead.

    **Added, 2026-07-22 Codex review finding (fifth round).**
    """

    df, file_sha256_hex = _read_csv_bytes_checked(path, required_columns, dtype)
    return df, file_sha256_hex


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

    **Disclosed, not changed, 2026-07-22 Codex review finding (sixth
    round): the sixth-round review calls this scoping "only partially
    fixed" since a nested output path under 'directory' is still
    permitted. That is unchanged from the fifth round's own reasoning
    above (a non-recursive glob genuinely never descends into a
    subdirectory, so a nested output cannot collide with a LATER read of
    the same directory via the same glob) -- widening this to a full
    ancestry check was tried and reverted during round 5's own
    remediation because it broke this project's own established
    ``tmp_path/out/`` output-subfolder pattern (three legitimate tests
    failed). No new counterexample specific to this scoping was
    reproduced against the current code; left as explicitly-named,
    intentionally-unchanged scope rather than re-broadening the check
    without one.**
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


def write_dataframe_csv_to_temp(df: pd.DataFrame, path: Path) -> Path:
    """Writes 'df' as CSV to a new temp file in the SAME directory as
    'path' (so a later os.replace stays on one filesystem), returning the
    temp file's own Path WITHOUT renaming it into place -- the caller
    commits (os.replace) or discards (os.remove) it.

    **Added, 2026-07-22 Codex review finding (ninth round, P1 finding
    12):** split out of ``atomic_write_dataframe_csv`` so a caller
    coordinating MULTIPLE output files as one atomic group
    (``report_metadata.publish_dataframe_csv_and_json`` and the
    three-output journal/news publishers) can fully prepare every file
    in temp BEFORE committing any of them -- the previous "unlink
    whatever this call already wrote" rollback policy destroyed a
    pre-existing valid file the moment its own (successful) write in the
    same group was followed by a LATER write's failure.
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
    except BaseException:
        try:
            os.remove(tmp_name)
        except OSError:
            pass
        raise
    return Path(tmp_name)


def atomic_write_dataframe_csv(df: pd.DataFrame, path: Path) -> None:
    """Writes 'df' to 'path' as CSV via write-to-temp-then-rename, so an
    interrupted write (crash, kill, disk full) never leaves a partially
    -written CSV at 'path'.

    **Added, 2026-07-22 Codex review finding (third round): JSON writes
    already use this discipline (``report_metadata.atomic_write_text``),
    but every CSV writer in this project remained a direct
    ``df.to_csv(path)`` call.**
    """

    tmp_path = write_dataframe_csv_to_temp(df, path)
    try:
        os.replace(tmp_path, path)
    except BaseException:
        try:
            os.remove(tmp_path)
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
