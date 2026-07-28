//+------------------------------------------------------------------+
//| NewsManager.mqh                                                  |
//| Themba Adaptive Intraday Engine — News                            |
//|                                                                    |
//| TASK-029 — begins Phase 7. The provider-agnostic core of the news    |
//| system, per `NEWS_INTEGRATION_SPEC.md` and                            |
//| TASK-002_PHASE2_SPECIFICATION.md section 10: the `SNewsEvent`           |
//| provider-interface shape (fields verbatim from the spec), and the        |
//| pure, hand-testable blackout-window predicate `NEWS_BLACKOUT` (section    |
//| 2) is defined from — "an active blackout window from section 10."          |
//|                                                                    |
//| Deliberately provider-agnostic: this module does not fetch events —   |
//| it only decides, given an already-fetched SNewsEvent[] array (from      |
//| whichever provider a caller selected — MT5CalendarProvider.mqh for       |
//| metals, NullNewsProvider.mqh for synthetics, per the spec's market-        |
//| family routing), whether a blackout is currently active. Matches this      |
//| project's "one implementation per concept, composed by consumers"           |
//| discipline — the same split RiskManager.mqh (pure math) has from             |
//| OrderManager.mqh (the thing that actually acts on it).                        |
//|                                                                    |
//| Array/scalar-based core only, matching every other detection-engine   |
//| module's split — a live wrapper belongs in each concrete provider        |
//| module (MT5CalendarProvider.mqh's own MTC_IsInBlackoutNow), not here.       |
//|                                                                    |
//| **NOT YET WIRED INTO THE LIVE EA** — ThembaAdaptiveIntradayEA.mq5's     |
//| REGIME_NEWS_BLACKOUT/REGIME_UNTRADEABLE_SPREAD_OR_LIQUIDITY overrides       |
//| and hysteresis application are a pre-existing gap from TASK-025 (see        |
//| MarketRegimeEngine.mqh's own header: "NEWS_BLACKOUT is accepted as a         |
//| caller-supplied boolean... a stated, explicit scope boundary"). Wiring        |
//| this module's output into that override, together with the also-             |
//| unwired UNTRADEABLE_SPREAD_OR_LIQUIDITY check and MRE_ApplyHysteresis,          |
//| is left for a dedicated follow-up "regime gating" task rather than             |
//| folded partially into this one — see TASK-029_NEWS_MANAGER.md's Scope           |
//| Boundary section.                                                                |
//+------------------------------------------------------------------+
#property strict

enum ENUM_NEWS_STATUS
  {
   NEWS_STATUS_SCHEDULED,
   NEWS_STATUS_RELEASED,
   NEWS_STATUS_UNKNOWN
  };

string NM_StatusToString(const ENUM_NEWS_STATUS status)
  {
   switch(status)
     {
      case NEWS_STATUS_SCHEDULED: return "scheduled";
      case NEWS_STATUS_RELEASED:  return "released";
      default:                    return "unknown";
     }
  }

//+------------------------------------------------------------------+
//| Provider-interface shape, fields verbatim from                        |
//| NEWS_INTEGRATION_SPEC.md's "Provider interface" section.               |
//| 'importance' is a provider-mapped ordinal (0=none/low ... up to           |
//| whatever scale the provider uses — MT5CalendarProvider.mqh maps            |
//| ENUM_CALENDAR_EVENT_IMPORTANCE directly via (int) cast, documented in       |
//| that file). 'scheduled_botswana_time' assumes UTC+2 (Central Africa          |
//| Time, no DST) — a project-wide assumption stated here since no project        |
//| document specifies an explicit offset.                                          |
//+------------------------------------------------------------------+
struct SNewsEvent
  {
   string           event_id;
   string           event_name;
   string           currency;
   int              importance;
   datetime         scheduled_utc;
   datetime         scheduled_server_time;
   datetime         scheduled_botswana_time;
   double           previous;
   double           forecast;
   double           actual;
   double           revision;
   string           source;
   datetime         retrieved_at;
   ENUM_NEWS_STATUS status;
  };

