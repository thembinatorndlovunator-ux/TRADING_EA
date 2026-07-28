# Claude → Codex handover — TASK-028 round 10 remediation

**Supersedes, for CURRENT status, `TASK-028_round9_handover.md`'s own
final "Requesting review" section** (which accurately reflects round
9's state at the time it was written, including its own implicit "next
review round" request — that request has since been fulfilled: round
10 happened, in full, and this file is its resolution record). That
file is left unedited apart from the P2 finding 20-labelled
corrections already applied to it (script-count undercounting, notebook
count); this one is the current one.

## What happened

Round 9 closed with all 23 findings resolved (two of them formally
registered as `TASK-043`/`TASK-044` rather than implemented, since each
is genuinely large, separate architecture) and its own remediation
implicitly requesting the next review round. That request was
fulfilled: a tenth independent review returned **21 findings — 7 P0,
11 P1, 3 P2 — disposition "Do not merge TASK-028 as complete"**,
written to `09_HANDOVERS/codex_to_claude/TASK-028_review.md`. The user's
own standing instruction after that review landed was explicit: "codex
is done, lets fix and merge."

**Disposition note, stated up front:** the review's own "do not merge
as complete" was written against the THEN-current (unfixed) state.
Every one of the 21 findings below has since received either a real,
committed code fix (P0/P1 findings 1-14, 18) or was confirmed as an
already-honest, correctly-scoped registration/documentation state, not
a new code defect (P1 findings 15-17), or a canonical-documentation
correction (P2 findings 19-21). This handover's own job is to give an
independent reviewer everything needed to judge whether that remaining
gap is closed for real.

## Per-finding disposition

| # | Sev | Finding | Disposition | Commit(s) |
|---|-----|---------|-------------|-----------|
| 1 | P0 | Account lock bootstrap race, non-atomic timestamp, non-transactional risk state | Fixed: readback-verified non-destructive bootstrap, timestamp folded into token, WAL-lite durable batch primitive | `9335a39` |
| 2 | P0 | Hard-risk reservations ownerless, exposure check not atomic | Fixed: unique per-attempt reservation key, owner-checked release, caller-held-lock variant, retired blind time-based sum exclusion | `8efe8f0` |
| 3 | P0 | Actual-fill 1% cap enforcement silent bypasses | Fixed: fail-closed on HistoryDealSelect failure, correct POSITION_IDENTIFIER resolution, directional loss formula, OrderCalcProfit cross-check everywhere | `f8d7965` |
| 4 | P0 | Durable-intent bootstrap repeats finding 1's destructive race | Fixed: same readback-verify technique applied to IntentManager.mqh | `a534c63` |
| 5 | P0 | Mixed valid/malformed FairEconomy response can hide a high-impact event | Fixed: missing-date/unparseable-date branches now set the malformed-payload flag before `continue` | `8779993` |
| 6 | P0 | Mandatory boundary/no-stop protection tick-dependent/non-durable | Fixed: OnInit refuses order-enabled init without a working timer; OnTimer now drives every wall-clock protection; NSG write retried until persisted | `e70f42d` |
| 7 | P0 | Daily/weekly state failure disables breach detection instead of a fail-closed obligation | Fixed: ground-truth re-evaluation (`ReEvaluateMandatoryClosureObligations`) run from OnInit/OnTick/OnTimer; unreadable state now itself arms closure | `e70f42d` |
| 8 | P1 | Async/partial-fill lifecycle loses position-mode and close-finalization state | Fixed: entry-mode carried through AsyncFillCorrelator for the async path; durable CloseFinalizationTracker.mqh + reconciliation pass | `282d1c9` |
| 9 | P1 | Chart-pattern lifecycle marks TRADED before confirmation/execution | Fixed: new CANDIDATE interim state, CAS-guarded finalize, InpPatternMaxAgeBars wired, CPL_CleanupStale wired | `d089e52` |
| 10 | P1 | Execution-event journaling can't guarantee the fill record | Fixed: FILE_SHARE_WRITE, durable retry queue, volume/price on async resolution, restart-reconciliation backfill event | `0ee5e1e` |
| 11 | P1 | Multi-file Python report publication not atomic on an ordinary exception | Fixed: `atomic_rename_group` rollback primitive shared by all three publish call sites | `61f859f` |
| 12 | P1 | Blank server timestamps silently erase days from daily equity analysis | Fixed: explicit NaT rejection after `pd.to_datetime` | `ecf88bc` |
| 13 | P1 | Equity run/account identities numerically inferred before string conversion | Fixed: `dtype=str` on ingestion for identity columns | `fc57019` |
| 14 | P1 | EquityTickRecorder appends new schema to incompatible existing files | Fixed: existing non-empty file's header validated before any row is appended; write results checked | `92f2231` |
| 15 | P1 | Mode-first routing remains explicitly unimplemented | Confirmed, not a new defect: `TASK-043` still "Not started," still explicitly says the EA must not be presented as launch-ready | (verification only) |
| 16 | P1 | Bar-zero unification and real cross-language pattern validation remain open | Confirmed, not a new defect: `TASK-044` still "Not started"; notebook 09 comparison still honestly labelled synthetic | (verification only) |
| 17 | P1 | Required MQL behavioral evidence does not exist | Acknowledged plainly, unchanged: this remains a real, batched gap — see "What is still NOT done" below | (documentation only) |
| 18 | P1 | Notebook 09 not re-executed in place after its comparison code changed | Fixed: re-executed via `jupyter execute --inplace`; all 4 code cells now have real, sequential, non-null execution_count/output | `a8cc3fe` |
| 19 | P2 | Canonical closure/history text contradicts open tasks and round count | Fixed: this handover states one durable status; TASKS.md/TASK-028 doc updated below | (this commit set) |
| 20 | P2 | Compile/notebook evidence metadata Git-verifiable inaccuracies | Fixed: script-count (2→5), notebook-count (7→8), TASK-044 date, README/handover correction notes added | (README.md, this handover, TASK-044 doc) |
| 21 | P2 | Runtime/build provenance and TASK-028 current-state narrative staleness | Fixed: THEMBA_EA_GIT_COMMIT comment now states "logical-parent tag" explicitly; stale news_state/candlestick/chart-pattern/exporter claims corrected inline | `e3da3f4` |

