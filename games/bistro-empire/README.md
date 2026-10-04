# Bistro Empire

An incremental restaurant tycoon. Start with one table in a corner diner, grow it into a franchise empire across 30 cities, then sell the company for stars and do it all again, stronger.

**Play:** https://jprier.github.io/GameTests/bistro-empire/

Mobile first: portrait layout, everything is a tap, tabs sit at the bottom within thumb reach, lists scroll with a drag (a drag never buys), and the Buy buttons repeat while held. Progress saves to browser storage every few seconds, and you earn a share of your income while away.

## How it plays

Running a restaurant is a fight. The first runs are an uphill battle to stay in business, and sloppy play goes bankrupt. Every sale or bankruptcy makes the next run easier.

Sales per second = guests served × bill × price × multipliers. Profit is what's left after running costs.

- **Ad Campaigns** bring guests in, **Tables** seat them, **Line Cooks** feed them, **Recipes** raise every bill.
- You serve as many guests as the weakest of guests, seats and kitchen allows. That one is your **bottleneck**, marked **LIMIT** in red. Buying more of it moves the limit to whatever is next weakest. Buying more of the limit never brings the limit back to it.
- **Everything costs money to run.** Every seat pays rent, every cook is paid, every ad costs money, and every plate needs food, busy or not. A lopsided restaurant bleeds money. Each Buy button shows what it does to your **profit** (green if it helps, orange if it would cost you), and the Profit & loss card on the Build tab shows where the money goes.
- **Menu prices** (unlocked by the Price Tags upgrade, or from the start for Fine Dining) turn a queue into profit: higher prices mean fewer guests but bigger bills, up to your brand's price limit. Ads are the catch: the higher your price, the more ads it takes to fill the room. The Floor Manager prices to fill every seat; with it on, extra guests show up as a higher price, so the limit shown is seats or kitchen.
- **A little slack is insurance.** A kitchen or dining room running flat out invites trouble (see events below). Spare capacity costs money but keeps you safe.
- **Tap the restaurant** to serve by hand. Each serve pays a bill plus a quarter-second of income. During a slump it counts at least half your best income this run, so taps stay worth making. Serving upgrades add more seconds per tap, and the Café's serves are worth 10× plus an extra second of income.

## Strategy

- **Concepts.** Each run you pick a concept, and each one plays differently:
  - **Diner**: forgiving. Running costs 8% lower and +25% income.
  - **Fast Food**: volume. Cheap food and rent, tiny bills, price-shy guests, and kitchens that run hot, so inspections come more often.
  - **Fine Dining**: margins. Prices from the first second, huge bills, but pricey food, rent and chefs, and critics and reviews hit twice as hard. Unlocks after your first sale or bankruptcy.
  - **Café**: taps are worth 10× and earn a second of income each, but margins are thin. Unlocks after two.

  The concept picker shows each one's food, rent, wage and ad costs and its price limit, so the best build order differs from the first minute.

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

**Every business has its own page.** The Business tab lists the bank and your businesses, each with its income, how much of its market it has captured, and a badge for upgrades ready to buy. Tap one to open its page:

- The top of the screen becomes that business's own animated scene (the truck drives between spots, ovens glow, the bar crowd gets rowdy, hotel windows light up with occupancy, the wholesale price line moves), with its sales, costs and market share underneath. Tapping the scene sells by hand.
- Below that are its twist controls, the market meter, its two builds, its automation (manager and Expansion Manager toggles) and its own upgrades, including what unlocks next.
- Business upgrades live only on their business's page. The Upgrades tab keeps the restaurant's and the company-wide ones.
- Tap Back, the Business tab again, or Escape to return to the list.

**How businesses scale.** Everything about a business is measured against your restaurant's best income this run (ignoring events), so a truck matters as much at $1B/s as at $1K/s:

- Each build adds a fixed share of that income, and its price is a number of seconds of it, rising about 5% per build. The first builds pay back in a minute or two, and each buy button shows its payback time.
- Milestones (10, then every 25 up to 1,000) give that business ×1.5, and its upgrades are priced in seconds of income too.
- **Market saturation.** Each business's sales level off as it fills its market, which is worth up to 20% of your restaurant's best sales this run. Company-wide upgrades and a Grit perk grow it with diminishing returns, up to 30%. Running costs keep rising, so overbuilding loses money. A well-run business adds 10–30% on top of the restaurant's profit. No business can outgrow the restaurant that feeds it, and upgrading the restaurant grows every market.
- Each business has an optional manager that runs its twist, and an **Expansion Manager** (from 25 builds) that buys whichever build pays back fastest, using at most a quarter of your cash.

## Money out: expenses, loans and events

