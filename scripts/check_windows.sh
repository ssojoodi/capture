#!/bin/bash
# Compile and run native AppKit checks for windows, editing, sharing, updates, and agent commands.
# Run manually with bash scripts/check_windows.sh after an Xcode Debug build in .build/DerivedData.
# Opens test windows; run separately from other UI checks to avoid focus conflicts. Not packaged with Capture.

set -eu
cd "$(dirname "$0")/.."

products="$PWD/.build/DerivedData/Build/Products/Debug"
mkdir -p .build/window-checks
xcrun swiftc -swift-version 5 -module-cache-path .build/window-checks/modules \
    -F "$products" -framework CaptureCore \
    -Xlinker -rpath -Xlinker "$products" \
    Sources/CaptureAutomation/AgentWire.swift Sources/CaptureAutomation/AgentTools.swift \
    Sources/CaptureApp/AgentDocument.swift Sources/CaptureApp/AgentServer.swift \
    Sources/CaptureApp/UpdateController.swift Sources/CaptureApp/AppDelegate.swift Sources/CaptureApp/AppMenu.swift \
    Sources/CaptureApp/MainWindowController.swift Sources/CaptureApp/AnnotationCanvasView.swift \
    Sources/CaptureApp/TextAnnotationEditorView.swift Tests/CaptureAppChecks/WindowChecks.swift Tests/CaptureAppChecks/UpdateChecks.swift Tests/CaptureAppChecks/AgentChecks.swift \
    -o .build/window-checks/check-windows
LLVM_PROFILE_FILE="$PWD/.build/window-checks/default.profraw" .build/window-checks/check-windows
