# NEWS INTEGRATION SPECIFICATION

## Markets

Metals:
- Use news controls.
- MT5 Economic Calendar is the primary structured live source.
- Historical CSV/SQLite is required for deterministic backtests.
- Optional Fair Economy adapter is secondary and cached.

Deriv synthetic indices:
- Use `NullNewsProvider`.
- Do not apply macroeconomic event direction or blackout logic.

## Provider interface

Each provider returns:

- event_id
- event_name
- currency
- importance
- scheduled_utc
- scheduled_server_time
- scheduled_botswana_time
- previous
- forecast
- actual
- revision
- source
- retrieved_at
- status

## Initial policy

- Block new metal entries around high-impact relevant events.
- Do not predict event direction.
- Do not widen stops.
- Resume only after the blackout and spread normalization.
- Post-news displacement trading is disabled until tested separately.
- Provider failure uses the configured fail-safe policy and is logged.

## Backtesting

- Store historical events in SQLite or CSV.
- Do not rely on live `WebRequest` in Strategy Tester.
- Repeated tests must produce identical event decisions.
