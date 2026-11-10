#!/usr/bin/env bash
# Benchmark every game on the built site against the phone in .github/bench/target.json.
# Run after build-site.sh. Games are found the same way the build finds them, so a new game is
# benchmarked the first time it's pushed, with no setup.
#   .github/scripts/bench-site.sh
#   BENCH_ONLY=bloom .github/scripts/bench-site.sh
# Env: SITE_DIR (default: _site), BENCH_OUT (default: _bench/results.json)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SITE="${SITE_DIR:-$ROOT/_site}"
export BENCH_OUT="${BENCH_OUT:-$ROOT/_bench/results.json}"
mkdir -p "$(dirname "$BENCH_OUT")"

game_list="$(python3 "$ROOT/.github/scripts/gamelist.py" "$ROOT/games")"
mapfile -t games <<< "$game_list"

node "$ROOT/.github/bench/bench.mjs" "$SITE" "${games[@]}"
