# Baseline Screenshot Visual Notes

Per `VISUAL_EVIDENCE_PROTOCOL.md`. **Important limitation, stated up front:**
none of these 13 screenshots are linked to a trade journal row, trade-history
export, EA version tag, or account identifier — there is no CSV/journal file
in this repo yet to cross-check against (see `profit_giveback_diagnosis_plan.md`).
Per the protocol, "never change code because of one screenshot" and
interpretation without linked evidence stays a **HYPOTHESIS**, not a
confirmed finding. Which of the two baseline EAs (or which version) produced
the markers in any given screenshot **cannot be confirmed** from the image
alone — no dashboard panel, EA name, account balance, or version string is
visible in any of the 13 images. That identification gap is itself a
finding (see "Missing evidence" below).

## Per-screenshot log

| # | Filename | Symbol / TF | Date range shown | Objectively visible |
|---|---|---|---|---|
| 1 | 190038.png | XAUUSD M15 | 15–17 Jul 2026 | Blue up-triangle / red down-diamond markers on ~35 swing points, many joined by short dashed connector lines. Two explicit order-price labels: **"BUY 0.01 at 4013.37"** and **"BUY 0.01 at 4010.72"**, with a solid horizontal line at 4013.37 (matches last price) and a dashed line at 4010.72. This is the only one of the 13 screenshots with a visible order/price-line label. |
| 2 | 190112.png | XAUUSD M15 | ~1–9 Jul 2026 | Sparse markers (~8 total), 3 short dashed connector segments, no order labels. |
| 3 | 190126.png | XAUUSD M15 | 7–9 Jul 2026 | One long near-vertical dashed line (red) linking a marker pair across a large single-candle drop (~08 Jul, ~07:45), plus a small cluster of 6 markers near a subsequent low (09 Jul). |
| 4 | 190140.png | XAUUSD M15 | 8–10 Jul 2026 | Denser marker cluster (~20 markers, several dashed connectors) inside a choppy consolidation band; no order labels. |
| 5 | 190333.png | XAGUSD M15 | 16–17 Jul 2026 | Sparse markers (~8), one dashed connector across a large green candle (~17 Jul, 05:45); green/white candle body colouring (different terminal colour scheme from the XAUUSD shots). |
| 6 | 190406.png | XAGUSD M15 | 14–15 Jul 2026 | One long near-vertical dashed red line linking a marker pair across the largest single candle in the image (14 Jul, ~13:00 — a sharp drop then reversal), plus a small cluster near 15 Jul 04:00–06:00. |
| 7 | 190510.png | Volatility 75 Index M15 | 17–19 Jul 2026 | Dense, near-continuous marker chain (~40+ markers with dashed connectors) tracking a large sustained decline (17 Jul evening through 19 Jul), sparser again on the partial recovery. Chart subtitle: "Constant Volatility of 75% with a tick every 2 seconds" (Deriv synthetic index). |
| 8 | 190527.png | Volatility 75 Index M15 | 12–14 Jul 2026 | Dense marker cluster (~15) around a single choppy zone (16–17 Jul boundary in-image), one straight dashed **trendline object** spanning from a 14 Jul low up to a 15 Jul high (this is a drawn line-segment object distinct from the short marker-to-marker connectors elsewhere). |
| 9 | 190540.png | Volatility 75 Index M15 | 14–16 Jul 2026 | Very dense marker cluster (~25) concentrated in the first third of the image (14 Jul 12:00–20:00), sparser afterward. |
| 10 | 190559.png | Volatility 75 Index M15 | 12–14 Jul 2026 | Scattered markers throughout (~25), two small dense clusters (12 Jul 06:00–10:00 and 13 Jul 06:00–10:00), no drawn trendline segment. |
| 11 | 191059.png | Volatility 100 Index M15 | 16–17 Jul 2026 | Sparse markers (~10), one small cluster (17 Jul 03:00–05:00) with one vertical dashed connector spanning a large single candle. Subtitle: "Constant Volatility of 100% with a tick every 2 seconds". |
| 12 | 191118.png | Volatility 100 Index M15 | 17–18 Jul 2026 | Small cluster (~10 markers) at 18 Jul 02:00–04:30 coinciding with a sharp decline into a low, then a separate isolated marker pair near 18 Jul 20:00. |
| 13 | 191146.png | Volatility 100 Index M15 | 18–19 Jul 2026 | Densest marker set of the three Volatility-100 screenshots (~30), spread across two separate clusters (18 Jul 20:00–00:00 and 19 Jul 02:00–06:00), each with several dashed connectors. |

