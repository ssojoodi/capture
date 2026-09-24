import AppKit

// Standalone AppKit integration checks; run with bash scripts/check_windows.sh.
@main
enum WindowChecks {
    private static weak var closedController: NSWindowController?
    static func key(_ characters: String, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
                        timestamp: 0, windowNumber: window.windowNumber, context: nil,
                        characters: characters, charactersIgnoringModifiers: characters,
                        isARepeat: false, keyCode: 0)!
    }

    static func canvas(in window: NSWindow) -> AnnotationCanvasView {
        window.contentView!.subviews.compactMap { $0 as? AnnotationCanvasView }.first!
    }

    static func markEdited(_ window: NSWindow) {
        let controller = window.windowController as! MainWindowController
        controller.selectTool(NSToolbarItem(itemIdentifier: .init("rectangle")))
        let canvas = canvas(in: window)
        let center = canvas.convert(NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: nil)
        func mouse(_ type: NSEvent.EventType, _ offset: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: center.x + offset, y: center.y + offset),
                              modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                              context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, -40))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 40))
        canvas.mouseUp(with: mouse(.leftMouseUp, 40))
        precondition(window.isDocumentEdited, "Fixture must have unsaved edits")
    }

    static func respondToAlerts(_ responses: [NSApplication.ModalResponse], during action: () -> Void) {
        var remaining = responses
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            if NSApp.modalWindow != nil, !remaining.isEmpty {
                NSApp.stopModal(withCode: remaining.removeFirst())
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        defer { timer.invalidate() }
        action()
        precondition(remaining.isEmpty, "Expected all unsaved-change prompts")
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.mainMenu = AppMenu.makeMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            autoreleasepool { runChecks(app: app, delegate: delegate) }
            precondition(closedController == nil, "Closed canvas controller was retained")
            print("PASS: Cmd-N, independent canvases, active-window shortcuts, quit cancellation, close cleanup")
            exit(0)
        }
        app.run()
    }

    static func runChecks(app: NSApplication, delegate: AppDelegate) {
        let first = app.keyWindow!
        let image = NSImage(size: NSSize(width: 400, height: 300), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        precondition(canvas(in: first).droppedImageHandler!(image))
        markEdited(first)

        precondition(app.mainMenu!.performKeyEquivalent(with: key("n", window: first)))
        let second = app.keyWindow!
        precondition(first !== second && first.isVisible && first.isDocumentEdited)
        precondition(!second.isDocumentEdited)
        precondition(canvas(in: second).droppedImageHandler!(image))
        let firstZoom = canvas(in: first).zoomPercentage
        let secondZoom = canvas(in: second).zoomPercentage
        app.sendEvent(key("-", window: second))
        precondition(canvas(in: first).zoomPercentage == firstZoom, "Background canvas changed")
        precondition(canvas(in: second).zoomPercentage < secondZoom, "Active canvas missed shortcut")
        (second.windowController as! MainWindowController).zoomToFit(nil)
        markEdited(second)

        respondToAlerts([.alertSecondButtonReturn, .alertThirdButtonReturn]) {
            precondition(delegate.applicationShouldTerminate(app) == .terminateCancel)
        }
        precondition(first.isDocumentEdited && second.isDocumentEdited,
                     "Cancel Quit must preserve unsaved state in every window")

        respondToAlerts([.alertThirdButtonReturn]) { second.performClose(nil) }
        precondition(second.isVisible && first.isVisible)
        closedController = second.windowController
        respondToAlerts([.alertSecondButtonReturn]) { second.performClose(nil) }
        precondition(!second.isVisible && first.isVisible)
        respondToAlerts([.alertSecondButtonReturn]) {
            precondition(delegate.applicationShouldTerminate(app) == .terminateNow)
        }
        // Avoid triggering the application's last-window-closed quit during cleanup.
        app.delegate = nil
        first.close()
    }
}
