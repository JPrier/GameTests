#!/usr/bin/env bash
# GameTests build hook (.github/scripts/build-site.sh runs this before importing the project):
# the game needs its Rust simulation built for native tests and for the web export.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
"$here/tools/build_native.sh"
"$here/tools/build_web.sh"
