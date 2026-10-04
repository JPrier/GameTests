#!/usr/bin/env python3
"""Write the home page (index.html) for every game exported into the site dir.
Usage: make-index.py <games_dir> <site_dir>

Games are grouped on the page by the folders they sit in under games/ (see gamelist.py):
  games/Daily/bloom               -> "Daily" section
  games/Daily/Airplanes/flightle  -> "Airplanes" group inside the "Daily" section
  games/Incremental/bistro-empire -> "Incremental" section
Daily comes first, Other last, the rest alphabetically; inside a section, games directly in it come
first, then each subfolder. Every game under games/Daily/ is a daily game and shows today's puzzle
number, so it needs "start" in its game.json.

Per game (all optional except where noted):
  homepage/.gdignore          empty file, keeps Godot from importing this folder into the game
  homepage/game.json          {"start": "YYYY-MM-DD",      date of puzzle #1 (required under Daily/)
                               "clock": "utc" | "local",   which date the game uses (default "utc")
                               "tagline": "One line.",     card text (default: config/description,
                                                           then the README's first paragraph)
                               "order": 10}                sort key, lower first (default: by title)
  homepage/thumbnail.png      card image, 16:9 (1280x720 recommended); .jpg/.webp also work.
                              Without one the card shows the title on the game's boot colour.

Played-today badge: when a run ends a game may store
  localStorage["gametests:<slug>:<YYYY-MM-DD>"] = JSON.stringify({"result": "<short result>"})
and the home page shows "Played" (plus the result) on that card for that day.
"""
import hashlib
import html
import json
import pathlib
import re
import shutil
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gamelist import find_games  # noqa: E402

games_dir, site = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
THUMB_EXTS = (".webp", ".png", ".jpg", ".jpeg")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
errors = []


def boot_colour(text):
    m = re.search(r"boot_splash/bg_color=Color\(([^)]*)\)", text)
    if not m:
        return None
    try:
        r, g, b = (float(x) for x in m.group(1).split(",")[:3])
    except ValueError:
        return None
    return "#%02x%02x%02x" % tuple(round(max(0, min(1, c)) * 255) for c in (r, g, b))


def is_light(hex_colour):
    r, g, b = (int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))
    return 0.299 * r + 0.587 * g + 0.114 * b > 150


def readme_blurb(folder):
    readme = folder / "README.md"
    if not readme.exists():
        return ""
    paras = [p.strip() for p in readme.read_text().split("\n\n")]
    p = next((p for p in paras if p and not p.startswith("#")), "")
    p = re.sub(r"\*\*(.+?)\*\*|`(.+?)`", lambda m: m.group(1) or m.group(2), " ".join(p.split()))
    return p if len(p) <= 180 else p[:177].rsplit(" ", 1)[0] + "…"


try:
    found = find_games(games_dir)
except ValueError as err:
    for line in str(err).splitlines():
        print(f"::error::{line}")
    sys.exit(1)

games = []
for folder, slug, category in found:
    if not (site / slug / "index.html").exists():
        continue
    text = (folder / "project.godot").read_text()
    m = re.search(r'config/name="([^"]+)"', text)
    title = m.group(1) if m else slug
    m = re.search(r'config/description="([^"]+)"', text)
    meta = {}
    meta_file = folder / "homepage" / "game.json"
    if meta_file.exists():
        try:
            meta = json.loads(meta_file.read_text())
        except json.JSONDecodeError as e:
            errors.append(f"{meta_file}: invalid JSON ({e})")
            continue
    daily = category[0].lower() == "daily"
    if "daily" in meta and bool(meta["daily"]) != daily:
        where = "move the game into games/Daily/" if meta["daily"] else "remove \"daily\" or move the game"
        errors.append(f"{meta_file}: \"daily\" doesn't match the game's folder ({where})")
        continue
    if daily and not DATE_RE.match(str(meta.get("start", ""))):
        errors.append(f"{meta_file}: daily games need \"start\": \"YYYY-MM-DD\" (date of puzzle #1)")
        continue
    if meta.get("clock", "utc") not in ("utc", "local"):
        errors.append(f"{meta_file}: \"clock\" must be \"utc\" or \"local\"")
        continue

    thumb = None
    for ext in THUMB_EXTS:
        src = folder / "homepage" / f"thumbnail{ext}"
        if src.exists():
            shutil.copyfile(src, site / slug / f"thumbnail{ext}")
            ver = hashlib.sha1(src.read_bytes()).hexdigest()[:8]
            thumb = f"./{slug}/thumbnail{ext}?v={ver}"
            break

    games.append({
        "slug": slug,
        "category": category,
        "title": title,
        "tagline": meta.get("tagline") or (m.group(1) if m else "") or readme_blurb(folder),
        "daily": daily,
        "start": meta.get("start"),
        "clock": meta.get("clock", "utc"),
        "order": meta.get("order", 1000),
        "thumb": thumb,
        "colour": boot_colour(text) or "#3a2a26",
    })

