#!/bin/bash
set -eu
cd "$(dirname "$0")/.."

# Run after building the Debug app with xcodebuild.
products="$PWD/.build/DerivedData/Build/Products/Debug"
mkdir -p .build/window-checks
xcrun swiftc -swift-version 5 -module-cache-path .build/window-checks/modules \
    -F "$products" -framework CaptureCore \
    -Xlinker -rpath -Xlinker "$products" \
    Sources/CaptureApp/AppDelegate.swift Sources/CaptureApp/AppMenu.swift \
    Sources/CaptureApp/MainWindowController.swift Sources/CaptureApp/AnnotationCanvasView.swift \
    Sources/CaptureApp/TextAnnotationEditorView.swift Tests/CaptureAppChecks/WindowChecks.swift \
    -o .build/window-checks/check-windows
.build/window-checks/check-windows
