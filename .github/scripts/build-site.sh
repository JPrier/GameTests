#!/usr/bin/env bash
# Build every Godot game under games/ into a static site in _site/.
#   .github/scripts/build-site.sh            # validate + test + export all games
#   SKIP_TESTS=1 .github/scripts/build-site.sh
# Env: GODOT_BIN (default: godot on PATH), SITE_DIR (default: _site)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
SITE="${SITE_DIR:-$ROOT/_site}"
mkdir -p "$SITE"
fail=0

for proj in "$ROOT"/games/*/project.godot; do
  dir="$(dirname "$proj")"
  name="$(basename "$dir")"
  echo "::group::$name"
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
  echo "::endgroup::"
done

python3 "$ROOT/.github/scripts/make-index.py" "$ROOT/games" "$SITE"
exit $fail
