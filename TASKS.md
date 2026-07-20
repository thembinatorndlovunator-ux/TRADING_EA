# Task Ledger — Themba Adaptive Intraday Engine

Running index of every task. One row per task; details live in each task's
own `TASK-###_*.md` file. Never edit `main` directly — every task gets its
own `claude/task-###-description` branch, merged only after independent
review per `PROJECT_RULES.md` and the release gates in
`00_MASTER_PROMPT_FOR_CLAUDE.md` section 21.

| ID | Title | Branch | Status | Date | Task file |
|---|---|---|---|---|---|
| TASK-001 | Baseline audit: SmartCoreEngine V6.37 & NdlovuSMC V8.11 | `claude/task-001-baseline-audit` | Findings open — see task file's Acceptance criteria for current pass count/status | 2026-07-20 | `TASK-001_BASELINE_AUDIT.md` |
| TASK-002 | Phase 2 specification: modes, regimes, strategies, patterns, risk, news | `claude/task-002-phase2-specification` | Self-certified after round-3 review (no round-4 review available); not independently approved | 2026-07-20 | `TASK-002_PHASE2_SPECIFICATION.md` |
| TASK-003 | Phase 3 common core: StateManager (account-wide scalar persistence) | `claude/task-003-state-manager` | In progress — compiled (real evidence); runtime logic-test confirmation pending manual desktop run | 2026-07-20 | `TASK-003_STATE_MANAGER.md` |
| TASK-004 | Phase 3 common core: SymbolProfile + BrokerValidator | `claude/task-004-symbol-profile` | In progress — compiled (real evidence); runtime logic-test confirmation pending manual desktop run | 2026-07-21 | `TASK-004_SYMBOL_PROFILE.md` |

## Status legend

- **Not started** — task file drafted, no branch yet.
- **In progress** — branch active, deliverables being written.
- **Awaiting Codex review** — deliverables complete, handover packet sent,
  waiting on independent review before merge.
- **Findings open** — Codex review returned issues not yet resolved.
- **Ready to merge** — review passed, gates satisfied.
- **Merged** — landed on `main`.
- **Rejected** — task abandoned or superseded; reason recorded in the task
  file's Final Decision section.
