#!/usr/bin/env bash
# Work out which web engine each game needs.
#
#   .github/scripts/plan-engines.sh <godot-source-dir> [out-dir]
#
# For every games/*/ project: imports it, runs .github/engine/detect-features.gd and
# writes <out-dir>/features/<game>.json. Games that detect the same features share
# an engine, so <out-dir>/engines.json lists each distinct engine once:
#   [{"key": "4.7.2-0ecf03154043-1a2b3c4d", "features": "features/bloom.json", "games": ["bloom", ...]}]
# The key also covers build-template.sh, so changing the build recipe rebuilds every engine.
# Env: GODOT_BIN (default: godot on PATH).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
SRC="$1"
OUT="$(mkdir -p "${2:-$ROOT/_engines}" && cd "${2:-$ROOT/_engines}" && pwd)"
mkdir -p "$OUT/features"

python3 "$ROOT/.github/engine/modules-map.py" "$SRC" > "$OUT/modules.json"
recipe="$(sha256sum "$ROOT/.github/engine/build-template.sh" | cut -c1-8)"

for proj in "$ROOT"/games/*/project.godot; do
  dir="$(dirname "$proj")"
  name="$(basename "$dir")"
  "$GODOT" --headless --path "$dir" --import >/dev/null 2>&1 || true
  if ! "$GODOT" --headless --path "$dir" --script "$ROOT/.github/engine/detect-features.gd" \
      -- --modules="$OUT/modules.json" --out="$OUT/features/$name.json" >/dev/null 2>&1 \
      || [ ! -s "$OUT/features/$name.json" ]; then
    echo "::warning::$name: feature detection failed; it will use the stock engine"
    printf '{"engine": "stock", "key": "stock", "flags": [], "features": {}}\n' > "$OUT/features/$name.json"
  fi
done

python3 - "$OUT" "$recipe" <<'EOF'
import json, pathlib, sys
out, recipe = pathlib.Path(sys.argv[1]), sys.argv[2]
engines = {}
for f in sorted((out / "features").glob("*.json")):
    d = json.loads(f.read_text())
    if d.get("engine") == "stock":
        print(f"{f.stem:18} stock engine")
        continue
    d["key"] = f'{d["key"]}-{recipe}'
    f.write_text(json.dumps(d, indent=2) + "\n")
    e = engines.setdefault(d["key"], {"key": d["key"], "features": f"features/{f.name}", "games": []})
    e["games"].append(f.stem)
    on = ", ".join(sorted(d["features"])) or "2D only"
    print(f'{f.stem:18} {d["key"]}  ({on}; modules: {", ".join(sorted(d["modules"]))})')
(out / "engines.json").write_text(json.dumps(list(engines.values()), indent=2) + "\n")
print(f"{len(engines)} distinct engine(s)")
EOF
