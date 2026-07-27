from __future__ import annotations

import hashlib
from pathlib import Path

import pytest

import pandas as pd

from analysis.report_metadata import (
    PIPELINE_VERSION,
    GitMetadataError,
    build_report_metadata,
    capture_git_commit,
    combine_labeled_hashes,
    compute_dataset_hash,
    compute_file_sha256,
    publish_dataframe_csv_and_json,
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


# --- publish_dataframe_csv_and_json (atomic CSV+JSON pair) ------------------


def test_publish_dataframe_csv_and_json_writes_both_on_success(tmp_path):
    df = pd.DataFrame({"a": [1, 2], "b": [3, 4]})
    output_csv = tmp_path / "result.csv"
    summary_json = tmp_path / "result.summary.json"

    publish_dataframe_csv_and_json(df, output_csv, {"n": 2}, summary_json)

    assert output_csv.exists()
    assert summary_json.exists()
    assert summary_json.read_text(encoding="utf-8").strip().startswith("{")


def test_publish_dataframe_csv_and_json_preserves_prior_valid_pair_when_json_write_fails(
    tmp_path, monkeypatch
):
    """Regression for a Codex review finding (2026-07-27, ninth round, P1
    finding 12): a probe starting from a COMPLETE, valid old-csv/old-json
    pair and injecting a JSON-write failure previously produced
    'csv_exists=False, json=old-json' -- the prior fix (write CSV, then
    JSON, unlink the CSV on JSON failure) unlinked the CSV, but
    atomic_write_dataframe_csv had ALREADY overwritten it in place with
    this call's new content by then, so the unlink destroyed a file that
    was genuinely valid BEFORE this call started, leaving no CSV at all
    paired with the stale old JSON.

    Both files are now fully prepared in TEMP first; neither final path is
    touched until both temp writes succeed. A JSON-write failure must
    leave the ORIGINAL old CSV and old JSON completely untouched, and no
    temp files behind."""

    import analysis.report_metadata as report_metadata_module

    output_csv = tmp_path / "result.csv"
    summary_json = tmp_path / "result.summary.json"
    output_csv.write_text("old-csv-content\n", encoding="utf-8")
    summary_json.write_text("old-json-content", encoding="utf-8")

    def failing_write_text_to_temp(path, content, encoding="utf-8"):
        raise OSError("simulated disk failure writing the provenance sidecar")

    monkeypatch.setattr(report_metadata_module, "write_text_to_temp", failing_write_text_to_temp)

    df = pd.DataFrame({"a": [1, 2], "b": [3, 4]})

    with pytest.raises(OSError, match="simulated disk failure"):
        publish_dataframe_csv_and_json(df, output_csv, {"n": 2}, summary_json)

    assert output_csv.exists(), "the pre-existing valid CSV must survive a JSON-write failure"
    assert output_csv.read_text(encoding="utf-8") == "old-csv-content\n", (
        "the pre-existing CSV's own content must be completely untouched, not silently "
        "overwritten with this call's new (never-committed) content"
    )
    assert summary_json.exists()
    assert summary_json.read_text(encoding="utf-8") == "old-json-content"

    leftover_tmp_files = [
        p for p in tmp_path.iterdir() if p.name not in {"result.csv", "result.summary.json"}
    ]
    assert leftover_tmp_files == [], f"unexpected leftover temp files: {leftover_tmp_files}"


def test_publish_dataframe_csv_and_json_preserves_prior_valid_pair_when_csv_write_fails(
    tmp_path, monkeypatch
):
    """Symmetric case: a CSV-write failure must equally leave a pre-existing
    valid old-csv/old-json pair completely untouched (never a case where
    the CSV's own preparation failure is allowed to reach or replace the
    JSON side either)."""

    output_csv = tmp_path / "result.csv"
    summary_json = tmp_path / "result.summary.json"
    output_csv.write_text("old-csv-content\n", encoding="utf-8")
    summary_json.write_text("old-json-content", encoding="utf-8")

    def failing_write_dataframe_csv_to_temp(df, path):
        raise OSError("simulated disk failure writing the result CSV")

    # publish_dataframe_csv_and_json imports write_dataframe_csv_to_temp
    # locally (a deliberate lazy import -- see that function's own header),
    # re-fetching it from analysis.csv_io's own namespace on every call, so
    # the patch target must be csv_io itself, not report_metadata's module.
    monkeypatch.setattr(
        "analysis.csv_io.write_dataframe_csv_to_temp",
        failing_write_dataframe_csv_to_temp,
    )

    df = pd.DataFrame({"a": [1, 2], "b": [3, 4]})

    with pytest.raises(OSError, match="simulated disk failure"):
        publish_dataframe_csv_and_json(df, output_csv, {"n": 2}, summary_json)

    assert output_csv.read_text(encoding="utf-8") == "old-csv-content\n"
    assert summary_json.read_text(encoding="utf-8") == "old-json-content"


def test_publish_dataframe_csv_and_json_only_csv_requested_no_rollback_logic_needed(tmp_path):
    """When summary_json is not requested at all, only the CSV is written
    -- no pairing/rollback concern applies (matches every pipeline's own
    optional-output_csv-without-summary_json calling convention)."""

    df = pd.DataFrame({"a": [1]})
    output_csv = tmp_path / "result.csv"

    publish_dataframe_csv_and_json(df, output_csv, None, None)

    assert output_csv.exists()


def test_publish_dataframe_csv_and_json_neither_requested_is_a_no_op(tmp_path):
    df = pd.DataFrame({"a": [1]})
    publish_dataframe_csv_and_json(df, None, None, None)  # must not raise
