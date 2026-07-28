"""Provenance metadata every generated report must carry.

Per the reproducibility contract: "Reports record Git commit, dataset
identity/hash, symbol, broker, period, modelling mode, costs, set file,
timezone, random seed, and pipeline version where applicable." This module
captures the mechanical parts of that (git commit, dataset hash, generation
timestamp) and defines the container the rest is recorded into -- it does
not decide what symbol/broker/period a given pipeline used, since only that
pipeline's caller knows that.
"""

from __future__ import annotations

import hashlib
import os
import subprocess
import tempfile
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING, Optional, Sequence

if TYPE_CHECKING:
    import pandas as pd

PIPELINE_VERSION = "0.3.0"  # bump when a pipeline's OUTPUT SHAPE changes,
# not on every code edit -- matches this
# project's #property version discipline of
# marking meaningful revisions, not churn.
# **Bumped, 2026-07-22 Codex review finding:**
# this remained 0.1.0 through the entire prior
# remediation round despite output-shape
# changes (renamed fields, new CI columns,
# new required checks) directly contrary to
# this comment's own stated rule.
# **Bumped again, 2026-07-22 Codex review
# finding (fourth round):** 0.2.0 -> 0.3.0 --
# b88b63a changed output shapes (renamed
# guard_helped_rate fields, added
# monte_carlo.py's bound_type/model/caveat
# keys, join_signal_to_outcome.py's new
# schema, compare_releases.py's mandatory
# period/manifest fields), which this same
# comment's rule required a bump for.


class GitMetadataError(RuntimeError):
    """Raised when the git commit cannot be determined -- a caller must
    handle this explicitly (e.g. label the report as provenance-incomplete)
    rather than have a report silently claim an "unknown" commit as if it
    were a normal value."""


def default_repo_root() -> Path:
    """The Themba_EA_Improvement_Lab repo root, computed from THIS file's
    own on-disk location (``analysis/report_metadata.py`` is always
    exactly 4 levels below the repo root) rather than from the process's
    current working directory.

    **Fixed, 2026-07-21 Codex review finding:** ``build_report_metadata``
    previously defaulted ``repo_path`` to ``None``, which made
    ``capture_git_commit`` fall back to the process cwd -- invoking any
    script from a different working directory (or from another
    repository entirely) could silently record an unrelated commit, or
    fail outright. Every caller in this project now gets a correct
    default without having to pass ``repo_path`` explicitly (tests that
    intentionally exercise a *different* repo, or none, still may).
    """

    return Path(__file__).resolve().parents[3]


def capture_git_commit(repo_path: Optional[Path] = None) -> tuple[str, bool]:
    """Returns (commit_hash, is_dirty) for the repository at 'repo_path'
    (defaults to ``default_repo_root()``, NOT the current working
    directory -- see that function's docstring). Raises GitMetadataError
    if git is unavailable or the path is not inside a git repository --
    never silently returns a placeholder string."""

    cwd = str(repo_path) if repo_path is not None else str(default_repo_root())
    try:
        commit = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        status = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise GitMetadataError(f"could not determine git commit: {exc}") from exc

    return commit, bool(status.strip())


def compute_file_sha256(path: Path, chunk_size: int = 1 << 20) -> str:
    """Streaming SHA-256 of a single file's bytes -- used as the concrete
    "dataset identity/hash" the reproducibility contract requires, so a
    report can later be checked against the exact bytes it was generated
    from, not just a filename that could have since changed."""

    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(chunk_size), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _portable_label(path: Path, repo_root: Optional[Path]) -> str:
    """A stable identifier for 'path' that does not depend on the
    absolute filesystem location it happens to be read from on this
    particular machine -- path relative to 'repo_root' when the file is
    inside the repo, else just the filename (e.g. a test's tmp_path
    fixture, which is never portable across machines/runs anyway)."""

    resolved = path.resolve()
    if repo_root is not None:
        try:
            return str(resolved.relative_to(repo_root.resolve())).replace("\\", "/")
        except ValueError:
            pass
    return resolved.name


def combine_labeled_hashes(labeled_hashes: Sequence[tuple[str, str]]) -> str:
    """Combines (label, hex-digest) pairs from possibly-heterogeneous
    sources (e.g. a journal directory's own inline hash plus a separately
    hashed news CSV) into ONE order-independent identity: sorts the pairs,
    then hashes that sorted manifest -- so the same set of (label, hash)
    pairs always produces the same combined hash regardless of input
    order, and any single differing hash is detected. This is
    ``compute_dataset_hash``'s own combination step, factored out so a
    caller that already computed one or more of its component hashes
    ABA-safely (e.g. via ``data_collection.journal_reader.read_journal_directory``'s
    inline ``dataset_hash``, or ``analysis.csv_io.read_csv_with_required_columns_and_hash``)
    can combine them without re-hashing anything.

    **Added, 2026-07-22 Codex review finding (fifth round).**
    """

    combined = hashlib.sha256()
    for name, file_hash in sorted(labeled_hashes):
        combined.update(name.encode("utf-8"))
        combined.update(file_hash.encode("utf-8"))
    return combined.hexdigest()


