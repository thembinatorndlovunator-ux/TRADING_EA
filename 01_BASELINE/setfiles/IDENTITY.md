# Set file identity — UNRESOLVED

- **File:** `SmartCore_v3_Tuned.set.txt`
- **Status:** does not match either baseline EA's actual `Inp*`-prefixed input variables, and is not a native MT5 `.set` file (it's INI-style with `[Section]` headers such as `[SMC]`, `[ChartPatterns]`, `[SRBounce]`). Native MT5 `.set` files are flat `Key=Value` lines with no bracketed sections.
- **Possible explanations (unverified):** an earlier/different version of one baseline before its current input names were refactored; a config for a third, undocumented EA build; or a manually drafted target config that was never actually loaded into either EA.
- **Resolution:** see `baseline_comparison.md` cross-reference (Phase 1, Task #8) for the attempted match. Treat as orphaned until proven otherwise — do not assume it belongs to either baseline.
