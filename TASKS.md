# Task Ledger — Themba Adaptive Intraday Engine

Running index of every task. One row per task; details live in each task's
own `TASK-###_*.md` file. Never edit `main` directly — every task gets its
own `claude/task-###-description` branch, merged only after independent
review per `PROJECT_RULES.md` and the release gates in
`00_MASTER_PROMPT_FOR_CLAUDE.md` section 21.

| ID | Title | Branch | Status | Date | Task file |
|---|---|---|---|---|---|
| TASK-001 | Baseline audit: SmartCoreEngine V6.37 & NdlovuSMC V8.11 | `claude/task-001-baseline-audit` | Findings open — 5th Codex review pass returned changes requested, resolving now | 2026-07-20 | `TASK-001_BASELINE_AUDIT.md` |

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
