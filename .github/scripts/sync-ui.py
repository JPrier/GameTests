#!/usr/bin/env python3
"""Copy the shared GameTests UI into every game, or check that the copies match.

The source of truth is ui/ at the repo root:
  ui/gametests_ui/*      -> games/<...>/<game>/addons/gametests_ui/*
  ui/tests/test_gtui.gd* -> games/<...>/<game>/tests/test_gtui.gd*

Godot projects can only load files inside their own folder, so each game carries a copy.

Usage:
  sync-ui.py           write the copies
  sync-ui.py --check   exit 1 if any game's copy differs from ui/ (run in CI)
"""
import filecmp
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gamelist import find_games  # noqa: E402

SRC = ROOT / "ui"


def pairs(game):
    for f in sorted((SRC / "gametests_ui").iterdir()):
        if f.is_file():
            yield f, game / "addons" / "gametests_ui" / f.name
    for name in ("test_gtui.gd", "test_gtui.gd.uid"):
        yield SRC / "tests" / name, game / "tests" / name


def main():
    check = "--check" in sys.argv[1:]
    bad = []
    for folder, slug, _ in find_games(ROOT / "games"):
        for src, dst in pairs(folder):
            if dst.exists() and filecmp.cmp(src, dst, shallow=False):
                continue
            if check:
                bad.append(f"{dst.relative_to(ROOT)} differs from {src.relative_to(ROOT)}")
            else:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, dst)
                print(f"wrote {dst.relative_to(ROOT)}")
        stale = folder / "addons" / "gametests_ui"
        if stale.exists():
            known = {d.name for _, d in pairs(folder)}
            for f in stale.iterdir():
                if f.name not in known:
                    if check:
                        bad.append(f"{f.relative_to(ROOT)} is not in ui/gametests_ui/")
                    else:
                        f.unlink()
                        print(f"removed {f.relative_to(ROOT)}")
    if bad:
        for b in bad:
            print(f"::error::{b} (run .github/scripts/sync-ui.py)")
        sys.exit(1)
    if check:
        print("ui: every game has the current shared UI")


if __name__ == "__main__":
    main()
