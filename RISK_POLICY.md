# RISK POLICY

Research defaults:

- XAUUSD: 0.25% risk per trade.
- Other metals: 0.25%–0.50%.
- Synthetic indices: 0.25%–0.50%.
- Hard per-trade cap: 1.00%.
- Hard total open-risk cap: 1.00%.
- Daily loss cap: 2.00%.
- Weekly loss cap: 4.00%.
- Consecutive-loss cooldown: 3 losses.
- No martingale.
- No grid.
- No averaging down.
- Add-ons and multi-leg baskets are disabled until independently proven.
- Reject broker minimum volume when actual risk exceeds the cap.
- Use `OrderCalcProfit` to cross-check risk.
- Validate tick value, tick size, contract size, volume step, stop level, freeze level, filling mode, and margin.
- Close all exposure by the approved intraday boundary.
- Never widen a stop merely to avoid a loss.
- Never increase risk after a loss.
