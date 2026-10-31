#!/bin/bash
# Build the MCP helper and copy it into Capture.app/Contents/Helpers.
# Xcode runs this build phase for Debug and Release, using CONFIGURATION and ARCHS.
# The compiled helper ships with Capture; this build script does not.

set -euo pipefail
cd "${SRCROOT:-$(dirname "$0")/..}"
configuration=$(echo "${CONFIGURATION:-Debug}" | tr '[:upper:]' '[:lower:]')
args=(--scratch-path "$PWD/.build/mcp-helper" -c "$configuration" --product capture-mcp)
# Release artifacts target Apple Silicon and optimize all helper modules for size.
if [[ "$configuration" == release ]]; then args+=(-Xswiftc -Osize); fi
# Xcode supplies the target architectures (arm64 for Release).
for arch in ${ARCHS:-$(uname -m)}; do args+=(--arch "$arch"); done
swift build "${args[@]}"
bin=$(swift build "${args[@]}" --show-bin-path)
destination="${TARGET_BUILD_DIR:-$PWD/.build/DerivedData/Build/Products/Debug}/${CONTENTS_FOLDER_PATH:-Capture.app/Contents}/Helpers"
mkdir -p "$destination"
cp "$bin/capture-mcp" "$destination/capture-mcp"

if [[ "$configuration" == release && -n "${DWARF_DSYM_FOLDER_PATH:-}" ]]; then
    xcrun dsymutil "$bin/capture-mcp" -o "$DWARF_DSYM_FOLDER_PATH/capture-mcp.dSYM"
fi

# Preserve the vendored SDK license in distributed app bundles.
mkdir -p "$destination/../Resources"
cp "$PWD/Vendor/swift-sdk/LICENSE" "$destination/../Resources/MCP-SDK-LICENSE.txt"
