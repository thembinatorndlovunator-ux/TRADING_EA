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
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import pandas as pd

from analysis.schema import SchemaValidationError, TradeDecision, validate_record


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


def _read_lines_from_file(path: Path) -> tuple[list[tuple[int, dict]], list[ParseError]]:
    """Parses each non-blank line of 'path' as JSON. A line that fails to
    parse is recorded as a ParseError and EXCLUDED from the returned
    records -- never silently dropped without a trace, and never allowed
    to abort reading the rest of the file (one malformed line must not
    hide every other valid line in the same file)."""

    parsed: list[tuple[int, dict]] = []
    errors: list[ParseError] = []

    with path.open("r", encoding="utf-8") as fh:
        for line_number, raw_line in enumerate(fh, start=1):
            stripped = raw_line.strip()
            if not stripped:
                continue
            try:
                record = json.loads(stripped)
            except json.JSONDecodeError as exc:
                errors.append(
                    ParseError(
                        source_file=str(path),
                        line_number=line_number,
                        raw_line=stripped,
                        error=str(exc),
                    )
                )
                continue
            if not isinstance(record, dict):
                errors.append(
                    ParseError(
                        source_file=str(path),
                        line_number=line_number,
                        raw_line=stripped,
                        error=f"expected a JSON object, got {type(record).__name__}",
                    )
                )
                continue
            parsed.append((line_number, record))

    return parsed, errors


def read_journal_directory(directory: Path, pattern: str = "decisions_*.jsonl") -> JournalReadResult:
    """Reads every file matching 'pattern' in 'directory' (non-recursive,
    matching DJ_JournalFilePath's own flat one-file-per-day layout),
    parses, and schema-validates every line. Files are processed in sorted
    filename order (which is also chronological order, since filenames are
    'decisions_YYYYMMDD.jsonl') so 'valid_records' is deterministically
    ordered given the same directory contents.

    Raises FileNotFoundError if 'directory' does not exist -- an empty
    result would otherwise be indistinguishable from "directory exists but
    has no journal files yet", which are different, worth-distinguishing
    situations for a caller.
    """

    if not directory.is_dir():
        raise FileNotFoundError(f"journal directory not found: {directory}")

    all_valid: list[TradeDecision] = []
    all_parse_errors: list[ParseError] = []
    all_validation_errors: list[ValidationError] = []

    for path in sorted(directory.glob(pattern)):
        parsed, parse_errors = _read_lines_from_file(path)
        all_parse_errors.extend(parse_errors)

        for line_number, raw_record in parsed:
            try:
                all_valid.append(validate_record(raw_record))
            except SchemaValidationError as exc:
                all_validation_errors.append(
                    ValidationError(
                        source_file=str(path),
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
