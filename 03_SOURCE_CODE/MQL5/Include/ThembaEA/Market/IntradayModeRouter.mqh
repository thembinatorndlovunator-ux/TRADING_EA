//+------------------------------------------------------------------+
//| IntradayModeRouter.mqh                                            |
//| Themba Adaptive Intraday Engine — Market                          |
//|                                                                    |
//| TASK-040 — the market_family classifier and a first-pass           |
//| intraday_mode ("scalp" vs "day-trade") classifier, per                 |
//| 00_MASTER_PROMPT_FOR_CLAUDE.md section 5 ("Mode decision... Create      |
//| an IntradayModeRouter") and section 18's symbol-family requirement.       |
//| Registered as TASK-040 because no earlier numbered task owned this          |
//| (Codex review finding, sixth round, P0 finding 3: "Live mode                 |
//| classification... remain[s] unowned").                                         |
//|                                                                    |
//| SCOPE, stated explicitly:                                           |
//| - market_family: classifies METAL / FOREX / SYNTHETIC_INDEX /            |
//|   UNKNOWN using the broker's OWN curated SYMBOL_PATH (Market Watch         |
//|   folder, e.g. "Metals\XAUUSD" or "Synthetic Indices\Continuous            |
//|   Indices\Volatility 75 Index") — NOT the traded symbol's own ticker         |
//|   name. This is the "real classifier" TASK-034's own                          |
//|   InpNewsProviderSource note said was missing; using the broker's own            |
//|   curated path (rather than guessing from e.g. "XAU" appearing in the             |
//|   ticker) is a materially different, more robust signal than the ad hoc              |
//|   symbol-name heuristic that note explicitly warned against, since a                  |
//|   ticker's own spelling varies per broker (XAUUSD/GOLD/XAUUSD.a/etc.)                   |
//|   while the broker's own category path is curated FOR exactly this                       |
//|   purpose. UNKNOWN is returned, never guessed, when the path contains no                   |
//|   recognizable keyword — callers must apply their OWN conservative                          |
//|   fallback for UNKNOWN (this project's own established direction, per                         |
//|   TASK-034_LIVE_SAFETY_WIRING.md, is to fail toward MORE filtering, not                          |
//|   less).                                                                                            |
//| - intraday_mode: a first-pass classifier using the section-5 inputs           |
//|   that are ALREADY computable from this project's existing modules            |
//|   (regime, ATR percentile, trend persistence, current-vs-average range,         |
//|   spread/ATR, session time remaining, news proximity, and — only when a           |
//|   decision exists — the routed winner's own composite score as a coarse            |
//|   proxy for "pattern quality"/"expected reward-to-risk", since neither               |
//|   is independently available before order sizing). Section 5's own                    |
//|   weighting is NOT specified anywhere in this project's documents, so                    |
//|   the scoring below is a stated, documented interpretation choice, not a                  |
//|   spec-verbatim formula — flagged here exactly like                                        |
//|   MarketRegimeEngine.mqh's own "interpretation choice" notes.                                |
//|                                                                    |
//| EXPLICITLY NOT DONE — a genuine, named gap, not silently skipped:      |
//| section 5's "historical performance of the setup in the same symbol/       |
//| regime, only after enough samples" input needs a persistent per-              |
//| symbol/regime performance-tracking store that does not exist yet (that          |
//| is TASK-032's score-correlation/ML backlog territory, not this task's).           |
//| This classifier's output is JOURNAL-ONLY in this task — none of the five            |
//| existing strategies branch on intraday_mode to change entry timeframe,               |
//| target sizing, or holding duration (they are still single-timeframe M15               |
//| evaluations); wiring intraday_mode into actual strategy BEHAVIOR is a                    |
//| separate, larger, explicitly-named future task, mirroring how this EA                     |
//| itself started journal-only (TASK-025) before order submission was wired                    |
//| in later (TASK-027).                                                                           |
//+------------------------------------------------------------------+
#property strict

#include "MarketRegimeEngine.mqh"

enum ENUM_MARKET_FAMILY
  {
   MARKET_FAMILY_METAL,
   MARKET_FAMILY_FOREX,
   MARKET_FAMILY_SYNTHETIC_INDEX,
   MARKET_FAMILY_UNKNOWN
  };

string IMR_MarketFamilyToString(const ENUM_MARKET_FAMILY family)
  {
   switch(family)
     {
      case MARKET_FAMILY_METAL:            return "METAL";
      case MARKET_FAMILY_FOREX:             return "FOREX";
      case MARKET_FAMILY_SYNTHETIC_INDEX:   return "SYNTHETIC_INDEX";
      default:                              return "UNKNOWN";
     }
  }

