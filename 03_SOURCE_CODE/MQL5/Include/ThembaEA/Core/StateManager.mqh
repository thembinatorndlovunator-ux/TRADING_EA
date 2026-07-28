//+------------------------------------------------------------------+
//| StateManager.mqh                                                 |
//| Themba Adaptive Intraday Engine — Core                           |
//|                                                                    |
//| Account-wide scalar persistence, per TASK-002_PHASE2_             |
//| SPECIFICATION.md section 8 ("Persistence and restart") and        |
//| section 11 (StateManager test boundary).                          |
//|                                                                    |
//| Scope of this module (TASK-003): the ACCOUNT-WIDE namespace only  |
//| (account_login + trade_server, deliberately unpartitioned by      |
//| magic/symbol, per section 8's two-namespace schema). Per-instance |
//| (symbol+magic+account+server) structured/file-based storage is    |
//| out of scope here and is a separate, later task — this keeps this |
//| task bounded, per CLAUDE.md's "implement one bounded task" rule.  |
//|                                                                    |
//| Storage mechanism: native MQL5 global variables                   |
//| (GlobalVariableSet/Get), which are double-only and persist across |
//| terminal restarts — exactly the "small scalar" storage the        |
//| specification calls for (daily/weekly equity baselines, peak      |
//| equity, reset timestamps, schema version).                        |
//|                                                                    |
//| Concurrency: a compare-and-set lock built on                      |
//| GlobalVariableSetOnCondition, per section 8's "single-writer"      |
//| requirement, with stale-lock breaking so a crashed instance can    |
//| never permanently wedge the lock.                                 |
//|                                                                    |
//| Schema: every account-wide record set is versioned. A version      |
//| mismatch triggers SM_EnsureAccountSchema()'s targeted migration —  |
//| per section 8, a mismatch must never blanket-reset a still-valid   |
//| period-loss baseline; this module's migration hook is additive     |
//| only (it may add new fields with defaults) and never deletes an   |
//| existing field.                                                   |
//+------------------------------------------------------------------+
#property strict

#include "KeyEncoding.mqh"

// Current schema version implemented by this build of StateManager.
// Bump this, and extend SM_EnsureAccountSchema()'s migration branch,
// whenever a new account-wide field is introduced by a later task.
#define SM_SCHEMA_VERSION 1.0

// Lock is considered abandoned (crashed holder) after this many seconds
// and force-broken by the next caller — prevents a permanent wedge.
#define SM_LOCK_STALE_SECONDS 30

//+------------------------------------------------------------------+
//| Namespace: account_login + trade_server, per section 8.           |
//| Deliberately excludes symbol/magic — this is the account-wide     |
//| namespace, shared by every instance of this EA on this account.   |
//|                                                                    |
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** previously concatenated the raw, unbounded trade-server name              |
//| (e.g. "Deriv-Demo", or a longer broker server string) directly into the             |
//| key -- combined with every field name this module appends, some                        |
//| genuinely exceeded MT5's 63-character global-variable name limit on a                      |
//| real broker server, silently failing every GlobalVariableSet call past                        |
//| it. Now delegates to KeyEncoding.mqh's KE_AccountNamespace, which hashes                          |
//| the unbounded components into a fixed-width 16-character digest instead                              |
//| of embedding them verbatim -- see that module's own header for why this                                  |
//| is collision-resistant enough for this project's actual key count.**                                          |
//+------------------------------------------------------------------+
string SM_AccountNamespace()
  {
   return KE_AccountNamespace("ThembaEA_AW");
  }

//+------------------------------------------------------------------+
//| Fully-qualified global-variable name for one account-wide field.  |
//+------------------------------------------------------------------+
string SM_AccountKey(const string field)
  {
   return SM_AccountNamespace() + "__" + field;
  }

//+------------------------------------------------------------------+
//| **Superseded, 2026-07-27 (Codex review finding, ninth round, P0     |
//| finding 2): this OnInit-only bootstrap is no longer called or       |
//| needed.** Bootstrap is now folded directly into SM_AcquireAccountLock|
//| itself (see that function's own header) using GetLastError() to     |
//| distinguish "variable does not exist yet" from "currently held by   |
//| someone else" -- every caller can safely call SM_AcquireAccountLock  |
//| from ANY context, not only after an OnInit-run bootstrap, and the    |
//| bootstrap step itself is now provably race-free (see below), closing|
//| the exact "late unconditional Set stomps an already-acquired lock"  |
//| race this function's own removed comment used to document as an     |
//| accepted, narrowed-but-not-airtight limitation. Kept only as a no-op |
//| so existing OnInit call sites do not need to be touched.**           |
//+------------------------------------------------------------------+
void SM_EnsureAccountLockInitialized()
  {
   // Intentionally a no-op -- see header comment above.
  }

