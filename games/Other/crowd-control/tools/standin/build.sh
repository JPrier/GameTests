#!/usr/bin/env bash
# Build the browser-plumbing stand-in into web/crowd_sim.wasm (overwrites the real module!).
set -euo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
clang --target=wasm32 -O2 -nostdlib -Wl,--no-entry -Wl,--export-memory -o "$here/web/crowd_sim.wasm" "$here/tools/standin/standin.c"
echo "stand-in wasm: $(wc -c < "$here/web/crowd_sim.wasm") bytes"
