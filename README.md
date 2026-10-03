# Game Tests

Small Godot games that run in the browser (desktop and mobile).

**Play:** https://jprier.github.io/GameTests/

| Game | Folder |
|---|---|
| Kitchen Crawl: a restaurant-sim roguelike | [`games/kitchen-crawl`](games/kitchen-crawl) |
| Bloom: a daily Game of Life puzzle | [`games/bloom`](games/bloom) |
| Earthquake Test: build a structure, then the same daily quake hits everyone | [`games/earthquake-test`](games/earthquake-test) |
| Daily Bridge: a daily bridge-building physics puzzle | [`games/daily-bridge`](games/daily-bridge) |
| Ticker Time: guess the year of real stock charts, then bet up or down with $1,000 | [`games/ticker-time`](games/ticker-time) |
| Bistro Empire: an incremental restaurant tycoon with 1,241 upgrades, franchises and prestige | [`games/bistro-empire`](games/bistro-empire) |
| X-Ray Shift: a daily airport x-ray game, flag the bags with contraband and find the illegal items | [`games/xray-shift`](games/xray-shift) |

## How deploys work

Every push to `main` runs [`.github/workflows/pages.yml`](.github/workflows/pages.yml), which:

1. installs Godot 4.7.2 and only the web export templates (cached between runs),
2. validates and runs the tests of every project in `games/*/`, failing the build on errors,
3. exports each game to `/<folder>/` and generates the home page,
4. deploys the result to GitHub Pages.

Pull requests run steps 1–3 without deploying.

To add a game, put a Godot project with a `Web` export preset in `games/<name>/` and push.

## Home page

The home page (`.github/scripts/make-index.py`) lists daily games automatically under "Today's games", with today's puzzle number, and every other game under "More games". A game opts in with a `games/<name>/homepage/` folder:

| File | What it does |
|---|---|
| `.gdignore` | Empty. Keeps Godot from importing the folder into the game. |
| `game.json` | `{"daily": true, "start": "YYYY-MM-DD", "clock": "utc", "tagline": "…", "order": 10}`. `start` is puzzle #1; `clock` is `"utc"` or `"local"`, matching the date the game uses. `tagline` and `order` are optional. |
| `thumbnail.png` | Optional 16:9 card image (1280×720; `.jpg`/`.webp` also work). Without one, the card shows the title on the game's boot colour. |

When a run ends, a game can write `localStorage["gametests:<name>:<YYYY-MM-DD>"] = JSON.stringify({result: "<short result>"})`; the home page then marks that game as played today and shows the result. A bad `game.json` fails the build.
Local build: `GODOT_BIN=godot .github/scripts/build-site.sh` writes the site to `_site/`.
