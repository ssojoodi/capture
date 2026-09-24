import AppKit
import CaptureCore

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
            autoreleasepool {
                runTextBackgroundChecks()
                runChecks(app: app, delegate: delegate)
            }
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

    static func runTextBackgroundChecks() {
        let controller = MainWindowController()
        let window = controller.window!
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        let canvas = canvas(in: window)
        let image = NSImage(size: NSSize(width: 600, height: 400), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        precondition(canvas.droppedImageHandler!(image))
        controller.selectTool(NSToolbarItem(itemIdentifier: .init("text")))
        let location = canvas.convert(NSPoint(x: canvas.bounds.midX - 130, y: canvas.bounds.midY - 38), to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                      clickCount: 1, pressure: 1)!
        canvas.mouseDown(with: event)
        let editor = canvas.subviews.compactMap { $0 as? TextAnnotationEditorView }.first!
        precondition(!editor.drawsBackground && !editor.contentView.drawsBackground && !editor.textView.drawsBackground,
                     "Editor must not compound the canvas background opacity")
        editor.textView.insertText("Text background", replacementRange: NSRange(location: 0, length: 0))
        precondition(canvas.selectedTextBackground.alphaComponent == 0.5)
        precondition(canvas.selectedTextBackground.withAlphaComponent(1).usingColorSpace(.sRGB) == NSColor.black.usingColorSpace(.sRGB))

        func snapshot(_ name: String) -> NSBitmapImageRep {
            window.displayIfNeeded()
            let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            let directory = URL(fileURLWithPath: "artifacts/verification", isDirectory: true)
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
            return bitmap
        }
        let editing = snapshot("text-background-editing.png")
        let samplePoint = NSPoint(x: editor.frame.minX + 20, y: editor.frame.minY + 12)
        canvas.commitTextEditing()
        let committed = snapshot("text-background-committed.png")
        let x = Int(samplePoint.x * CGFloat(editing.pixelsWide) / canvas.bounds.width)
        let y = Int((canvas.bounds.height - samplePoint.y) * CGFloat(editing.pixelsHigh) / canvas.bounds.height)
        let before = editing.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        let after = committed.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        precondition(abs(before.redComponent - after.redComponent) < 0.02, "Editing and committed backgrounds differ")
        precondition(before.redComponent > 0.4 && before.redComponent < 0.65, "Expected a half-opacity background")

        let item = window.toolbar!.items.first { $0.itemIdentifier.rawValue == "textBackground" }!
        let menu = (item.view as! NSPopUpButton).menu!
        let colors = menu.items.first { $0.title == "Colour" }!.submenu!
        let opacities = menu.items.first { $0.title == "Opacity" }!.submenu!
        controller.menuWillOpen(colors)
        controller.menuWillOpen(opacities)
        precondition(colors.items.first { $0.title == "Black" }!.state == .on)
        precondition(opacities.items.first { $0.tag == 50 }!.state == .on)
        let blue = colors.items.first { $0.title == "Blue" }!
        precondition(NSApp.sendAction(blue.action!, to: blue.target, from: blue))
        precondition(canvas.selectedTextBackground.alphaComponent == 0.5)
        let blueColor = canvas.selectedTextBackground.withAlphaComponent(1)
        let transparent = opacities.items.first { $0.tag == 0 }!
        precondition(NSApp.sendAction(transparent.action!, to: transparent.target, from: transparent))
        precondition(canvas.selectedTextBackground.alphaComponent == 0)
        precondition(canvas.selectedTextBackground.withAlphaComponent(1) == blueColor)
        controller.undo(nil)
        precondition(canvas.selectedTextBackground.alphaComponent == 0.5)
        controller.redo(nil)
        precondition(canvas.selectedTextBackground.alphaComponent == 0)
        controller.menuWillOpen(opacities)
        precondition(transparent.state == .on)
        window.close()
        print("PASS: text background defaults, editing compositing, colour/opacity menu, undo/redo")
    }
}
