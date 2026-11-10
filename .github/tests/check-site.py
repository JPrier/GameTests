#!/usr/bin/env python3
"""Structural checks on the built site (_site), run at the end of build-site.sh.

Guards the iOS 18 frozen-screen fix and the things the PR previews rely on:
  - every game page carries render-options.js, verbatim, as the first injected script and ahead
    of the engine script (it must patch WebGL before Godot creates its context);
  - every game's GODOT_CONFIG points at engine files that exist (shared engine, see share-engine.py);
  - build.json and .nojekyll exist;
  - the whole site fits the size budget, so the live site plus PR previews stay under GitHub
    Pages' 1 GB limit.

    check-site.py _site
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPTS = os.path.join(ROOT, ".github", "scripts")
BUDGET_MB = int(os.environ.get("SITE_BUDGET_MB", "300"))
CONFIG_RE = re.compile(r"const GODOT_CONFIG = (\{.*?\});\n")
ENGINE_SCRIPT_RE = re.compile(r'<script src="([^"]*index\.js)"></script>')


def main(site):
    errors = []
    render = open(os.path.join(SCRIPTS, "render-options.js")).read()
    others = [open(os.path.join(SCRIPTS, f)).read() for f in ("input-debug.js", "touch-fix.js", "stale-reload.js")]
    games = 0
    for name in sorted(os.listdir(site)):
        page = os.path.join(site, name, "index.html")
        if name == "engine" or not os.path.isfile(os.path.join(site, name, "index.pck")) or not os.path.isfile(page):
            continue
        games += 1
        html = open(page, encoding="utf-8").read()
        err = lambda msg: errors.append(f"{name}: {msg}")

        r = html.find("<script>" + render + "</script>")
        if r < 0:
            err("render-options.js (iOS 18 frozen-screen fix) is not injected verbatim")
        first_script = html.find("<script>")
        if r >= 0 and html.find("<script>", first_script + 1) != r:
            err("render-options.js is not the first injected script after the build stamp")
        for js in others:
            i = html.find("<script>" + js + "</script>")
            if i < 0:
                err("an injected helper script is missing")
            elif r >= 0 and i < r:
                err("a helper script is injected before render-options.js")

        m = ENGINE_SCRIPT_RE.search(html)
        if not m:
            err("no engine <script src=...index.js>")
        elif r >= 0 and m.start() < r:
            err("the engine script loads before render-options.js")

        c = CONFIG_RE.search(html)
        if not c:
            err("no GODOT_CONFIG")
            continue
        config = json.loads(c.group(1))
        exe = config.get("executable", "")
        base = os.path.normpath(os.path.join(site, name, exe))
        for ext in (".wasm", ".js", ".audio.worklet.js", ".audio.position.worklet.js"):
            if not os.path.isfile(base + ext):
                err(f"engine file missing: {exe}{ext}")
        if m and os.path.normpath(os.path.join(site, name, m.group(1))) != base + ".js":
            err(f"engine script {m.group(1)} does not match executable {exe}")
        pack = config.get("mainPack") or exe + ".pck"
        if not os.path.isfile(os.path.join(site, name, pack)):
            err(f"main pack missing: {pack}")
        if exe != "index" and os.path.exists(os.path.join(site, name, "index.wasm")):
            err("a private index.wasm is left next to a shared engine")

    if games == 0:
        errors.append("no games found in the site")
    for f in ("build.json", ".nojekyll", "index.html"):
        if not os.path.isfile(os.path.join(site, f)):
            errors.append(f"site is missing {f}")

    total = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(site) for f in fs)
    mb = total / 1e6
    print(f"check-site: {games} games, {mb:.0f} MB (budget {BUDGET_MB} MB)")
    if mb > BUDGET_MB:
        errors.append(f"site is {mb:.0f} MB, over the {BUDGET_MB} MB budget (live + PR previews must fit in 1 GB)")

    for e in errors:
        print(f"::error::check-site: {e}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "_site"))