Findings 6 and 7 share one commit (`e70f42d`) because both were closed
by the SAME architectural fix (ground-truth re-evaluation replacing a
fragile persisted-flag/tick-dependent design) — see that commit's own
message for the full reasoning, matching this project's own precedent
for genuinely coupled findings.

## Verification evidence

- **MQL5:** every commit above that touched `.mq5`/`.mqh` files was
  compiled via MetaEditor64.exe before committing; a **full, current,
  individually-hashed compile of all 46 real `.mq5` targets** (same
  count as round 9 — no new `.mq5` target was added this round) is
  retained at
  `09_HANDOVERS/compile_evidence/TASK-028_round10_full_compile_evidence_2026-07-28.txt`.
  All 46 compile clean (0 errors, 0 warnings). `THEMBA_EA_GIT_COMMIT`
  updated to `e3da3f4` (this round's own final content commit,
  immediately before this evidence pass), now explicitly documented in
  the macro's own header comment as a logical-parent tag, not a
  byte-exact "compiled from" identifier (finding 21).
- **Python:** the full `pytest` suite passes at every commit above; by
  the final content fix it stands at **758 passed, 0 failed** (up from
  round 9's 749 — 9 new regression tests added across findings 11-13).
  `ruff check`, `ruff format --check`, and `mypy .` were all re-run as
  a genuine whole-project final gate; all three report clean.
- **Notebooks:** notebook 09 re-executed via `jupyter execute --inplace`
  (finding 18) — see that commit for the exact before/after
  execution_count state. No other notebook's own code changed this
  round, so no other notebook was re-executed.
- **Regression tests reproducing the reviewer's own reported
  counterexample:** findings 1, 2, 4, 5, 8, 9, 11, 12, 13 each have a
  dedicated MQL5 Test_*.mq5 or Python pytest regression reproducing the
  exact scenario the review described (bootstrap race readback-verify,
  same-symbol concurrent reservations, mixed-payload malformed-date
  events, CANDIDATE-not-TRADED on no-confirm, rename-stage OSError
  rollback, blank-timestamp zero-day report, leading-zero identity
  collapse). Findings 3, 6, 7, 10, 14 are verified by MetaEditor
  compile plus hand-derived logic tracing (fail-closed branches,
  timer-driven reconciliation, durable-queue drain) — these are
  EA-internal orchestration paths with no standalone Test_*.mq5 harness,
  matching this project's own established precedent (the main EA has
  never had one).

## What is still genuinely NOT done (explicit, not glossed over)

- **Real MT5 terminal runtime verification remains categorically
  blocked by this sandbox** — confirmed across multiple independent
  attempts earlier in this project and not re-attempted this round.
  Every MQL5 fix across all 10 review rounds is verified by MetaEditor
  compile + hand-derived/script-based logic checks only, never an
  actual executed Strategy Tester run or live/demo terminal attachment.
  This is finding 17's own standing complaint, unresolved by
  construction — no runtime output is claimed or fabricated anywhere in
  this remediation.
- **TASK-043 (mode-first routing reorder)** and **TASK-044 (bar-0
  convention unification)** remain "Not started" — real, substantial
  architecture work, correctly not attempted as part of this
  review-remediation pass (both are explicitly named as the reason the
  EA must not be presented as launch-ready while they remain open).
- **A real (not self-consistent-synthetic) cross-language pattern
  comparison** against `Export_PatternDetectorResults.mq5`'s own
  live/demo output remains part of the same batched runtime-
  verification gap above.

## Requesting review

This remediation is presented as complete for round 10's own 21
findings, with the same disclosed, unresolved gap (no real MT5 runtime
verification) that has applied to every prior round. The user has
directed that after this round's fixes are complete, the branch is to
be merged. Requesting an eleventh independent review is the user's own
call, not assumed here.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KMx6XPK1Gcg3VjjTpYvjyf
