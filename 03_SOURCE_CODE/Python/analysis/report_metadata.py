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
import subprocess
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Sequence

PIPELINE_VERSION = "0.1.0"  # bump when a pipeline's OUTPUT SHAPE changes,
                            # not on every code edit -- matches this
                            # project's #property version discipline of
                            # marking meaningful revisions, not churn.


class GitMetadataError(RuntimeError):
    """Raised when the git commit cannot be determined -- a caller must
    handle this explicitly (e.g. label the report as provenance-incomplete)
    rather than have a report silently claim an "unknown" commit as if it
    were a normal value."""


def capture_git_commit(repo_path: Optional[Path] = None) -> tuple[str, bool]:
    """Returns (commit_hash, is_dirty) for the repository at 'repo_path'
    (defaults to the current working directory). Raises GitMetadataError if
    git is unavailable or the path is not inside a git repository -- never
    silently returns a placeholder string."""

    cwd = str(repo_path) if repo_path is not None else None
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


def compute_dataset_hash(paths: Sequence[Path]) -> str:
    """Combined dataset identity for a MULTI-file input (e.g. a whole
    journal directory of daily .jsonl files): hashes each file
    independently, sorts the (relative-path, hash) pairs for order-
    independence, then hashes that sorted manifest -- so the same set of
    files always produces the same combined hash regardless of directory
    listing order, and any single byte changing anywhere is detected."""

    if not paths:
        raise ValueError("compute_dataset_hash: no input paths given")

    manifest = sorted((str(p), compute_file_sha256(p)) for p in paths)
    combined = hashlib.sha256()
    for name, file_hash in manifest:
        combined.update(name.encode("utf-8"))
        combined.update(file_hash.encode("utf-8"))
    return combined.hexdigest()


@dataclass(frozen=True)
class ReportMetadata:
    git_commit: str
    git_dirty: bool
    dataset_paths: tuple[str, ...]
    dataset_hash: str
    symbol: Optional[str]
    broker: Optional[str]
    period_start: Optional[str]
    period_end: Optional[str]
    timezone: str
    random_seed: Optional[int]
    pipeline_version: str
    generated_at_utc: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat(timespec="seconds")
    )

    def to_dict(self) -> dict:
        return asdict(self)


def build_report_metadata(
    dataset_paths: Sequence[Path],
    *,
    symbol: Optional[str] = None,
    broker: Optional[str] = None,
    period_start: Optional[str] = None,
    period_end: Optional[str] = None,
    timezone_label: str = "UTC",
    random_seed: Optional[int] = None,
    repo_path: Optional[Path] = None,
) -> ReportMetadata:
    """Convenience constructor: captures git commit/dirty state and the
    dataset hash automatically; the caller supplies everything only it
    knows (symbol, broker, period, seed)."""

    commit, dirty = capture_git_commit(repo_path)
    dataset_hash = compute_dataset_hash(list(dataset_paths))

    return ReportMetadata(
        git_commit=commit,
        git_dirty=dirty,
        dataset_paths=tuple(str(p) for p in dataset_paths),
        dataset_hash=dataset_hash,
        symbol=symbol,
        broker=broker,
        period_start=period_start,
        period_end=period_end,
        timezone=timezone_label,
        random_seed=random_seed,
        pipeline_version=PIPELINE_VERSION,
    )