def compute_dataset_hash(paths: Sequence[Path], repo_root: Optional[Path] = None) -> str:
    """Combined dataset identity for a MULTI-file input (e.g. a whole
    journal directory of daily .jsonl files): hashes each file
    independently, sorts the (portable-label, hash) pairs for order-
    independence, then hashes that sorted manifest -- so the same set of
    files always produces the same combined hash regardless of directory
    listing order, and any single byte changing anywhere is detected.

    **Fixed, 2026-07-21 Codex review finding:** previously used
    ``str(p)`` (the full, often-absolute path) as the per-file label
    baked into the hash, which (a) meant identical file bytes addressed
    by a relative vs. absolute path, or moved to another machine, hashed
    differently, and (b) could leak a username or private folder name
    into a committed report. Now uses a path relative to 'repo_root'
    (falling back to the bare filename for anything outside the repo,
    e.g. a test's temp directory).

    **Still a separate-read hash, stated explicitly (Codex review
    finding, 2026-07-22, fifth round):** this opens and reads each path a
    SECOND time, independently of wherever a caller's own parsing
    happens -- a race detector (via a before/after comparison), not proof
    the hashed bytes equal whatever was actually parsed elsewhere. A
    caller that can read+hash+parse from one single pass (journal
    directories via ``read_journal_directory``, single CSVs via
    ``read_csv_with_required_columns_and_hash``) should prefer that and
    combine the results with ``combine_labeled_hashes`` instead of this
    function, which remains appropriate only when no such single-pass
    reader exists yet for a given input.
    """

    if not paths:
        raise ValueError("compute_dataset_hash: no input paths given")

    manifest = [(_portable_label(p, repo_root), compute_file_sha256(p)) for p in paths]
    return combine_labeled_hashes(manifest)


def write_text_to_temp(path: Path, content: str, encoding: str = "utf-8") -> Path:
    """Writes 'content' to a new temp file in the SAME directory as
    'path', returning the temp file's own Path WITHOUT renaming it into
    place -- the caller commits (os.replace) or discards (os.remove) it.

    **Added, 2026-07-22 Codex review finding (ninth round, P1 finding
    12):** split out of ``atomic_write_text`` for the same reason as
    ``csv_io.write_dataframe_csv_to_temp`` -- see that function's own
    header.
    """

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding=encoding) as fh:
            fh.write(content)
    except BaseException:
        try:
            os.remove(tmp_name)
        except OSError:
            pass
        raise
    return Path(tmp_name)


def atomic_write_text(path: Path, content: str, encoding: str = "utf-8") -> None:
    """Writes 'content' to 'path' via write-to-temp-then-rename, so an
    interrupted write (crash, kill, disk full) never leaves a partially-
    written file at 'path' -- either the old contents remain untouched or
    the new contents are complete, never a truncated mix of both."""

    tmp_path = write_text_to_temp(path, content, encoding)
    try:
        os.replace(tmp_path, path)
    except BaseException:
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        raise


def atomic_rename_group(renames: Sequence[tuple[Path, Path]]) -> None:
    """Performs a GROUP of temp->final ``os.replace`` renames with rollback.

    **Added, 2026-07-28 Codex review finding (tenth round, P1 finding 11):**
    the prior fix in this module (write every file fully to temp first, then
    rename in order) closed the process-crash residual risk named in
    ``publish_dataframe_csv_and_json``'s own header, but did NOT close an
    ORDINARY (catchable) ``OSError`` raised by a LATER rename in the group --
    the review's own fault injection reproduced exactly this: a second
    ``os.replace`` failure left an already-renamed FIRST file's own NEW
    content paired with an un-renamed (still old) later file, a genuinely
    mismatched generation, not merely a crash-window artifact.

    Fixed by preserving each final path's own pre-existing content (bytes,
    if any) before any rename in the group runs, then -- if any rename in
    the group raises -- restoring every ALREADY-renamed final path back to
    its own pre-call content (or removing it, if it did not exist before
    this call) before re-raising.

    **Residual risk, named honestly:** this is a best-effort rollback, not a
    true transaction -- the rollback's own restoring write could itself fail
    (e.g. the same underlying disk/permission issue that broke the original
    rename). In that narrow, doubly-unlucky case a mismatched generation can
    still result. A full versioned-directory-plus-manifest-pointer scheme
    (the review's own alternative suggestion) would close even that but is
    materially larger design work, not attempted here.
    """
    committed: list[tuple[Path, Optional[bytes]]] = []
    try:
        for tmp_path, final_path in renames:
            old_bytes: Optional[bytes] = final_path.read_bytes() if final_path.exists() else None
            os.replace(tmp_path, final_path)
            committed.append((final_path, old_bytes))
    except OSError:
        for final_path, old_bytes in reversed(committed):
            try:
                if old_bytes is not None:
                    final_path.write_bytes(old_bytes)
                else:
                    final_path.unlink()
            except OSError:
                pass  # best-effort rollback -- see docstring's own residual-risk disclosure
        raise


