#!/bin/bash
# Check that the app, framework, and MCP helper contain only the Apple Silicon architecture.
# Also check the bundle identifier, app icon and bundled SDK license. Called by release.py before release signing.
# Run manually with bash scripts/verify_release.sh <path-to-Capture.app> after an Apple Silicon Release build.
# Build check only; does not verify notarization and is not packaged with Capture.

set -euo pipefail
app="${1:?Pass the built Capture.app path}"
app_archs=$(xcrun lipo -archs "$app/Contents/MacOS/Capture")
core_archs=$(xcrun lipo -archs "$app/Contents/Frameworks/CaptureCore.framework/Versions/A/CaptureCore")
helper_archs=$(xcrun lipo -archs "$app/Contents/Helpers/capture-mcp")
[[ "$app_archs" == "$core_archs" && "$app_archs" == "$helper_archs" ]]
[[ "$app_archs" == arm64 ]]
[[ "$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")" == "com.local.Capture" ]]
[[ -f "$app/Contents/Resources/AppIcon.icns" ]]
[[ -s "$app/Contents/Resources/MCP-SDK-LICENSE.txt" ]]
echo "Verified Capture app, framework and MCP helper architectures: $app_archs"
