# TEST PLAN

## Baseline
Run both old EAs unchanged and archive all reports.

## Candidate
Use identical symbols, periods, data, costs, and broker settings.

## Metrics
- Net profit
- Profit factor
- Expectancy
- Max balance drawdown
- Max equity drawdown
- Equity-peak giveback
- Recovery factor
- Average win/loss
- Longest losing streak
- MFE/MAE
- Duration
- Trades per day
- Results by setup/regime/mode/session/symbol/news state
- Spread and slippage sensitivity

## Partitions
- Development
- Validation
- Untouched out-of-sample
- Demo forward

## Robustness
- Neighbouring parameters
- Multiple periods
- Multiple symbols
- Spread stress
- Slippage stress
- Delay
- Restart
- Missing news
- Low balance
- Minimum lot
- Netting and hedging
- Intraday close
- Time-zone changes

## Release rejection
Reject a candidate that:
- Raises profit through unacceptable drawdown.
- Depends on one short period.
- Fails out of sample.
- Has unstable neighbouring parameters.
- Hides failed configurations.
- Repaints.
- Cannot explain its trades.
