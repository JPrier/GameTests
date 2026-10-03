# Bistro Empire

An incremental restaurant tycoon. Start with one table in a corner diner, grow it into a franchise empire across 30 cities, then sell the company for stars and do it all again, stronger.

**Play:** https://jprier.github.io/GameTests/bistro-empire/

Mobile first: portrait layout, everything is a tap, tabs sit at the bottom within thumb reach, lists scroll with a drag (a drag never buys), and the Buy buttons repeat while held. Progress saves to browser storage every few seconds, and you earn a share of your income while away.

## How it plays

Income per second = guests served × bill × price × multipliers.

- **Ad Campaigns** bring guests in, **Tables** seat them, **Line Cooks** feed them, **Recipes** raise every bill.
- You can only serve as many guests as the weaker of seats and kitchen allow, and only as many as want to come. Whichever is smallest is your **bottleneck**, marked **LIMIT** in red. Money spent elsewhere is mostly wasted until it moves.
- **Menu prices** (unlocked by the Price Tags upgrade) trade guests for profit: higher prices shrink the queue but raise every bill, up to your brand's price limit. The best price is roughly where guests just match capacity. The Floor Manager can set it for you.
- **Tap the restaurant** to serve by hand. Worth a lot early, and a whole strategy for the Café.

## Strategy

- **Concepts.** Each run you pick a concept, and each one plays differently:
  - **Diner**: balanced.
  - **Fast Food**: huge volume and tiny bills, so price-sensitive guests.
  - **Fine Dining**: few seats and huge bills, so pricing matters a lot. Unlocks after your first sale.
  - **Café**: taps are worth 10× and earn a share of income, rewarding active play. Unlocks after two sales.

  Each concept also has 30 signature upgrades of its own.
- **Crossroads.** 40 pairs of upgrades where buying one locks the other until you sell. Some examples:
  - Union Kitchen (big kitchen boost, pricier cooks) or Gig Cooks (cheap cooks).
  - Corporate Chain (royalties) or Owner-Operators (cheap franchises).
  - Open 24/7 (big income boost, everything costs more) or Weekends Off.

  Some of them help one concept far more than another.
- **Franchises.** 30 cities. Each location adds royalties that multiply all income, later cities pay far more per location, and every city has 8 milestone upgrades.
- **Ventures.** At 15 locations you unlock 8 side businesses, from food trucks to a Global Spice Co. Each one boosts a single stat per level.
- **Selling the company.** You get stars from lifetime earnings, and each star adds +2% income. Selling resets the run but keeps your stars and your **Legacy perks** (80 tiers across 9 lines), which you buy with stars. Knowing when to sell is the main long-term decision.

## Upgrades: 1,241 in total

| Kind | Count |
|---|---|
| Stat tiers (demand, seating, kitchen, menu dishes) | 240 |
| Ambience (all income) | 60 |
| Build milestones (25 → 2,000 of each build) | 84 |
| Synergies (one build boosts another stat) | 60 |
| Savings (cheaper builds) | 40 |
| Serving (tap power) | 40 |
| Brand (price limit, pricing unlock) | 25 |
| Managers (automation) and Night Shift (offline earnings) | 16 |
| Franchise royalties and lawyers | 60 |
| City milestones (30 cities × 8) | 240 |
| Venture milestones (8 × 12) | 96 |
| Concept signatures (4 × 30) | 120 |
| Crossroads (40 pairs) | 80 |
| Legacy perks (bought with stars) | 80 |

## Saving and offline time

- **Leaving the game.** The browser pauses the game when you switch apps, lock your phone or hide the tab. The game saves the moment the page is hidden. When you come back:
  - A gap of up to a minute is paid in full.
  - A longer gap is paid at the offline rate. That starts at 25% for up to 2 hours, and Night Shift upgrades and Legacy perks raise it.
  - Closing the tab or reloading the page works the same way.
- **Two copies of every save.** Each save goes to Godot's `user://` files (IndexedDB) and to `localStorage`. The `localStorage` write is synchronous, so it survives the tab being killed straight away.
- **Rolling backups.** Each of the two copies also keeps a backup of the previous save, refreshed every 2 minutes.
- **Checks on loading:**
  - Every copy carries a checksum, and a truncated or corrupt copy is ignored. The newest valid copy wins.
  - If nothing can be read, the unreadable files are moved aside, never overwritten.
  - The game refuses to write a save with lower lifetime earnings than the one it loaded.
- **Persistent storage.** The game asks the browser for persistent storage, so it shouldn't evict the save when space runs low.
- **Your own backup.** More → Your save has three options:
  - **Copy save code**: copies a compressed text code you can keep anywhere.
  - **Download backup**: saves the same code as a file.
  - **Restore from a save code**: loads a code. It shows what's in the code first and keeps your current game as a backup.

  This is the only thing that survives the browser wiping site data, for example after clearing your history, or Safari after about 7 days without a visit.
- **Rebuilds don't touch saves.** Saves live in the browser, not the build. To keep old saves loading:
  - Upgrades are saved by key, and a test checks that all 1,241 keys still exist in every build.
  - The original save format still loads.
  - A test pins `application/config/name`, which on the web decides where `user://` lives, and the `localStorage` key. Never rename either.

## Code

- `econ.gd`: all rules, the upgrade catalogue, saving to and loading from a dictionary, and number formatting. No rendering.
- `main.gd`: input, layout and immediate-mode drawing. The scrolling list is a clipped child `Control`, and pop-ups draw on an overlay `Control`.
- `tools/sim.gd`: a greedy bot that plays the economy headless and prints pacing. It isn't exported. Run it with `godot --headless --path . --script res://tools/sim.gd -- hours=8 concept=diner`, which takes options `noprestige=1`, `taps=N` and `stars=N`. With the current numbers it makes its first sale after about 1h40m.
- Agent hooks:
  - `get_agent_state()`
  - `press_button("rep:tables")` (any button id)
  - `dev_add_cash(x)`
  - `dev_skip(seconds)`

Tests: `gck test bistro-empire` (`tests/test_main.gd`, 32 tests). They cover save safety (checksums, fallback to the second copy and the backups, quarantine of unreadable saves, loading the old format, export and import, frozen upgrade keys), crediting time spent in the background, the catalogue size and uniqueness, bottleneck and pricing maths, crossroads locks, concepts, franchises and ventures, prestige, saving and offline earnings, and the UI: tap to buy, a drag doesn't buy, and the whole sell-and-pick-a-concept flow.