enum ENUM_INTRADAY_MODE
  {
   INTRADAY_MODE_SCALP,
   INTRADAY_MODE_DAY_TRADE
  };

string IMR_IntradayModeToString(const ENUM_INTRADAY_MODE mode)
  {
   return (mode == INTRADAY_MODE_DAY_TRADE) ? "DAY_TRADE" : "SCALP";
  }

//+------------------------------------------------------------------+
//| Classifies 'symbol' via the broker's own curated SYMBOL_PATH (see    |
//| file header for why this differs from a ticker-name heuristic).       |
//| Returns MARKET_FAMILY_UNKNOWN if the path contains no recognizable      |
//| keyword — never guessed from the ticker itself.                           |
//+------------------------------------------------------------------+
ENUM_MARKET_FAMILY IMR_ClassifyMarketFamily(const string symbol)
  {
   string path = SymbolInfoString(symbol, SYMBOL_PATH);
   string path_lower = path;
   StringToLower(path_lower);

   if(StringFind(path_lower, "synthetic") >= 0 || StringFind(path_lower, "volatility") >= 0 ||
      StringFind(path_lower, "boom") >= 0 || StringFind(path_lower, "crash") >= 0 ||
      StringFind(path_lower, "step index") >= 0 || StringFind(path_lower, "jump") >= 0 ||
      StringFind(path_lower, "range break") >= 0 || StringFind(path_lower, "drift switch") >= 0)
      return MARKET_FAMILY_SYNTHETIC_INDEX;

   if(StringFind(path_lower, "metal") >= 0)
      return MARKET_FAMILY_METAL;

   if(StringFind(path_lower, "forex") >= 0 || StringFind(path_lower, "currenc") >= 0)
      return MARKET_FAMILY_FOREX;

   return MARKET_FAMILY_UNKNOWN;
  }

//+------------------------------------------------------------------+
//| PURE — first-pass intraday_mode scoring classifier. Positive          |
//| 'day_trade_score_out' selects DAY_TRADE, negative or zero selects        |
//| SCALP. Every weight below is this task's own documented interpretation    |
//| choice (see file header) — trace any future disagreement to this          |
//| function, not to a master-prompt formula, since none exists.                |
//|                                                                    |
//| 'has_decision'/'winner_score_0_to_100' are optional (pass                |
//| has_decision=false, winner_score_0_to_100 ignored, when no candidate       |
//| has been routed yet this bar) — the coarse pattern-quality/R:R proxy        |
//| only applies once a decision exists.                                          |
//+------------------------------------------------------------------+
ENUM_INTRADAY_MODE IMR_ClassifyMode(const ENUM_MARKET_REGIME regime, const double atr_percentile,
                                     const double trend_persistence,
                                     const double current_range_ratio,
                                     const double spread_atr_ratio,
                                     const double session_remaining_ratio,
                                     const bool news_proximity_active, const bool has_decision,
                                     const double winner_score_0_to_100,
                                     double &day_trade_score_out)
  {
   double score = 0.0;

   // Trending regimes with high persistence favor a full day-trade hold.
   if(regime == REGIME_TRENDING_UP || regime == REGIME_TRENDING_DOWN)
      score += 0.30;
   if(trend_persistence > 0.6)
      score += 0.20;

   // High ATR percentile (expansion-like conditions) resolves quickly --
   // favors a faster, shorter scalp-style management instead.
   if(atr_percentile > 0.75)
      score -= 0.20;

   // An unusually wide current bar relative to its own average range is
   // the same "already moved a lot, right now" signal -- scalp-favoring.
   if(current_range_ratio > 1.5)
      score -= 0.15;

   // A wide spread relative to ATR erodes a scalp's thin edge faster than
   // a day-trade's wider target -- day-trade-favoring when spread is wide.
   if(spread_atr_ratio > 0.3)
      score += 0.10;

   // Enough of the trading day left to reasonably hold a day-trade
   // position; session_remaining_ratio is in [0,1].
   score += 0.25 * session_remaining_ratio;

   // An imminent news event favors NOT holding a multi-hour day-trade
   // position into an unpredictable catalyst (the news gate itself still
   // blocks entry outright near the event -- this only affects mode
   // classification for the surrounding bars where entry remains allowed).
   if(news_proximity_active)
      score -= 0.15;

   // Coarse pattern-quality/expected-R:R proxy, only once a decision
   // exists (neither is independently available before order sizing).
   if(has_decision && winner_score_0_to_100 >= 70.0)
      score += 0.15;

   day_trade_score_out = score;
   return (score >= 0.0) ? INTRADAY_MODE_DAY_TRADE : INTRADAY_MODE_SCALP;
  }
