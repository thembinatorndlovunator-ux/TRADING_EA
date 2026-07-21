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
| TASK-005 | Phase 3 common core: MarketData (completed-bar logical-index accessor) | `claude/task-005-market-data` | In progress — compiled (real evidence); runtime logic-test confirmation batched with TASK-003/004 for one manual session | 2026-07-21 | `TASK-005_MARKET_DATA.md` |
| TASK-006 | Phase 3 common core: SessionManager (session-time-remaining + boundary clock) | `claude/task-006-session-manager` | In progress — compiled clean (real evidence); runtime logic-test confirmation batched | 2026-07-21 | `TASK-006_SESSION_MANAGER.md` |
| TASK-007 | Phase 3 common core: RiskManager (core risk-math functions) | `claude/task-007-risk-manager` | In progress — compiled clean (real evidence); runtime logic-test confirmation batched | 2026-07-21 | `TASK-007_RISK_MANAGER.md` |
| TASK-008 | Phase 3 common core: DailyWeeklyLimits + EquityPeakManager + DrawdownController | `claude/task-008-daily-weekly-limits` | In progress — compiled clean (real evidence); runtime logic-test confirmation batched | 2026-07-21 | `TASK-008_DAILY_WEEKLY_LIMITS.md` |
| TASK-009 | Phase 3 common core: DecisionJournal (TRADE_DECISION_SCHEMA.json serialization) | `claude/task-009-decision-journal` | In progress — compiled clean (real evidence); runtime logic-test confirmation batched | 2026-07-21 | `TASK-009_DECISION_JOURNAL.md` |
| TASK-010 | Phase 3 common core: IntradayCloseManager (intraday boundary close) — completes Phase 3 | `claude/task-010-intraday-close-manager` | In progress — compiled clean (real evidence); runtime test batched, requires deliberate demo run (real trading actions) | 2026-07-21 | `TASK-010_INTRADAY_CLOSE_MANAGER.md` |
| TASK-011 | Phase 4 detection engines: SwingEngine (canonical confirmed-swing pivot predicate) — begins Phase 4 | `claude/task-011-swing-engine` | In progress — compiled clean (real evidence); array-based core hand-verifiable, live-symbol wrapper batched | 2026-07-21 | `TASK-011_SWING_ENGINE.md` |
| TASK-012 | Phase 4 detection engines: MarketStructure (BOS/CHoCH, range, equilibrium) | `claude/task-012-market-structure` | In progress — compiled clean (real evidence); array-based core hand-verifiable, live-symbol wrapper batched | 2026-07-21 | `TASK-012_MARKET_STRUCTURE.md` |
| TASK-013 | Phase 4 detection engines: SupportResistance (SR zones, equal-high/low liquidity) | `claude/task-013-support-resistance` | In progress — compiled clean (real evidence); array-based core hand-verifiable, live-symbol wrapper batched | 2026-07-21 | `TASK-013_SUPPORT_RESISTANCE.md` |
| TASK-014 | Phase 4 detection engines: CandlestickPatternEngine (full section-5 pattern set) | `claude/task-014-candlestick-pattern-engine` | In progress — compiled clean (real evidence); array-based core hand-verifiable, live-symbol wrapper batched | 2026-07-21 | `TASK-014_CANDLESTICK_PATTERN_ENGINE.md` |
| TASK-015 | Phase 4 detection engines: ICTSMCGeometry (FVG, order blocks, liquidity sweeps, premium/discount) | `claude/task-015-ict-smc-geometry` | In progress — compiled clean (real evidence); array-based core hand-verifiable, live-symbol wrapper batched | 2026-07-21 | `TASK-015_ICT_SMC_GEOMETRY.md` |
| TASK-016 | Phase 4 detection engines: MarketRegimeEngine (nine-state classifier, corrected confidence formula) | `claude/task-016-market-regime-engine` | In progress — compiled clean (real evidence); array-based core hand-verifiable (reproduces spec's own extreme-value checks), live-symbol wrapper batched | 2026-07-21 | `TASK-016_MARKET_REGIME_ENGINE.md` |

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
