# Game Tests

Small Godot games that run in the browser (desktop and mobile).

**Play:** https://jprier.github.io/GameTests/

| Game | Folder |
|---|---|
| Kitchen Crawl: a restaurant-sim roguelike | [`games/kitchen-crawl`](games/kitchen-crawl) |

## How deploys work

Every push to `main` runs [`.github/workflows/pages.yml`](.github/workflows/pages.yml), which:

1. installs Godot 4.7.2 and only the web export templates (cached between runs),
2. validates and runs the tests of every project in `games/*/`, failing the build on errors,
3. exports each game to `/<folder>/` and generates the landing page,
4. deploys the result to GitHub Pages.

Pull requests run steps 1–3 without deploying.

To add a game, put a Godot project with a `Web` export preset in `games/<name>/` and push.
Local build: `GODOT_BIN=godot .github/scripts/build-site.sh` writes the site to `_site/`.