if errors:
    for e in errors:
        print(f"::error::{e}")
    sys.exit(1)

games.sort(key=lambda g: (g["order"], g["title"].lower()))
daily = [g for g in games if g["daily"]]
e = html.escape


def section_key(name):
    low = name.lower()
    return (0 if low == "daily" else 2 if low == "other" else 1, low)


def label(name):
    return name.replace("-", " ").replace("_", " ")


def card(g):
    if g["thumb"]:
        art = f'<img src="{e(g["thumb"])}" alt="" loading="lazy" decoding="async">'
    else:
        ink = "#1d1514" if is_light(g["colour"]) else "#f3e9dc"
        art = (f'<div class="fallback" style="--c:{g["colour"]};--k:{ink}">'
               f'<span>{e(g["title"])}</span></div>')
    num = '<span class="num" hidden></span>' if g["daily"] else ""
    badge = '<span class="badge" hidden></span>' if g["daily"] else ""
    attrs = (f' data-slug="{e(g["slug"])}" data-start="{e(g["start"])}" data-clock="{g["clock"]}"'
             if g["daily"] else "")
    return (f'<a class="card" href="./{e(g["slug"])}/"{attrs}>'
            f'<div class="art">{art}{badge}</div>'
            f'<div class="body"><div class="row"><h3>{e(g["title"])}</h3>{num}</div>'
            f'<p>{e(g["tagline"])}</p><span class="result" hidden></span></div></a>')


def grid(gs):
    return f'<div class="grid">{"".join(card(g) for g in gs)}</div>'


sections = []
for top in sorted({g["category"][0] for g in games}, key=section_key):
    in_top = [g for g in games if g["category"][0] == top]
    loose = [g for g in in_top if len(g["category"]) == 1]
    parts = [grid(loose)] if loose else []
    for sub in sorted({g["category"][1:] for g in in_top if len(g["category"]) > 1},
                      key=lambda c: [x.lower() for x in c]):
        gs = [g for g in in_top if g["category"][1:] == sub]
        parts.append(f'<div class="group"><h3 class="sub">{e(" / ".join(label(x) for x in sub))}</h3>{grid(gs)}</div>')
    sections.append(f'<section><h2>{e(label(top))}</h2>{"".join(parts)}</section>')
sections_html = "\n".join(sections) or '<p class="empty">No games yet.</p>'