//+------------------------------------------------------------------+
//| Returns a SNewsEvent with every field at a safe, explicit default —   |
//| matching DJ_NewDecision()'s "every field defaulted" pattern so a         |
//| caller only sets the fields it actually has values for.                    |
//+------------------------------------------------------------------+
SNewsEvent NM_NewEvent()
  {
   SNewsEvent e;
   e.event_id = "";
   e.event_name = "";
   e.currency = "";
   e.importance = 0;
   e.scheduled_utc = 0;
   e.scheduled_server_time = 0;
   e.scheduled_botswana_time = 0;
   e.previous = 0.0;
   e.forecast = 0.0;
   e.actual = 0.0;
   e.revision = 0.0;
   e.source = "";
   e.retrieved_at = 0;
   e.status = NEWS_STATUS_UNKNOWN;
   return e;
  }

//+------------------------------------------------------------------+
//| ARRAY-BASED CORE                                                   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| True iff 'current_server_time' falls within [scheduled_server_time -  |
//| before_minutes, scheduled_server_time + after_minutes] for ANY event   |
//| in 'events' whose importance is >= min_importance — the base window,     |
//| per section 10's "InpNewsBlackoutBeforeMinutes (default 15) before       |
//| scheduled_server_time, InpNewsBlackoutAfterMinutes (default 15) after."     |
//| 'triggering_event_id' is always set (empty string if no event triggers      |
//| the blackout), so a caller can log which event caused it.                     |
//+------------------------------------------------------------------+
bool NM_IsInBlackoutWindowArray(const SNewsEvent &events[], const datetime current_server_time,
                                 const int before_minutes, const int after_minutes,
                                 const int min_importance, string &triggering_event_id)
  {
   triggering_event_id = "";
   for(int i = 0; i < ArraySize(events); i++)
     {
      if(events[i].importance < min_importance)
         continue;

      datetime window_start = events[i].scheduled_server_time - before_minutes * 60;
      datetime window_end   = events[i].scheduled_server_time + after_minutes * 60;
      if(current_server_time >= window_start && current_server_time <= window_end)
        {
         triggering_event_id = events[i].event_id;
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| As NM_IsInBlackoutWindowArray, but also extends the blackout past       |
//| the nominal window end when the spread has not yet normalized to         |
//| within 'max_spread_atr_multiple' of ATR, per section 10: "extended if      |
//| spread has not normalized... by the nominal end of the window."             |
//|                                                                    |
//| **Interpretation choice, stated explicitly (the spec does not give a  |
//| number here):** the extension is bounded by 'max_extension_minutes' —   |
//| an unbounded extension is not what "resume only after... spread            |
//| normalization" implies in practice (a permanently wide spread should         |
//| not blackout trading forever), so this caps how far past the nominal          |
//| window a still-wide spread can push the blackout. Flagged for whoever            |
//| eventually reviews this task to confirm the cap value/existence is                |
//| the right call.                                                                     |
//+------------------------------------------------------------------+
bool NM_IsInBlackoutWindowExtended(const SNewsEvent &events[], const datetime current_server_time,
                                    const int before_minutes, const int after_minutes,
                                    const int max_extension_minutes, const int min_importance,
                                    const double current_spread, const double current_atr,
                                    const double max_spread_atr_multiple,
                                    string &triggering_event_id)
  {
   triggering_event_id = "";
   for(int i = 0; i < ArraySize(events); i++)
     {
      if(events[i].importance < min_importance)
         continue;

      datetime window_start = events[i].scheduled_server_time - before_minutes * 60;
      datetime window_end   = events[i].scheduled_server_time + after_minutes * 60;

      if(current_server_time >= window_start && current_server_time <= window_end)
        {
         triggering_event_id = events[i].event_id;
         return true;
        }

      datetime extension_deadline = window_end + max_extension_minutes * 60;
      if(current_server_time > window_end && current_server_time <= extension_deadline)
        {
         bool spread_normalized = (current_atr > 0.0) &&
                                   (current_spread <= current_atr * max_spread_atr_multiple);
         if(!spread_normalized)
           {
            triggering_event_id = events[i].event_id;
            return true;
           }
        }
     }
   return false;
  }