- **Expenses.** Your restaurant pays for:
  - Food for every plate served (35% of a plate's base value, adjusted by concept).
  - Rent on every seat.
  - Wages for every cook.
  - Ads for every guest they bring in.
  - Insurance, if you buy it.

  Costs are measured against a plate's base value. Price never adds to them, so raising prices widens your margin. Franchise royalties carry half the costs. Stars and Grit widen your margin too, but only by their square root, so costs matter in every run.
- **Bank.** In the Business tab you can borrow up to 10 minutes of income to expand faster. Interest comes out of profit every second, and the rate climbs as you max out your credit.
- **Events are consequences.** Every few minutes something happens. It opens as a pop-up you have to answer. There's no timer, and taps in its first moment are ignored, so a stray tap can't pick for you. Bad events come from how you run things:
  - Kitchen at full stretch (over 70% busy): inspections, freezer breakdowns, walkouts, food poisoning.
  - Packed dining room: slip-and-fall lawsuits, the fire marshal.
  - Turning guests away: viral bad reviews, an angry queue.
  - Heavy borrowing: the bank wants a word.
  - Some, like a power cut, are just bad luck.

  The card says why it happened and how to avoid it, and the odds of any gamble depend on the same risk. A riskier restaurant also gets into trouble sooner. A calm, well-run restaurant gets more good news (critics, celebrities, tour buses) and passes inspections outright. Bills are measured in seconds of your profit.
- **Hedges.** Spare capacity keeps the risk low. **Insurance** (in the Bank card) pays 75% of every event bill for 2.5% of your sales. Keeping some cash in the bank covers the rest.
- **Bankruptcy.** If cash drops below $0, the strip under the restaurant turns red with a 5-minute countdown. It replaces the stats strip, so nothing on screen moves. Tap it for your options: take an emergency loan, sell a franchise location, sell a side business, or file. If you can't recover, the whole empire goes bankrupt:
  - The run resets, like selling the company.
  - You get **Grit** instead of stars, and the stars this run would have paid are lost. Even an early bust pays some Grit.
  - Each Grit adds +1% income and buys Grit perks: 73 perks across 10 lines, including cheaper fines, a bigger credit limit, lower interest, leaner costs, a longer deadline, bigger markets and luckier events.

  You can also file for bankruptcy yourself while you're in the red. Bankruptcies count towards unlocking concepts, the same as sales.
- **Updating mid-run.** A run saved under the old, easier rules gets 10 minutes with no bankruptcy clock and no events to rebalance, and a one-time note explaining what changed.
- **Nothing jumps.** Events and the in-the-red options are pop-ups. The bank, the Profit & loss card, the "Buy all" bars, and each business page's automation and upgrade sections keep the same size whatever happens, so a button is never pushed out from under your thumb.

## Upgrades: 1,726 in total

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
| Side businesses (6 × 67, plus 10 company-wide) | 412 |
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
- `events.gd`: the events, what makes each one likely (kitchen strain, crowding, queues, debt), and how their choices resolve.
- `main.gd`: input, layout and immediate-mode drawing. The scrolling list is a clipped child `Control`, and pop-ups draw on an overlay `Control`.
- `tools/sim.gd`: a greedy bot that plays the economy headless and prints pacing. It isn't exported. Run it with `godot --headless --path . --script res://tools/sim.gd -- hours=8 concept=diner`. It takes options `noprestige=1`, `nobiz=1`, `events=0`, `reserve=SECONDS` (cash it keeps for emergencies), `taps=N`, `stars=N` and `policy=`:
    - `greedy` (default) buys whatever pays back fastest. It makes its first sale after about 70 minutes and occasionally goes bankrupt.
    - `skilled` also keeps spare capacity, insures and holds a bigger reserve. It survives and sells after 80–110 minutes.
    - `random` and `cheapest` click whatever they can afford. They go bankrupt within the first hour or two, which is the point.
- Agent hooks:
  - `get_agent_state()`
  - `press_button("rep:tables")` (any button id)
  - `dev_add_cash(x)`
  - `dev_skip(seconds)`
  - `dev_event("lawsuit")` (any id from `events.gd`)

Tests: `gck test bistro-empire` (`tests/test_main.gd`, 63 tests). They cover the bottleneck never flipping back to guests as you buy guests, every stat costing money to run (a lopsided restaurant loses money), events following kitchen strain, crowding, queues and debt (and the odds changing with it), insurance, businesses never outgrowing the restaurant, nothing on screen moving when an event, debt or the red banner appears, older saves getting a grace period, each business's page, business payback staying under an hour, expenses, loans, every event and both of its choices, timed effects, the deadline and bankruptcy, Grit perks, each business's twist run live, a real player's save from before these systems loading cleanly, save safety (checksums, fallback to the second copy and the backups, quarantine of unreadable saves, loading the old format, export and import, frozen upgrade keys), crediting time spent in the background, the catalogue size and uniqueness, bottleneck and pricing maths, crossroads locks, concepts, franchises and ventures, prestige, saving and offline earnings, and the UI: tap to buy, a drag doesn't buy, and the whole sell-and-pick-a-concept flow.
