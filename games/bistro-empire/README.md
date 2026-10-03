# Bistro Empire

An incremental restaurant tycoon. Start with one table in a corner diner, grow it into a franchise empire across 30 cities, then sell the company for stars and do it all again, stronger.

**Play:** https://jprier.github.io/GameTests/bistro-empire/

Mobile first: portrait layout, everything is a tap, tabs sit at the bottom within thumb reach, lists scroll with a drag (a drag never buys), and the Buy buttons repeat while held. Progress saves to browser storage every few seconds, and you earn a share of your income while away.

## How it plays

Franchise royalties and the business tab ease the mid-game wall, and the first sale of the company now pays about 2.5× more stars (about 25 stars at around an hour in), so selling is worth it sooner.

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

## Side businesses

Run them alongside the restaurant. Each one unlocks as your earnings this run grow, costs money to open, and has two builds plus its own twist. It also has its own running costs, so a badly run business can lose money.

| Business | Twist |
|---|---|
| Food Truck | Choose one of 4 spots. Each spot's crowd changes every 3 minutes, and driving to a new one takes 15s. |
| Bakery | Ovens bake and counters sell. Bread you can't sell goes stale. A morning rush every 4 minutes sells three times as fast, so it pays to keep a little stock. |
| Catering Co. | Take contracts. Each one ties up crew for a set time and pays when it ends, and vans limit how many jobs run at once. Crew are paid whether they're busy or not. |
| Cocktail Bar | Big margins, but a rowdiness meter fills as you serve. When it's full there's a fight: a fine and 10s closed. Bouncers keep the peace. Happy hour sells more drinks for less, and gets rowdier. |
| Boutique Hotel | Set the room rate. The season changes every 4 minutes, and rent is due on every room, full or empty. |
| Wholesale Co. | Stock piles up in warehouses; sell it when the moving market price is high. Delivery trucks cut food costs across the whole empire. |

Each business has an optional manager upgrade that runs its twist for you. Franchising also boosts every business a little through brand fame.

## Money out: expenses, loans and events

- **Expenses.** The restaurant pays four running costs, and the Profit & loss card on the Build tab breaks them down:
  - Food for every plate served.
  - Rent on seats nobody is sitting in.
  - Wages for cooks with nothing to cook.
  - Ads for guests you had to turn away.

  A balanced restaurant runs lean; a lopsided one bleeds money. Raising prices widens your margin, and franchise royalties carry no costs.
- **Bank.** In the Business tab, you can borrow up to 10 minutes of income to expand faster. Interest comes out of profit every second, and the rate climbs as you max out your credit.
- **Random events.** Every few minutes something happens, from an inspection or a lawsuit to a food critic or a tour bus. Each one is a card with a choice and a 45s timer. If you don't answer in time, the default, usually the risky gamble, happens for you. Costs are measured in seconds of your income, so they always matter.
- **Bankruptcy.** If cash drops below $0 you have 5 minutes to recover. You can take an emergency loan, sell a franchise location, or sell a side business. If you can't recover, the whole empire goes bankrupt:
  - The run resets, like selling the company.
  - You get **Grit** instead of stars, and the stars this run would have paid are lost.
  - Each Grit adds +1% income and buys Grit perks: 73 perks across 10 lines, including cheaper fines, a bigger credit limit, lower interest, leaner costs, a longer deadline, stronger businesses and luckier events.

  You can also file for bankruptcy yourself while you're in the red. Bankruptcies count towards unlocking concepts, the same as sales.

## Upgrades: 1,564 in total

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
| Side businesses (6 × 40, plus 10 for every business) | 250 |
| Grit perks (bought with Grit) | 73 |

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

- `econ.gd`: all rules, the upgrade catalogue, expenses, loans, bankruptcy, saving to and loading from a dictionary, and number formatting. No rendering.
- `biz.gd`: the side businesses. `step()` simulates each twist in real time; `estimate()` gives steady-state rates for display, offline time and the balance bot.
- `events.gd`: the random events and how their choices resolve.
- `main.gd`: input, layout and immediate-mode drawing. The scrolling list is a clipped child `Control`, and pop-ups draw on an overlay `Control`.
- `tools/sim.gd`: a greedy bot that plays the economy headless and prints pacing. It isn't exported. Run it with `godot --headless --path . --script res://tools/sim.gd -- hours=8 concept=diner`, which takes options `noprestige=1`, `nobiz=1`, `events=0`, `reserve=SECONDS` (cash it keeps for emergencies), `taps=N` and `stars=N`. With the current numbers it makes its first sale after about 45–60 minutes.
- Agent hooks:
  - `get_agent_state()`
  - `press_button("rep:tables")` (any button id)
  - `dev_add_cash(x)`
  - `dev_skip(seconds)`
  - `dev_event("lawsuit")` (any id from `events.gd`)

Tests: `gck test bistro-empire` (`tests/test_main.gd`, 51 tests). They cover expenses, loans, every event and both of its choices, timed effects, the deadline and bankruptcy, Grit perks, each business's twist run live, a real player's save from before these systems loading cleanly, save safety (checksums, fallback to the second copy and the backups, quarantine of unreadable saves, loading the old format, export and import, frozen upgrade keys), crediting time spent in the background, the catalogue size and uniqueness, bottleneck and pricing maths, crossroads locks, concepts, franchises and ventures, prestige, saving and offline earnings, and the UI: tap to buy, a drag doesn't buy, and the whole sell-and-pick-a-concept flow.
