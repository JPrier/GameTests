# Bistro Empire

An incremental restaurant tycoon. Start with one table in a corner diner, grow it into a franchise empire across 30 cities, then sell the company for stars and do it all again, stronger.

**Play:** https://jprier.github.io/GameTests/bistro-empire/

Mobile first: portrait layout, everything is a tap, tabs sit at the bottom within thumb reach, lists scroll with a drag (a drag never buys), and the Buy buttons repeat while held. Progress saves to browser storage every few seconds, and you earn a share of your income while away.

## How it plays

A normal run can't lose money: income per second = guests served × bill × price × multipliers, with no running costs. If you want a fight, **Challenges** (below) turn on running costs, loans and the risk of going bust, and pay Grit.

- **Ad Campaigns** bring guests in, **Tables** seat them, **Line Cooks** feed them, **Recipes** raise every bill.
- You serve as many guests as the weakest of guests, seats and kitchen allows. That one is your **bottleneck**, marked **LIMIT** in red. Buying more of it moves the limit to whatever is next weakest. Buying more of the limit never brings the limit back to it.
- **Synergy upgrades** make one build boost another stat (Reservations by Ad: every Ad Campaign you own adds seats). Each build row spells this out: what the buy adds to its own stat, then "Also +… seats" for anything else it changes.
- Each Buy button shows what it does to your income (green if it helps, grey if it does nothing right now). In a challenge it shows profit, and turns orange when a buy would cost more to run than it earns.
- **Menu prices** (unlocked by the Price Tags upgrade, or from the start for Fine Dining) turn a queue into profit: higher prices mean fewer guests but bigger bills, up to your brand's price limit. In a challenge, ads are the catch: the higher your price, the more ads it takes to fill the room. The Floor Manager prices to fill every seat; with it on, extra guests show up as a higher price, so the limit shown is seats or kitchen.
- **A little slack keeps trouble away.** A kitchen or dining room running flat out invites bad events (see below).
- **Tap the restaurant** to serve by hand. Each serve pays a bill plus a quarter-second of income. During a slump it counts at least half your best income this run, so taps stay worth making. Serving upgrades add more seconds per tap, and the Café's serves are worth 10× plus an extra second of income.

## Strategy

- **Concepts.** Each run you pick a concept, and each one plays differently:
  - **Diner**: forgiving. +25% income and cheap tables.
  - **Fast Food**: volume. Huge crowds and kitchens, tiny bills, price-shy guests, and kitchens that run hot, so inspections come more often.
  - **Fine Dining**: prices from the first second and huge bills, but tables and cooks cost 40% more, and critics and reviews hit twice as hard. Unlocks after your first sale.
  - **Café**: taps are worth 10× and earn a second of income each, but other income is 10% lower. Unlocks after two sales.

  Each concept also has its own running-cost profile, which the concept picker shows in a challenge. Concepts unlock with sales (bankruptcies from before challenges existed still count).

  Each concept also has 30 signature upgrades of its own.
- **Crossroads.** 40 pairs of upgrades where buying one locks the other until you sell. Some examples:
  - Union Kitchen (big kitchen boost, pricier cooks) or Gig Cooks (cheap cooks).
  - Corporate Chain (royalties) or Owner-Operators (cheap franchises).
  - Open 24/7 (big income boost, everything costs more) or Weekends Off.

  Some of them help one concept far more than another.
- **Franchises.** 30 cities. Each location adds royalties that multiply all income, later cities pay far more per location, and every city has 8 milestone upgrades.
- **Ventures.** At 15 locations you unlock 8 side businesses, from food trucks to a Global Spice Co. Each one boosts a single stat per level.
- **Selling the company.** You get stars from lifetime earnings. Selling resets the run but keeps your stars and your **Legacy perks** (80 tiers across 9 lines), which you buy with stars. Every star you have ever earned adds +2% income for good, so spending stars on perks never lowers your bonus. Knowing when to sell is the main long-term decision.

## Side businesses

Run them alongside the restaurant. Each one unlocks as your earnings this run grow, costs money to open, and has two builds plus its own twist. In a challenge each business also has running costs (crew, rent, fines), so a badly run one can lose money.

| Business | Twist |
|---|---|
| Food Truck | Choose one of 4 spots. Each spot's crowd changes every 3 minutes, and driving to a new one takes 15s. |
| Bakery | Ovens bake and counters sell. Bread you can't sell goes stale. A morning rush every 4 minutes sells three times as fast, so it pays to keep a little stock. |
| Catering Co. | Take contracts. Each one ties up crew for a set time and pays when it ends, and vans limit how many jobs run at once. In a challenge, crew are paid whether they're busy or not. |
| Cocktail Bar | Big margins, but a rowdiness meter fills as you serve. When it's full there's a fight: the bar shuts for 30s (in a challenge, 10s and a fine). Bouncers keep the peace. Happy hour sells more drinks for less, and gets rowdier. |
| Boutique Hotel | Set the room rate. The season changes every 4 minutes. Empty rooms earn nothing and a half-empty hotel earns less per guest (in a challenge, rent is due on every room instead). |
| Wholesale Co. | Stock piles up in warehouses; sell it when the moving market price is high. Delivery trucks boost the restaurant's income by up to 15% (in a challenge they cut food costs across the empire instead). |

