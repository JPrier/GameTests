#!/usr/bin/env bash
# Build every Godot game under games/ into a static site in _site/.
#   .github/scripts/build-site.sh            # validate + test + export all games
#   SKIP_TESTS=1 .github/scripts/build-site.sh
# Env: GODOT_BIN (default: godot on PATH), SITE_DIR (default: _site)
#      ENGINES_DIR: output of plan-engines.sh plus built engines (<key>.zip). When set,
#      each game is exported with the slim engine built for it; a game whose engine
#      is missing falls back to the stock engine with a warning.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
SITE="${SITE_DIR:-$ROOT/_site}"
ENGINES="${ENGINES_DIR:-}"
[ -n "$ENGINES" ] && ENGINES="$(cd "$ENGINES" && pwd)"
mkdir -p "$SITE"
fail=0

# Pick the engine for a game: prints the template zip path, or nothing for stock.
engine_for() {
  local name="$1" feat key
  [ -n "$ENGINES" ] || return 0
  feat="$ENGINES/features/$name.json"
  [ -f "$feat" ] || { echo "::warning::$name: no feature file, using the stock engine" >&2; return 0; }
  key="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("" if d.get("engine")=="stock" else d["key"])' "$feat")"
  [ -n "$key" ] || return 0
  if [ -f "$ENGINES/$key.zip" ]; then echo "$ENGINES/$key.zip"
  else echo "::warning::$name: engine $key was not built, using the stock engine" >&2; fi
}

# Start downloading the engine and game data while the page is still loading.
add_preload() {
  python3 - "$1" <<'EOF'
import sys
p = sys.argv[1]
html = open(p, encoding="utf-8").read()
if 'rel="preload" href="index.wasm"' not in html:
    tags = ('<link rel="preload" href="index.wasm" as="fetch" type="application/wasm" crossorigin>'
            '<link rel="preload" href="index.pck" as="fetch" crossorigin>')
    html = html.replace("<head>", "<head>" + tags, 1)
    open(p, "w", encoding="utf-8").write(html)
EOF
}

for proj in "$ROOT"/games/*/project.godot; do
  dir="$(dirname "$proj")"
  name="$(basename "$dir")"
  echo "::group::$name"
  "$GODOT" --headless --path "$dir" --import >/dev/null 2>&1 || true

  # Gate on the AgentBridge validator (parse/compile errors) and the game's tests.
  # Every game must ship tests: they run here headless and again in the browser
  # on the game's own engine (.github/scripts/verify-web.js).
  if [ -z "${SKIP_TESTS:-}" ] && ! ls "$dir"/tests/test_*.gd >/dev/null 2>&1; then
    echo "::error::$name has no tests: add tests/test_*.gd (see README, 'Adding a game')"; fail=1; echo "::endgroup::"; continue
  fi
  if [ -f "$dir/addons/agent_bridge/agent_bridge.gd" ]; then
    report="$(mktemp)"
    if ! "$GODOT" --headless --path "$dir" -- --agent-validate --agent-out="$report" >/dev/null 2>&1; then
      echo "::error::$name failed validation"; cat "$report" 2>/dev/null || true; fail=1; echo "::endgroup::"; continue
    fi
    if [ -z "${SKIP_TESTS:-}" ] && [ -d "$dir/tests" ]; then
      if ! "$GODOT" --headless --path "$dir" -- --agent-run-tests --agent-out="$report" >/dev/null 2>&1; then
        echo "::error::$name tests failed"; cat "$report" 2>/dev/null || true; fail=1; echo "::endgroup::"; continue
      fi
      python3 -c "import json,sys;r=json.load(open(sys.argv[1]));print(f\"tests: {r['passed']}/{r['total']} passed\")" "$report"
    fi
  elif [ -z "${SKIP_TESTS:-}" ]; then
    echo "::error::$name has no addons/agent_bridge, so its tests can't run"; fail=1; echo "::endgroup::"; continue
  fi

  # Export with the game's own engine by pointing its preset at it for this run only.
  template="$(engine_for "$name")"
  presets="$dir/export_presets.cfg"
  cp "$presets" "$presets.bak"
  if [ -n "$template" ]; then
    echo "engine: $(basename "$template" .zip)"
    python3 - "$presets" "$template" <<'EOF'
import re, sys
p, t = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
s = re.sub(r'(?m)^custom_template/release=.*$', 'custom_template/release="%s"' % t, s)
open(p, "w", encoding="utf-8").write(s)
EOF
  else
    echo "engine: stock"
  fi
  rm -rf "$SITE/$name" && mkdir -p "$SITE/$name"
  "$GODOT" --headless --path "$dir" --export-release "Web" "$SITE/$name/index.html" || true
  mv "$presets.bak" "$presets"
  if [ -s "$SITE/$name/index.wasm" ]; then
    add_preload "$SITE/$name/index.html"
  else
    echo "::error::$name export produced no build"; fail=1
  fi
  echo "::endgroup::"
done

python3 "$ROOT/.github/scripts/make-index.py" "$ROOT/games" "$SITE"
exit $fail
