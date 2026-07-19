# CANDLESTICK PATTERN SPECIFICATION

Every pattern must be defined with OHLC mathematics, ATR normalization, context, location, confirmation, invalidation, and age.

Initial patterns:

- Bullish and bearish pin bars.
- Hammer and shooting star.
- Dragonfly and gravestone rejection.
- Displacement or marubozu candle.
- Doji and spinning top as filters.
- Bullish and bearish engulfing.
- Inside and outside bars.
- Tweezer top and bottom.
- Morning and evening star.
- Three white soldiers and three black crows.
- Three-bar reversal.

Required fields:

- pattern_id
- name
- direction
- first_bar_time
- last_bar_time
- body_ratio
- wick_ratios
- atr_ratio
- relative_size
- context
- location
- confirmation
- confidence
- invalidation
- status

Rules:

- Never trade the name alone.
- Use completed candles.
- Require context.
- Draw stable labels.
- Avoid duplicate labels.
- Validate custom rules in Python.
