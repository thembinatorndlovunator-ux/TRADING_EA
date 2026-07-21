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
from typing import Optional, Sequence

PIPELINE_VERSION = "0.2.0"  # bump when a pipeline's OUTPUT SHAPE changes,
                            # not on every code edit -- matches this
                            # project's #property version discipline of
                            # marking meaningful revisions, not churn.
                            # **Bumped, 2026-07-22 Codex review finding:**
                            # this remained 0.1.0 through the entire prior
                            # remediation round despite output-shape
                            # changes (renamed fields, new CI columns,
                            # new required checks) directly contrary to
                            # this comment's own stated rule.


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
    """

    if not paths:
        raise ValueError("compute_dataset_hash: no input paths given")

    manifest = sorted((_portable_label(p, repo_root), compute_file_sha256(p)) for p in paths)
    combined = hashlib.sha256()
    for name, file_hash in manifest:
        combined.update(name.encode("utf-8"))
        combined.update(file_hash.encode("utf-8"))
    return combined.hexdigest()


def atomic_write_text(path: Path, content: str, encoding: str = "utf-8") -> None:
    """Writes 'content' to 'path' via write-to-temp-then-rename, so an
    interrupted write (crash, kill, disk full) never leaves a partially-
    written file at 'path' -- either the old contents remain untouched or
    the new contents are complete, never a truncated mix of both."""

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding=encoding) as fh:
            fh.write(content)
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.remove(tmp_name)
        except OSError:
            pass
        raise


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
    repo_path: Optional[Path] = None,
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
    dataset_hash = compute_dataset_hash(list(dataset_paths), repo_root=root)

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
    )
