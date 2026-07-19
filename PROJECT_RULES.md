# PROJECT RULES — Themba Adaptive Intraday Engine

1. Preserve both original EAs as immutable baselines.
2. No direct edits to main, develop, baseline, demo-approved, or live-approved releases.
3. No martingale, grid recovery, averaging down, or loss-chasing.
4. No future-candle access or repainting.
5. Confirmed pattern logic uses completed candles.
6. Every signal, rejection, order, modification, and exit receives a machine-readable reason.
7. Metals and synthetic indices use separate profiles.
8. Macroeconomic news filters apply to metals, not Deriv synthetic indices.
9. Live code never rewrites itself.
10. Learning is offline, versioned, bounded, reviewed, and reversible.
11. MetaEditor is the compilation authority.
12. MT5 Strategy Tester and demo forward tests are behavioural authorities.
13. Every experiment must identify its Git commit, set file, data period, modelling mode, symbol, broker, and costs.
14. Failed experiments remain documented.
15. One major behavioural change per experiment.
16. Risk controls have priority over strategy signals.
17. No trade is a valid and often preferred decision.
18. Never claim guaranteed profitability.