//+------------------------------------------------------------------+
//| Acquire the account-wide write lock (compare-and-set), owner-token  |
//| based. Returns true once acquired, false on timeout. On success,    |
//| 'owner_token_out' receives the exact nonzero token this call wrote  |
//| -- the caller MUST pass that same token to SM_ReleaseAccountLock()  |
//| (never a bare release-by-anyone), so a release can never clear a    |
//| lock some OTHER holder has since legitimately acquired.             |
//|                                                                    |
//| A lock held longer than SM_LOCK_STALE_SECONDS is treated as        |
//| abandoned (its holder crashed without releasing it) and broken.    |
//|                                                                    |
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding   |
//| 2 -- round 8's own finding 4 fix left two real gaps this closes):**       |
//|                                                                    |
//| 1. **Owner-token ABA fix.** The lock value was previously a bare      |
//|    boolean (0.0/1.0) with no owner identity: ANY caller's                |
//|    SM_ReleaseAccountLock() unconditionally wrote 0.0, and the stale-        |
//|    breaker also unconditionally wrote 0.0. Sequence that silently             |
//|    corrupted the lock: holder A's release call is delayed (e.g. a               |
//|    slow tick); meanwhile A's lock is force-broken as stale by holder B,             |
//|    which then legitimately acquires it; A's now-late release call                  |
//|    finally runs and clears B's still-active lock, letting a THIRD                       |
//|    holder C acquire concurrently with B. Fixed: the lock value is now                       |
//|    a unique per-acquisition token (never 0.0), and release/stale-break                          |
//|    both use GlobalVariableSetOnCondition(lock_key, 0.0, <the exact token                             |
//|    being cleared>) -- an atomic compare-and-set that only succeeds if                                    |
//|    that specific token is STILL the current value, so a delayed/stale                                        |
//|    release from a PRIOR holder can never clear a DIFFERENT holder's                                            |
//|    live lock.                                                                                                     |
//| 2. **Bootstrap race fix (superseded 2026-07-28, round-10 P0 finding 1     |
//|    -- see the "Redesigned"/"Fixed" comments inside the function body        |
//|    below for what changed and why the round-9 version here was still         |
//|    genuinely racy). The separate OnInit-only                                    |
//|    SM_EnsureAccountLockInitialized() bootstrap remains retired (see its           |
//|    own header) -- bootstrap now happens directly inside this function,               |
//|    on ERR_GLOBALVARIABLE_NOT_FOUND, via a create-then-verify-readback                     |
//|    step that can never overwrite a concurrently-acquired live lock.**                          |
//| 3. **Timestamp-desync fix (round-10 P0 finding 1).** The staleness            |
//|    timestamp is no longer a separate "__since" global written by a               |
//|    separate later call -- it is now encoded directly into the token               |
//|    itself, so staleness is derived from the SAME atomic value the CAS                |
//|    operates on, with no window where a fresh token could be observed                     |
//|    alongside a stale leftover timestamp from a previous holder. See the                       |
//|    token-construction comment inside the function body below.                                     |
//+------------------------------------------------------------------+
bool SM_AcquireAccountLock(double &owner_token_out, const int timeout_ms = 500)
  {
   string lock_key = SM_AccountKey("lock");
   owner_token_out = 0.0;

   ulong start_tick = GetTickCount64();
   while(true)
     {
      // **Redesigned, 2026-07-28 (Codex review finding, tenth round, P0
      // finding 1):** token now ENCODES its own acquisition second in its
      // high-order digits (epoch_seconds * 1,000,000 + tiebreak + 1), so
      // staleness can be derived directly from the token's own value below
      // -- no separate "__since" field, and therefore no window where a
      // reader can observe a fresh token paired with a stale leftover
      // timestamp from a PREVIOUS holder (round-9's own separate-write
      // design had exactly that gap). The tiebreak (microsecond counter +
      // random, folded into six low-order digits) keeps two callers racing
      // the same second from minting the same token. epoch_seconds*1e6
      // stays well under a double's exact-integer range (2^53 ~= 9.0e15)
      // through the dates this project runs in, so the cast below is
      // always an exact integer, never a precision-lossy approximation.
      long   now_sec  = (long)TimeCurrent();
      long   tiebreak = ((long)GetMicrosecondCount() + (long)MathRand()) % 1000000L;
      double token    = (double)(now_sec * 1000000L + tiebreak + 1L);

      ResetLastError();
      if(GlobalVariableSetOnCondition(lock_key, token, 0.0))
        {
         owner_token_out = token;
         return true;
        }

      int err = GetLastError();
      if(err == ERR_GLOBALVARIABLE_NOT_FOUND)
        {
         // **Fixed, 2026-07-28 (round-10 P0 finding 1):** round 9's
         // bootstrap here was an UNCONDITIONAL GlobalVariableSet(lock_key,
         // 0.0) -- a blind overwrite, not a create-if-absent. A second,
         // merely-delayed caller reaching that same line AFTER a first
         // caller had already raced through bootstrap-then-CAS and
         // legitimately acquired a live nonzero token would stomp that
         // live token back to 0.0, letting both callers believe they held
         // the lock simultaneously. Native MQL5 has no atomic "create only
         // if absent" primitive, so this is fixed differently: write THIS
         // caller's own acquisition token directly (never the neutral 0.0
         // value), then read the value back. GlobalVariableSet is the
         // terminal's own single, indivisible operation, so whichever
         // concurrent caller's write physically lands last is the one
         // whose value survives -- every OTHER racing caller's own
         // readback observes a value that is not its own token and
         // correctly retries via the normal CAS path instead of ever
         // believing it holds a lock it does not. Because this write is
         // always a real nonzero token (never 0.0), a concurrent normal-
         // path GlobalVariableSetOnCondition(lock_key, token_x, 0.0) can
         // never spuriously succeed against it either: the variable is
         // either still genuinely absent (that caller lands here too) or
         // already holds SOME caller's real token (its own compare against
         // 0.0 correctly fails) -- there is no window where the variable
         // holds 0.0 while a live acquisition exists.
         GlobalVariableSet(lock_key, token);
         if(GlobalVariableGet(lock_key) == token)
           {
            owner_token_out = token;
            return true;
           }
         continue; // lost the bootstrap race to a concurrent first-time caller
        }

      // Someone else holds it — staleness is derived from the held
      // token's own encoded acquisition second (see token comment above).
      double held_token = GlobalVariableGet(lock_key);
      if(held_token != 0.0)
        {
         datetime held_since = (datetime)(long)(held_token / 1000000.0);
         if((TimeCurrent() - held_since) > SM_LOCK_STALE_SECONDS)
           {
            // Force-break an abandoned lock -- atomic compare-and-set from the
            // EXACT stale token observed above, never a blind write, so a
            // holder that finishes and releases normally between the read
            // above and this call cannot have this call incorrectly clear a
            // brand-new, unrelated holder's fresh acquisition.
            GlobalVariableSetOnCondition(lock_key, 0.0, held_token);
            continue;
           }
        }

      if((GetTickCount64() - start_tick) >= (ulong)timeout_ms)
         return false;

      Sleep(10);
     }
   return false; // unreachable — satisfies MQL5's control-path analysis
  }