**Every business has its own page.** The Business tab lists your businesses (and the bank, in a challenge), each with its income, progress to its next milestone, and a badge for upgrades ready to buy. Tap one to open its page:

- The top of the screen becomes that business's own animated scene (the truck drives between spots, ovens glow, the bar crowd gets rowdy, hotel windows light up with occupancy, the wholesale price line moves), with its sales, what it has earned this run (its costs, in a challenge) and its next milestone underneath. Tapping the scene sells by hand.
- Below that are its twist controls, a growth card (next milestone, what its upgrades and your stars and Grit multiply it by), its two builds, its automation (manager and Expansion Manager toggles) and its own upgrades, including what unlocks next.
- Business upgrades live only on their business's page. The Upgrades tab keeps the restaurant's and the company-wide ones.
- Tap Back, the Business tab again, or Escape to return to the list.

**How businesses scale: on their own.** A business doesn't depend on the restaurant at all. It has its own fixed prices and earnings (bigger for the ones that unlock later), so it costs the same to open after your tenth sale as after your first, and restaurant upgrades never change it. It grows through:

- **Its own builds.** Each build adds income; prices rise about 12% per build. The first builds pay back in seconds, and each buy button shows its payback time.
- **Its own upgrades.** Milestones (10, then every 25 builds, forever) give that business ×1.5, extras along the way give ×1.3, and company-wide upgrades give every business ×1.25. All of these go on forever.
- **Prestige.** Stars, Grit and Grit's Battle-Tested perk multiply every business exactly as they multiply the restaurant.
- Each business has an optional manager that runs its twist, and an **Expansion Manager** (from 25 builds) that buys whichever build pays back fastest, using at most a quarter of your cash.

## Events

Every few minutes something happens. It opens as a pop-up you have to answer. There's no timer, and taps in its first moment are ignored, so a stray tap can't pick for you. In a normal run a bill can never take you below $0. If you can't cover it, you pay what you have and the rest comes out of income: half your income for long enough to make up the difference. Choices that would only raise running costs (the supplier price hike, a walkout's raises) cost income instead. Managers don't spend your cash while a pop-up is waiting.

Bad events come from how you run things:
- Kitchen at full stretch (over 70% busy): inspections, freezer breakdowns, walkouts, food poisoning.
- Packed dining room: slip-and-fall lawsuits, the fire marshal.
- Turning guests away: viral bad reviews, an angry queue.
- Heavy borrowing (challenges only): the bank wants a word.
- Some, like a power cut, are just bad luck.

The card says why it happened and how to avoid it, and the odds of any gamble depend on the same risk. A riskier restaurant also gets into trouble sooner. A calm, well-run restaurant gets more good news (critics, celebrities, tour buses) and passes inspections outright. Bills are measured in seconds of your income.

## Challenges and Grit

Challenges are optional runs, started from the Legacy tab, where you can actually lose. Each one has endless levels. Reach the level's goal (earn $X in one run), then sell the company to collect Grit as well as your stars. The more you earned, the more Grit, and harder challenges and higher levels multiply it.

| Challenge | Rules | Grit |
|---|---|---|
| Tight Margins | Running costs and the risk of going bust | ×1 |
| Health Code | Tight Margins, bad events cost twice as much, no insurance | ×1.5 |
| Shoestring | Tight Margins, no bank (no loans or insurance), no Legacy starting cash | ×1.75 |
| One Restaurant | Tight Margins, no side businesses or franchises | ×2 |
| Recession | Tight Margins, price limit halved, running costs 20% higher | ×2 |

Each level's goal is 1,000× the last, each level's running costs are 15% higher than the one before, and Grit grows by half per level. Earnings past 20× the goal don't add more Grit, so climbing levels pays better than farming one.