## Objective observations common to all 13

- All markers are one of two glyphs: a small blue up-triangle or a small red
  down-diamond, sometimes joined pairwise by a thin dashed line (colour
  matches the direction of the more recent marker in the pair — blue dash or
  red dash). This is consistent with a **swing-point / structure-shift
  marker** style (e.g. fractal highs/lows, or BOS/CHoCH markers) rather than
  a full pattern-name label, order-fill marker, or dashboard readout.
- **No dashboard panel, EA name, account balance/equity readout, spread
  value, session label, or explicit chart-pattern boundary (no rectangles,
  triangle boundaries, or named necklines) appears in any of the 13
  screenshots.** Both baseline EAs' source implements much richer visual
  furniture than this (V637: clean-theme dashboard functions ~4009–4579;
  V811: `DrawDashboard` 1997–2114, `DrawWorkingChart` 1819–1891) — none of
  it is visible here. Either that visual layer was toggled off when these
  captures were taken, or these are zoomed/cropped views that cut it off.
  Cannot be confirmed either way from the image alone.
- Screenshot 1 is the only one showing an explicit trade/order artifact (the
  two "BUY 0.01 at ..." price labels). All other 12 show structure markers
  only — no visible evidence of an actual order having been placed.
- Symbol coverage across the 13: XAUUSD (4), XAGUSD (2), Volatility 75 Index
  (4), Volatility 100 Index (3) — confirms both a real metal and Deriv
  synthetic-index symbols were captured, consistent with the project's dual
  metals + synthetics scope. No Boom/Crash symbols appear in this batch.
- Two distinct candle colour schemes are used across the set (black/white
  hollow-body for the XAUUSD/XAGUSD shots vs. green/white filled-body for
  the Volatility-index shots) — this is a terminal chart-template
  difference, not something either EA's code controls, and has no bearing
  on the audit.

## Certain findings

- 13 screenshots exist, all M15 timeframe, spanning four symbols across
  roughly 5–19 Jul 2026 (dates as shown in-chart; not cross-checked against
  any server-time record since none exists yet).
- Exactly one screenshot (190038.png) shows an explicit order/trade artifact;
  the remaining 12 show only structure/swing markers with no confirmed
  trade linkage.
- No chart-pattern name labels, candlestick-pattern name labels, or news/
  session state overlays are visible in any of the 13 images.

## Hypotheses (require a linked trade journal/CSV to confirm)

1. The blue/red marker pairs are swing-high/swing-low or BOS/CHoCH structure
   markers from one of the two baseline EAs' visual layer — **not
   confirmed** which EA, since no distinguishing label is visible.
2. The "BUY 0.01 at 4013.37 / 4010.72" labels in screenshot 1 correspond to
   a real basket or pilot-trade entry — **not confirmed** against
   `01_BASELINE` journal output (no CSV present) or which EA placed it.
3. The dense marker clusters in the Volatility-index screenshots coincide
   with visibly choppy/ranging price action, which — if these are genuine
   structure-shift markers — would suggest frequent false BOS/CHoCH signals
   in ranging conditions on synthetic symbols. This matches a risk already
   flagged in both code audits (signal frequency / contradictory-gate risk)
   but is not proven by the screenshots alone.
4. The single drawn trendline segment in screenshot 8 is consistent with
   V637's trendline-detection code (`BuildThreePointTrendLine`,
   `BuildTrendlineBreakRetestSignal`) given that feature exists only in
   that baseline per the code audit — but V811 also draws structure lines,
   so this remains a hypothesis, not a confirmed attribution.

## Missing evidence

- No trade-history CSV, journal file, or account statement exists anywhere
  in this repo to link any screenshot to a specific trade, EA version, or
  outcome.
- No EA identification (name, version, magic number) is visible in any
  screenshot, so marker-style attribution to V637 vs. V811 is unresolved.
- No server-time or broker-time reference is visible, only the chart's
  local axis dates — timezone cannot be verified.

## Proposed test

Once a trade-history export or journal CSV exists (per
`profit_giveback_diagnosis_plan.md`), match each screenshot's visible price
level, timestamp, and symbol against journal rows to confirm: which EA
produced it, what the marker glyphs actually represent in that EA's source
(cross-reference against the audited function names in
`baseline_v637_audit.md` / `baseline_v811_audit.md`), and whether the
screenshot 1 order labels correspond to a real executed trade.