//+------------------------------------------------------------------+
//| Release the account-wide write lock. 'owner_token' MUST be the      |
//| exact value SM_AcquireAccountLock() returned for THIS hold -- the   |
//| release is itself an atomic compare-and-set from that exact token   |
//| to 0.0, so it silently does nothing (never corrupts a different     |
//| holder's lock) if that token is no longer the current value (e.g.   |
//| this lock was already force-broken as stale and re-acquired by      |
//| someone else). See SM_AcquireAccountLock's own header for the ABA   |
//| scenario this specifically prevents.                                 |
//+------------------------------------------------------------------+
void SM_ReleaseAccountLock(const double owner_token)
  {
   string lock_key = SM_AccountKey("lock");
   GlobalVariableSetOnCondition(lock_key, 0.0, owner_token);
  }

//+------------------------------------------------------------------+
//| **Superseded, 2026-07-28 (Codex review finding, tenth round, P0     |
//| finding 1): no longer needed or called.** The staleness timestamp is |
//| now encoded directly into the lock token itself (see                  |
//| SM_AcquireAccountLock's header/body), so there is no longer a          |
//| separate "__since" field to stamp -- doing so was the source of a       |
//| genuine bug (a contender could observe a brand-new token paired with     |
//| a stale leftover timestamp in the window before this function ran,        |
//| and incorrectly force-break a fresh lock; and SM_ReleaseAccountLock's       |
//| own former unconditional clear of that field could corrupt a               |
//| legitimately new holder's fresh stamp on a stale/failed release). Kept       |
//| only as a no-op so existing call sites do not need to be touched --          |
//| same pattern as SM_EnsureAccountLockInitialized() above.                       |
//+------------------------------------------------------------------+
void SM_StampAccountLockHeld()
  {
   // Intentionally a no-op -- see header comment above.
  }

