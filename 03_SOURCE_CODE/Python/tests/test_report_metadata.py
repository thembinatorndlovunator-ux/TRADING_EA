from __future__ import annotations

import hashlib
from pathlib import Path

import pytest

from analysis.report_metadata import (
    PIPELINE_VERSION,
    GitMetadataError,
    build_report_metadata,
    capture_git_commit,
    combine_labeled_hashes,
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


def test_combine_labeled_hashes_matches_compute_dataset_hash(tmp_path):
    """combine_labeled_hashes is compute_dataset_hash's own combination
    step, factored out (Codex review finding, 2026-07-22, fifth round) so
    a caller with its own ABA-safe, single-pass-computed component hashes
    can combine them without re-hashing anything -- the two must agree
    exactly when fed the same underlying (label, hash) pairs."""

    file_a = tmp_path / "a.jsonl"
    file_b = tmp_path / "b.jsonl"
    file_a.write_text("line-a\n", encoding="utf-8")
    file_b.write_text("line-b\n", encoding="utf-8")

    via_compute_dataset_hash = compute_dataset_hash([file_a, file_b], repo_root=tmp_path)
    via_combine = combine_labeled_hashes(
        [
            ("a.jsonl", compute_file_sha256(file_a)),
            ("b.jsonl", compute_file_sha256(file_b)),
        ]
    )
    assert via_compute_dataset_hash == via_combine


def test_combine_labeled_hashes_order_independent():
    a = combine_labeled_hashes([("x", "hash1"), ("y", "hash2")])
    b = combine_labeled_hashes([("y", "hash2"), ("x", "hash1")])
    assert a == b


def test_combine_labeled_hashes_changes_when_a_component_hash_changes():
    a = combine_labeled_hashes([("x", "hash1"), ("y", "hash2")])
    b = combine_labeled_hashes([("x", "hash1"), ("y", "hash2-changed")])
    assert a != b


def test_build_report_metadata_dataset_hash_override(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round): a
    caller that already computed its own ABA-safe hash (e.g. from a
    single-pass reader) should be able to supply it directly instead of
    triggering a second, independent re-read of 'dataset_paths' via
    compute_dataset_hash."""

    repo_root = Path(__file__).resolve().parents[3]
    file_a = tmp_path / "a.csv"
    file_a.write_text("trade_id,profit\nt1,10.0\n", encoding="utf-8")

    metadata = build_report_metadata(
        [file_a], repo_path=repo_root, dataset_hash_override="deadbeef" * 8
    )
    assert metadata.dataset_hash == "deadbeef" * 8


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
