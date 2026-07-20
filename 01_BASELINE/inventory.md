# Baseline Evidence Inventory

Consolidated evidence inventory for TASK-001. Re-verifies every hash recorded
in the per-item `IDENTITY.md` files against a fresh `sha256sum` of the
currently tracked file, so the baselines can be proven unchanged at any
later point by re-running the same commands. Generated on the
`claude/task-001-baseline-audit` branch; the underlying preserved artifacts
themselves are untouched — **scoped diff wording corrected in fourth-pass
review, was previously stated as an unscoped claim that contradicts its own
correctly-scoped commands below**: `git diff baseline-v637 --
01_BASELINE/EA_V637` and `git diff baseline-v811 -- 01_BASELINE/EA_V811` are
both empty. An *unscoped* `git diff <baseline-tag> -- 01_BASELINE` is
**not** empty, because this very file and `screenshots/visual_notes.md`
were added under that path — **commit attribution corrected in fifth-pass
review, was wrongly stated as the same commit that introduced the
baselines**: the baselines were introduced by commit `0d65f95` (tagged
`baseline-v637`/`baseline-v811`); these two audit-documentation files were
added later, by the separate TASK-001 commit `c61903f` — new audit
documentation, not edits to the preserved evidence, and not part of the
baseline-preservation commit itself.

## EA source files

| File | Identity | Size (bytes) | SHA-256 | Matches IDENTITY.md |
|---|---|---|---|---|
| `EA_V637/Thembabot14 Max.mq5` | SmartCoreEngine V6.37 | 359,297 | `c35bcc7e0095d60b0c672faeeba696b4db8587b0afb80e6efbbfdc8accdfbc1d` | YES |
| `EA_V811/NdlovuSMC_V8.11.mq5` | NdlovuSMC V8.11 | 90,210 | `b5740327f6d84fd7c00807001418df0fcc3912a8101bca2dbb55de0e51cd1f1b` | YES |

Both hashes were recomputed on this date and match the values recorded in
`01_BASELINE/EA_V637/IDENTITY.md` and `01_BASELINE/EA_V811/IDENTITY.md`
exactly. No modification since the original preservation commit
(`0d65f95`, tags `baseline-v637` / `baseline-v811`).

Reproduce with:
```
sha256sum "01_BASELINE/EA_V637/Thembabot14 Max.mq5"
sha256sum "01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5"
```

## Set file

| File | Size (bytes) | SHA-256 | Status |
|---|---|---|---|
| `setfiles/SmartCore_v3_Tuned.set.txt` | 1,848 | `ea9452d4475d55f1aadd35a6f8f83b76c6046e2118d02aa5a918e673af4bce96` | **Orphaned — provenance unresolved** |

Per `01_BASELINE/setfiles/IDENTITY.md`: this file is INI-style with bracketed
sections (`[SMC]`, `[ChartPatterns]`, `[SRBounce]`), which is not the format
either baseline EA's `Inp*`-prefixed inputs would produce as a native MT5
`.set` export (native `.set` files are flat `Key=Value`, no sections). The
attempted cross-reference against both EAs' actual input names is carried
out in `baseline_comparison.md`, closing the loop this inventory file was
asked to open.

## Screenshots (13 files, `01_BASELINE/screenshots/`)

All timestamps below are filesystem mtimes (local), consistent with the
filename-embedded capture time. No linked trade journal or CSV export exists
yet in this repo to cross-check these against (see `profit_giveback_diagnosis_plan.md`
and `screenshots/visual_notes.md` — visual interpretations are therefore
hypotheses, not confirmed findings, per `VISUAL_EVIDENCE_PROTOCOL.md`).

| # | Filename | Size (bytes) | Timestamp | SHA-256 |
|---|---|---|---|---|
| 1 | Screenshot 2026-07-19 190038.png | 50,599 | 2026-07-19 19:00:39 | `5ce2a99baa919f255c3e68c0826eaa54ef16466fd17fc723b45f7e060847325f` |
| 2 | Screenshot 2026-07-19 190112.png | 19,538 | 2026-07-19 19:01:13 | `254ab20f084ff950b26d4d69112c10103736aba10538b20b884527b751471d83` |
| 3 | Screenshot 2026-07-19 190126.png | 24,730 | 2026-07-19 19:01:27 | `d36390b03052327aca202e9b81f0b358adfb97beffbede27962b5cfa508e6ee5` |
| 4 | Screenshot 2026-07-19 190140.png | 29,033 | 2026-07-19 19:01:41 | `08b8071a1ea1eb76f44ed0bb50d6a5d0cfb23902fff53ed69991d32a6454bc04` |
| 5 | Screenshot 2026-07-19 190333.png | 21,659 | 2026-07-19 19:03:34 | `2f6e50154df65a90f0df1c0a00984b7901e11abc359fb3a90740d3b534f49658` |
| 6 | Screenshot 2026-07-19 190406.png | 25,104 | 2026-07-19 19:04:07 | `e1d2b4ef4f4630f54cbf3ef8c9199c507c3d14fa8aa9431977106601429a7d82` |
| 7 | Screenshot 2026-07-19 190510.png | 35,787 | 2026-07-19 19:05:11 | `38c6c3cb7ea5950c95304344991c581551512e210d44006db4d3ec5bde03707e` |
| 8 | Screenshot 2026-07-19 190527.png | 31,832 | 2026-07-19 19:05:28 | `da078b2556708df6b043a18178f4ad07e5000b56281cf78539687bf22fdb4077` |
| 9 | Screenshot 2026-07-19 190540.png | 37,414 | 2026-07-19 19:05:41 | `8261927a8bd1fee721c616c16424cf8e7601c84f10ea4be2aa3208935a4e34be` |
| 10 | Screenshot 2026-07-19 190559.png | 37,087 | 2026-07-19 19:06:00 | `2a826775cf5d1b22e2fcb96365835f20cbb855070b57e5a3cc83407d57549660` |
| 11 | Screenshot 2026-07-19 191059.png | 26,654 | 2026-07-19 19:11:09 | `91df40e16386cf9ef951b894ba533d1a0e4cd39b7d113b416310ec5b74217bce` |
| 12 | Screenshot 2026-07-19 191118.png | 27,149 | 2026-07-19 19:11:37 | `9c5e20532bba2c3322873ad0c4d71bc8e56582182aa343c3ce0dcc68bbba0861` |
| 13 | Screenshot 2026-07-19 191146.png | 36,408 | 2026-07-19 19:12:01 | `55894ddd8bd4854a203fe37cf7d8f3e9fb8f31572dac2b83f48c9da95a1d00de` |

Content observations and hypotheses for each screenshot are in
`01_BASELINE/screenshots/visual_notes.md`.

## Raw pre-audit duplicates (not tracked in git, kept on disk only)

`01 BASELINEEA V637/`, `01 BASELINEEA V811/`, `EA Files/`, and
`screenshots of past trades/` at the repo root are the original, mis-named
raw folders these baselines were organized from. All four were verified
byte-identical (`sha256sum`) to their `01_BASELINE/` counterparts before this
task began, then excluded from version control via `.gitignore` (kept on
disk as redundant extra proof, never committed — `EA Files/` also contains
copyrighted reference PDFs that must not enter the repository per
`SOURCE_LIBRARY.md`).

## Reproducibility

Git commit that introduced these baselines: `0d65f95`. Tags: `baseline-v637`,
`baseline-v811`. To re-verify at any later date: `git diff baseline-v637 --
01_BASELINE/EA_V637` and `git diff baseline-v811 -- 01_BASELINE/EA_V811` must
both return empty, and the `sha256sum` values above must be unchanged.
