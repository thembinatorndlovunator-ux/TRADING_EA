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

**Encoding, fixed 2026-07-22 (TASK-036):** ``DJ_AppendDecision`` previously
opened its file with MQL5's ``FILE_ANSI`` flag using the terminal's default
codepage, while this reader decodes as UTF-8 -- byte-identical for
pure-ASCII content, but a latent mismatch for a future non-ASCII value.
``DecisionJournal.mqh`` now passes ``CP_UTF8`` as ``FileOpen``'s explicit
codepage argument (still ``FILE_ANSI`` mode -- single-byte-per-character --
but encoded as real UTF-8, not the system codepage), verified against a
real non-ASCII round trip in ``Test_DecisionJournal.mq5`` (a raw-byte check
for the UTF-8 encoding of an accented character, not just an ASCII smoke
test). This reader's own UTF-8 decode now matches the writer's actual
on-disk encoding.
"""

from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence

import pandas as pd

from analysis.schema import SchemaValidationError, TradeDecision, validate_record

DEFAULT_MAX_RECORDS_PER_DIRECTORY = 1_000_000
# **Added, 2026-07-22 Codex review finding (fourth round):** a single
# physical line with no newline could previously be materialized in full
# (arbitrarily large) before any truncation ever applied -- the
# 2000-char cap on ParseError.raw_line only capped what was RETAINED in
# the error record, not what was READ into memory to get there. A real
# DecisionJournal line (one TradeDecision JSON object) is at most a few
# KB; this is a generous but genuinely bounded ceiling.
#
# **Simplified, 2026-07-22 Codex review finding (sixth round): the file
# is now opened in BINARY mode (see ``_read_lines_from_file``'s own
# docstring), so ``readline(MAX_LINE_BYTES + 1)`` bounds BYTES directly
# -- the previous text-mode character-vs-byte discrepancy this constant's
# name used to require a second, separate byte-length check for no longer
# exists; this is now a genuine, single byte bound.**
MAX_LINE_BYTES = 1_000_000
# **Added, 2026-07-22 Codex review finding (sixth round): only
# nonblank-record count and per-line size were previously bounded -- a
# caller-controlled directory had no maximum file count, no maximum total
# source bytes (a flood of whitespace-only lines bypassed the per-line
# and per-record checks entirely, see ``_read_lines_from_file``'s
# docstring), and no cap on retained error records (up to
# DEFAULT_MAX_RECORDS_PER_DIRECTORY 2000-char error payloads can
# approach gigabytes). All three are now real, enforced ceilings.**
DEFAULT_MAX_FILES_PER_DIRECTORY = 10_000
DEFAULT_MAX_TOTAL_SOURCE_BYTES = 2_000_000_000  # 2 GB of raw source bytes per directory
DEFAULT_MAX_RETAINED_ERRORS = 50_000  # combined parse_errors + validation_errors


class JournalReaderLimitError(RuntimeError):
    """Raised when a journal directory contains more raw lines, raw bytes,
    files, or retained error records than the configured maximum -- a
    caller-controlled or corrupted journal directory must not be allowed
    to exhaust process memory silently."""


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


_MAX_RETAINED_RAW_RECORD_CHARS = 2000


def _cap_raw_record(raw_record: dict) -> dict:
    """Bounds how much of a syntactically-valid-but-schema-invalid JSON
    record is RETAINED in a ``ValidationError`` -- **added, 2026-07-22
    Codex review finding (fourth round): unlike ``ParseError.raw_line``
    (already capped at 2000 chars), ``ValidationError.raw_record``
    previously retained the FULL parsed dict verbatim, with no size
    bound -- an unconstrained nested field (e.g. ``score_breakdown``,
    a caller-controlled dict with no schema of its own) could make a
    single validation-error record an unbounded in-memory payload.**"""

    serialized = json.dumps(raw_record, default=str)
    if len(serialized) <= _MAX_RETAINED_RAW_RECORD_CHARS:
        return raw_record
    return {
        "_truncated": True,
        "_original_length_chars": len(serialized),
        "preview": serialized[:_MAX_RETAINED_RAW_RECORD_CHARS],
    }


@dataclass(frozen=True)
class JournalReadResult:
    valid_records: list[TradeDecision]
    parse_errors: list[ParseError]
    validation_errors: list[ValidationError]
    # **Added, 2026-07-22 Codex review finding (fifth round):** a combined
    # SHA-256 identity of exactly the files/bytes this result was actually
    # produced from -- computed INLINE during the same read pass that
    # produced 'valid_records'/'parse_errors'/'validation_errors' above
    # (see '_read_lines_from_file's own docstring), never via a separate
    # later re-read of the same paths. A caller should use THIS hash as
    # the dataset identity for whatever it derives from this result,
    # instead of independently calling analysis.report_metadata's
    # compute_dataset_hash on the same file list -- that separate call
    # (a) reopens each file a second time, reintroducing the ABA-mutation
    # race this hash exists to avoid, and (b) would also include any
    # candidate path (e.g. an outward symlink resolving outside
    # 'directory') that THIS reader itself skipped as out-of-scope,
    # producing nonempty provenance for zero analyzed rows -- structurally
    # impossible here, since only files this loop actually entered ever
    # contribute to the hash.
    dataset_hash: str = ""

    @property
    def total_lines(self) -> int:
        return len(self.valid_records) + len(self.parse_errors) + len(self.validation_errors)


_UTF8_BOM = b"\xef\xbb\xbf"


def _read_lines_from_file(
    path: Path,
    source_label: str,
    remaining_budget: int,
    remaining_byte_budget: int,
    remaining_error_budget: int,
) -> tuple[list[tuple[int, dict]], list[ParseError], int, int, str]:
    """Parses each non-blank line of 'path' as JSON, STREAMING line-by-line
    (never loading the whole file into memory at once) and raising
    ``JournalReaderLimitError`` as soon as more than 'remaining_budget'
    non-blank lines, or 'remaining_byte_budget' raw bytes (blank lines
    included -- see the sixth-round note below), have been seen -- across
    this file alone; the caller tracks both running totals across the
    whole directory. A line that fails to parse (including a non-standard
    NaN/Infinity constant, a duplicate JSON key, or a decoding failure) is
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

    **Fixed, 2026-07-22 Codex review finding (fourth round): a single
    physical line with no newline was previously materialized in full
    (arbitrarily large) via plain line iteration, before ANY length check
    -- the 2000-char cap applied only to what got RETAINED in the error
    record, not to what was read into memory to produce it.** An oversized
    line is reported as a single ParseError (its remainder consumed and
    discarded, not re-parsed as if it were multiple lines) rather than
    exhausting memory.

    **Rewritten, 2026-07-22 Codex review finding (sixth round): the file
    was previously opened in TEXT mode (``encoding="utf-8-sig"``), which
    (a) performs universal newline translation -- CRLF and bare CR bytes
    are silently rewritten to LF before this function ever sees them --
    and (b) transparently strips a leading BOM. The per-line hash was then
    computed by RE-ENCODING that already-translated/stripped text
    (``raw_line.encode("utf-8")``), not the original on-disk bytes.
    Reproduced counterexample: byte-distinct LF-only, CRLF, and BOM+LF
    files with otherwise identical content all produced the SAME digest
    -- the documented claim that this hash represents "the exact parsed
    bytes" was false. A second, related counterexample: a decode failure
    previously raised INSIDE the text-mode ``readline()`` call itself,
    before any bytes for that call reached the hasher (Python's own
    internal decode buffering can consume more raw bytes than it
    successfully decodes) -- two byte-distinct invalid UTF-8 streams could
    therefore collapse to the same digest, since neither contributed the
    bytes at/after its own failure point.

    Both are closed by opening in BINARY mode and hashing each raw
    ``bytes`` line the INSTANT it is read, strictly before any decoding is
    attempted -- decode failure or success can no longer affect what was
    already hashed. A leading UTF-8 BOM is still stripped for PARSING
    (matching "utf-8-sig"'s tolerant behavior), but only from the bytes
    handed to ``.decode()``, never from what was hashed -- the BOM itself
    is now part of the exact-byte identity, as it must be for the identity
    to be genuinely exact. A per-line (not file-level) decode failure is
    reported and reading STOPS for this file (matching the prior
    file-level-abort behavior as closely as possible while still hashing
    every byte actually read).

    **Added, 2026-07-22 Codex review finding (sixth round): a flood of
    whitespace-only (or otherwise blank-after-strip) lines previously
    bypassed both the record-count budget AND any byte-based budget
    entirely -- each is discarded before either check runs, so a file
    consisting almost entirely of near-``MAX_LINE_BYTES``-sized blank
    lines could grow arbitrarily large while only a handful of lines ever
    counted as "records".** The new byte-budget check below runs on EVERY
    line read (blank or not), immediately after hashing and before the
    blank-line short-circuit, so no line -- record or not -- is exempt
    from it.

    **Returns a 5th element, a hex SHA-256 digest** (added fifth round,
    unchanged in spirit by the binary rewrite above): accumulated INLINE,
    one line at a time, from the very same read calls that produce
    'parsed'/'errors' below -- computed from a single open file handle in
    a single pass, so it is structurally impossible for the hashed bytes
    to differ from the parsed ones: there is no second read, and
    therefore no window for the file to change in between.

    **Added, 2026-07-22 Codex review finding (seventh round, P1 finding
    16): 'remaining_error_budget' -- previously, max_retained_errors was
    only checked by the CALLER after this function returned, i.e. after
    an ENTIRE file's own parse errors had already been fully accumulated
    in memory. A single file consisting of up to 'remaining_budget' (as
    large as max_records, e.g. 1,000,000) malformed-but-individually-
    small lines could retain far more error records than
    max_retained_errors (default 50,000) before that ceiling ever took
    effect. This function now enforces the SAME ceiling incrementally,
    from within its own per-line loop, so a single hostile file can never
    itself exceed the remaining budget.**
    """

    def _append_error(err: ParseError) -> None:
        errors.append(err)
        if len(errors) > remaining_error_budget:
            raise JournalReaderLimitError(
                f"{source_label}: retained parse error count exceeds the remaining "
                f"max_retained_errors budget of {remaining_error_budget} -- refusing to retain "
                "any more error records"
            )

    parsed: list[tuple[int, dict]] = []
    errors: list[ParseError] = []
    non_blank_count = 0
    bytes_read = 0
    hasher = hashlib.sha256()

    with path.open("rb") as fh:
        line_number = 0
        is_first_line = True
        while True:
            raw_bytes = fh.readline(MAX_LINE_BYTES + 1)
            if raw_bytes == b"":
                break  # EOF
            line_number += 1
            # Hashed INLINE from the EXACT raw bytes read from disk, before
            # any BOM-stripping or decoding -- see the docstring above for
            # why this (not a decoded-then-re-encoded str) is the only way
            # to make this a true exact-byte identity.
            hasher.update(raw_bytes)
            bytes_read += len(raw_bytes)
            if bytes_read > remaining_byte_budget:
                raise JournalReaderLimitError(
                    f"{source_label}: more than the remaining max_total_source_bytes budget of "
                    f"{remaining_byte_budget} bytes -- refusing to load the rest into memory"
                )

            oversized = len(raw_bytes) > MAX_LINE_BYTES and not raw_bytes.endswith(b"\n")
            if oversized:
                # Consume and discard the rest of this physical line
                # (bounded per read) so the file position lands correctly
                # at the start of the NEXT real line.
                while True:
                    chunk = fh.readline(MAX_LINE_BYTES + 1)
                    hasher.update(chunk)
                    bytes_read += len(chunk)
                    if bytes_read > remaining_byte_budget:
                        raise JournalReaderLimitError(
                            f"{source_label}: more than the remaining "
                            f"max_total_source_bytes budget of {remaining_byte_budget} "
                            f"bytes -- refusing to load the rest into memory"
                        )
                    if chunk == b"" or chunk.endswith(b"\n"):
                        break
                _append_error(
                    ParseError(
                        source_file=source_label,
                        line_number=line_number,
                        raw_line=raw_bytes[:2000].decode("utf-8", errors="replace"),
                        error=f"line exceeds max line length of {MAX_LINE_BYTES} bytes",
                    )
                )
                continue

            line_bytes = raw_bytes
            if is_first_line and line_bytes.startswith(_UTF8_BOM):
                # Tolerant of a leading BOM for PARSING only, matching
                # "utf-8-sig"'s prior behavior -- the BOM bytes themselves
                # were already hashed above, unstripped, so they still
                # count toward the exact-byte identity.
                line_bytes = line_bytes[len(_UTF8_BOM) :]
            is_first_line = False

            try:
                raw_line = line_bytes.decode("utf-8")
            except UnicodeDecodeError as exc:
                _append_error(
                    ParseError(
                        source_file=source_label,
                        line_number=line_number,
                        raw_line="",
                        error=f"file-level decode failure (not valid UTF-8): {exc}",
                    )
                )
                # **Fixed, 2026-07-22 Codex review finding (seventh round,
                # P1 finding 16): parsing stops here (matching the prior
                # file-level-abort behavior), but the hash must still cover
                # the REST of the file's raw bytes -- otherwise two files
                # sharing an identical prefix up to this exact decode
                # failure, but differing arbitrarily afterward, would
                # receive the SAME dataset hash (the unread suffix was
                # previously never hashed at all, since the loop simply
                # stopped calling fh.readline()). Drains and hashes the
                # remainder in bounded 64KB chunks, still enforcing
                # remaining_byte_budget, without attempting to parse any
                # of it.**
                while True:
                    tail_chunk = fh.read(65536)
                    if tail_chunk == b"":
                        break
                    hasher.update(tail_chunk)
                    bytes_read += len(tail_chunk)
                    if bytes_read > remaining_byte_budget:
                        raise JournalReaderLimitError(
                            f"{source_label}: more than the remaining max_total_source_bytes "
                            f"budget of {remaining_byte_budget} bytes -- refusing to load the "
                            "rest into memory"
                        )
                break  # matches the prior file-level-abort behavior

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
            # **Added, 2026-07-22 Codex review finding (fifth round):**
            # a deeply-nested-but-sub-megabyte JSON row (e.g. thousands
            # of nested arrays/objects) exhausts Python's own call
            # stack inside json.loads, raising RecursionError -- NOT a
            # ValueError, so it previously propagated straight out of
            # this function, aborting the ENTIRE directory read on one
            # malformed row instead of becoming a single row error.
            except (ValueError, RecursionError) as exc:
                # Cap the retained raw line so one hostile/huge line
                # cannot itself become an unbounded in-memory payload
                # inside the error record (Codex review finding).
                _append_error(
                    ParseError(
                        source_file=source_label,
                        line_number=line_number,
                        raw_line=stripped[:2000],
                        error=str(exc) or type(exc).__name__,
                    )
                )
                continue
            if not isinstance(record, dict):
                _append_error(
                    ParseError(
                        source_file=source_label,
                        line_number=line_number,
                        raw_line=stripped[:2000],
                        error=f"expected a JSON object, got {type(record).__name__}",
                    )
                )
                continue
            parsed.append((line_number, record))

    return parsed, errors, non_blank_count, bytes_read, hasher.hexdigest()


def read_journal_directory(
    directory: Path,
    pattern: str = "decisions_*.jsonl",
    max_records: int = DEFAULT_MAX_RECORDS_PER_DIRECTORY,
    files: Optional[Sequence[Path]] = None,
    # **Added, 2026-07-22 Codex review finding (sixth round): see the
    # module-level constants' own comment for what each of these three
    # newly-enforced ceilings closes.**
    max_files: int = DEFAULT_MAX_FILES_PER_DIRECTORY,
    max_total_source_bytes: int = DEFAULT_MAX_TOTAL_SOURCE_BYTES,
    max_retained_errors: int = DEFAULT_MAX_RETAINED_ERRORS,
) -> JournalReadResult:
    """Reads every file matching 'pattern' in 'directory' (non-recursive,
    matching DJ_JournalFilePath's own flat one-file-per-day layout),
    parses, and schema-validates every line. Files are processed in sorted
    filename order (which is also chronological order, since filenames are
    'decisions_YYYYMMDD.jsonl') so 'valid_records' is deterministically
    ordered given the same directory contents.

    **'files', added 2026-07-22 (Codex review finding, fourth round):** if
    given, reads EXACTLY this pre-enumerated file list instead of globbing
    'directory' again internally. A caller that already globbed
    'directory' once to compute a dataset hash (e.g. join_trade_journal.py,
    join_news_events.py) MUST pass that same list here -- otherwise a
    second, independent glob can observe a file added between the two
    reads, silently analyzing content the hash never covered (a probe
    added a second decisions_*.jsonl file after the caller's initial
    glob/hash: both files got parsed here, but the caller's metadata and
    post-parse re-hash both still only knew about the first). Each entry
    is still verified to resolve to an immediate child of 'directory' (the
    same sandboxing this function already applies to its own glob).

    Raises FileNotFoundError if 'directory' does not exist -- an empty
    result would otherwise be indistinguishable from "directory exists but
    has no journal files yet", which are different, worth-distinguishing
    situations for a caller. Raises JournalReaderLimitError if the total
    number of raw (non-blank) lines across every matched file exceeds
    'max_records', if the total raw byte count across every matched file
    exceeds 'max_total_source_bytes', if the number of matched files
    exceeds 'max_files', or if the combined count of retained parse/
    validation error records exceeds 'max_retained_errors' -- an unbounded
    read of a caller-controlled directory must not be allowed to exhaust
    process memory along any of these dimensions.

    **Fixed, 2026-07-22 Codex review finding (sixth round): a candidate
    path that is not a regular file (e.g. a subdirectory whose NAME
    happens to match 'pattern', or a broken symlink) previously reached
    ``_read_lines_from_file``'s own ``path.open()`` call directly, raising
    an unhandled ``PermissionError``/``IsADirectoryError`` that aborted
    the entire directory read. It is now excluded and reported as a
    ParseError instead, the same way an outward-resolving symlink is.**

    **Fixed, 2026-07-22 Codex review finding (sixth round): a candidate
    path resolving OUTSIDE 'directory' (an outward symlink, or a
    caller-supplied 'files' entry escaping 'directory') was previously
    silently skipped with a bare ``continue`` -- indistinguishable from
    "this file simply does not exist". It is now recorded as a ParseError
    (source-labelled by its own un-resolved name, since a path escaping
    'directory' cannot be safely relativized against it) so an excluded
    requested source is never silently invisible.**
    """

    if not directory.is_dir():
        raise FileNotFoundError(f"journal directory not found: {directory}")

    resolved_directory = directory.resolve()

    all_valid: list[TradeDecision] = []
    all_parse_errors: list[ParseError] = []
    all_validation_errors: list[ValidationError] = []
    total_records_seen = 0
    total_bytes_seen = 0
    per_file_hashes: list[tuple[str, str]] = []

    # **Fixed, 2026-07-22 Codex review finding (seventh round, P1 finding
    # 16): 'sorted(directory.glob(pattern))' previously fully materialized
    # (and sorted) EVERY matching path before max_files ever got a chance
    # to reject the directory -- an adversarial directory with far more
    # than max_files matching entries could exhaust memory/time building
    # that full list before the ceiling check below ever ran. This now
    # consumes the (unsorted) candidate iterator incrementally, aborting
    # the instant more than max_files entries have been seen, and only
    # THEN sorts the bounded result.
    candidate_source = iter(files) if files is not None else directory.glob(pattern)
    candidate_paths_unsorted: list[Path] = []
    for candidate in candidate_source:
        candidate_paths_unsorted.append(candidate)
        if len(candidate_paths_unsorted) > max_files:
            raise JournalReaderLimitError(
                f"{directory}: more than max_files budget of {max_files} candidate file(s) -- "
                "refusing to read the rest into memory"
            )
    candidate_paths = sorted(candidate_paths_unsorted)

    for path in candidate_paths:
        # Defensive: 'pattern' is normally a fixed literal
        # ("decisions_*.jsonl"), but a caller-supplied pattern containing
        # ".." components (e.g. "../*.jsonl") must not be allowed to
        # escape 'directory' -- Path.glob itself does not prevent this.
        # Every legitimate match's immediate parent is 'directory' itself
        # (glob's default is non-recursive); anything else is rejected.
        # **Reported, not silently skipped, 2026-07-22 Codex review
        # finding (sixth round): see this function's own docstring.**
        if path.resolve().parent != resolved_directory:
            all_parse_errors.append(
                ParseError(
                    source_file=str(path),
                    line_number=0,
                    raw_line="",
                    error=f"excluded: resolves outside journal directory {directory}",
                )
            )
            continue

        # **Added, 2026-07-22 Codex review finding (sixth round):** a
        # non-regular-file candidate (a subdirectory whose name matches
        # 'pattern', a broken symlink, a FIFO/device node, etc.) must
        # never reach ``_read_lines_from_file``'s own ``path.open()`` --
        # opening a directory raises PermissionError on Windows
        # (IsADirectoryError on POSIX), which previously propagated
        # unhandled and aborted the whole directory read.
        if not path.is_file():
            all_parse_errors.append(
                ParseError(
                    source_file=str(path.resolve().relative_to(resolved_directory)),
                    line_number=0,
                    raw_line="",
                    error="excluded: matched pattern but is not a regular file",
                )
            )
            continue

        # Source labelled relative to 'directory', not an absolute path
        # -- a Codex review finding: error artifacts previously retained
        # the full absolute filesystem path (which can embed a username
        # or private folder name) despite the rest of this project's
        # portable-metadata discipline.
        source_label = str(path.resolve().relative_to(resolved_directory))
        remaining_budget = max_records - total_records_seen
        remaining_byte_budget = max_total_source_bytes - total_bytes_seen
        # **Added, 2026-07-22 Codex review finding (seventh round, P1
        # finding 16): the remaining error budget is now passed IN so a
        # single file cannot itself retain more parse errors than the
        # combined ceiling allows -- see _read_lines_from_file's own
        # docstring.**
        remaining_error_budget = max_retained_errors - (
            len(all_parse_errors) + len(all_validation_errors)
        )
        parsed, parse_errors, non_blank_count, bytes_read, file_hash = _read_lines_from_file(
            path, source_label, remaining_budget, remaining_byte_budget, remaining_error_budget
        )
        all_parse_errors.extend(parse_errors)
        total_records_seen += non_blank_count
        total_bytes_seen += bytes_read
        per_file_hashes.append((source_label, file_hash))

        # **Fixed, 2026-07-22 Codex review finding (eighth round, P1 finding
        # 16): the budget check previously ran ONLY after this ENTIRE file's
        # records had all been schema-validated -- the remaining_error_budget
        # computed above bounds PARSE errors within _read_lines_from_file,
        # but nothing bounded VALIDATION errors appended in this loop until
        # the file was fully processed. Five syntactically valid,
        # schema-invalid records with max_retained_errors=1 were all
        # validated and retained (this loop ran to completion) before the
        # (then-only) post-loop check ever raised -- the claimed memory
        # bound did not actually hold for validation errors within one
        # file. The check now runs inside the loop, immediately after each
        # append, so it fails fast the INSTANT the combined budget is
        # exceeded, mid-file, exactly like _read_lines_from_file's own
        # per-line parse-error bound already does.**
        for line_number, raw_record in parsed:
            try:
                all_valid.append(validate_record(raw_record))
            except SchemaValidationError as exc:
                all_validation_errors.append(
                    ValidationError(
                        source_file=source_label,
                        line_number=line_number,
                        raw_record=_cap_raw_record(raw_record),
                        error=str(exc),
                    )
                )
                if len(all_parse_errors) + len(all_validation_errors) > max_retained_errors:
                    raise JournalReaderLimitError(
                        f"{directory}: retained parse/validation error count exceeds "
                        f"max_retained_errors budget of {max_retained_errors} -- refusing to "
                        f"retain any more error records"
                    )

        # **Added, 2026-07-22 Codex review finding (sixth round):** a
        # defensive, redundant re-check after each file -- the in-loop
        # check above already fails fast on every validation error, but
        # this also catches the (already correctly bounded) parse-error
        # count from _read_lines_from_file itself, so a directory of many
        # heavily-malformed files still cannot retain an unbounded number
        # of (up to 2000-char each) error records in memory.
        if len(all_parse_errors) + len(all_validation_errors) > max_retained_errors:
            raise JournalReaderLimitError(
                f"{directory}: retained parse/validation error count exceeds max_retained_errors "
                f"budget of {max_retained_errors} -- refusing to retain any more error records"
            )

    # Combined, order-independent identity of every file actually read --
    # same sorted-manifest scheme as analysis.report_metadata.compute_dataset_hash
    # (so the two remain comparable in shape), but computed entirely from
    # the per-file hashes accumulated INLINE above, never a second re-read.
    combined = hashlib.sha256()
    for name, file_hash in sorted(per_file_hashes):
        combined.update(name.encode("utf-8"))
        combined.update(file_hash.encode("utf-8"))

    return JournalReadResult(
        valid_records=all_valid,
        parse_errors=all_parse_errors,
        validation_errors=all_validation_errors,
        dataset_hash=combined.hexdigest(),
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
