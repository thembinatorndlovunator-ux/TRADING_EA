from __future__ import annotations

import hashlib
from pathlib import Path

import pytest

from analysis.report_metadata import (
    PIPELINE_VERSION,
    GitMetadataError,
    build_report_metadata,
    capture_git_commit,
    compute_dataset_hash,
    compute_file_sha256,
)


def test_capture_git_commit_in_real_repo():
    # This test file itself lives inside the real Themba_EA_Improvement_Lab
    # git repository, so this is a real (not fabricated) evidence check --
    # deliberately not mocked, since the whole point is confirming this
    # function works against an actual repository.
    repo_root = Path(__file__).resolve().parents[3]
    commit, dirty = capture_git_commit(repo_root)
    assert len(commit) == 40
    assert all(c in "0123456789abcdef" for c in commit)
    assert isinstance(dirty, bool)


def test_capture_git_commit_raises_outside_a_repo(tmp_path):
    with pytest.raises(GitMetadataError):
        capture_git_commit(tmp_path)


def test_compute_file_sha256_matches_hashlib_directly(tmp_path):
    content = b"themba adaptive intraday engine test content\n"
    path = tmp_path / "sample.txt"
    path.write_bytes(content)

    expected = hashlib.sha256(content).hexdigest()
    assert compute_file_sha256(path) == expected


def test_compute_dataset_hash_empty_raises():
    with pytest.raises(ValueError):
        compute_dataset_hash([])


def test_compute_dataset_hash_order_independent(tmp_path):
    file_a = tmp_path / "a.jsonl"
    file_b = tmp_path / "b.jsonl"
    file_a.write_text("line-a\n", encoding="utf-8")
    file_b.write_text("line-b\n", encoding="utf-8")

    hash_ab = compute_dataset_hash([file_a, file_b])
    hash_ba = compute_dataset_hash([file_b, file_a])
    assert hash_ab == hash_ba


def test_compute_dataset_hash_changes_when_content_changes(tmp_path):
    file_a = tmp_path / "a.jsonl"
    file_a.write_text("original\n", encoding="utf-8")
    hash_before = compute_dataset_hash([file_a])

    file_a.write_text("modified\n", encoding="utf-8")
    hash_after = compute_dataset_hash([file_a])

    assert hash_before != hash_after


def test_build_report_metadata(tmp_path):
    repo_root = Path(__file__).resolve().parents[3]
    dataset_file = tmp_path / "decisions_20260721.jsonl"
    dataset_file.write_text('{"example": true}\n', encoding="utf-8")

    metadata = build_report_metadata(
        [dataset_file],
        symbol="XAUUSD",
        broker="Deriv",
        period_start="2026-07-01",
        period_end="2026-07-21",
        random_seed=42,
        repo_path=repo_root,
    )

    assert len(metadata.git_commit) == 40
    assert metadata.symbol == "XAUUSD"
    assert metadata.broker == "Deriv"
    assert metadata.random_seed == 42
    assert metadata.pipeline_version == PIPELINE_VERSION
    assert metadata.timezone == "UTC"
    assert metadata.dataset_hash == compute_dataset_hash([dataset_file])
    # generated_at_utc must be a parseable ISO-8601 timestamp
    from datetime import datetime

    datetime.fromisoformat(metadata.generated_at_utc)
