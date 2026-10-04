#!/bin/bash
set -euo pipefail
app="${1:?Pass the built Capture.app path}"
app_archs=$(xcrun lipo -archs "$app/Contents/MacOS/Capture")
core_archs=$(xcrun lipo -archs "$app/Contents/Frameworks/CaptureCore.framework/Versions/A/CaptureCore")
[[ "$app_archs" == "$core_archs" ]]
[[ "$app_archs" == *arm64* && "$app_archs" == *x86_64* ]]
[[ "$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")" == "com.local.Capture" ]]
[[ -f "$app/Contents/Resources/AppIcon.icns" ]]
echo "Verified Capture app and framework architectures: $app_archs"
