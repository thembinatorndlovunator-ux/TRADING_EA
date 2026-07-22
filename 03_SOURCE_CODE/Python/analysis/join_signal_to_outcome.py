"""join_signal_to_outcome.py -- joins cleaned journal decisions
(``join_trade_journal.py``'s output) to their eventual trade outcomes
(``analyse_baseline.py``'s trades.csv schema, extended with ``order_id``/
``deal_id`` columns) by the durable ``order_id`` key, producing the
unified per-position CSV ``performance_breakdown.py`` documents as its
required input.

**Provenance (Codex review finding, 2026-07-22, third round): this join
was previously unimplemented and unowned** -- ``join_trade_journal.py``
only cleans journal records, ``performance_breakdown.py`` requires an
already-unified CSV but never builds one, and TASK-036/037 each excluded
the consuming join from their own scope while their test plans implied
one existed. This script is that missing, explicit owner.

**Identity semantics, stated explicitly (Codex review finding, 2026-07-22,
fifth round -- previously left undefined, which the review demonstrated
produces incoherent results):**

- ``order_id`` here means MT5's **position identifier**
  (``SOrderOpenResult.position_id`` in ``OrderManager.mqh``, MT5's own
  ``POSITION_IDENTIFIER``), the identifier MT5 documents as staying
  STABLE across every fill AND across the position's entire lifetime --
  **corrected, 2026-07-22 Codex review finding (sixth round, P0 finding
  1): this previously said ``position_ticket``/``POSITION_TICKET``,
  which MT5 documents as changeable after a server-side service re-open
  or, in netting mode, after a reversal. ``POSITION_IDENTIFIER`` is the
  field MT5 documents as constant for the position's whole life, and is
  what every related deal itself carries back as ``DEAL_POSITION_ID`` --
  the genuinely durable key this join's own "stays constant across
  partial fills" requirement actually needs.** NOT a literal MT5 "order
  ticket" (a pending/market order request that is consumed once filled
  and is not a durable position-lifetime key) and NOT ``position_ticket``
  either (session-scoped, not durable); `TASK-036_JOURNAL_PRODUCER_COMPLETION.md`
  must populate it from ``position_id``/``POSITION_IDENTIFIER``, not
  ``position_ticket`` or ``order_ticket``.
- ``deal_id`` means MT5's **deal ticket** (``deal_ticket``), a distinct
  identifier PER FILL. A journal decision (recorded before any fill
  exists) legitimately has no real ``deal_id`` yet -- ``deal_id`` is
  therefore treated as FILL-scoped data, never compared as a
  journal/trade invariant (see ``deal_id``'s exclusion from
  ``shared_cols`` below; this closes a real bug where a null journal
  ``deal_id`` against a real trade ``deal_id`` was reported as a
  conflict, and a second partial fill's ``deal_id`` was rejected as
  disagreeing with the first).
- ``trade_id`` is this project's own CSV-row identity (one row per FILL
  in ``trades.csv``, matching ``analyse_baseline.py``'s schema) --
  independent of, and just as fill-scoped as, ``deal_id``. A normalized
  export MUST assign a distinct ``trade_id`` per fill row for a
  multi-fill position (this script's ``trade_id`` uniqueness check
  enforces that); ``deal_id`` is the separate, MT5-native fill identity
  used for cross-referencing back to the real deal history.

**Corrected, 2026-07-22 Codex review finding (fourth round): the round-3
implementation contradicted its own stated rules in several ways, all
fixed then:** a null/blank journal ``order_id`` is filtered as a normal
unsubmitted decision rather than aborting the whole journal;
``deal_id``/``trade_id`` are read as ``str`` (never pandas' inferred
numeric type) and checked for null/duplicate values; ``profit`` is
checked for finiteness; partial fills are aggregated into one output row
per position.

**Corrected, 2026-07-22 Codex review finding (fifth round): several of
those round-4 fixes were themselves incomplete or newly broken, all
fixed here:**

1. **``deal_id`` excluded from the shared-field conflict check** (see
   identity semantics above) -- previously caused two reproduced
   failures: a null journal ``deal_id`` against a real trade ``deal_id``
   was flagged as a conflict (rejecting the whole match), and a second
   partial fill's different ``deal_id`` was rejected as "disagreeing"
   with the first fill's, rather than being aggregated.
2. **A cross-schema invariant check for ``direction``/``is_long``
   added** -- these are the SAME underlying fact under different names
   (journal ``direction`` is ``BUY``/``SELL``; trade ``is_long`` is
   boolean) and were previously never compared at all; a probe with
   journal ``direction=BUY`` and trade ``is_long=False`` joined
   successfully before this fix.
3. **A whole POSITION is now rejected as a unit if ANY constituent fill
   fails integrity** -- the round-4 version checked each fill
   independently and silently kept the other, non-conflicting fills of
   the same position, which is invalid evidence (a partial, silently
   incomplete position reported as if it were the whole thing).
4. **The validated, coerced ``profit`` series is now actually assigned
   back** to the working frame before any arithmetic -- round 4 computed
   a validated ``profit_numeric`` series but discarded it, so the
   ORIGINAL (possibly string-typed) ``profit`` column was what actually
   got summed: two string profits ``"30"``/``"20"`` produced the
   concatenated ``3020.0``, not ``50.0``.
5. **Per-fill fields with no defined position-level aggregation are now
   explicitly dropped (set to ``None``) for multi-fill positions, not
   silently taken from the first fill** -- ``entry_price``/
   ``exit_price``/``stop_price``/``r_multiple`` have no volume/lot
   column to weight them across fills, so round 4's ``group.iloc[0]``
   silently reported the FIRST fill's R-multiple as the entire
   position's R outcome (fills of profit 30/20 and R 1/4 produced
   position profit 50 but R 1). A single-fill position (the common
   case until real partial fills exist) still reports these fields
   normally, since there is no aggregation ambiguity for it.

**Corrected, 2026-07-22 Codex review finding (sixth round): three more
concrete counterexamples survived round 5's fixes above, all closed
here:**

1. **``deal_id`` was excluded from EVERY conflict check, not only the
   equality-with-every-fill check that's genuinely wrong for fill-scoped
   data.** A probe with journal ``deal_id="WRONG"`` against a trade group
   whose only real fill had ``deal_id="d1"`` previously joined
   successfully. A journal ``deal_id`` (when a caller has supplied one --
   e.g. an async follow-up record) must now be a MEMBERSHIP match against
   the position's own fill ``deal_id`` values, not excluded outright.
2. **Unrecognized ``direction``/``is_long`` values were silently
   accepted or silently coerced** -- an unrecognized ``direction``
   (anything but BUY/SELL) previously skipped the cross-check entirely,
   and an unparseable ``is_long`` string (e.g. ``"banana"``) was silently
   coerced to ``False``; a probe with ``direction=SELL,
   is_long="banana"`` joined successfully because ``"banana" -> False``
   happened to agree with SELL. Both cases are now treated as a genuine
   conflict.
3. **Two individually finite fill profits could still overflow to a
   non-finite SUM with no row error** -- the per-fill finiteness check
   validates each input value, not the aggregated output; two fills of
   ``1e308`` each previously produced ``profit=inf`` silently. The
   aggregated sum is now itself checked for finiteness before being
   accepted.

**Cardinality/duplicate rules, stated explicitly:**

- A submitted (non-null ``order_id``) journal decision's ``order_id``
  must be UNIQUE among journal decisions -- a decision legitimately
  submits at most one order/position, so a duplicate SUBMITTED journal
  ``order_id`` is a schema error, not a valid multi-decision position.
- A journal decision with a null/blank ``order_id`` is normal (rejected
  before submission, or not yet filled) -- filtered out, never an error.
- A ``order_id`` may appear MULTIPLE TIMES among trade outcomes -- this
  is the normal partial-fill case (one position, several deals/fills).
  All such fills are aggregated into ONE output row, or the whole
  position is rejected as a unit if any fill fails integrity (see point
  3 above).
- A trade outcome whose ``order_id`` matches no SUBMITTED journal
  decision is an orphaned outcome (a fill with no recorded decision) --
  a row-level error, never silently dropped or silently joined to
  nothing.
- A journal decision with NO matching trade outcome is normal and
  expected -- it simply does not appear in the joined output; this is
  not an error.

Required input formats:

``journal.csv`` -- ``join_trade_journal.py``'s own output shape (every
``TradeDecision`` field, including ``order_id``/``deal_id`` -- see
``analysis/schema.py``).

``trades.csv`` -- ``analyse_baseline.py``'s normalized schema
(``trade_id, symbol, is_long, entry_time, exit_time, entry_price,
exit_price, stop_price, profit``) PLUS ``order_id``/``deal_id`` columns
linking each fill back to the journal decision that produced it. **Only
``trade_id``/``order_id``/``deal_id``/``profit`` are structurally
REQUIRED** (corrected, 2026-07-22 Codex review finding, fifth round:
this previously implied the full schema was enforced, which it is
not) -- every other column (symbol, direction/is_long, entry_time,
exit_time, entry_price, exit_price, stop_price) is used if present, same
"genuinely optional" convention ``performance_breakdown.py`` already
documents. No MQL5 export or journal producer populates ``order_id``/
``deal_id`` in either file yet (see
``TASK-036_JOURNAL_PRODUCER_COMPLETION.md``) -- this script is ready to
run the moment one does.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Optional

import pandas as pd

from analysis.csv_io import (
    CsvSchemaError,
    assert_output_paths_distinct,
    assert_path_not_same_file,
    atomic_write_dataframe_csv,
    read_csv_with_required_columns_and_hash,
    sanitize_dataframe_for_csv,
)
from analysis.metrics import InsufficientSampleError
from analysis.report_metadata import (
    atomic_write_text,
    build_report_metadata,
    combine_labeled_hashes,
)

REQUIRED_JOURNAL_COLUMNS = {"order_id"}
REQUIRED_TRADE_COLUMNS = {"trade_id", "order_id", "deal_id", "profit"}
# Durable identifiers must never be inferred as numeric -- see module
# docstring's identity-semantics section.
IDENTITY_DTYPE = {"order_id": str, "deal_id": str, "trade_id": str}
# Per-fill fields with no defined position-level aggregation (no volume/
# lot column exists to weight them across partial fills) -- dropped
# (set to None) for a multi-fill position, kept as-is for a single-fill
# position (Codex review finding, 2026-07-22, fifth round). 'trade_id'/
# 'deal_id' are included here too: for n_fills==1 they unambiguously
# identify the one fill and are kept for convenience/backward
# compatibility; for a real multi-fill position they are superseded by
# 'fill_trade_ids'/'fill_deal_ids' (comma-joined, every fill) and are set
# to None rather than silently reporting only the first fill's identity.
_AMBIGUOUS_MULTI_FILL_FIELDS = (
    "entry_price",
    "exit_price",
    "stop_price",
    "r_multiple",
    "trade_id",
    "deal_id",
)


def _is_blank(value: object) -> bool:
    return (
        value is None
        or (isinstance(value, float) and math.isnan(value))
        or str(value).strip() == ""
    )


def _values_equal(a: object, b: object) -> bool:
    if _is_blank(a) and _is_blank(b):
        return True
    return a == b


_TRUE_IS_LONG_STRINGS = frozenset({"true", "1", "yes", "long"})
_FALSE_IS_LONG_STRINGS = frozenset({"false", "0", "no", "short"})


def _direction_matches_is_long(direction: object, is_long: object) -> bool:
    """Cross-schema invariant: journal 'direction' (BUY/SELL) and trade
    'is_long' (bool) describe the SAME underlying fact under different
    names -- added, 2026-07-22 Codex review finding (fifth round): a
    probe with direction=BUY and is_long=False previously joined
    successfully since the generic same-name shared-column check never
    compares differently-named fields.

    **Fixed, 2026-07-22 Codex review finding (sixth round): an
    unrecognized 'direction' value (anything other than BUY/SELL)
    previously returned True unconditionally ("not this check's job to
    validate"), and an unrecognized 'is_long' string (anything not in
    the truthy list) was silently coerced to False -- a reproduced probe
    with direction=SELL, is_long="banana" joined successfully because
    "banana" -> False happened to agree with SELL. Both cases are now
    treated as a genuine conflict (return False) rather than silently
    accepted or silently coerced.**"""

    if _is_blank(direction) or _is_blank(is_long):
        return True  # nothing to cross-check if either side is absent
    direction_str = str(direction).strip().upper()
    if direction_str not in ("BUY", "SELL"):
        return False  # unrecognized direction value is a conflict, not a skipped check
    if isinstance(is_long, str):
        is_long_str = is_long.strip().lower()
        if is_long_str in _TRUE_IS_LONG_STRINGS:
            is_long_bool = True
        elif is_long_str in _FALSE_IS_LONG_STRINGS:
            is_long_bool = False
        else:
            return False  # unparseable is_long string is a conflict, not a silent False
    # **Fixed, 2026-07-22 Codex review finding (seventh round, P1 finding
    # 15): the previous `else: is_long_bool = bool(is_long)` branch
    # accepted ANY object via Python's own truthiness rules -- a numeric
    # is_long=2 (not a valid boolean encoding under this project's own
    # true/false convention) was silently accepted as truthy ("long"),
    # exactly like a genuine True. Only an actual bool, or a canonical
    # 1/0 numeric encoding, is now recognized; anything else is a
    # conflict, matching the string branch's own strict "unrecognized is
    # a conflict, never silently coerced" behavior.**
    elif is_long is True or is_long == 1:
        is_long_bool = True
    elif is_long is False or is_long == 0:
        is_long_bool = False
    else:
        return False  # unrecognized is_long value is a conflict, not silently coerced via bool()
    return (direction_str == "BUY") == is_long_bool


def join_signal_to_outcome(
    journal_df: pd.DataFrame, trades_df: pd.DataFrame
) -> tuple[pd.DataFrame, list[dict]]:
    """Returns (joined_df, row_errors), one row of 'joined_df' per
    aggregated POSITION (order_id == MT5 position_id / POSITION_IDENTIFIER,
    not position_ticket -- see module docstring's identity-semantics
    section), not per individual fill.
    'row_errors' entries have shape {"trade_id": ..., "order_id": ...,
    "error": ...} for an orphaned trade outcome, or for EVERY fill of a
    position that fails an integrity check (the whole position is
    rejected as a unit -- see module docstring point 3).

    Raises CsvSchemaError if any SUBMITTED (non-null order_id) journal
    decision has a duplicate order_id, if any trade_id/deal_id is null or
    duplicated, or if 'profit' contains a non-finite value -- see module
    docstring for the full cardinality rules this enforces.
    """

    order_id_blank = journal_df["order_id"].apply(_is_blank)
    submitted = journal_df[~order_id_blank]
    # Unsubmitted (null/blank order_id) decisions are normal -- rejected
    # before submission, or not yet filled -- and are simply excluded
    # from matching, never raised as an error.

    dup_submitted = submitted[submitted.duplicated(subset=["order_id"], keep=False)]
    if not dup_submitted.empty:
        raise CsvSchemaError(
            f"join_signal_to_outcome: duplicate SUBMITTED journal order_id values: "
            f"{sorted(dup_submitted['order_id'].unique())}"
        )

    if trades_df["trade_id"].apply(_is_blank).any():
        raise CsvSchemaError("join_signal_to_outcome: trades has a null/blank trade_id")
    dup_trade_id = trades_df[trades_df.duplicated(subset=["trade_id"], keep=False)]
    if not dup_trade_id.empty:
        raise CsvSchemaError(
            f"join_signal_to_outcome: duplicate trade_id values: "
            f"{sorted(dup_trade_id['trade_id'].unique())}"
        )

    if trades_df["deal_id"].apply(_is_blank).any():
        raise CsvSchemaError("join_signal_to_outcome: trades has a null/blank deal_id")
    dup_deal_id = trades_df[trades_df.duplicated(subset=["deal_id"], keep=False)]
    if not dup_deal_id.empty:
        raise CsvSchemaError(
            f"join_signal_to_outcome: duplicate deal_id values: "
            f"{sorted(dup_deal_id['deal_id'].unique())}"
        )

    # **Fixed, 2026-07-22 Codex review finding (fifth round): the
    # validated, numerically-coerced series was previously computed but
    # never assigned back to 'trades_df' -- the ORIGINAL (possibly
    # string-typed) 'profit' column was what actually got summed later,
    # so two string profits "30"/"20" produced the concatenated 3020.0,
    # not 50.0.**
    trades_df = trades_df.copy()
    trades_df["profit"] = pd.to_numeric(trades_df["profit"], errors="coerce")
    if not trades_df["profit"].apply(lambda v: pd.notna(v) and math.isfinite(v)).all():
        raise CsvSchemaError("join_signal_to_outcome: trades has a non-finite/missing profit value")

    # Shared-field conflict detection: any column present on BOTH sides
    # (other than 'order_id', the join key, and 'deal_id', which is
    # FILL-scoped data a journal decision never legitimately has a real
    # value for -- see module docstring's identity-semantics section)
    # must agree for a matched pair, or the row is a conflict error
    # rather than a silent trade-row-wins overwrite.
    shared_cols = (set(journal_df.columns) & set(trades_df.columns)) - {"order_id", "deal_id"}
    check_direction = "direction" in journal_df.columns and "is_long" in trades_df.columns
    # **Added, 2026-07-22 Codex review finding (sixth round): 'deal_id'
    # was excluded from ALL conflict checks above, not just the
    # equality-with-every-fill check that's genuinely wrong for
    # fill-scoped data -- a probe with journal deal_id="WRONG" against a
    # trade group whose only fill has deal_id="d1" previously joined
    # successfully, since nothing checked that the journal's own
    # deal_id (when a caller HAS supplied one, e.g. an async follow-up
    # record) actually corresponds to a real fill of THIS position. This
    # is a MEMBERSHIP check (journal deal_id must be among the group's
    # own fill deal_ids), not an equality-with-every-fill check --
    # different fills legitimately have different deal_ids.
    check_journal_deal_id = "deal_id" in journal_df.columns

    submitted_by_order = submitted.set_index("order_id")
    journal_order_ids = set(submitted_by_order.index)

    row_errors: list[dict] = []
    position_rows: list[dict] = []

    orphan_mask = trades_df["order_id"].apply(lambda v: _is_blank(v) or v not in journal_order_ids)
    for _, trade_row in trades_df[orphan_mask].iterrows():
        order_id = trade_row["order_id"]
        row_errors.append(
            {
                "trade_id": str(trade_row.get("trade_id", "")),
                "order_id": None if _is_blank(order_id) else str(order_id),
                "error": "order_id matches no SUBMITTED journal decision (orphaned trade outcome)",
            }
        )

    matched = trades_df[~orphan_mask]
    for order_id, group in matched.groupby("order_id", sort=False):
        journal_row = submitted_by_order.loc[order_id]

        journal_deal_id_conflict = (
            check_journal_deal_id
            and not _is_blank(journal_row["deal_id"])
            and str(journal_row["deal_id"]) not in {str(v) for v in group["deal_id"]}
        )

        # **Fixed, 2026-07-22 Codex review finding (fifth round): a
        # position must be rejected AS A WHOLE if any constituent fill
        # fails integrity -- the round-4 version checked each fill
        # independently and silently kept the other, non-conflicting
        # fills of the same position, which is invalid (a silently
        # incomplete position reported as if it were the whole thing).
        # Every fill in the group becomes a row error, not only the
        # literally-conflicting one(s), since none of them may be
        # aggregated once the position as a whole is rejected.**
        conflicts_by_trade_id: dict[str, list[str]] = {}
        for _, trade_row in group.iterrows():
            conflicts = [
                col for col in shared_cols if not _values_equal(journal_row[col], trade_row[col])
            ]
            if check_direction and not _direction_matches_is_long(
                journal_row["direction"], trade_row["is_long"]
            ):
                conflicts.append("direction/is_long")
            if journal_deal_id_conflict:
                conflicts.append("deal_id (journal deal_id not found among this position's fills)")
            if conflicts:
                conflicts_by_trade_id[str(trade_row.get("trade_id", ""))] = conflicts

        if conflicts_by_trade_id:
            for _, trade_row in group.iterrows():
                trade_id_str = str(trade_row.get("trade_id", ""))
                own_conflicts = conflicts_by_trade_id.get(trade_id_str)
                if own_conflicts is not None:
                    detail = f"journal/trade shared field(s) disagree: {sorted(own_conflicts)}"
                else:
                    detail = "a sibling fill in this position failed integrity"
                row_errors.append(
                    {
                        "trade_id": trade_id_str,
                        "order_id": str(order_id),
                        "error": (
                            f"{detail} -- the whole position is rejected as a unit, "
                            "not just the fill(s) that conflicted"
                        ),
                    }
                )
            continue

        # **Added, 2026-07-22 Codex review finding (sixth round): two
        # individually finite fill profits (e.g. two fills of 1e308 each)
        # can still overflow to a non-finite SUM -- the per-row
        # finiteness check above validates each INPUT fill, not the
        # aggregated OUTPUT. A reproduced probe with fills [1e308, 1e308]
        # previously produced profit=inf with no row error at all.**
        aggregated_profit = float(group["profit"].sum())
        if not math.isfinite(aggregated_profit):
            for _, trade_row in group.iterrows():
                row_errors.append(
                    {
                        "trade_id": str(trade_row.get("trade_id", "")),
                        "order_id": str(order_id),
                        "error": (
                            f"aggregated profit overflowed to a non-finite value "
                            f"({aggregated_profit!r}) summing this position's "
                            f"{len(group)} fill(s)"
                        ),
                    }
                )
            continue

        agg: dict = {**journal_row.to_dict()}
        agg["order_id"] = order_id
        agg["profit"] = aggregated_profit
        agg["n_fills"] = len(group)
        agg["fill_trade_ids"] = ",".join(str(v) for v in group["trade_id"])
        agg["fill_deal_ids"] = ",".join(str(v) for v in group["deal_id"])
        if "entry_time" in group.columns:
            agg["entry_time"] = group["entry_time"].min()
        if "exit_time" in group.columns:
            agg["exit_time"] = group["exit_time"].max()
        if "is_long" in group.columns:
            # Direction must already be internally consistent within one
            # real position -- report it if uniform, else leave absent
            # (data-quality signal, not a value to silently pick from).
            unique_is_long = group["is_long"].unique()
            agg["is_long"] = unique_is_long[0] if len(unique_is_long) == 1 else None

        single_fill = len(group) == 1
        first = group.iloc[0]
        for field in _AMBIGUOUS_MULTI_FILL_FIELDS:
            if field not in group.columns:
                continue
            agg[field] = first[field] if single_fill else None

        position_rows.append(agg)

    joined_df = pd.DataFrame(position_rows)
    return joined_df, row_errors


def run(
    journal_csv: Path,
    trades_csv: Path,
    output_csv: Optional[Path] = None,
    errors_json: Optional[Path] = None,
    *,
    symbol: Optional[str] = None,
    seed: Optional[int] = None,
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> tuple[pd.DataFrame, list[dict]]:
    # **Fixed, 2026-07-22 Codex review finding (fifth round): the implicit
    # errors_json sidecar was previously derived AFTER the collision
    # checks below already ran (and after the input had been read and
    # output_csv written) -- a run with the journal input named
    # 'out.errors.json' and output 'out.csv' completed and REPLACED the
    # journal CSV with JSON metadata. This exact defect was already fixed
    # in join_trade_journal.py/join_news_events.py; the same fix applies
    # here -- derive every implicit path FIRST, then validate the
    # complete final path set once, before any I/O.**
    if errors_json is None and output_csv is not None:
        errors_json = output_csv.parent / f"{output_csv.stem}.errors.json"

    # Uses OS-level file-identity (not just Path.resolve()) so a hard
    # link to an input is also caught -- Codex review finding, third round.
    for out_path in (output_csv, errors_json):
        assert_path_not_same_file(out_path, journal_csv, "output path")
        assert_path_not_same_file(out_path, trades_csv, "output path")
    assert_output_paths_distinct([output_csv, errors_json])

    # **Fixed, 2026-07-22 Codex review finding (sixth round): both files
    # were previously read via the plain (non-hashing) helper, and
    # 'build_report_metadata' below then re-read them a SECOND time to
    # compute their hash -- a deterministic probe (mutate the journal
    # between those reads, restore, rehash-matches-original) produced an
    # output containing the ORIGINAL row while its metadata hash exactly
    # matched the REPLACEMENT file -- the exact old-analysis/new-hash race
    # round 5 already closed for join_trade_journal.py/join_news_events.py/
    # analyse_baseline.py but left open here. Reading once and hashing
    # from that same pass, then combining both files' hashes below,
    # closes the race structurally.**
    journal_df, journal_csv_hash = read_csv_with_required_columns_and_hash(
        journal_csv, REQUIRED_JOURNAL_COLUMNS, dtype=IDENTITY_DTYPE
    )
    trades_df, trades_csv_hash = read_csv_with_required_columns_and_hash(
        trades_csv, REQUIRED_TRADE_COLUMNS, dtype=IDENTITY_DTYPE
    )
    if trades_df.empty:
        raise InsufficientSampleError(f"{trades_csv}: zero trade rows")

    joined_df, row_errors = join_signal_to_outcome(journal_df, trades_df)

    # **Reordered, 2026-07-22 Codex review finding (seventh round, P1
    # finding 16): metadata (git commit/dirty state, which capture_git_commit
    # can raise GitMetadataError computing) is now captured BEFORE
    # output_csv is written, not after -- previously, an invalid repo_path
    # raised AFTER the result CSV already existed on disk, leaving an
    # apparently-valid result with no provenance sidecar at all.**
    if errors_json is not None:
        # **Fixed, 2026-07-22 Codex review finding (seventh round, P1
        # finding 16): the label was previously the bare basename -- see
        # analyse_giveback.py's matching fix for the exact
        # role-swap-collision counterexample this closes.**
        combined_hash = combine_labeled_hashes(
            [
                (f"journal_csv:{journal_csv.name}", journal_csv_hash),
                (f"trades_csv:{trades_csv.name}", trades_csv_hash),
            ]
        )
        metadata = build_report_metadata(
            [journal_csv, trades_csv],
            symbol=symbol,
            random_seed=seed,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=repo_path,
            dataset_hash_override=combined_hash,
        )

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_dataframe_csv(sanitize_dataframe_for_csv(joined_df), output_csv)

    if errors_json is not None:
        errors_json.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_journal_decisions": len(journal_df),
                "n_trade_outcomes": len(trades_df),
                "n_joined": len(joined_df),
                "n_row_errors": len(row_errors),
            },
            "row_errors": row_errors,
        }
        atomic_write_text(errors_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return joined_df, row_errors


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal-csv", required=True, type=Path)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--errors-json", type=Path, default=None)
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        joined_df, row_errors = run(
            journal_csv=args.journal_csv,
            trades_csv=args.trades_csv,
            output_csv=args.output_csv,
            errors_json=args.errors_json,
            symbol=args.symbol,
            seed=args.seed,
            spread_note=args.spread_note,
            slippage_note=args.slippage_note,
        )
    except (FileNotFoundError, CsvSchemaError, InsufficientSampleError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"join_signal_to_outcome: {len(joined_df)} joined, {len(row_errors)} row errors.")
    return 1 if row_errors else 0


if __name__ == "__main__":
    sys.exit(main())
