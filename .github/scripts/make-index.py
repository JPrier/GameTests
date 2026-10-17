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

Played-today status: when a run ends a game may store
  localStorage["gametests:<slug>:<YYYY-MM-DD>"] = JSON.stringify({"result": "<short result>"})
and the home page shows "Played today" (plus the result) on that game for that day.
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
        # No thumbnail: the game's boot colour, flat, with its name. No gradients.
        ink = "#1d1514" if is_light(g["colour"]) else "#f3e9dc"
        art = f'<span class="fallback" style="--c:{g["colour"]};--k:{ink}">{e(g["title"])}</span>'
    num = '<span class="num" hidden></span>' if g["daily"] else ""
    status = '<span class="status" hidden></span>' if g["daily"] else ""
    attrs = (f' data-slug="{e(g["slug"])}" data-start="{e(g["start"])}" data-clock="{g["clock"]}"'
             if g["daily"] else "")
    return (f'<li><a class="game" href="./{e(g["slug"])}/"{attrs}>'
            f'<span class="art">{art}</span>'
            f'<span class="info"><span class="line"><span class="title">{e(g["title"])}</span>{num}</span>'
            f'<span class="tag">{e(g["tagline"])}</span>{status}</span></a></li>')


def grid(gs):
    return f'<ul class="games">{"".join(card(g) for g in gs)}</ul>'


sections = []
for top in sorted({g["category"][0] for g in games}, key=section_key):
    in_top = [g for g in games if g["category"][0] == top]
    loose = [g for g in in_top if len(g["category"]) == 1]
    parts = [grid(loose)] if loose else []
    for sub in sorted({g["category"][1:] for g in in_top if len(g["category"]) > 1},
                      key=lambda c: [x.lower() for x in c]):
        gs = [g for g in in_top if g["category"][1:] == sub]
        parts.append(f'<div class="group"><h3>{e(" / ".join(label(x) for x in sub))}</h3>{grid(gs)}</div>')
    sections.append(f'<section><h2>{e(label(top))}</h2>{"".join(parts)}</section>')
sections_html = "\n".join(sections) or '<p class="empty">No games yet.</p>'

page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Daily Games</title>
<meta name="description" content="A handful of small browser games with a new puzzle every day.">
<meta name="theme-color" content="#1d1514">
<style>
/* GameTests homepage. Tokens match ui/VISUAL_GUIDE.md: spacing 4/8/12/16/24/32/48, radii 6/8, 1px borders. */
:root{{--bg:#1d1514;--surface:#261c1a;--line:#3d2d28;--ink:#f3e9dc;--muted:#bba893;--accent:#ffcf6b;--ok:#8fd694;
  --s1:4px;--s2:8px;--s3:12px;--s4:16px;--s5:24px;--s6:32px;--s7:48px;--r-control:6px;--r-panel:8px}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif;-webkit-text-size-adjust:100%}}
main{{max-width:1040px;margin:0 auto;padding:var(--s7) var(--s5) var(--s7)}}
header{{display:flex;flex-wrap:wrap;align-items:baseline;justify-content:space-between;gap:var(--s1) var(--s4);padding-bottom:var(--s4);border-bottom:1px solid var(--line)}}
h1{{margin:0;font-size:2rem;line-height:1.2;font-weight:700;letter-spacing:-.01em;color:var(--accent)}}
.today{{margin:0;color:var(--muted);font-variant-numeric:tabular-nums}}
.today b{{color:var(--ink);font-weight:600}}
section{{margin-top:var(--s6)}}
h2{{margin:0 0 var(--s2);font-size:.75rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted)}}
.group{{margin-top:var(--s5)}}
.group h3{{margin:0 0 var(--s2);font-size:.875rem;font-weight:600;color:var(--ink)}}
.games{{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(440px,1fr));column-gap:var(--s6)}}
.games li{{border-top:1px solid var(--line)}}
.game{{display:flex;gap:var(--s4);align-items:flex-start;padding:var(--s4) var(--s2);margin:0 calc(var(--s2) * -1);border-radius:var(--r-panel);color:inherit;text-decoration:none;transition:background-color .1s}}
.game:hover{{background:var(--surface)}}
.game:focus-visible{{outline:2px solid var(--accent);outline-offset:-2px}}
.art{{flex:0 0 160px;aspect-ratio:16/9;border-radius:var(--r-control);overflow:hidden;background:var(--surface);border:1px solid var(--line)}}
.art img{{display:block;width:100%;height:100%;object-fit:cover}}
.fallback{{display:flex;align-items:flex-end;height:100%;padding:var(--s2);background:var(--c);color:var(--k);font-weight:700;font-size:.875rem;line-height:1.2}}
.info{{display:flex;flex-direction:column;gap:var(--s1);min-width:0;flex:1}}
.line{{display:flex;align-items:baseline;justify-content:space-between;gap:var(--s2)}}
.title{{font-size:1.0625rem;font-weight:600;line-height:1.3}}
.num{{color:var(--muted);font-size:.8125rem;font-variant-numeric:tabular-nums;white-space:nowrap}}
.tag{{color:var(--muted);font-size:.9375rem;line-height:1.45}}
.status{{font-size:.8125rem;font-weight:600;color:var(--accent)}}
.status.done{{color:var(--ok)}}
.empty{{color:var(--muted)}}
@media (max-width:600px){{
  main{{padding:var(--s6) var(--s4) var(--s7)}}
  h1{{font-size:1.625rem}}
  .games{{grid-template-columns:1fr}}
  .game{{gap:var(--s3);padding:var(--s3) var(--s2)}}
  .art{{flex-basis:104px}}
  .fallback{{font-size:.75rem;padding:var(--s1) var(--s2)}}
  .tag{{font-size:.875rem;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}}
}}
@media (prefers-reduced-motion:reduce){{.game{{transition:none}}}}
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
  var cards=document.querySelectorAll(".game[data-slug]"),played=0;
  cards.forEach(function(c){{
    var d=day[c.dataset.clock]||day.utc,n=dayNum(c.dataset.start,d);
    var num=c.querySelector(".num"),st=c.querySelector(".status");
    if(n>=1){{num.textContent="#"+n;num.hidden=false}}
    var rec=null;
    try{{rec=store&&store.getItem("gametests:"+c.dataset.slug+":"+d)}}catch(e){{}}
    if(rec){{
      played++;var r="";try{{r=JSON.parse(rec).result||""}}catch(e){{}}
      st.textContent="Played today"+(r?" · "+r:"");st.classList.add("done");st.hidden=false;
    }}else if(n===1){{st.textContent="New today";st.hidden=false}}
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
