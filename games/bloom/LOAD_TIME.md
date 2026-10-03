# Bloom: web load time

Bloom took 10–30 s to load on the live site. Almost all of that was the Godot
engine, not the game: Bloom's own data (`index.pck`) is 84 KB, while the stock
engine (`index.wasm`) is 39.5 MB. This folder's game now ships a slimmed-down
engine built just for it, which cuts the download by more than half and the time
to first frame by about 2.5x.

## What gets downloaded

Stock Godot 4.7.2 web export of Bloom, file by file:

| File | Raw | Gzipped | Share of download |
|---|---:|---:|---:|
| `index.wasm` (engine) | 39.51 MB | 10.08 MB | 97% |
| `index.js` (loader) | 0.28 MB | 0.07 MB | <1% |
| `index.pck` (Bloom itself) | 0.08 MB | 0.08 MB | <1% |
| html, icons, worklets | 0.06 MB | 0.04 MB | <1% |

So the only lever that matters is the engine. Its 39.5 MB holds the whole of
Godot: 3D, 2D and 3D physics, navigation, XR, the advanced GUI controls,
HarfBuzz+ICU text shaping (with ~4 MB of ICU data), and every image, audio and
video codec. Bloom draws 2D shapes and text with the built-in font in `_draw()`
and uses none of that.

The engine also costs time *after* it arrives: the browser has to compile ~35 MB
of WebAssembly code before Godot can start, which is slow on phones. A smaller
engine helps both halves.

### How the live site serves it

Checked from CI (`engine/build-info.txt`): GitHub Pages already gzips the engine
on the fly (`index.wasm` arrives as 10.25 MB), with `cache-control: max-age=600`.
So compression was not the problem; the engine's size was. Two smaller things
showed up too:

- The first request after a deploy hits a cold CDN edge (`x-cache: MISS`), so
  the first players each day pay full price from the origin.
- `jprier.github.io/GameTests/...` 301-redirects to `joshprier.dev/GameTests/...`.
  Links shared with the `joshprier.dev` address skip that extra round trip.

## Results

Measured with `engine/bench/bench.js` (headless Chromium, cache disabled, files
served with on-the-fly gzip like GitHub Pages), median of 3–5 runs. Time is from
navigation until Godot's loading overlay is gone (engine running, first frame).

| Build | Over the wire | Good connection (50 Mbps, 20 ms) | Phone (12 Mbps, 70 ms, 4x slower CPU) |
|---|---:|---:|---:|
| Stock engine | 10.36 MB | 4.6 s | 12.8 s |
| Stock + preload hints | 10.36 MB | – | 12.4 s |
| **Slim engine + preload (shipped)** | **4.88 MB** | **1.9 s** | **5.4 s** |

The sandbox's numbers are lower than the 10–30 s seen live (real phones are
slower than a 4x-throttled desktop CPU, and first hits go to a cold CDN edge),
but the ratio carries over: roughly half the bytes and less than half the
compile and start-up work.

Gameplay was checked in the browser on the slim build: tutorial, planting, a full
150-step run and scoring all work, with no console errors, and the same seeds give
the same Impact score (335 on puzzle #3) as on the stock engine. All 16 tests pass.

## What changed

1. **Slim engine template** (`engine/godot.web.template_release.wasm32.nothreads.zip`,
   used through `custom_template/release` in `export_presets.cfg`). Built by
   `engine/build-template.sh` from Godot 4.7.2 source with:
   - `modules_enabled_by_default=no`, then only `gdscript`, `regex` (date
     check), `text_server_fb` + `freetype` (built-in font), `websocket`
     (AgentBridge references `WebSocketPeer`);
   - `disable_3d`, `disable_advanced_gui`, `disable_physics_2d/3d`,
     `disable_navigation_2d/3d`, `disable_xr`, `deprecated=no`, `minizip=no`;
   - `production=yes optimize=size_extra lto=full`.

   Result: `godot.wasm` 15.9 MB raw / 4.67 MB gzipped (was 39.5 / 10.1 MB). The
   biggest single wins are dropping 3D and swapping the HarfBuzz/ICU text server
   for the simple one (Bloom's text is plain English, so nothing visible changes
   apart from sub-pixel glyph placement).

2. **Preload hints** in `html/head_include`: `<link rel="preload">` for
   `index.wasm` and `index.pck`, so the engine download starts while the HTML is
   still parsing instead of after `index.js` has loaded. Verified there is no
   double download. Small gain (~0.3 s), no cost.

3. **AgentBridge** (`addons/agent_bridge/agent_bridge.gd`): one line changed from
   `n is Node3D` to `n.is_class("Node3D")`. Without 3D compiled in, the type name
   doesn't exist and the autoload failed to parse. The kit's copy of the bridge
   should get the same change, or `gck update-bridge bloom` will undo it.

## How the template is built and kept up to date

Emscripten can't be installed in the agent sandbox, so the template is built in
CI by `.github/workflows/bloom-engine.yml`. It only runs when
`engine/build-template.sh` or the workflow itself changes, builds the template
(~10 minutes), and commits the zip plus `engine/build-info.txt` (sizes, versions,
and how the live site serves Bloom's files) back to that branch. The regular
deploy workflow is untouched and simply exports with the committed zip.

**When bumping Godot** (`GODOT_VERSION` in `pages.yml`), rebuild Bloom's template
too: the engine and the exported `.pck` must be the same version. The script reads
the version from `pages.yml`, so touching `build-template.sh` (or running the
workflow by hand from the Actions tab) on the bump's branch is enough.

**When Bloom starts using something new** (an audio file, a texture format, a
`Control` node, a physics body), check it's compiled in: export locally and run
`engine/bench/play.js` on the build, which prints console errors such as
`Could not find type ...`. Turn the matching module or `disable_*` flag back on in
`build-template.sh` and push.

## Measuring it yourself

```bash
cd games/bloom/engine/bench && npm install
godot --headless --path ../.. --export-release Web /tmp/bloom/index.html
node bench.js /tmp/bloom 5 good     # or: phone
node play.js /tmp/bloom '[]'        # screenshot + console errors
```

## Ideas considered and not done

- **Extra `wasm-opt -Oz` pass:** another 2% off the gzipped engine (4.67 →
  4.56 MB). Not worth adding a step to the build.
- **Brotli:** ~15–20% smaller than gzip for wasm, but GitHub Pages only serves
  gzip and won't serve pre-compressed `.br` files, so it would need a JavaScript
  Brotli decoder in the page, which eats most of the gain.
- **Class-level build profile** (`build_profile=*.gdbuild` listing unused
  classes): could trim a bit more of the remaining 13 MB of code, but needs
  care with class dependencies. Next step if more is wanted.
- **Service worker / PWA** (`progressive_web_app/enabled`): would make repeat
  visits work offline, but repeat visits within 10 minutes already come from the
  browser's HTTP cache, and after that the browser only revalidates. A cache-first
  worker can also serve a stale build for one visit after each deploy. Not worth
  it for first-load time.
- **Threads build:** needs cross-origin isolation headers GitHub Pages can't set,
  and doesn't help load time.

## Applying this to other games

The same recipe works for any game in this repo; only the module list differs.
Games that use 3D, physics, audio or GUI controls need those flags left on, so
each game needs its own template (or a shared "2D + GUI + audio" template). The
win scales with how little of the engine a game uses: Bloom is close to the best
case.