//+------------------------------------------------------------------+
//| Set one account-wide double field. Lock-guarded (single-writer).   |
//| Returns false if the lock could not be acquired within timeout.    |
//+------------------------------------------------------------------+
bool SM_SetAccountDouble(const string field, const double value,
                          const int lock_timeout_ms = 500)
  {
   double owner_token;
   if(!SM_AcquireAccountLock(owner_token, lock_timeout_ms))
      return false;
   SM_StampAccountLockHeld();

   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 6):
   // the write's own success is now propagated -- this previously always
   // returned true once the lock was acquired, ignoring whether
   // GlobalVariableSet itself actually succeeded.**
   bool write_ok = KE_SetDoubleChecked(SM_AccountKey(field), value);

   SM_ReleaseAccountLock(owner_token);
   return write_ok;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, seventh round, P1 finding  |
//| 14):** sets MULTIPLE account-wide double fields under ONE lock            |
//| acquisition — the single-field SM_SetAccountDouble above acquires and       |
//| releases the lock PER CALL, so a caller updating several logically-           |
//| related fields (e.g. a baseline value alongside its own reset                    |
//| timestamp, or a cash-flow-adjusted baseline alongside the cursor that                |
//| tracks which deals have already been applied) leaves a real crash-window                |
//| between those separate writes.                                                                   |
//|                                                                    |
//| **Corrected, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 4):** the claim this previously made here -- "a crash either sees none of       |
//| them applied or all of them" -- is FALSE and has been removed. MQL5 native           |
//| global variables have no multi-field transactional commit primitive: this               |
//| lock only serializes against OTHER CONCURRENT WRITERS (no interleaving              |
//| between two callers' field writes), it does NOT make the writes atomic                   |
//| against THIS PROCESS crashing partway through the loop below -- a crash                     |
//| after field 0 but before field 1 leaves field 0 updated and field 1 stale.                      |
//| The real, honest guarantee callers get is weaker: EVERY CALLER OF THIS                            |
//| FUNCTION MUST ORDER ITS OWN fields[]/values[] SO THE LAST ELEMENT IS THE                              |
//| ONE A READER TREATS AS THE "IS THIS FRESH?" SIGNAL (e.g. a reset                                        |
//| timestamp, or a cursor) -- a crash before that final write leaves the                                       |
//| signal stale, so the next read naturally re-triggers an idempotent retry                                        |
//| of the whole batch rather than silently trusting a half-applied one. Both                                           |
//| existing callers (DailyWeeklyLimits.mqh's DWL_EnsureDailyBaseline/                                                     |
//| DWL_EnsureWeeklyBaseline/DWL_ApplyCashFlowAdjustments) already follow this                                                 |
//| convention. This is self-healing for THIS project's specific idempotent-                                                      |
//| retry-driven callers, not general transactional atomicity -- a future                                                             |
//| caller that is NOT idempotent-retry-safe must not assume this function                                                                |
//| gives it a real all-or-nothing guarantee.                                                                                                |
//|                                                                    |
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P1 finding    |
//| 2):** the loop below previously kept writing every remaining field         |
//| even after an earlier one failed, so a batch like [baseline (fails),         |
//| freshness_marker (succeeds)] left the freshness marker updated to             |
//| "fresh" even though the baseline write it is supposed to vouch for               |
//| never actually landed -- exactly the "baseline write can fail while              |
//| the final freshness timestamp/cursor succeeds" defect the review                    |
//| reported. The loop now STOPS at the first failed write, so if any                     |
//| earlier field fails, the freshness marker (by this function's own                        |
//| stated caller contract, always the LAST element) is never reached/                           |
//| written -- the next read then correctly sees a stale marker and                                  |
//| re-triggers the whole batch as an idempotent retry, per this header's                                 |
//| own established contract, instead of trusting a half-applied write.**                                     |
//|                                                                    |
//| **Honestly scoped, 2026-07-27 (same finding): what this DOES vs. does |
//| NOT close.** A genuine PROCESS CRASH between two successful writes            |
//| (not a write FAILURE -- the crash happens with no chance for either                |
//| write to fail or succeed cleanly) still self-heals for this project's                  |
//| existing callers, by the same freshness-marker-last argument: if the                       |
//| crash lands after field 0 (e.g. a fresh baseline) but before the                               |
//| freshness marker is even attempted, the marker is left at its OLD                                  |
//| value, which the next read correctly treats as stale and re-triggers                                  |
//| exactly one more idempotent rebase pass -- this is NOT a residual gap.                                     |
//| What remains a genuine, NOT-yet-attempted architectural gap (the                                              |
//| review's own "or an atomic file replacement"/"versioned single-record                                             |
//| prepare/commit protocol" alternative): a retry after a crash always                                                |
//| recomputes its baseline from WHATEVER equity/cursor state exists AT                                                    |
//| RETRY TIME, not the exact equity/cursor state at the ORIGINAL moment                                                      |
//| the boundary was crossed or the cash flow occurred -- so a retry that                                                        |
//| happens some time after the crash can capture a DIFFERENT (later)                                                                |
//| equity reading than the original attempt would have, potentially                                                                     |
//| hiding intervening P/L or double-applying a cash flow whose cursor                                                                       |
//| advance was itself the field that got interrupted. Closing THAT                                                                              |
//| specific class requires a real write-ahead log (persist "intend to                                                                              |
//| rebase to computed value X" BEFORE touching either field, so a crash-                                                                               |
//| recovery pass can resume from the LOGGED intent rather than                                                                                          |
//| recomputing from current state).                                                                                                                       |
//|                                                                    |
//| **Closed, 2026-07-28 (Codex review finding, tenth round, P0 finding   |
//| 1):** the write-ahead log named above as a deferred gap is now             |
//| implemented -- see SM_SetAccountDoublesBatchDurable() /                        |
//| SM_RecoverAccountDoublesBatch() below this function. Callers whose             |
//| fields are a binding risk path (DailyWeeklyLimits.mqh's three coupled            |
//| daily/weekly/cash-flow-cursor fields, the concrete case the review               |
//| named) now use the durable variant instead of this plain one.**                     |
//+------------------------------------------------------------------+
bool SM_SetAccountDoublesBatch(const string &fields[], const double &values[],
                                 const int lock_timeout_ms = 500)
  {
   int n = ArraySize(fields);
   if(n != ArraySize(values) || n == 0)
      return false;

   double owner_token;
   if(!SM_AcquireAccountLock(owner_token, lock_timeout_ms))
      return false;
   SM_StampAccountLockHeld();

   bool all_ok = true;
   for(int i = 0; i < n; i++)
     {
      if(!KE_SetDoubleChecked(SM_AccountKey(fields[i]), values[i]))
        {
         all_ok = false;
         break; // stop at the first failure -- see header comment
        }
     }

   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 6):
   // "No code calls GlobalVariablesFlush... sudden failure can lose
   // unflushed terminal globals" -- these are the daily/weekly loss-cap
   // baseline writes section 8 explicitly requires to survive a restart, so
   // they are forced to disk immediately rather than left to MT5's own
   // periodic flush cadence.**
   GlobalVariablesFlush();

   SM_ReleaseAccountLock(owner_token);
   return all_ok;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-28 (Codex review finding, tenth round, P0 finding 1):  |
