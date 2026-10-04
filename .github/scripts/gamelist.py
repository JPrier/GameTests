#!/usr/bin/env python3
"""Find every game under games/, grouped by the category folders it sits in.

A game is any folder with a project.godot. The folders above it are its category path:
  games/Daily/bloom                 -> category ("Daily",)
  games/Daily/Airplanes/flightle    -> category ("Daily", "Airplanes")
  games/Other/kitchen-crawl         -> category ("Other",)

The game's folder name is its slug and its URL on the site (/<slug>/), so slugs must be unique
across all categories. Moving a game to another category never changes its URL.

Usage: gamelist.py <games_dir>    prints one game folder per line (exit 1 on duplicate slugs)
"""
import pathlib
import sys


def find_games(games_dir):
    """Return [(folder, slug, category_tuple)], sorted by path. Raises ValueError on bad layout."""
    games_dir = pathlib.Path(games_dir).resolve()
    found = []
    # Shallowest first, so a game is seen before anything nested inside it (e.g. in addons/).
    for proj in sorted(games_dir.rglob("project.godot"), key=lambda p: (len(p.parts), str(p))):
        folder = proj.parent
        if any(g in folder.parents for g, _, _ in found):
            continue
        found.append((folder, folder.name, folder.relative_to(games_dir).parts[:-1]))
    found.sort(key=lambda g: str(g[0]))

    problems = []
    seen = {}
    for folder, slug, cat in found:
        if not cat:
            problems.append(f"{folder}: put the game in a category folder, e.g. games/Other/{slug}/")
        if slug in seen:
            problems.append(f"{folder}: slug '{slug}' is already used by {seen[slug]} (folder names must be unique)")
        seen.setdefault(slug, folder)
    if problems:
        raise ValueError("\n".join(problems))
    return found


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    try:
        games = find_games(sys.argv[1])
    except ValueError as e:
        for line in str(e).splitlines():
            print(f"::error::{line}", file=sys.stderr)
        sys.exit(1)
    for folder, _, _ in games:
        print(folder)
