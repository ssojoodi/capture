#!/bin/bash
set -euo pipefail
cd "${SRCROOT:-$(dirname "$0")/..}"
configuration=$(echo "${CONFIGURATION:-Debug}" | tr '[:upper:]' '[:lower:]')
args=(--scratch-path "$PWD/.build/mcp-helper" -c "$configuration" --product capture-mcp)
# Xcode supplies both architectures for distribution builds.
for arch in ${ARCHS:-$(uname -m)}; do args+=(--arch "$arch"); done
swift build "${args[@]}"
bin=$(swift build "${args[@]}" --show-bin-path)
destination="${TARGET_BUILD_DIR:-$PWD/.build/DerivedData/Build/Products/Debug}/${CONTENTS_FOLDER_PATH:-Capture.app/Contents}/Helpers"
mkdir -p "$destination"
cp "$bin/capture-mcp" "$destination/capture-mcp"
