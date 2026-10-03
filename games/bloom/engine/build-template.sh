#!/usr/bin/env bash
# Build Bloom's slimmed-down Godot web export template.
#
# The stock web template ships the whole engine (3D, physics, advanced GUI,
# ICU text shaping, every image/audio/video codec, ...) in a ~39.5 MB .wasm.
# Bloom only draws 2D shapes and text with the built-in font, so this build
# keeps just what it needs. See ../LOAD_TIME.md for the measurements.
#
#   games/bloom/engine/build-template.sh [path/to/godot-source]
#
# Needs Emscripten (the version Godot's own CI uses, see EM_VERSION below) and
# SCons on PATH. Writes godot.web.template_release.wasm32.nothreads.zip next to
# this script; export_presets.cfg points custom_template/release at it.
# CI builds it with .github/workflows/bloom-engine.yml.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
EM_VERSION="${EM_VERSION:-4.0.11}"
SRC="${1:-$HERE/.godot-src}"

if [ ! -d "$SRC" ]; then
  git clone --depth 1 --branch "${GODOT_VERSION}-stable" https://github.com/godotengine/godot "$SRC"
fi

FLAGS=(
  platform=web target=template_release threads=no
  production=yes optimize=size_extra lto=full
  # Only the engine modules Bloom (and the AgentBridge autoload) touch.
  modules_enabled_by_default=no
  module_gdscript_enabled=yes      # game code
  module_regex_enabled=yes         # date validation in main.gd
  module_text_server_fb_enabled=yes  # simple text server instead of HarfBuzz/ICU
  module_freetype_enabled=yes      # renders the built-in fallback font
  module_websocket_enabled=yes     # AgentBridge references WebSocketPeer
  # Whole engine areas Bloom never uses.
  disable_3d=yes
  disable_advanced_gui=yes
  disable_physics_2d=yes
  disable_physics_3d=yes
  disable_navigation_2d=yes
  disable_navigation_3d=yes
  disable_xr=yes
  deprecated=no
  minizip=no
  # brotli stays on: the built-in font is WOFF2.
)

echo "Emscripten $(emcc --version | head -1) (Godot CI uses $EM_VERSION)"
(cd "$SRC" && scons -j"$(nproc)" "${FLAGS[@]}")
cp "$SRC/bin/godot.web.template_release.wasm32.nothreads.zip" "$HERE/"
ls -l "$HERE/godot.web.template_release.wasm32.nothreads.zip"
