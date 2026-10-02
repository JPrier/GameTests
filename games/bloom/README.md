# Bloom

A daily Conway's Game of Life puzzle. Everyone gets the same map each day: plant a handful of seed cells in the green zone, run Life for 150 generations, and score Impact — every cell your colony touches, plus 5 for each gold star it reaches. Three tries a day; your best counts.

New players get a four-page, plain-language tutorial: what the squares and neighbours are, the 4 rules with before/after pictures, animated examples (block, blinker, glider), then how Bloom scores. The **?** next to the title reopens it.

**Playground:** the chip next to the date opens a free 40×40 board with a shape library (still lifes, blinkers, pulsar, glider, spaceship, R-pentomino, acorn, glider gun), each with a one-line explanation. Draw or stamp shapes, then Play / Step / Reset / Clear.

Planting happens in a zoomed view of the zone (big, easy tap targets on phones) with a small full-map inset; tap the inset to swap views.

When you finish, **Share score** sends your result with a link (`?d=<date>&s=<score>`) that opens the same day's map for the receiver, with your score shown as the one to beat. On phones it opens the share sheet; on desktop it copies to the clipboard.

- Daily map: seeded from the local date (`generate()` in `main.gd`); puzzle #1 is 2026-10-01.
- Rules: B3/S23 on a bounded 56×56 grid (16–28 seeds, 10–14 wide zone); walls are always dead.
- Progress is saved per day in browser storage, so a reload keeps your tries.

Dev menu (hidden): tap the **Bloom** title 5 times quickly, or open with `?dev=1`. It can reset today's progress, or every saved day plus the tutorial-seen flag.

Tests: `gck test bloom` (tests/test_main.gd).
