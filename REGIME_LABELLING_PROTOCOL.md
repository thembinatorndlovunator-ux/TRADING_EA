# Regime labelling protocol (TASK-037 Specification item 4)

## Purpose

`analysis/regime_validation.py`'s `build_confusion_matrix(predicted, actual)`
needs two INDEPENDENT sequences: what the live classifier predicted, and
what a human analyst, working from the raw chart alone, judges the regime
to actually have been. Comparing the classifier against its own output
(or a synthetic fixture) is not a real validation — this protocol defines
how to produce the genuinely independent `actual` side.

## Who does this, and when

This is a **human, manual task** — it cannot be automated or performed
from this sandbox. The labeller must complete every row for a chart
segment **before** ever opening `predicted_regime.csv`
(`Export_PredictedRegime.mq5`'s own output) for that same segment.
Looking at the prediction first, even briefly, invalidates the
independence this protocol exists to guarantee — start over on a fresh
segment if that happens.

## Step 1 — pick a segment

Choose one `symbol` + `timeframe` + contiguous date range (a few hundred
bars is a reasonable size — enough for a confusion matrix to be
meaningful, small enough to label by hand in one sitting). Record the
exact range; `Export_PredictedRegime.mq5`'s own `InpBarCount`/timeframe
inputs must be set to cover the identical range later.

## Step 2 — label every bar, bar by bar, left to right

Open the chart at that symbol/timeframe/range in MT5 (or any charting
tool showing the same OHLC data), with NO indicators from this project
loaded (no regime overlay, no EA running) — plain candles only, so the
label reflects your own visual judgment, not a leaked classifier hint.

For each completed bar, assign exactly one label from the nine states
below, per `TASK-002_PHASE2_SPECIFICATION.md` section 2's own
definitions (restated here in plain, chart-readable terms — not the
underlying formulas, which a human labeller cannot compute by eye):

| Label | What to look for on the raw chart |
|---|---|
| `TRENDING_UP` | A clear sequence of higher highs and higher lows over the recent swing structure; price is making sustained directional progress upward, not just one large bar. |
| `TRENDING_DOWN` | The mirror of `TRENDING_UP` — lower highs and lower lows, sustained downward progress. |
| `RANGING` | Price is oscillating between a recognizable ceiling and floor with no sustained directional progress either way; swings are choppy/inconsistent in direction. |
| `VOLATILITY_EXPANSION_UP` | A sudden, unusually large-range move upward relative to the recent bars around it (a visible size/range spike), still net upward in direction. |
| `VOLATILITY_EXPANSION_DOWN` | The mirror of `VOLATILITY_EXPANSION_UP` — a sudden unusually large-range move downward. |
| `COMPRESSION` | Bars are visibly smaller/tighter in range than the recent surrounding bars — a visible narrowing, often preceding a breakout. |
| `TRANSITION_OR_UNCERTAIN` | None of the above cleanly applies — direction and range both look ambiguous or mixed, or you are genuinely unsure. **Use this rather than forcing a bar into one of the other 6 labels; a false confident label is worse than an honest "uncertain."** |
| `NEWS_BLACKOUT` | You have independent knowledge (an economic calendar) that a high-impact scheduled news event's blackout window covers this bar. Skip this label entirely if you have no calendar reference open — do not guess from price action alone. |
| `UNTRADEABLE_SPREAD_OR_LIQUIDITY` | You have independent knowledge (tick/volume data, or a broker note) that the spread was abnormally wide or liquidity was abnormally thin at this bar. Skip this label entirely if you have no such independent reference — do not guess from price action alone. |

**Do not look up or reuse this project's own precise thresholds** (ATR
percentile cutoffs, ADX values, efficiency ratios) while labelling — that
would make your label a manual re-derivation of the same formula, not an
independent check on it.

## Step 3 — record the labelled CSV

Write one CSV row per bar, in the SAME chronological order as
`Export_PredictedRegime.mq5`'s own output, with this exact schema:

```
symbol,timestamp,labelled_regime,labeller_id,labelling_date
```

- `timestamp`: the bar's own UTC timestamp, ISO-8601
  (`YYYY-MM-DDTHH:MM:SSZ`) — must match `predicted_regime.csv`'s own
  `timestamp` values exactly for the join in Step 4 to work.
- `labelled_regime`: one of the 9 values above, spelled exactly as
  written in the table (matching `analysis/regime_validation.py`'s own
  `Regime` enum vocabulary — no `REGIME_` prefix).
- `labeller_id`: a stable identifier for who did the labelling (a name or
  initials is enough — this is provenance, not authentication).
- `labelling_date`: the date labelling was actually performed
  (`YYYY-MM-DD`), for traceability.

## Step 4 — join and run the confusion matrix

The two CSVs (this file's `labelled_regime` column and
`Export_PredictedRegime.mq5`'s own `predicted_regime` column) join on
`(symbol, timestamp)` into exactly the two parallel sequences
`regime_validation.build_confusion_matrix(predicted, actual)` already
accepts:

```python
import pandas as pd
from analysis.regime_validation import build_confusion_matrix

predicted_df = pd.read_csv("predicted_regime.csv")
labelled_df = pd.read_csv("labelled_regime.csv")
joined = predicted_df.merge(
    labelled_df, on=["symbol", "timestamp"], how="inner", validate="one_to_one"
)
matrix = build_confusion_matrix(
    joined["predicted_regime"].tolist(), joined["labelled_regime"].tolist()
)
```

Report the row/column counts from the merge (a mismatch means the two
timestamp sequences didn't line up — investigate before trusting the
matrix) alongside the confusion matrix itself.

## Why this cannot be done from this sandbox

Steps 1-3 require a human looking at a real chart and exercising
judgment — there is no synthetic substitute that satisfies "independently
labelled." This document is the protocol and exact schema; performing it
is the user's own step, same as every other real-data run this project's
`TASK-037` depends on.
