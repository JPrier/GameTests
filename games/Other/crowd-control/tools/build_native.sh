#!/usr/bin/env bash
# Build the Rust simulation as a GDExtension for this machine and copy it into native/.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here/sim"
cargo build --release --locked -p crowd_gdext
case "$(uname -s)" in
  Linux) cp target/release/libcrowd_gdext.so "$here/native/" ;;
  Darwin) cp target/release/libcrowd_gdext.dylib "$here/native/" ;;
  *) cp target/release/crowd_gdext.dll "$here/native/" ;;
esac
echo "native library ready in native/"
