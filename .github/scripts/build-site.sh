#!/usr/bin/env bash
# Build every Godot game under games/<Category>/[<Subcategory>/]<slug>/ into a static site in _site/<slug>/.
#   .github/scripts/build-site.sh            # validate + test + export all games
#   SKIP_TESTS=1 .github/scripts/build-site.sh
# Env: GODOT_BIN (default: godot on PATH), SITE_DIR (default: _site)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
SITE="${SITE_DIR:-$ROOT/_site}"
# One stamp for the whole site: pages compare theirs with build.json to notice they are stale.
export GT_BUILD="${GITHUB_SHA:-local}"
GT_BUILD="${GT_BUILD:0:7} $(date -u +%Y-%m-%dT%H:%MZ)"
mkdir -p "$SITE"
fail=0

# Shared UI: every game carries the current ui/ copy, and product UI follows ui/VISUAL_GUIDE.md.
python3 "$ROOT/.github/scripts/sync-ui.py" --check || fail=1
python3 "$ROOT/.github/scripts/ui-lint.py" || fail=1

# Game folders, one per line; fails on duplicate slugs or games outside a category folder.
game_list="$(python3 "$ROOT/.github/scripts/gamelist.py" "$ROOT/games")"
mapfile -t games <<< "$game_list"

for dir in "${games[@]}"; do
  name="$(basename "$dir")"
  echo "::group::$name"
  # Optional per-game build hook (e.g. a native simulation library), run before the import.
  if [ -x "$dir/prebuild.sh" ]; then
    if ! "$dir/prebuild.sh"; then
      echo "::error::$name prebuild.sh failed"; fail=1; echo "::endgroup::"; continue
    fi
  fi
  "$GODOT" --headless --path "$dir" --import >/dev/null 2>&1 || true

  # Gate on the AgentBridge validator (parse/compile errors) and the game's tests, when present.
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
  fi

  mkdir -p "$SITE/$name"
  "$GODOT" --headless --path "$dir" --export-release "Web" "$SITE/$name/index.html"
  [ -s "$SITE/$name/index.wasm" ] || { echo "::error::$name export produced no build"; fail=1; }
  # Touch hardening (always on) and input diagnostics (inert unless the page has ?debug=input).
  python3 - "$SITE/$name/index.html" "$ROOT/.github/scripts/input-debug.js" "$ROOT/.github/scripts/touch-fix.js" "$ROOT/.github/scripts/stale-reload.js" <<'PY'
import json, os, sys
page, scripts = sys.argv[1], [open(f).read() for f in sys.argv[2:]]
html = open(page).read()
if "</head>" in html and "debug=input" not in html:
    build = os.environ["GT_BUILD"]
    tags = "<script>window.__gtBuild=%s</script>" % json.dumps(build)
    tags += "".join("<script>" + js + "</script>" for js in scripts)
    open(page, "w").write(html.replace("</head>", tags + "</head>", 1))
PY
  echo "::endgroup::"
done

python3 "$ROOT/.github/scripts/make-index.py" "$ROOT/games" "$SITE"
printf '{"build": "%s"}\n' "$GT_BUILD" > "$SITE/build.json"
exit $fail
