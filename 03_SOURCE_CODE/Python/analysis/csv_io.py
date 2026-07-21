"""Shared CSV-reading helper: every script in this analysis layer takes
explicit CSV input paths (per the reproducibility contract, "pipelines
accept explicit input/output paths"), and every one of them must fail
loudly, not silently, on a missing required column -- this is the one
place that check is implemented."""

from __future__ import annotations

from pathlib import Path

import pandas as pd


class CsvSchemaError(ValueError):
    """Raised when a CSV is missing one or more required columns."""


def read_csv_with_required_columns(path: Path, required_columns: set[str]) -> pd.DataFrame:
    """Reads 'path' as CSV and raises CsvSchemaError if any of
    'required_columns' is absent. Raises FileNotFoundError (pandas' own,
    propagated) if 'path' does not exist -- a caller must distinguish "the
    file is missing" from "the file exists but has the wrong shape", since
    they call for different remediation."""

    df = pd.read_csv(path)
    missing = required_columns - set(df.columns)
    if missing:
        raise CsvSchemaError(f"{path}: missing required columns: {sorted(missing)}")
    return df


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
