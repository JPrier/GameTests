# Ticker Time

A daily stock-chart game with two modes. Everyone gets the same charts each day.

**Play:** https://jprier.github.io/GameTests/ticker-time/

## Modes

- **Guess the Year**: five real one-year price charts (January to December), each with its ticker and modern company name. Drag the slider (or use ← →) to pick a year from 1995 to 2025 and lock it in. Points by distance: exact 100, then 80, 60, 45, 30, 20, 10 for 1–6 years off. Max 500. Each day draws one year from each era (1995–2000, 2001–06, 2007–12, 2013–18, 2019–25) in shuffled order.
- **Up or Down**: start with $1,000. Each of five rounds shows a ticker, the company name and its last 12 months of prices, with no dates. Slide your bet (5% to all in, in 5% steps; ← → or 1/2/3 for 25%/50%/all in on a keyboard) and bet up or down. The bet settles on the real price 4 weeks later: you gain or lose your stake times the move (a losing short can't lose more than its stake). Afterwards the dates are revealed. The end screen also shows what perfect all-in calls would have made.

**Share** copies a spoiler-free summary (score, coloured squares, final cash) with a link `?day=YYYY-MM-DD` that opens the same day. Puzzle #1 is 2026-10-02. Progress is saved per day in browser storage.

## Data

`data/stocks.json` holds weekly (Friday) split-adjusted closing prices for 173 well-known current S&P 500 companies, 1995 to Sep 2026, from the [Johnbrick123/sp500-data](https://github.com/Johnbrick123/sp500-data) dataset; company names come from [datasets/s-and-p-500-companies](https://github.com/datasets/s-and-p-500-companies). `data/build_stocks.py` regenerates it (it expects `prices.parquet` and `sp.csv` next to it). A few spin-off artefacts (Altria 2008, Keurig Dr Pepper 2018) are marked and never used. Prices are not dividend-adjusted.

## Dev mode

Hidden in the published build. Open with `?dev=1` (it's on automatically in debug/editor runs), then tap the title 5 times, long-press it, or press `` ` ``. The panel shows the day, seeds and answers, and can jump days (±1, ±30, today, random, any future date), reset the day, reveal answers on the charts, and instantly win or lose. Dev progress is saved separately from real progress. The same controls exist as methods for agents: `dev_set_day("2026-11-05")`, `dev_shift(n)`, `dev_reset()`, `dev_win()`, `dev_lose()`.

Tests: `gck test ticker-time` (tests/test_main.gd): determinism, 60 upcoming days valid, scoring, money maths, saving, share text and dev controls.