//| write-ahead-logged companion to SM_SetAccountDoublesBatch above, closing  |
//| the "honestly scoped" gap that function's own header names. Before          |
//| touching any real field, this persists the EXACT target values as a           |
//| durable "intent" record (via SM_SetAccountDoublesBatch itself, so the             |
//| intent write inherits that function's own stop-at-first-failure +                    |
//| freshness-marker-last self-healing). The real fields are then written,               |
//| and the intent is acknowledged (cleared) only once that succeeds. A                      |
//| companion recovery pass, SM_RecoverAccountDoublesBatch(), must be called                       |
//| with the SAME batch_name/fields[] before any read of those fields --                              |
//| if a previous call's real-field write was interrupted (process crash                                  |
//| or a write failure) before its intent was acknowledged, recovery                                          |
//| REPLAYS the exact logged target values, not values recomputed from                                            |
//| whatever equity/cursor state exists at recovery time -- closing the                                               |
//| crash window named above where recompute-at-retry could hide                                                          |
//| intervening P/L or double-apply a cash flow whose cursor advance was                                                      |
//| itself the field that got interrupted.                                                                                        |
//|                                                                    |
//| batch_name must be a short, stable identifier unique to this logical    |
//| field-group (becomes part of the intent record's own key names) --      |
//| never reuse a batch_name for two different field groups.                |
//+------------------------------------------------------------------+
bool SM_SetAccountDoublesBatchDurable(const string batch_name, const string &fields[],
                                        const double &values[], const int lock_timeout_ms = 500)
  {
   int n = ArraySize(fields);
   if(n != ArraySize(values) || n == 0)
      return false;

   string intent_fields[];
   double intent_values[];
   ArrayResize(intent_fields, n + 1);
   ArrayResize(intent_values, n + 1);
   for(int i = 0; i < n; i++)
     {
      intent_fields[i]  = "wal_" + batch_name + "_" + IntegerToString(i);
      intent_values[i]  = values[i];
     }
   intent_fields[n] = "wal_" + batch_name + "_pending";
   intent_values[n] = 1.0;
   if(!SM_SetAccountDoublesBatch(intent_fields, intent_values, lock_timeout_ms))
      return false; // could not even log intent -- real fields must not be touched

   bool applied = SM_SetAccountDoublesBatch(fields, values, lock_timeout_ms);

   // Acknowledge only once the real fields are confirmed applied. If this
   // acknowledgement write itself fails, or a crash happens before it
   // lands, SM_RecoverAccountDoublesBatch will replay the SAME
   // already-correct intent values again next time -- a harmless
   // idempotent re-write, not a correctness gap.
   if(applied)
      SM_SetAccountDouble("wal_" + batch_name + "_pending", 0.0, lock_timeout_ms);

   return applied;
  }

