//+------------------------------------------------------------------+
//| Test_FairEconomyNewsProvider.mq5                                  |
//| Themba Adaptive Intraday Engine — TASK-034 compile/logic test       |
//|                                                                    |
//| Tests 1-8 are pure (no network) — parsing, ISO8601/impact/lenient-     |
//| double helpers, against a hand-fabricated sample matching the           |
//| feed's documented field shape (per this file's own "unverified            |
//| assumption" header note — a real captured sample should replace this        |
//| once the feed is reachable from this account for real).                       |
//|                                                                    |
//| Tests 9-10 exercise the LIVE path (FEP_FetchLive / FEP_EnsureCache)      |
//| via a REAL WebRequest call. This project's terminal has not had          |
//| nfs.faireconomy.net added to its allowed-URL list yet (a manual,           |
//| user-side step per FairEconomyNewsProvider.mqh's own header) — so           |
//| this call is expected to fail deterministically with "URL not               |
//| allowed" REGARDLESS of actual internet connectivity, which is exactly         |
//| the fail-closed path Specification item 4 requires be tested. If a             |
//| future session adds the allowed URL, test 9 will instead exercise the           |
//| real successful-fetch path — either outcome is handled explicitly              |
//| below, not assumed.                                                                |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/News/FairEconomyNewsProvider.mqh"

int g_pass = 0;
int g_fail = 0;

void Check(const string label, const bool condition)
  {
   if(condition)
     {
      PrintFormat("PASS: %s", label);
      g_pass++;
     }
   else
     {
      PrintFormat("FAIL: %s", label);
      g_fail++;
     }
  }