- **Running costs.** In a challenge the restaurant pays for food on every plate (35% of a plate's base value, adjusted by concept), rent on every seat, wages for every cook and ads for every guest they bring in, busy or not. A lopsided restaurant bleeds money, and the Profit & loss card shows where it goes. Costs are measured against a plate's base value, so raising prices widens your margin. Franchise royalties carry half the costs. Stars and Grit widen your margin too, by their square root.
- **Bank.** Borrow up to 10 minutes of income to expand faster. Interest climbs as you max out your credit. **Insurance** pays 75% of every event bill for 2.5% of your sales.
- **Going bust.** If cash drops below $0, the strip under the restaurant turns red with a 5-minute countdown (it replaces the stats strip, so nothing moves). Tap it for options: an emergency loan, selling a franchise location or a side business, or giving up. If time runs out, the challenge is over and you're back to a normal run. Nothing else is lost: that run's earnings still count towards your next sale's stars.
- **Grit.** Every Grit you have ever earned adds +1% income for good, even after you spend it. Spend it on Grit perks (73 tiers across 10 lines to start, each tier 4× the price of the last, and every line goes on forever past them). Every line helps in normal runs, and some carry a smaller part marked "(challenges)" that only matters there:

  | Perk | Every run | Challenges |
  |---|---|---|
  | Battle-Tested | All income ×1.5 | |
  | Thick Skin | Guests ×1.25, event bills ×0.85 | |
  | Supplier Credit | All build prices ×0.85 | Credit limit ×1.4 |
  | Trusted Name | Franchise prices ×0.8 | Loan interest ×0.85 |
  | Lean Operations | Seats and kitchen ×1.4 | Running costs ×0.9 |
  | Supply Chain | Bills ×1.5 | Food costs -2 pts |
  | Second Wind | Start with +5 of each build | +60s to recover from the red |
  | Side Hustle | All business income ×1.4 | |
  | Lucky Break | +6% good events, restaurant income ×1.15 | |
  | Know Your Worth | Price limit ×1.2 | +8% back when selling off |
- **Updating.** Saves from the version where costs applied to every run load as normal runs: any debt is forgiven, and a one-time note explains what changed.

## Interface

- **Text always fits.** Nothing is ever cut off with "...". Text with a fixed slot shrinks a little to fit, longer text wraps, and every row reserves a line for each thing it shows, so nothing overlaps. Tests check this on every screen.
- **Nothing jumps.** Events and the in-the-red options are pop-ups. The bank, the income card, the "Buy all" bars, and each business page's automation and upgrade sections keep the same size whatever happens, so a button is never pushed out from under your thumb.

## Upgrades: 1,726 in total

| Kind | Count |
|---|---|
| Stat tiers (demand, seating, kitchen, menu dishes) | 240 |
| Ambience (all income) | 60 |
| Build milestones (25 → 2,000 of each build) | 84 |
| Synergies (one build boosts another stat) | 60 |
| Discounts (cheaper builds) | 40 |
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
- `tools/sim.gd`: a greedy bot that plays the economy headless and prints pacing. It isn't exported. Run it with `godot --headless --path . --script res://tools/sim.gd -- hours=8 concept=diner`. It takes options `noprestige=1`, `nobiz=1`, `events=0`, `reserve=SECONDS` (cash it keeps for emergencies), `taps=N`, `stars=N`, `challenge=ID` (play level I of a challenge, e.g. `challenge=margins`) and `policy=`:
    - `greedy` (default) buys whatever pays back fastest. In normal runs it first sells after about 40–50 minutes, and each sale after that comes faster.
    - `skilled` also keeps spare capacity, insures and holds a bigger reserve. With no stars it reaches Tight Margins level I in about 85 minutes; Health Code can still bankrupt it.
    - `random` and `cheapest` click whatever they can afford. In a challenge they go bust within an hour or two.
- Agent hooks:
  - `get_agent_state()`
  - `press_button("rep:tables")` (any button id)
  - `dev_add_cash(x)`
  - `dev_skip(seconds)`
  - `dev_event("lawsuit")` (any id from `events.gd`)

Tests: `gck test bistro-empire` (`tests/test_main.gd`, 90 tests). They cover normal runs never losing money (no costs, no bank, event bills capped at your cash with the shortfall taken from income, cash floored at $0), every Grit perk line doing something in a normal run and labelling its challenge-only part, cost-only event choices turning into income penalties, the bar and hotel still having teeth without costs, Wholesale trucks boosting income, Fine Dining's pricier builds, challenge-only buttons doing nothing in a normal run, managers waiting while a pop-up is open, build rows explaining synergy upgrades, challenges (rules per challenge, goals, Grit on completion, rewards capped at 20× the goal, levels getting harder, going bust only ending the run and not unlocking concepts, saving), star and Grit bonuses counting everything ever earned, old saves having debt forgiven, text never overlapping, running off screen, spilling out of or under a button, or shrinking too small to read (16 tests walk every tab and filter top to bottom, every business page, every pop-up and event, and challenge runs, at 360px and 412px wide, early in a run and with enormous numbers), the bottleneck never flipping back to guests as you buy guests, every stat costing money to run in a challenge (a lopsided restaurant loses money), events following kitchen strain, crowding, queues and debt (and the odds changing with it), insurance, businesses never outgrowing the restaurant, nothing on screen moving when an event, debt or the red banner appears, each business's page, business payback staying under an hour, expenses, loans, every event and both of its choices, timed effects, the deadline and bankruptcy, Grit perks, each business's twist run live, a real player's save from before these systems loading cleanly, save safety (checksums, fallback to the second copy and the backups, quarantine of unreadable saves, loading the old format, export and import, frozen upgrade keys), crediting time spent in the background, the catalogue size and uniqueness, bottleneck and pricing maths, crossroads locks, concepts, franchises and ventures, prestige, saving and offline earnings, and the UI: tap to buy, a drag doesn't buy, and the whole sell-and-pick-a-concept flow.