//+------------------------------------------------------------------+
//| Recovery pass companion to SM_SetAccountDoublesBatchDurable(): if a  |
//| previous call's real-field write was interrupted before its intent   |
//| was acknowledged, replay the EXACT logged intent values now. MUST be |
//| called with the SAME batch_name/fields[] the original write used,    |
//| before any read of those fields. A no-op (returns true) when no      |
//| incomplete intent is pending.                                        |
//+------------------------------------------------------------------+
bool SM_RecoverAccountDoublesBatch(const string batch_name, const string &fields[],
                                     const int lock_timeout_ms = 500)
  {
   int n = ArraySize(fields);
   if(n == 0)
      return true;

   if(SM_GetAccountDouble("wal_" + batch_name + "_pending", 0.0) == 0.0)
      return true; // nothing to recover

   double values[];
   ArrayResize(values, n);
   for(int i = 0; i < n; i++)
      values[i] = SM_GetAccountDouble("wal_" + batch_name + "_" + IntegerToString(i), 0.0);

   if(!SM_SetAccountDoublesBatch(fields, values, lock_timeout_ms))
      return false; // still pending -- caller must retry recovery later

   return SM_SetAccountDouble("wal_" + batch_name + "_pending", 0.0, lock_timeout_ms);
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 4):** atomically raises one account-wide double field to 'candidate' ONLY     |
//| if it exceeds the field's current stored value (or the field has never          |
//| been set) -- holds the account lock across the READ, COMPARE, and WRITE            |
//| as one critical section. EquityPeakManager.mqh's peak-tracking functions               |
//| previously did their own separate SM_GetAccountDouble() read followed by                   |
//| a conditional SM_SetAccountDouble() call -- each individually lock-guarded,                    |
//| but the read and the write were NOT under the same lock hold, so two                              |
//| concurrent instances could interleave: both read the same (lower) current                            |
//| peak, both compute "my equity is higher, write it", and whichever write                                  |
//| lands SECOND wins even if its own equity reading was the LOWER of the two --                                 |
//| silently losing a genuine peak update. Returns false only if the lock                                            |
//| could not be acquired within timeout (fail-closed for the caller to treat                                            |
//| as "peak state unknown this tick", never "no update needed").                                                        |
//+------------------------------------------------------------------+
bool SM_SetAccountDoubleIfGreater(const string field, const double candidate,
                                   const int lock_timeout_ms = 500)
  {
   double owner_token;
   if(!SM_AcquireAccountLock(owner_token, lock_timeout_ms))
      return false;
   SM_StampAccountLockHeld();

   string key    = SM_AccountKey(field);
   bool   exists = GlobalVariableCheck(key);
   double current = exists ? GlobalVariableGet(key) : 0.0;
   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 6):
   // a write that was actually attempted now has its own success checked
   // and returned -- previously this always returned true once the lock
   // was acquired regardless of whether GlobalVariableSet succeeded.**
   bool write_ok = true;
   if(!exists || candidate > current)
      write_ok = KE_SetDoubleChecked(key, candidate);

   SM_ReleaseAccountLock(owner_token);
   return write_ok;
  }