def publish_dataframe_csv_and_json(
    df: Optional[pd.DataFrame],
    output_csv: Optional[Path],
    payload: Optional[dict],
    summary_json: Optional[Path],
) -> None:
    """Publishes an optional result CSV and an optional provenance/summary
    JSON sidecar as ONE atomic unit whenever BOTH are requested together.

    **Added, 2026-07-22 Codex review finding (eighth round, P1 finding
    16):** every pipeline in this layer that produces a result CSV plus a
    mandatory provenance JSON sidecar (pattern_validation.py cited as the
    review's own representative example; the identical shape recurs in
    analyse_baseline.py, analyse_giveback.py, calculate_mfe_mae.py,
    join_news_events.py, join_signal_to_outcome.py, join_trade_journal.py,
    parameter_stability.py, performance_breakdown.py, walk_forward.py)
    wrote the result CSV via atomic_write_dataframe_csv, THEN the summary
    JSON via atomic_write_text -- each individually atomic (write-to-temp-
    then-rename), but NOT atomic as a PAIR: a fault injected during the
    second (JSON) write left the first (CSV) file genuinely, durably
    present on disk with no accompanying provenance at all, exactly the
    "apparently valid result with no provenance" failure mode round 7's
    own P1 finding 16 fix already closed for one specific ordering bug
    (an invalid repo_path raised AFTER the CSV existed) but did not make
    the two writes atomic as a unit.

    **Rewritten, 2026-07-27 Codex review finding (ninth round, P1 finding
    12):** the previous fix (write CSV, then JSON, and unlink the CSV if
    JSON fails) was itself unsound on a REPUBLISH: ``atomic_write_dataframe_csv``
    overwrites 'output_csv' in place, so by the time the JSON write failed,
    a pre-existing VALID CSV from an earlier successful run had already
    been replaced with this call's new content -- the subsequent unlink
    then destroyed that (new) CSV entirely, leaving no CSV at all paired
    with the OLD JSON (a probe reproduced exactly this: starting from a
    complete old-csv/old-json pair and injecting a JSON-write failure
    produced ``csv_exists=False, json='old-json'``).

    This now writes BOTH files fully to TEMP locations first (neither
    final path is touched at all while either write is in progress); only
    once both temp writes have fully succeeded are they renamed into
    place (JSON first, then CSV). If either temp write raises, every temp
    file this call created is removed and NEITHER final path is ever
    touched -- a pre-existing valid CSV/JSON pair survives completely
    untouched, closing the review's own primary complaint. If only one of
    output_csv/summary_json was requested, this degrades to that single
    file's own write-to-temp-then-rename atomicity.

    **Fixed, 2026-07-28 Codex review finding (tenth round, P1 finding 11):**
    the two renames below now go through ``atomic_rename_group`` (see its
    own docstring), which rolls back an already-completed JSON rename if
    the subsequent CSV rename raises an ORDINARY (catchable) ``OSError`` --
    the review's own fault injection demonstrated this is a normal
    exception path, not only the process-crash residual named below.

    **Residual risk, named honestly, not silently closed:** a literal
    process crash (not a normal exception -- those are fully handled
    above, including the rollback path) landing between the JSON rename
    and the CSV rename is not closed by this fix, nor is the narrow case
    where the rollback's own restoring write itself fails (see
    ``atomic_rename_group``'s own residual-risk disclosure). A full
    versioned-directory-plus-manifest-pointer scheme (the review's own
    alternative suggestion) would close this too but is materially larger
    design work, not attempted here.
    """

    # Local import (not at module top) to avoid a hard import-time
    # dependency from this lightweight provenance module onto csv_io.py for
    # every caller, even ones that never touch a DataFrame.
    from analysis.csv_io import write_dataframe_csv_to_temp

    csv_tmp: Optional[Path] = None
    json_tmp: Optional[Path] = None
    try:
        if output_csv is not None and df is not None:
            csv_tmp = write_dataframe_csv_to_temp(df, output_csv)

        if summary_json is not None and payload is not None:
            import json

            json_tmp = write_text_to_temp(
                summary_json, json.dumps(payload, indent=2, default=str, allow_nan=False)
            )

        renames: list[tuple[Path, Path]] = []
        if json_tmp is not None and summary_json is not None:
            renames.append((json_tmp, summary_json))
        if csv_tmp is not None and output_csv is not None:
            renames.append((csv_tmp, output_csv))
        if renames:
            atomic_rename_group(renames)
            json_tmp = None
            csv_tmp = None
    finally:
        for tmp_path in (csv_tmp, json_tmp):
            if tmp_path is not None:
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass


