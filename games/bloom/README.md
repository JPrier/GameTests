# Bloom

A daily Conway's Game of Life puzzle. Everyone gets the same map each day: plant a handful of seed cells in the green zone, run Life for 150 generations, and score Impact — every cell your colony touches, plus 5 for each gold star it reaches. Three tries a day; your best counts.

When you finish, **Share score** sends your result with a link (`?d=<date>&s=<score>`) that opens the same day's map for the receiver, with your score shown as the one to beat. On phones it opens the share sheet; on desktop it copies to the clipboard.

- Daily map: seeded from the local date (`generate()` in `main.gd`); puzzle #1 is 2026-10-01.
- Rules: B3/S23 on a bounded 28×28 grid; walls are always dead.
- Progress is saved per day in browser storage, so a reload keeps your tries.

Tests: `gck test bloom` (tests/test_main.gd).
