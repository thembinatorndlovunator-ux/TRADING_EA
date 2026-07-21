//+------------------------------------------------------------------+
//| NullNewsProvider.mqh                                              |
//| Themba Adaptive Intraday Engine — News                            |
//|                                                                    |
//| Per NEWS_INTEGRATION_SPEC.md: "Deriv synthetic indices use            |
//| NullNewsProvider. Do not apply macroeconomic event direction or         |
//| blackout logic." Always reports zero events — trading on synthetic       |
//| symbols is never blocked by news, by design, not by omission.               |
//+------------------------------------------------------------------+
#property strict

#include "NewsManager.mqh"

//+------------------------------------------------------------------+
//| Always returns 0 events. 'events' is cleared (never left with          |
//| stale data from a prior call), matching every other provider-shaped     |
//| fetch function's own-array-ownership convention in this project.          |
//+------------------------------------------------------------------+
int NNP_FetchEvents(SNewsEvent &events[])
  {
   ArrayFree(events);
   return 0;
  }