@dataclass(frozen=True)
class ReportMetadata:
    git_commit: str
    git_dirty: bool
    dataset_paths: tuple[str, ...]
    dataset_hash: str
    symbol: Optional[str]
    currency: Optional[str]
    broker: Optional[str]
    period_start: Optional[str]
    period_end: Optional[str]
    timeframe: Optional[str]
    modelling_mode: Optional[str]
    costs_note: Optional[str]
    set_file: Optional[str]
    timezone: str
    random_seed: Optional[int]
    pipeline_version: str
    # **Added, 2026-07-22 Codex review finding:** the master requirement
    # (00_MASTER_PROMPT_FOR_CLAUDE.md:45-58) names EA version and data
    # source among the facts every result must record; neither field
    # existed on this dataclass at all.
    ea_version: Optional[str] = None
    data_source: Optional[str] = None
    # **Added, 2026-07-22 Codex review finding (third round): spread and
    # slippage (named explicitly in 00_MASTER_PROMPT_FOR_CLAUDE.md:54-58's
    # required-provenance list) had no distinct fields -- only the
    # generic, unstructured costs_note existed.
    spread_note: Optional[str] = None
    slippage_note: Optional[str] = None
    generated_at_utc: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat(timespec="seconds")
    )

    def to_dict(self) -> dict:
        return asdict(self)


def build_report_metadata(
    dataset_paths: Sequence[Path],
    *,
    symbol: Optional[str] = None,
    currency: Optional[str] = None,
    broker: Optional[str] = None,
    period_start: Optional[str] = None,
    period_end: Optional[str] = None,
    timeframe: Optional[str] = None,
    modelling_mode: Optional[str] = None,
    costs_note: Optional[str] = None,
    set_file: Optional[str] = None,
    timezone_label: str = "UTC",
    random_seed: Optional[int] = None,
    ea_version: Optional[str] = None,
    data_source: Optional[str] = None,
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
    # **Added, 2026-07-22 Codex review finding (fifth round):** a caller
    # that already computed a hash INLINE during its own single read pass
    # (e.g. data_collection.journal_reader.read_journal_directory's own
    # JournalReadResult.dataset_hash, accumulated one line at a time from
    # the same file handle used to parse -- see that function's docstring
    # for why this is the only way to structurally close the ABA-mutation
    # race a separate hash-then-parse-then-rehash pattern cannot) should
    # pass it here instead of falling through to a SECOND, independent
    # re-read of 'dataset_paths' below, which would reopen exactly the
    # race window the caller's own single-pass hash already avoided.
    dataset_hash_override: Optional[str] = None,
) -> ReportMetadata:
    """Convenience constructor: captures git commit/dirty state and the
    dataset hash automatically; the caller supplies everything only it
    knows (symbol, currency, broker, period, timeframe, modelling mode,
    costs, set file, seed, EA version, data source).

    'repo_path' defaults to ``default_repo_root()`` (this repo's own
    root), NOT the process's current working directory -- see
    ``capture_git_commit``'s docstring.
    """

    root = repo_path if repo_path is not None else default_repo_root()
    commit, dirty = capture_git_commit(root)
    dataset_hash = (
        dataset_hash_override
        if dataset_hash_override is not None
        else compute_dataset_hash(list(dataset_paths), repo_root=root)
    )

    return ReportMetadata(
        git_commit=commit,
        git_dirty=dirty,
        dataset_paths=tuple(_portable_label(p, root) for p in dataset_paths),
        dataset_hash=dataset_hash,
        symbol=symbol,
        currency=currency,
        broker=broker,
        period_start=period_start,
        period_end=period_end,
        timeframe=timeframe,
        modelling_mode=modelling_mode,
        costs_note=costs_note,
        set_file=set_file,
        timezone=timezone_label,
        random_seed=random_seed,
        pipeline_version=PIPELINE_VERSION,
        ea_version=ea_version,
        data_source=data_source,
        spread_note=spread_note,
        slippage_note=slippage_note,
    )