//+------------------------------------------------------------------+
//| Read one account-wide double field. Returns default_value if the   |
//| field has never been set. Reads are not lock-guarded (a torn read  |
//| is impossible — GlobalVariableGet returns one already-committed    |
//| double atomically at the platform level).                          |
//+------------------------------------------------------------------+
double SM_GetAccountDouble(const string field, const double default_value)
  {
   string key = SM_AccountKey(field);
   if(!GlobalVariableCheck(key))
      return default_value;
   return GlobalVariableGet(key);
  }

//+------------------------------------------------------------------+
//| True if an account-wide field has ever been set.                   |
//+------------------------------------------------------------------+
bool SM_AccountFieldExists(const string field)
  {
   return GlobalVariableCheck(SM_AccountKey(field));
  }

//+------------------------------------------------------------------+
//| Delete one account-wide field (used only by tests / explicit       |
//| operator reset actions — never called by normal risk logic).       |
//+------------------------------------------------------------------+
void SM_DeleteAccountField(const string field)
  {
   string key = SM_AccountKey(field);
   if(GlobalVariableCheck(key))
      GlobalVariableDel(key);
  }

//+------------------------------------------------------------------+
//| Current stored schema version (0.0 if never initialized).          |
//+------------------------------------------------------------------+
double SM_GetAccountSchemaVersion()
  {
   return SM_GetAccountDouble("schema_version", 0.0);
  }

//+------------------------------------------------------------------+
//| Ensure the account-wide record set matches SM_SCHEMA_VERSION.      |
//|                                                                    |
//| Per section 8: a version mismatch performs a TARGETED migration —  |
//| it may only add fields that did not exist under the old version,   |
//| defaulted to a neutral value; it must never reset or delete a      |
//| still-valid field (in particular, never the daily/weekly equity    |
//| baselines once those fields exist, from a later task onward).      |
//|                                                                    |
//| At schema 1.0 there is nothing to migrate from (this is the first  |
//| version) — calling this simply stamps the version on first use.    |
//| Future schema bumps extend the if-chain below additively; they     |
//| must not remove an existing branch or add a blanket reset.         |
//+------------------------------------------------------------------+
void SM_EnsureAccountSchema(const int lock_timeout_ms = 500)
  {
   double stored = SM_GetAccountSchemaVersion();
   if(stored == SM_SCHEMA_VERSION)
      return; // already current — no-op, nothing touched.

   double owner_token;
   if(!SM_AcquireAccountLock(owner_token, lock_timeout_ms))
      return; // caller may retry on a later tick; never blocks trading.
   SM_StampAccountLockHeld();

   // stored == 0.0 means "never initialized" — first run on this
   // account+server. Every future migration branch below must be
   // additive only (see header comment).
   if(stored == 0.0)
     {
      // No pre-existing fields to preserve; just stamp the version.
      KE_SetDoubleChecked(SM_AccountKey("schema_version"), SM_SCHEMA_VERSION);
     }
   // else if(stored == 1.0 && SM_SCHEMA_VERSION == 2.0) { ... additive
   //    migration for a future schema bump goes here ... }

   SM_ReleaseAccountLock(owner_token);
  }
