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
| Flightle: name both airports of a real flight path; every miss reveals a clue | [`games/flightle`](games/flightle) |

## How deploys work

Every push to `main` runs [`.github/workflows/pages.yml`](.github/workflows/pages.yml). Pull requests run everything except the deploy.

1. **Plan.** For each game in `games/*/`, [`detect-features.gd`](.github/engine/detect-features.gd) works out which parts of the Godot engine it uses (3D, physics, navigation, advanced GUI controls, audio and image codecs, text shaping, …) from its scenes, scripts and imported files.
2. **Engines.** Each distinct feature set gets its own web engine, built from Godot source with only those parts ([`build-template.sh`](.github/engine/build-template.sh)). Games with the same features share one. Engines are cached, so a rebuild (~10 minutes) only happens when a game starts using something new, the Godot version changes, or the build recipe changes. A 2D game's engine is about 16 MB (4.7 MB gzipped) instead of the stock 39.5 MB (10 MB), and starts about 2.5x faster.
3. **Build.** Every game is validated and its tests run headless; then it's exported with its own engine and the home page is generated. If a game's engine failed to build, that game ships with the stock engine and the run shows a warning.
4. **Verify.** Every exported game is loaded in headless Chrome and its tests run again inside the real web build, on the engine it will ship with ([`verify-web.js`](.github/scripts/verify-web.js)). The run summary lists each game's engine size, download size, start time and test count.
5. **Deploy** to GitHub Pages.

The build fails if any game has no tests, fails a test (headless or in the browser), or logs a script error on start.

## Adding a game

Put a Godot project with a `Web` export preset in `games/<name>/` and push. It needs:

- **The AgentBridge addon** (`addons/agent_bridge/`, autoloaded as `AgentBridge`). `gck new`/`gck adopt` from [GodotAgentSandbox](https://github.com/JPrier/GodotAgentSandbox) set this up.
- **Tests:** at least one `tests/test_*.gd` that `extends GameTest` with `test_*` methods. They are the game's proof that it works: they run headless and then in the browser on the game's slim engine, so they should load the main scene and exercise the real game (input, scoring, saving), not just pass. Run them locally with `gck test <name>` and `gck test <name> --browser`.

Nothing else is needed for the engine: it's detected. If detection ever misses something (the browser run fails with an error like `Could not find type "X"`), add `games/<name>/engine.json`:

| `engine.json` | Effect |
|---|---|
| `{"include": ["AudioStreamPlayer"]}` | Treat these engine classes as used. |
| `{"flags": ["module_noise_enabled=yes"]}` | Extra SCons flags for this game's engine. |
| `{"engine": "stock"}` | Use the full stock engine. |

Checks written by name, such as `node.is_class("Node3D")`, don't count as using a class; that's how the shared addon inspects nodes without pulling 3D into every game.

Local build: `GODOT_BIN=godot .github/scripts/build-site.sh` writes the site to `_site/` with the stock engine. To see what a game's engine would contain: `GODOT_BIN=godot .github/scripts/plan-engines.sh <godot-source-dir>` (a checkout of the Godot source; only `modules/` is read). To run the browser checks: `npm install --prefix .github/scripts puppeteer-core && node .github/scripts/verify-web.js _site` (set `CHROME_PATH` if Chrome isn't in a standard place).

## Home page

The home page (`.github/scripts/make-index.py`) lists daily games automatically under "Today's games", with today's puzzle number, and every other game under "More games". A game opts in with a `games/<name>/homepage/` folder:

| File | What it does |
|---|---|
| `.gdignore` | Empty. Keeps Godot from importing the folder into the game. |
| `game.json` | `{"daily": true, "start": "YYYY-MM-DD", "clock": "utc", "tagline": "…", "order": 10}`. `start` is puzzle #1; `clock` is `"utc"` or `"local"`, matching the date the game uses. `tagline` and `order` are optional. |
| `thumbnail.png` | Optional 16:9 card image (1280×720; `.jpg`/`.webp` also work). Without one, the card shows the title on the game's boot colour. |

When a run ends, a game can write `localStorage["gametests:<name>:<YYYY-MM-DD>"] = JSON.stringify({result: "<short result>"})`; the home page then marks that game as played today and shows the result. A bad `game.json` fails the build.
