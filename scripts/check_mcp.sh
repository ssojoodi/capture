#!/bin/bash
# Compile an isolated test app and run check_mcp.py against the bundled MCP helper.
# Run manually with bash scripts/check_mcp.sh after an Xcode Debug build in .build/DerivedData.
# Development check only; not packaged with Capture. Run separately from check_windows.sh to avoid focus conflicts.

set -euo pipefail
cd "$(dirname "$0")/.."
products="$PWD/.build/DerivedData/Build/Products/Debug"
mkdir -p .build/agent-checks
xcrun swiftc -swift-version 5 -module-cache-path .build/agent-checks/modules \
    -F "$products" -framework CaptureCore -Xlinker -rpath -Xlinker "$products" \
    Sources/CaptureAutomation/*.swift Sources/CaptureApp/AgentDocument.swift Sources/CaptureApp/AgentServer.swift \
    Sources/CaptureApp/UpdateController.swift Sources/CaptureApp/AppDelegate.swift Sources/CaptureApp/AppMenu.swift \
    Sources/CaptureApp/MainWindowController.swift Sources/CaptureApp/AnnotationCanvasView.swift \
    Sources/CaptureApp/TextAnnotationEditorView.swift Tests/CaptureAppChecks/AgentFixture.swift \
    -o .build/agent-checks/fixture
LLVM_PROFILE_FILE="$PWD/.build/agent-checks/default.profraw" python3 scripts/check_mcp.py "$products/Capture.app/Contents/Helpers/capture-mcp" .build/agent-checks/fixture
