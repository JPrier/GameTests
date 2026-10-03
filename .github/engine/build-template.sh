#!/usr/bin/env bash
# Build a Godot web export template containing only the engine features in a
# features file written by detect-features.gd.
#
#   .github/engine/build-template.sh <features.json> <out.zip> [godot-source-dir]
#
# Needs Emscripten and SCons on PATH (CI sets both up). Clones the Godot source
# for the version named in the features file when no source dir is given.
set -euo pipefail

features="$1"
out="$2"
version="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["godot"])' "$features")"
src="${3:-$HOME/godot-src-$version}"
mapfile -t detected < <(python3 -c 'import json,sys;print("\n".join(json.load(open(sys.argv[1]))["flags"]))' "$features")

if [ ! -d "$src" ]; then
  git clone --depth 1 --branch "${version}-stable" https://github.com/godotengine/godot "$src"
fi

flags=(
  platform=web target=template_release threads=no
  production=yes optimize=size_extra lto=full
  "${detected[@]}"
)
echo "Building Godot $version web template with: ${flags[*]}"
(cd "$src" && scons -j"$(nproc)" "${flags[@]}")
mkdir -p "$(dirname "$out")"
cp "$src/bin/godot.web.template_release.wasm32.nothreads.zip" "$out"
ls -l "$out"
