"""Reads and validates ThembaEA's DecisionJournal ``.jsonl`` output.

Matches ``DecisionJournal.mqh``'s actual on-disk contract exactly: one
JSON object per line (``DJ_AppendDecision``'s ``FileWriteString(line +
"\\r\\n")``), files named ``decisions_YYYYMMDD.jsonl``
(``DJ_JournalFilePath``), one file per UTC day.

**Known, confirmed cross-layer gap (not a bug in this module -- see
``analysis/schema.py``'s own docstring for the full explanation):**
``ThembaAdaptiveIntradayEA.mq5`` never sets ``signal_id``, so every real
journal record currently has ``signal_id == ""``. Duplicate-detection on
``signal_id`` alone would therefore flag every single row as a "duplicate"
of every other, which is useless. This module additionally offers
duplicate detection on ``(timestamp_utc, symbol)`` as the practical interim
key -- two decisions for the same symbol at the same completed-bar
timestamp should never both exist (``OnTick``'s own once-per-completed-bar
guard, TASK-025, should prevent this on the MQL5 side; if this module ever
finds one, that is a genuine finding worth investigating, not a schema
quirk to filter out).

**Known, stated encoding caveat:** ``DJ_AppendDecision`` opens its file
with MQL5's ``FILE_ANSI`` flag while this reader decodes as UTF-8 (with a
tolerant BOM check). For pure-ASCII content (the only kind any current
strategy/setup name in this project actually produces) the two encodings
are byte-identical, so this has not caused a real failure yet -- but it is
not a matching, tested contract, and a future non-ASCII value (e.g. a
symbol or comment containing an accented character) could decode
incorrectly or raise. Fixing this properly needs an MQL5-side change
(write UTF-8, not ANSI) -- registered as part of a future numbered
follow-up (see TASK-028_PYTHON_STATISTICAL_LAB.md), not silently patched
around here by ignoring decode errors.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

from analysis.schema import SchemaValidationError, TradeDecision, validate_record

DEFAULT_MAX_RECORDS_PER_DIRECTORY = 1_000_000


class JournalReaderLimitError(RuntimeError):
    """Raised when a journal directory contains more raw lines than
    'max_records' -- a caller-controlled or corrupted journal directory
    must not be allowed to exhaust process memory silently."""


def _reject_non_finite_json_constant(token: str) -> None:
    """``json.loads``'s ``parse_constant`` hook: Python's json module, by
    default, silently accepts the non-standard tokens ``NaN``,
    ``Infinity``, and ``-Infinity`` (not valid per RFC 8259). Raising here
    turns that into a normal, reported parse error instead of a silently
    admitted non-finite value that could poison downstream arithmetic."""

    raise ValueError(f"non-standard JSON constant {token!r} (NaN/Infinity) is not permitted")


def _parse_float_rejecting_overflow(text: str) -> float:
    """``json.loads``'s ``parse_float`` hook: a numeric literal that
    OVERFLOWS to infinity when converted to float (e.g. ``1e400``) is a
    completely standard-looking JSON number token -- it never reaches
    ``parse_constant`` at all (that hook only intercepts the literal
    non-standard tokens ``NaN``/``Infinity``/``-Infinity``, not a
    numeric literal that merely evaluates to one via float overflow).

    **Fixed, 2026-07-22 Codex review finding (third round):** because
    nested ``score_breakdown`` is an unconstrained dict, a record
    containing ``{"overflow": 1e400}`` previously validated successfully
    and was written to CSV as ``{'overflow': inf}``, with the CLI
    returning 0 (no error reported anywhere)."""

    value = float(text)
    if not math.isfinite(value):
        raise ValueError(f"numeric literal {text!r} overflows to a non-finite float ({value})")
    return value


def _reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict:
    """``json.loads``'s ``object_pairs_hook``: Python's json module, by
    default, uses last-value-wins semantics for a JSON object containing
    the same key twice (not valid per a strict reading of RFC 8259, and
    never a legitimate DJ_SerializeDecision output). Reproduced Codex
    review counterexample (2026-07-22): a record with two ``score`` keys
    parsed as one valid record with zero parse errors, silently dropping
    the first value. Raising here makes a duplicate key a visible parse
    error instead."""

    seen: dict[str, object] = {}
    for key, value in pairs:
        if key in seen:
            raise ValueError(f"duplicate JSON object key {key!r}")
        seen[key] = value
    return seen


@dataclass(frozen=True)
class ParseError:
    source_file: str
    line_number: int
    raw_line: str
    error: str


@dataclass(frozen=True)
class ValidationError:
    source_file: str
    line_number: int
    raw_record: dict
    error: str


@dataclass(frozen=True)
class JournalReadResult:
    valid_records: list[TradeDecision]
    parse_errors: list[ParseError]
    validation_errors: list[ValidationError]

    @property
    def total_lines(self) -> int:
        return len(self.valid_records) + len(self.parse_errors) + len(self.validation_errors)


def _read_lines_from_file(
    path: Path, source_label: str, remaining_budget: int
) -> tuple[list[tuple[int, dict]], list[ParseError], int]:
    """Parses each non-blank line of 'path' as JSON, STREAMING line-by-line
    (never loading the whole file into memory at once) and raising
    ``JournalReaderLimitError`` as soon as more than 'remaining_budget'
    non-blank lines have been seen -- across this file alone; the caller
    tracks the running total across the whole directory. A line that
    fails to parse (including a non-standard NaN/Infinity constant, a
    duplicate JSON key, or a decoding failure for the whole file) is
    recorded as a ParseError and EXCLUDED from the returned records --
    never silently dropped without a trace, and never allowed to abort
    reading the rest of the DIRECTORY (one bad file must not hide every
    other file's valid lines).

    **Fixed, 2026-07-22 Codex review finding:** this previously called
    ``readlines()`` (loading the entire file into memory) BEFORE the
    caller ever checked the running total against ``max_records`` -- a
    single huge file could exhaust process memory before the limit was
    ever consulted. Returns the count of non-blank lines actually read so
    the caller can maintain a running total without re-reading anything.
    """

    parsed: list[tuple[int, dict]] = []
    errors: list[ParseError] = []
    non_blank_count = 0

    try:
        # "utf-8-sig" tolerates a leading UTF-8 BOM (transparently
        # stripped) while behaving identically to plain "utf-8" for any
        # file without one -- a real, benign case worth handling for
        # free; see the module docstring for the separate, NOT-yet-fixed
        # FILE_ANSI-vs-UTF-8 cross-language encoding caveat.
        with path.open("r", encoding="utf-8-sig") as fh:
            for line_number, raw_line in enumerate(fh, start=1):
                stripped = raw_line.strip()
                if not stripped:
                    continue
                non_blank_count += 1
                if non_blank_count > remaining_budget:
                    raise JournalReaderLimitError(
                        f"{source_label}: more than the remaining max_records budget of "
                        f"{remaining_budget} lines -- refusing to load the rest into memory"
                    )
                try:
                    record = json.loads(
                        stripped,
                        parse_constant=_reject_non_finite_json_constant,
                        parse_float=_parse_float_rejecting_overflow,
                        object_pairs_hook=_reject_duplicate_keys,
                    )
                except ValueError as exc:  # json.JSONDecodeError is itself a ValueError
                    # Cap the retained raw line so one hostile/huge line
                    # cannot itself become an unbounded in-memory payload
                    # inside the error record (Codex review finding).
                    errors.append(
                        ParseError(
                            source_file=source_label,
                            line_number=line_number,
                            raw_line=stripped[:2000],
                            error=str(exc),
                        )
                    )
                    continue
                if not isinstance(record, dict):
                    errors.append(
                        ParseError(
                            source_file=source_label,
                            line_number=line_number,
                            raw_line=stripped[:2000],
                            error=f"expected a JSON object, got {type(record).__name__}",
                        )
                    )
                    continue
                parsed.append((line_number, record))
    except UnicodeDecodeError as exc:
        errors.append(
            ParseError(
                source_file=source_label,
                line_number=0,
                raw_line="",
                error=f"file-level decode failure (not valid UTF-8): {exc}",
            )
        )

    return parsed, errors, non_blank_count


def read_journal_directory(
    directory: Path,
    pattern: str = "decisions_*.jsonl",
    max_records: int = DEFAULT_MAX_RECORDS_PER_DIRECTORY,
) -> JournalReadResult:
    """Reads every file matching 'pattern' in 'directory' (non-recursive,
    matching DJ_JournalFilePath's own flat one-file-per-day layout),
    parses, and schema-validates every line. Files are processed in sorted
    filename order (which is also chronological order, since filenames are
    'decisions_YYYYMMDD.jsonl') so 'valid_records' is deterministically
    ordered given the same directory contents.

    Raises FileNotFoundError if 'directory' does not exist -- an empty
    result would otherwise be indistinguishable from "directory exists but
    has no journal files yet", which are different, worth-distinguishing
    situations for a caller. Raises JournalReaderLimitError if the total
    number of raw (non-blank) lines across every matched file exceeds
    'max_records' -- an unbounded read of a caller-controlled directory
    must not be allowed to exhaust process memory.
    """

    if not directory.is_dir():
        raise FileNotFoundError(f"journal directory not found: {directory}")

    resolved_directory = directory.resolve()

    all_valid: list[TradeDecision] = []
    all_parse_errors: list[ParseError] = []
    all_validation_errors: list[ValidationError] = []
    total_records_seen = 0

    for path in sorted(directory.glob(pattern)):
        # Defensive: 'pattern' is normally a fixed literal
        # ("decisions_*.jsonl"), but a caller-supplied pattern containing
        # ".." components (e.g. "../*.jsonl") must not be allowed to
        # escape 'directory' -- Path.glob itself does not prevent this.
        # Every legitimate match's immediate parent is 'directory' itself
        # (glob's default is non-recursive); anything else is rejected.
        if path.resolve().parent != resolved_directory:
            continue

        # Source labelled relative to 'directory', not an absolute path
        # -- a Codex review finding: error artifacts previously retained
        # the full absolute filesystem path (which can embed a username
        # or private folder name) despite the rest of this project's
        # portable-metadata discipline.
        source_label = str(path.resolve().relative_to(resolved_directory))
        remaining_budget = max_records - total_records_seen
        parsed, parse_errors, non_blank_count = _read_lines_from_file(
            path, source_label, remaining_budget
        )
        all_parse_errors.extend(parse_errors)
        total_records_seen += non_blank_count

        for line_number, raw_record in parsed:
            try:
                all_valid.append(validate_record(raw_record))
            except SchemaValidationError as exc:
                all_validation_errors.append(
                    ValidationError(
                        source_file=source_label,
                        line_number=line_number,
                        raw_record=raw_record,
                        error=str(exc),
                    )
                )

    return JournalReadResult(
        valid_records=all_valid,
        parse_errors=all_parse_errors,
        validation_errors=all_validation_errors,
    )


def to_dataframe(records: list[TradeDecision]) -> pd.DataFrame:
    """Converts validated TradeDecision records to a pandas DataFrame, one
    row per record, columns matching TradeDecision's own field names
    exactly (no renaming) so a caller can cross-reference back to the
    schema/MQL5 source without a translation table. Returns an EMPTY
    DataFrame (with the correct column set, not a bare `pd.DataFrame()`
    with zero columns) when 'records' is empty, so downstream code can
    still inspect `.columns` safely."""

    columns = list(TradeDecision.model_fields.keys())
    if not records:
        return pd.DataFrame(columns=columns)
    return pd.DataFrame([r.model_dump() for r in records], columns=columns)


def find_duplicate_signal_ids(df: pd.DataFrame) -> pd.DataFrame:
    """Rows sharing a NON-EMPTY signal_id with at least one other row.
    Empty signal_ids are excluded from this check entirely (see module
    docstring: every real row currently has signal_id == "", which would
    otherwise trivially flag the whole dataset)."""

    if df.empty or "signal_id" not in df.columns:
        return df.iloc[0:0]
    non_empty = df[df["signal_id"] != ""]
    dup_mask = non_empty.duplicated(subset=["signal_id"], keep=False)
    return non_empty[dup_mask]


def find_duplicate_timestamp_symbol(df: pd.DataFrame) -> pd.DataFrame:
    """Rows sharing (timestamp_utc, symbol) with at least one other row --
    the practical interim duplicate key while signal_id remains unpopulated
    (see module docstring)."""

    if df.empty:
        return df
    dup_mask = df.duplicated(subset=["timestamp_utc", "symbol"], keep=False)
    return df[dup_mask]
