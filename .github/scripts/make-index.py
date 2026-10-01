#!/usr/bin/env python3
"""Write the landing page (index.html) listing every game that was exported into the site dir.
Usage: make-index.py <games_dir> <site_dir>
Each game's title comes from project.godot (config/name); its blurb is the first paragraph of its README.md.
"""
import html
import pathlib
import re
import sys

games_dir, site = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
cards = []
for proj in sorted(games_dir.glob("*/project.godot")):
    slug = proj.parent.name
    if not (site / slug / "index.html").exists():
        continue
    m = re.search(r'config/name="([^"]+)"', proj.read_text())
    title = m.group(1) if m else slug
    blurb = ""
    readme = proj.parent / "README.md"
    if readme.exists():
        paras = [p.strip() for p in readme.read_text().split("\n\n")]
        blurb = next((p for p in paras if p and not p.startswith("#")), "")
        blurb = " ".join(blurb.split())
    cards.append(
        f'<a class="card" href="./{slug}/"><h2>{html.escape(title)}</h2>'
        f"<p>{html.escape(blurb)}</p><span>Play &rarr;</span></a>"
    )

page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Game Tests</title>
<style>
:root{{--bg:#1d1514;--card:#2e2220;--ink:#f3e9dc;--muted:#c9b8a6;--accent:#ffcf6b}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,-apple-system,Segoe UI,sans-serif}}
main{{max-width:880px;margin:0 auto;padding:40px 16px}}
h1{{margin:0 0 4px;font-size:2rem;color:var(--accent)}}
.sub{{margin:0 0 28px;color:var(--muted)}}
.grid{{display:grid;gap:16px;grid-template-columns:repeat(auto-fill,minmax(260px,1fr))}}
.card{{display:block;background:var(--card);border:2px solid #4a3530;border-radius:12px;padding:18px;color:inherit;text-decoration:none}}
.card:hover,.card:focus{{border-color:var(--accent)}}
.card h2{{margin:0 0 8px;font-size:1.25rem}}
.card p{{margin:0 0 12px;color:var(--muted);font-size:.95rem}}
.card span{{color:var(--accent);font-weight:600}}
</style></head>
<body><main>
<h1>Game Tests</h1>
<p class="sub">Small Godot games, built and deployed automatically. Each runs in the browser, on desktop or phone.</p>
<div class="grid">{''.join(cards) or '<p>No games yet.</p>'}</div>
</main></body></html>
"""
(site / "index.html").write_text(page)
(site / ".nojekyll").write_text("")
print(f"index: {len(cards)} game(s)")
