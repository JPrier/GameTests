#!/usr/bin/env python3
"""Make the exported games share one copy of the Godot engine.

Every web export carries its own ~40 MB engine (index.wasm + index.js + audio worklets), and for
games built with the same Godot version and export settings those files are byte-identical. This
moves each distinct engine to _site/engine/<hash>/ and points the games at it, so:
  - the site stays small enough for GitHub Pages (1 GB limit) with PR previews beside it, and
  - a player who opens a second game reuses the engine already in the browser cache.

A game whose engine differs (another Godot version, GDExtension support) simply gets its own
engine folder. Godot's loader takes these paths from GODOT_CONFIG: `executable` is the engine
base path (it loads <executable>.wasm and <executable>.audio*.worklet.js), `mainPack` the game's
.pck, and `fileSizes` is keyed by those same paths (sizes only drive the progress bar).

    share-engine.py _site
"""
import hashlib
import json
import os
import re
import shutil
import sys

ENGINE_FILES = ["index.wasm", "index.js", "index.audio.worklet.js", "index.audio.position.worklet.js"]
CONFIG_RE = re.compile(r"const GODOT_CONFIG = (\{.*?\});\n")


def engine_hash(game_dir):
    h = hashlib.sha256()
    for name in ENGINE_FILES:
        path = os.path.join(game_dir, name)
        h.update(name.encode() + b"\0")
        if os.path.exists(path):
            with open(path, "rb") as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
        h.update(b"\0")
    return h.hexdigest()[:12]


def share(site):
    shared, moved = {}, 0
    for name in sorted(os.listdir(site)):
        game = os.path.join(site, name)
        page = os.path.join(game, "index.html")
        if name == "engine" or not os.path.isfile(os.path.join(game, "index.wasm")) or not os.path.isfile(page):
            continue
        html = open(page, encoding="utf-8").read()
        m = CONFIG_RE.search(html)
        if not m:
            sys.exit(f"share-engine: {name}/index.html has no GODOT_CONFIG")
        config = json.loads(m.group(1))
        if config.get("executable") != "index":
            sys.exit(f"share-engine: {name} has executable={config.get('executable')!r}, expected 'index'")
        if config.get("gdextensionLibs"):
            continue  # extension libraries are located next to the engine; leave such games whole

        digest = engine_hash(game)
        engine_dir = os.path.join(site, "engine", digest)
        os.makedirs(engine_dir, exist_ok=True)
        for f in ENGINE_FILES:
            src = os.path.join(game, f)
            if not os.path.exists(src):
                continue
            if os.path.exists(os.path.join(engine_dir, f)):
                os.remove(src)
            else:
                shutil.move(src, os.path.join(engine_dir, f))
        base = f"../engine/{digest}/index"
        sizes = config.get("fileSizes", {})
        if "index.wasm" in sizes:
            sizes[base + ".wasm"] = sizes.pop("index.wasm")
        config["executable"] = base
        config["mainPack"] = "index.pck"
        config["fileSizes"] = sizes
        html = html[: m.start(1)] + json.dumps(config, separators=(",", ":")) + html[m.end(1):]
        if html.count('<script src="index.js"></script>') != 1:
            sys.exit(f"share-engine: {name}/index.html does not load index.js exactly once")
        html = html.replace('<script src="index.js"></script>', f'<script src="{base}.js"></script>')
        open(page, "w", encoding="utf-8").write(html)
        shared.setdefault(digest, []).append(name)
        moved += 1

    for digest, games in shared.items():
        print(f"engine/{digest}: {len(games)} game(s): {', '.join(games)}")
    print(f"share-engine: {moved} game(s) now load a shared engine")


if __name__ == "__main__":
    share(sys.argv[1] if len(sys.argv) > 1 else "_site")
