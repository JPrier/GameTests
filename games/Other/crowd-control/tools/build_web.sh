#!/usr/bin/env bash
# Build the Rust simulation for browsers (wasm32-unknown-unknown) into web/crowd_sim.wasm.
# Needs the target: rustup target add wasm32-unknown-unknown
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here/sim"
cargo build --locked --profile release-wasm --target wasm32-unknown-unknown -p crowd_wasm
cp target/wasm32-unknown-unknown/release-wasm/crowd_wasm.wasm "$here/web/crowd_sim.wasm"
if command -v wasm-opt >/dev/null 2>&1; then
  wasm-opt -O3 "$here/web/crowd_sim.wasm" -o "$here/web/crowd_sim.wasm"
fi
echo "web module ready: $(wc -c < "$here/web/crowd_sim.wasm") bytes"
