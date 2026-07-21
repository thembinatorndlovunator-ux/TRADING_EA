"""Shared CSV-reading helper: every script in this analysis layer takes
explicit CSV input paths (per the reproducibility contract, "pipelines
accept explicit input/output paths"), and every one of them must fail
loudly, not silently, on a missing required column -- this is the one
place that check is implemented."""

from __future__ import annotations

from pathlib import Path
from typing import Sequence

import numpy as np
import pandas as pd


class CsvSchemaError(ValueError):
    """Raised when a CSV is missing one or more required columns, contains
    a duplicate durable ID, a non-finite/missing numeric value, or invalid
    OHLC geometry -- every one of these is a reportable data-integrity
    problem per the reproducibility contract's "visible failures, never
    silently coerced" rule, not something a caller should filter out
    quietly."""


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


def assert_unique_ids(df: pd.DataFrame, id_column: str, path: Path) -> None:
    """Raises CsvSchemaError if 'id_column' contains any duplicate,
    non-null value -- per the reproducibility contract, duplicate durable
    IDs (trade_id, event_id, etc.) must be a visible failure, never
    silently deduplicated or averaged over."""

    non_null = df[df[id_column].notna()]
    duplicated = non_null[non_null.duplicated(subset=[id_column], keep=False)]
    if not duplicated.empty:
        dup_ids = sorted(duplicated[id_column].astype(str).unique())
        raise CsvSchemaError(f"{path}: duplicate {id_column} values found: {dup_ids}")


def assert_finite_columns(df: pd.DataFrame, columns: Sequence[str], path: Path) -> None:
    """Raises CsvSchemaError if any of 'columns' contains a missing,
    non-numeric, or non-finite (NaN/inf) value in any row. Column values
    are coerced via pandas' own numeric parser first, so a string like
    "abc" is treated identically to a missing/NaN cell -- both are
    reportable data problems, not silently-different failure modes."""

    for col in columns:
        parsed = pd.to_numeric(df[col], errors="coerce")
        bad_mask = ~np.isfinite(parsed.to_numpy(dtype=float))
        if bad_mask.any():
            bad_rows = df.index[bad_mask].tolist()
            raise CsvSchemaError(
                f"{path}: column '{col}' has non-finite/missing/non-numeric values at rows {bad_rows}"
            )


def assert_high_low_geometry(df: pd.DataFrame, high_column: str, low_column: str, path: Path) -> None:
    """Raises CsvSchemaError if any row has high < low -- an impossible
    bar that would otherwise silently corrupt any MFE/MAE or pattern
    calculation built on it."""

    bad = df[df[high_column] < df[low_column]]
    if not bad.empty:
        raise CsvSchemaError(
            f"{path}: {len(bad)} row(s) have {high_column} < {low_column} (impossible bar geometry): "
            f"rows {bad.index.tolist()}"
        )