page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Daily Games</title>
<meta name="description" content="A handful of small browser games with a new puzzle every day.">
<meta name="theme-color" content="#1d1514">
<style>
:root{{--bg:#1d1514;--card:#2a1f1d;--line:#45322d;--ink:#f3e9dc;--muted:#c2b09e;--accent:#ffcf6b;--ok:#8fd694}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}}
main{{max-width:960px;margin:0 auto;padding:40px 16px 64px}}
header{{display:flex;flex-wrap:wrap;align-items:baseline;justify-content:space-between;gap:4px 16px;margin-bottom:28px}}
h1{{margin:0;font-size:clamp(1.8rem,5vw,2.4rem);letter-spacing:-.02em;color:var(--accent)}}
.today{{margin:0;color:var(--muted);font-variant-numeric:tabular-nums}}
.today b{{color:var(--ink);font-weight:600}}
h2{{margin:0 0 14px;font-size:.8rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted)}}
section+section{{margin-top:40px}}
.grid{{display:grid;gap:16px;grid-template-columns:repeat(auto-fill,minmax(260px,1fr))}}
.card{{display:flex;flex-direction:column;background:var(--card);border:1px solid var(--line);border-radius:14px;overflow:hidden;color:inherit;text-decoration:none;transition:transform .15s,border-color .15s}}
.card:hover,.card:focus-visible{{border-color:var(--accent);transform:translateY(-2px);outline:none}}
.art{{position:relative;aspect-ratio:16/9;background:#000}}
.art img{{display:block;width:100%;height:100%;object-fit:cover}}
.fallback{{display:grid;place-items:center;height:100%;padding:16px;background:radial-gradient(120% 90% at 30% 20%,color-mix(in srgb,var(--c) 70%,#fff) 0%,var(--c) 55%,color-mix(in srgb,var(--c) 70%,#000) 100%)}}
.fallback span{{color:var(--k);font-weight:800;font-size:clamp(1.5rem,6vw,2rem);letter-spacing:-.02em;text-align:center;line-height:1.1}}
.badge{{position:absolute;top:10px;left:10px;padding:3px 10px;border-radius:999px;font-size:.75rem;font-weight:700;background:var(--accent);color:#1d1514;box-shadow:0 1px 4px #0006}}
.badge.done{{background:var(--ok)}}
.body{{padding:14px 16px 16px;display:flex;flex-direction:column;gap:6px;flex:1}}
.row{{display:flex;align-items:baseline;justify-content:space-between;gap:8px}}
.card h3{{margin:0;font-size:1.15rem}}
.grid+.group,.group+.group{{margin-top:28px}}
.sub{{margin:0 0 10px;font-size:1rem;font-weight:600;color:var(--ink)}}
.num{{color:var(--muted);font-size:.9rem;font-variant-numeric:tabular-nums;white-space:nowrap}}
.card p{{margin:0;color:var(--muted);font-size:.93rem}}
.result{{margin-top:auto;padding-top:6px;color:var(--ok);font-size:.9rem;font-weight:600}}
.empty{{color:var(--muted)}}
@media (max-width:600px){{
  main{{padding-top:28px}}
  .grid{{gap:12px}}
  .card{{flex-direction:row}}
  .art{{flex:0 0 38%;aspect-ratio:auto;min-height:118px}}
  .fallback span{{font-size:1.05rem}}
  .badge{{top:6px;left:6px;padding:2px 8px;font-size:.7rem}}
  .body{{padding:12px 14px;gap:4px}}
  .card h3{{font-size:1.05rem}}
  .card p{{font-size:.88rem;line-height:1.4}}
}}
</style></head>
<body><main>
<header><h1>Daily Games</h1><p class="today" id="today"></p></header>
{sections_html}
</main>
<script>
(function(){{
  var pad=function(n){{return String(n).padStart(2,"0")}};
  var now=new Date();
  var day={{
    local:now.getFullYear()+"-"+pad(now.getMonth()+1)+"-"+pad(now.getDate()),
    utc:now.getUTCFullYear()+"-"+pad(now.getUTCMonth()+1)+"-"+pad(now.getUTCDate())
  }};
  var dayNum=function(start,d){{return Math.round((Date.parse(d)-Date.parse(start))/864e5)+1}};
  var store=null;try{{store=window.localStorage}}catch(e){{}}
  var cards=document.querySelectorAll(".card[data-slug]"),played=0;
  cards.forEach(function(c){{
    var d=day[c.dataset.clock]||day.utc,n=dayNum(c.dataset.start,d);
    var num=c.querySelector(".num"),badge=c.querySelector(".badge"),res=c.querySelector(".result");
    if(n>=1){{num.textContent="#"+n;num.hidden=false}}
    var rec=null;
    try{{rec=store&&store.getItem("gametests:"+c.dataset.slug+":"+d)}}catch(e){{}}
    if(rec){{
      played++;badge.textContent="Played ✓";badge.classList.add("done");badge.hidden=false;
      try{{var r=JSON.parse(rec).result;if(r){{res.textContent=r;res.hidden=false}}}}catch(e){{}}
    }}else if(n===1){{badge.textContent="New";badge.hidden=false}}
  }});
  var label=now.toLocaleDateString(undefined,{{weekday:"long",month:"long",day:"numeric"}});
  var t=document.getElementById("today");
  t.innerHTML="<b>"+label+"</b>"+(cards.length&&played?" · "+played+" of "+cards.length+" played":"");
}})();
</script>
</body></html>
"""
(site / "index.html").write_text(page)
(site / ".nojekyll").write_text("")
print(f"index: {len(games)} game(s) in {len(sections)} section(s), {len(daily)} daily")
