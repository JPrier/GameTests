# Game Tests

Small Godot games that run in the browser (desktop and mobile).

**Play:** https://jprier.github.io/GameTests/

Games live in category folders under `games/`, and the home page has one section per folder:

```
games/
  Daily/
    bloom/  daily-bridge/  earthquake-test/  ticker-time/
    Airplanes/
      flightle/  xray-shift/
  Incremental/
    bistro-empire/
  Other/
    kitchen-crawl/
```

| Game | Folder |
|---|---|
| **Daily** | |
| Bloom: a daily Game of Life puzzle | [`games/Daily/bloom`](games/Daily/bloom) |
| Daily Bridge: a daily bridge-building physics puzzle | [`games/Daily/daily-bridge`](games/Daily/daily-bridge) |
| Earthquake Test: build a structure, then the same daily quake hits everyone | [`games/Daily/earthquake-test`](games/Daily/earthquake-test) |
| Ticker Time: guess the year of real stock charts, then bet up or down with $1,000 | [`games/Daily/ticker-time`](games/Daily/ticker-time) |
| **Daily / Airplanes** | |
| Flightle: name both airports of a real flight path; every miss reveals a clue | [`games/Daily/Airplanes/flightle`](games/Daily/Airplanes/flightle) |
| X-Ray Shift: a daily airport x-ray game, flag the bags with contraband and find the illegal items | [`games/Daily/Airplanes/xray-shift`](games/Daily/Airplanes/xray-shift) |
| **Incremental** | |
| Bistro Empire: an incremental restaurant tycoon with 1,726 upgrades, franchises, side businesses, prestige and opt-in challenges | [`games/Incremental/bistro-empire`](games/Incremental/bistro-empire) |
| **Other** | |
| Kitchen Crawl: a restaurant-sim roguelike | [`games/Other/kitchen-crawl`](games/Other/kitchen-crawl) |

## How deploys work

Every push to `main` runs [`.github/workflows/pages.yml`](.github/workflows/pages.yml), which:

1. installs Godot 4.7.2 and only the web export templates (cached between runs),
2. validates and runs the tests of every Godot project under `games/` (found in any category folder), failing the build on errors,
3. exports each game to `/<folder>/` and generates the home page,
4. benchmarks every game against an iPhone X class phone at 60 fps, failing the build if any game is over its frame budget ([details](.github/bench/README.md)),
5. deploys the result to GitHub Pages.

Pull requests run steps 1–4 without deploying. New games are tested and benchmarked automatically; there's nothing to register.

To add a game, put a Godot project with a `Web` export preset in `games/<Category>/<name>/` (or one level deeper, `games/<Category>/<Subcategory>/<name>/`) and push. A new category is just a new folder.

The game's folder name is its URL (`https://jprier.github.io/GameTests/<name>/`), whatever category it's in, so folder names must be unique across categories, and moving a game between categories never breaks its links or saved results. The build fails if two games share a folder name or a game sits directly in `games/`.

## Home page

The home page (`.github/scripts/make-index.py`) has a section for each top-level category folder: Daily first, Other last, the rest alphabetically. Inside a section, games directly in the folder come first, then a group for each subfolder (e.g. Airplanes under Daily). Every game under `games/Daily/` is a daily game and shows today's puzzle number. A game can add details with a `homepage/` folder:

| File | What it does |
|---|---|
| `.gdignore` | Empty. Keeps Godot from importing the folder into the game. |
| `game.json` | `{"start": "YYYY-MM-DD", "clock": "utc", "tagline": "…", "order": 10}`. `start` is puzzle #1 and is required for games under `Daily/`; `clock` is `"utc"` or `"local"`, matching the date the game uses. `tagline` and `order` (sort within its group, lower first) are optional. |
| `thumbnail.png` | Optional 16:9 card image (1280×720; `.jpg`/`.webp` also work). Without one, the card shows the title on the game's boot colour. |

When a run ends, a game can write `localStorage["gametests:<name>:<YYYY-MM-DD>"] = JSON.stringify({result: "<short result>"})`; the home page then marks that game as played today and shows the result. A bad `game.json` fails the build.
Local build: `GODOT_BIN=godot .github/scripts/build-site.sh` writes the site to `_site/`.
