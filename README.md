# Game Tests

Small Godot games that run in the browser (desktop and mobile).

**Play:** https://jprier.github.io/GameTests/

Games live in category folders under `games/`, and the home page has one section per folder:

```
games/
  Daily/
    bloom/  bouquet-toss/  daily-bridge/  earthquake-test/  drinkle/  plans-tonight/  seating-chart/  ticker-time/
    Airplanes/
      flightle/  xray-shift/
  Incremental/
    bistro-empire/
  Other/
    crowd-control/  kitchen-crawl/
```

[Game idea backlog](game-ideas/README.md): add concepts to the inbox for agents to review and claim.

| Game | Folder |
|---|---|
| **Daily** | |
| Bloom: a daily Game of Life puzzle | [`games/Daily/bloom`](games/Daily/bloom) |
| Bouquet Toss: five daily wedding bouquet trick shots; drag, aim, let go, fewest tries wins | [`games/Daily/bouquet-toss`](games/Daily/bouquet-toss) |
| Daily Bridge: a daily bridge-building physics puzzle | [`games/Daily/daily-bridge`](games/Daily/daily-bridge) |
| Earthquake Test: build a structure, then the same daily quake hits everyone | [`games/Daily/earthquake-test`](games/Daily/earthquake-test) |
| Drinkle: Cocktail Wordle meets Mastermind; every guess shows how close you are, deduce the drink in six | [`games/Daily/drinkle`](games/Daily/drinkle) |
| Plans Tonight?: a daily deduction puzzle, find the one plan that works for the whole friend group | [`games/Daily/plans-tonight`](games/Daily/plans-tonight) |
| Seating Chart: seat ten wedding guests so every clue holds; a daily logic puzzle, easy on Monday, devious by Sunday | [`games/Daily/seating-chart`](games/Daily/seating-chart) |
| Ticker Time: guess the year of real stock charts, then bet up or down with $1,000 | [`games/Daily/ticker-time`](games/Daily/ticker-time) |
| **Daily / Airplanes** | |
| Flightle: name both airports of a real flight path; every miss reveals a clue | [`games/Daily/Airplanes/flightle`](games/Daily/Airplanes/flightle) |
| X-Ray Shift: a daily airport x-ray game, flag the bags with contraband and find the illegal items | [`games/Daily/Airplanes/xray-shift`](games/Daily/Airplanes/xray-shift) |
| **Incremental** | |
| Bistro Empire: an incremental restaurant tycoon with 1,726 upgrades, franchises, side businesses, prestige and opt-in challenges | [`games/Incremental/bistro-empire`](games/Incremental/bistro-empire) |
| **Other** | |
| Crowd Control: you don't control people, you control the system they move through; get 1,000 fans home after the match | [`games/Other/crowd-control`](games/Other/crowd-control) |
| Kitchen Crawl: a restaurant-sim roguelike | [`games/Other/kitchen-crawl`](games/Other/kitchen-crawl) |

## How deploys work

Every push to `main` and every pull request runs [`.github/workflows/pages.yml`](.github/workflows/pages.yml), which:

1. installs Godot 4.7.2 and only the web export templates (cached between runs),
2. validates and runs the tests of every Godot project under `games/` (found in any category folder), failing the build on errors; a game with an executable `prebuild.sh` runs it first (Crowd Control builds its Rust simulation there, so the workflow also installs Rust with the wasm target),
3. exports each game to `/<folder>/`, generates the home page, and moves the Godot engine (identical for every game, ~40 MB) to one shared copy in `/engine/<hash>/`,
4. plays every game in Chromium, Firefox and WebKit (see below); `main` only deploys if that passes,
5. deploys it: `main` to the root of the `gh-pages` branch (the live site), a pull request to `https://joshprier.dev/GameTests/pr-preview/pr-<number>/` (a bot comments the link on the PR; the preview is deleted when the PR closes).

GitHub Pages serves the `gh-pages` branch (Settings → Pages → Source: Deploy from a branch, `gh-pages`, `/ (root)`). Previews only run for branches in this repo, not forks.

### Browser tests

Godot's headless tests check game logic; they never run the exported web page. [`.github/tests/browsers.mjs`](.github/tests/browsers.mjs) does, in Chromium, Firefox and WebKit (Playwright), on two kinds of screen: a phone (390x844 at 3x, touch input, then rotated to landscape) and a desktop (1280x800, mouse). For every game it checks the engine boots, nothing logs an error, the canvas fills the screen at full resolution, tapping a real button redraws the screen (gtui lists the buttons on `?debug=input`), and rotating re-lays it out. `--self-test` freezes the screen on purpose and requires the check to fail.

Run locally: `npm i --no-save playwright && npx playwright install chromium && node .github/tests/browsers.mjs _site --browsers chromium`.

These are Linux browser builds, so bugs that only exist on a real device (like iOS 18 Safari's frozen screen) still need a real iPhone: see [`CLAUDE.md`](CLAUDE.md).

To add a game, put a Godot project with a `Web` export preset in `games/<Category>/<name>/` (or one level deeper, `games/<Category>/<Subcategory>/<name>/`) and push. A new category is just a new folder.

The game's folder name is its URL (`https://jprier.github.io/GameTests/<name>/`), whatever category it's in, so folder names must be unique across categories, and moving a game between categories never breaks their links or saved results. The build fails if two games share a folder name or a game sits directly in `games/`.

## Shared UI

Every game draws its product UI (header, buttons, dialogs, help, results, "Past puzzles", toasts,
focus) with the shared GameTests UI, `GTUI`, and keeps its own art direction and colours.
Start with [`ui/VISUAL_GUIDE.md`](ui/VISUAL_GUIDE.md) (a five-minute read); notes on what changed are
in [`ui/CHANGES.md`](ui/CHANGES.md).

- The source lives in `ui/`; `.github/scripts/sync-ui.py` copies it into each game's
  `addons/gametests_ui/` (plus `tests/test_gtui.gd`). Edit `ui/`, never a game's copy.
- The build fails if a copy drifts (`sync-ui.py --check`) or product UI breaks the rules
  (`ui-lint.py`); every game's tests include touch-target and keyboard-focus checks.

## Home page

The home page (`.github/scripts/make-index.py`) has a section for each top-level category folder: Daily first, Other last, the rest alphabetically. Inside a section, games directly in the folder come first, then a group for each subfolder (e.g. Airplanes under Daily). Every game under `games/Daily/` is a daily game and shows today's puzzle number. A game can add details with a `homepage/` folder:

| File | What it does |
|---|---|
| `.gdignore` | Empty. Keeps Godot from importing the folder into the game. |
| `game.json` | `{"start": "YYYY-MM-DD", "clock": "utc", "tagline": "…", "order": 10}`. `start` is puzzle #1 and is required for games under `Daily/`; `clock` is `"utc"` or `"local"`, matching the date the game uses. `tagline` and `order` (sort within its group, lower first) are optional. |
| `thumbnail.png` | Optional 16:9 card image (1280×720; `.jpg`/`.webp` also work). Without one, the card shows the title on the game's boot colour. |

When a run ends, a game can write `localStorage["gametests:<name>:<YYYY-MM-DD>"] = JSON.stringify({result: "<short result>"})`; the home page then marks that game as played today and shows the result. A bad `game.json` fails the build.
Local build: `GODOT_BIN=godot .github/scripts/build-site.sh` writes the site to `_site/`.