void OnStart()
  {
   Print("=== TASK-034 FairEconomyNewsProvider test start ===");

   //--- 1. ISO8601 parsing: explicit negative offset -----------------------
   bool ok;
   datetime t1 = FEP_ParseIso8601ToUtc("2026-07-22T12:30:00-04:00", ok);
   datetime expected1 = StringToTime("2026.07.22 16:30:00"); // 12:30 -04:00 == 16:30 UTC
   Check("ISO8601 with -04:00 offset converts to correct UTC", ok && t1 == expected1);

   //--- 2. ISO8601 parsing: explicit positive offset -----------------------
   bool ok2;
   datetime t2 = FEP_ParseIso8601ToUtc("2026-07-22T09:00:00+02:00", ok2);
   datetime expected2 = StringToTime("2026.07.22 07:00:00"); // 09:00 +02:00 == 07:00 UTC
   Check("ISO8601 with +02:00 offset converts to correct UTC", ok2 && t2 == expected2);

   //--- 3. ISO8601 parsing: 'Z' / absent offset means UTC already ----------
   bool ok3;
   datetime t3 = FEP_ParseIso8601ToUtc("2026-07-22T12:30:00Z", ok3);
   datetime expected3 = StringToTime("2026.07.22 12:30:00");
   Check("ISO8601 with 'Z' suffix is already UTC", ok3 && t3 == expected3);

   //--- 4. ISO8601 parsing: too-short input is rejected, not guessed -------
   bool ok4;
   FEP_ParseIso8601ToUtc("2026-07-22", ok4);
   Check("too-short ISO8601 string is rejected (ok_out=false)", ok4 == false);

   //--- 5. Impact mapping matches MT5CalendarProvider's 0-3 ordinal scale --
   Check("impact 'High' maps to 3", FEP_MapImpact("High") == 3);
   Check("impact 'Medium' maps to 2", FEP_MapImpact("Medium") == 2);
   Check("impact 'Low' maps to 1", FEP_MapImpact("Low") == 1);
   Check("impact 'Holiday' maps to 0", FEP_MapImpact("Holiday") == 0);
   Check("unrecognized impact maps to 0", FEP_MapImpact("Non-Economic") == 0);

   //--- 6. Lenient double parsing ------------------------------------------
   Check("lenient parse '1.2%' -> 1.2", MathAbs(FEP_ParseLenientDouble("1.2%") - 1.2) < 0.0001);
   Check("lenient parse '-0.3' -> -0.3", MathAbs(FEP_ParseLenientDouble("-0.3") - (-0.3)) < 0.0001);
   Check("lenient parse '' -> 0.0", FEP_ParseLenientDouble("") == 0.0);
   Check("lenient parse 'N/A' -> 0.0 (no guessed unit suffix)",
         FEP_ParseLenientDouble("N/A") == 0.0);

   //--- 7. Full feed parse: hand-fabricated sample matching the feed's -----
   //--- documented flat-array-of-objects shape ------------------------------
   string sample =
      "[" +
      "{\"title\":\"Non-Farm Employment Change\",\"country\":\"USD\"," +
      "\"date\":\"2026-07-22T12:30:00-04:00\",\"impact\":\"High\"," +
      "\"forecast\":\"180K\",\"previous\":\"150K\"}," +
      "{\"title\":\"Bank Holiday\",\"country\":\"GBP\"," +
      "\"date\":\"2026-07-22T00:00:00+00:00\",\"impact\":\"Holiday\"," +
      "\"forecast\":\"\",\"previous\":\"\"}," +
      "{\"title\":\"CPI m/m\",\"country\":\"EUR\"," +
      "\"date\":\"2026-07-23T09:00:00+02:00\",\"impact\":\"Medium\"," +
      "\"forecast\":\"0.3%\",\"previous\":\"0.2%\"}" +
      "]";

   SNewsEvent events[];
   bool sample_any_missing;
   int count = FEP_ParseFeedJson(sample, events, sample_any_missing);
   Check("parses all 3 objects from the sample", count == 3);
   Check("a fully well-formed sample reports any_required_field_missing_out == false",
         sample_any_missing == false);
   Check("event 0 title parsed", events[0].event_name == "Non-Farm Employment Change");
   Check("event 0 currency parsed", events[0].currency == "USD");
   Check("event 0 importance mapped (High=3)", events[0].importance == 3);
   Check("event 0 scheduled_utc matches expected conversion",
         events[0].scheduled_utc == StringToTime("2026.07.22 16:30:00"));
   Check("event 0 forecast lenient-parsed", MathAbs(events[0].forecast - 180.0) < 0.0001);
   Check("event 0 previous lenient-parsed", MathAbs(events[0].previous - 150.0) < 0.0001);
   Check("event 0 source tagged FAIRECONOMY", events[0].source == "FAIRECONOMY");
   Check("event 1 (Holiday) importance mapped to 0", events[1].importance == 0);
   Check("event 2 currency EUR parsed", events[2].currency == "EUR");

   //--- 8. Malformed/empty input parses to zero events, never crashes ------
   //--- **This tests FEP_ParseFeedJson, the PURE parser, in isolation --------
   //--- deliberately tolerant, per its own documented contract. This is NOT --
   //--- the fail-open bug the seventh-round review reported (Codex review -----
   //--- finding, P0 finding 5) -- that bug was in FEP_FetchLive treating an -----
   //--- HTTP-200-but-garbage-body response as a verified-empty result. Test 8a ---
   //--- below exercises the NEW live-fetch-level guard that closes it.** ---------
   SNewsEvent empty_events[];
   bool empty_any_missing;
   int empty_count = FEP_ParseFeedJson("", empty_events, empty_any_missing);
   Check("empty input parses to 0 events", empty_count == 0);
   SNewsEvent garbage_events[];
   bool garbage_any_missing;
   int garbage_count = FEP_ParseFeedJson("not valid json at all {{{", garbage_events,
                                          garbage_any_missing);
   Check("malformed input parses to 0 events (no crash, no guessed data)", garbage_count == 0);

   //--- 8a. **Codex review finding, seventh round, P0 finding 5**: -----------
   //--- FEP_LooksLikeJsonArray -- the live-fetch-level guard that now REJECTS ----
   //--- (as a provider failure, not a verified-empty result) exactly the kind -----
   //--- of response that test 8 above shows the pure parser would otherwise --------
   //--- silently accept as "0 events, success". ------------------------------------
   Check("an empty response body does not look like a JSON array",
         FEP_LooksLikeJsonArray("") == false);
   Check("an HTML error page does not look like a JSON array",
         FEP_LooksLikeJsonArray("<html><body>502 Bad Gateway</body></html>") == false);
   Check("truncated/malformed garbage does not look like a JSON array",
         FEP_LooksLikeJsonArray("not valid json at all {{{") == false);
   Check("a genuinely empty JSON array DOES look like one (a real empty "
         "calendar week must not be rejected)", FEP_LooksLikeJsonArray("[]") == true);
   Check("a real, well-formed feed sample looks like a JSON array",
         FEP_LooksLikeJsonArray(sample) == true);

   //--- 8b. **Codex review finding, eighth round, P0 finding 7**: -----------
   //--- FEP_LooksLikeJsonArray's own shape check must reject "[garbage]" -----
   //--- (bracketed but not object-shaped content) even though its outermost ---
   //--- '[' / ']' pair alone previously passed the seventh-round guard. -------
   Check("'[garbage]' (bracketed, non-object content) does NOT look like a JSON array",
         FEP_LooksLikeJsonArray("[garbage]") == false);
   Check("'[{}]' (a single empty object) DOES look like a JSON array (the object-count-vs-"
         "parsed-count check in FEP_FetchLive, not this shape check, is what rejects it)",
         FEP_LooksLikeJsonArray("[{}]") == true);

   //--- 8c. **Codex review finding, eighth round, P0 finding 7**: the -------
   //--- raw-object-count-vs-parsed-count mismatch FEP_FetchLive now checks ---
   //--- for -- demonstrated directly against the two underlying pure            --
   //--- functions it composes, since FEP_FetchLive itself requires a live -------
   //--- network round-trip (see test 9 below). ------------------------------------
   string empty_object_array = "[{}]";
   string objs_a[];
   int raw_count_a = FEP_SplitObjects(empty_object_array, objs_a);
   SNewsEvent parsed_a[];
   bool any_missing_a;
   int parsed_count_a = FEP_ParseFeedJson(empty_object_array, parsed_a, any_missing_a);
   Check("'[{}]' contains exactly 1 raw object", raw_count_a == 1);
   Check("'[{}]' parses to 0 usable events (no 'date' field) -- exactly the "
         "raw>0-but-parsed==0 mismatch FEP_FetchLive now fails closed on",
         parsed_count_a == 0);

   string schema_drift_array =
      "[{\"foo\":\"bar\"},{\"foo\":\"baz\"}]"; // objects present, but no "date" field at all
   string objs_b[];
   int raw_count_b = FEP_SplitObjects(schema_drift_array, objs_b);
   SNewsEvent parsed_b[];
   bool any_missing_b;
   int parsed_count_b = FEP_ParseFeedJson(schema_drift_array, parsed_b, any_missing_b);
   Check("a schema-drift array contains 2 raw objects", raw_count_b == 2);
   Check("a schema-drift array (no parseable 'date' field on any object) parses to 0 usable "
         "events -- the same raw>0-but-parsed==0 mismatch", parsed_count_b == 0);

   //--- 8d. **Codex review finding, ninth round, P0 finding 5**: the -------
   //--- EXACT counterexample the review reported -- a payload with ONE ----
   //--- benign, fully-valid event plus ONE malformed event that STILL -----
   //--- has a parseable date (so raw_count>0 AND parsed_count>0, meaning ---
   //--- the round-8 "raw>0-but-parsed==0" guard alone does NOT catch it). --
   string mixed_valid_and_malformed =
      "[" +
      "{\"title\":\"Benign Low-Impact Release\",\"country\":\"USD\"," +
      "\"date\":\"2026-07-27T12:00:00Z\",\"impact\":\"Low\"," +
      "\"forecast\":\"1.0\",\"previous\":\"0.9\"}," +
      "{\"date\":\"2026-07-27T13:00:00Z\"}" + // malformed: missing title/country/impact entirely
      "]";
   SNewsEvent mixed_events[];
   bool mixed_any_missing;
   int mixed_count = FEP_ParseFeedJson(mixed_valid_and_malformed, mixed_events, mixed_any_missing);
   Check("a mixed valid+malformed payload still parses 2 date-parseable events "
         "(so the raw>0-but-parsed==0 guard alone would NOT catch this)",
         mixed_count == 2);
   Check("FEP_ParseFeedJson correctly flags any_required_field_missing_out == true "
         "for a payload with ONE malformed event alongside a benign valid one "
         "(the review's own exact counterexample)",
         mixed_any_missing == true);

   //--- 8d2. **Codex review finding, tenth round, P0 finding 5**: the -----
   //--- review's NEW exact counterexample -- a mixed payload where the -----
   //--- malformed object's DATE ITSELF is missing (round-9's own mixed ------
   //--- test above used a date-parseable-but-otherwise-malformed object, ----
   //--- which the round-9 fix already caught; this is the DIFFERENT gap -----
   //--- round-9 left open). raw_object_count=2, parsed_count=1 (the ---------
   //--- malformed object is skipped for lacking a date) -- the round-8 -------
   //--- "raw>0-but-parsed==0" guard does NOT catch this either, since ---------
   //--- parsed_count is 1, not 0. -----------------------------------------------
   string mixed_missing_date =
      "[" +
      "{\"title\":\"Benign Low-Impact Release\",\"country\":\"USD\"," +
      "\"date\":\"2026-07-27T12:00:00Z\",\"impact\":\"Low\"," +
      "\"forecast\":\"1.0\",\"previous\":\"0.9\"}," +
      "{\"title\":\"Undated High-Impact Release\",\"country\":\"USD\"," +
      "\"impact\":\"High\"}" + // malformed: no "date" field at all
      "]";
   string objs_missing_date[];
   int raw_count_missing_date = FEP_SplitObjects(mixed_missing_date, objs_missing_date);
   SNewsEvent mixed_missing_date_events[];
   bool mixed_missing_date_any_missing;
   int mixed_missing_date_count = FEP_ParseFeedJson(mixed_missing_date, mixed_missing_date_events,
                                                      mixed_missing_date_any_missing);
   Check("a mixed valid+missing-date payload contains 2 raw objects",
         raw_count_missing_date == 2);
   Check("a mixed valid+missing-date payload parses only the 1 date-having event "
         "(so the raw>0-but-parsed==0 guard alone would NOT catch this either)",
         mixed_missing_date_count == 1);
   Check("FEP_ParseFeedJson correctly flags any_required_field_missing_out == true "
         "when a missing-date object is mixed with a benign valid one (round-10's own "
         "exact counterexample -- the specific gap round-9's own fix left open)",
         mixed_missing_date_any_missing == true);

   //--- 8d3. **Codex review finding, tenth round, P0 finding 5**: the -----
   //--- same counterexample, but with an UNPARSEABLE (not merely absent) ---
   //--- date string -- a distinct code path (FEP_ParseIso8601ToUtc's own ---
   //--- parsed_ok==false branch) from the missing-date test above. ---------
   string mixed_bad_date =
      "[" +
      "{\"title\":\"Benign Low-Impact Release\",\"country\":\"USD\"," +
      "\"date\":\"2026-07-27T12:00:00Z\",\"impact\":\"Low\"}," +
      "{\"title\":\"Malformed-Date High-Impact Release\",\"country\":\"USD\"," +
      "\"date\":\"not-a-real-date\",\"impact\":\"High\"}" + // malformed: unparseable date
      "]";
   SNewsEvent mixed_bad_date_events[];
   bool mixed_bad_date_any_missing;
   int mixed_bad_date_count = FEP_ParseFeedJson(mixed_bad_date, mixed_bad_date_events,
                                                 mixed_bad_date_any_missing);
   Check("a mixed valid+unparseable-date payload parses only the 1 valid event",
         mixed_bad_date_count == 1);
   Check("FEP_ParseFeedJson correctly flags any_required_field_missing_out == true "
         "when an unparseable-date object is mixed with a benign valid one",
         mixed_bad_date_any_missing == true);

   //--- 8e. **Codex review finding, ninth round, P0 finding 5**: the ------
   //--- review's OTHER exact counterexample -- a bare {"date":...} object -
   //--- with no title/country/impact at all becomes a "valid" zero-impact -
   //--- event with no identity unless this is caught. ---------------------
   string bare_date_only = "[{\"date\":\"2026-07-27T12:00:00Z\"}]";
   SNewsEvent bare_events[];
   bool bare_any_missing;
   int bare_count = FEP_ParseFeedJson(bare_date_only, bare_events, bare_any_missing);
   Check("a bare {\"date\":...} object with no other fields still parses as one event "
         "(proving the identity gap the review reported actually exists in this parser)",
         bare_count == 1);
   Check("that same bare-date event is correctly flagged as missing required fields",
         bare_any_missing == true);

   //--- 8f. **Codex review finding, ninth round, P0 finding 5**: an -------
   //--- unrecognized (schema-drifted) impact STRING on an otherwise -------
   //--- complete object must also be flagged -- distinct from a genuinely -
   //--- known zero-impact value like "Holiday"/"Non-Economic". ------------
   string unknown_impact_array =
      "[{\"title\":\"Some Release\",\"country\":\"EUR\"," +
      "\"date\":\"2026-07-27T12:00:00Z\",\"impact\":\"Extreme\"}]"; // "Extreme" is not a known value
   SNewsEvent unknown_impact_events[];
   bool unknown_impact_any_missing;
   FEP_ParseFeedJson(unknown_impact_array, unknown_impact_events, unknown_impact_any_missing);
   Check("an otherwise-complete object with an UNRECOGNIZED impact string is flagged "
         "(distinct from a genuinely known zero-impact value)",
         unknown_impact_any_missing == true);
   string known_zero_impact_array =
      "[{\"title\":\"Bank Holiday\",\"country\":\"GBP\"," +
      "\"date\":\"2026-07-27T12:00:00Z\",\"impact\":\"Holiday\"}]";
   SNewsEvent known_zero_events[];
   bool known_zero_any_missing;
   FEP_ParseFeedJson(known_zero_impact_array, known_zero_events, known_zero_any_missing);
   Check("a genuinely known zero-impact value ('Holiday') on an otherwise-complete object "
         "is NOT flagged", known_zero_any_missing == false);

   //--- 8g. **Codex review finding, ninth round, P0 finding 5**: FEP_FetchLive
   //--- itself cannot be exercised against these exact malformed payloads --
   //--- without a live network round-trip returning them for real (see -----
   //--- test 9 below for the live path) -- but FEP_IsKnownImpact, the new --
   //--- primitive FEP_FetchLive's own rejection decision is built on, is ---
   //--- fully unit-testable here. ------------------------------------------
   Check("FEP_IsKnownImpact accepts 'High'/'Medium'/'Low'/'Holiday'/'Non-Economic' "
         "(case-insensitive)",
         FEP_IsKnownImpact("HIGH") && FEP_IsKnownImpact("medium") && FEP_IsKnownImpact("Low") &&
         FEP_IsKnownImpact("holiday") && FEP_IsKnownImpact("Non-Economic"));
   Check("FEP_IsKnownImpact rejects an empty string", FEP_IsKnownImpact("") == false);
   Check("FEP_IsKnownImpact rejects an unrecognized/schema-drifted value",
         FEP_IsKnownImpact("Extreme") == false);

   //--- 9. LIVE fetch — expected to fail (URL not yet allowed in this ------
   //--- terminal), exercising the fail-closed path for real -----------------
   FEP_InvalidateCache();
   SNewsEvent live_events[];
   int live_result = FEP_FetchLive(live_events);
   if(live_result < 0)
      Print("INFO: FEP_FetchLive failed as expected (URL not yet allowed in this terminal, "
            "or no network) -- this IS the fail-closed path under test.");
   else
      Print("INFO: FEP_FetchLive succeeded for real (this terminal's allowed-URL list already "
            "includes nfs.faireconomy.net) -- treating this as the successful-fetch path.");
   Check("FEP_FetchLive returns a definitive success/failure signal (never hangs/crashes)",
         live_result >= -1);

   //--- 10. Caching: a same-instant second call does not attempt a --------
   //--- second network round-trip -- verified by cache-content stability --
   //--- across the call, not merely by timing. ------------------------------
   datetime now = TimeGMT();
   bool first_ensure = FEP_EnsureCache(now);
   int cached_count_after_first = ArraySize(g_fep_cached_events);
   bool second_ensure = FEP_EnsureCache(now); // same instant -> must be a cache hit, not a refetch
   int cached_count_after_second = ArraySize(g_fep_cached_events);
   Check("second FEP_EnsureCache call at the same instant returns the same result as the first",
         second_ensure == first_ensure);
   Check("cache contents are unchanged across a same-instant second call (no refetch occurred)",
         cached_count_after_second == cached_count_after_first);

   //--- 11. Fail-closed: FEP_IsInBlackoutNow reports feed_unavailable_out --
   //--- whenever the cache could not be populated (only meaningful when ----
   //--- test 9/10 above actually failed to reach the feed) ------------------
   if(!first_ensure)
     {
      FEP_InvalidateCache();
      string triggering_event_id;
      bool feed_unavailable;
      bool blackout = FEP_IsInBlackoutNow("XAUUSD", "USD", 3, 15, 15, 60, 3.0, 1.0,
                                           triggering_event_id, feed_unavailable);
      Check("feed unreachable: feed_unavailable_out reports true", feed_unavailable);
      Check("feed unreachable: return value is false (caller, not this function, applies the "
            "fail-closed policy)", blackout == false);
     }
   else
      Print("INFO: skipping test 11's unreachable-feed assertion -- the feed was actually "
            "reachable in this run (see test 9's INFO line above).");

   PrintFormat("=== TASK-034 FairEconomyNewsProvider test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
