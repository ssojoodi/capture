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
                runTextBoundsChecks()
                runTextClickAwayChecks()
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

    static func runTextBoundsChecks() {
        let state = AnnotationDocumentState()
        let canvas = AnnotationCanvasView(state: state)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let pixels = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixels.setFillColor(NSColor.white.cgColor)
        pixels.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        state.load(image: NSImage(cgImage: pixels.makeImage()!, size: NSSize(width: 400, height: 300)))
        canvas.zoomToFit()
        func mouse(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        state.selectedTool = .text
        canvas.toolDidChange()
        canvas.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: 595, y: 445)))
        let text = state.annotations[0] as! TextAnnotation
        let imageBounds = CGRect(origin: .zero, size: state.imageSize)
        precondition(imageBounds.contains(text.bounds), "Edge placement must fit inside the image")
        let originalWidth = text.bounds.width
        let editor = canvas.subviews.compactMap { $0 as? TextAnnotationEditorView }.first!
        let longText = String(repeating: "Long text wraps within this box. ", count: 15)
        editor.textView.insertText(longText, replacementRange: NSRange(location: 0, length: 0))
        precondition(text.bounds.width == originalWidth && imageBounds.contains(text.bounds))
        precondition(editor.hasOverflow && editor.text == longText, "Overflow must preserve all text")
        let handle = NSPoint(x: editor.frame.maxX, y: editor.frame.maxY)
        precondition(canvas.hitTest(handle) === canvas, "Editor must not intercept a resize handle")
        canvas.commitTextEditing()
        precondition(text.text == longText)

        // Legacy overflowing box: the right handle is 60 pixels beyond the image.
        text.bounds = CGRect(x: 300, y: 100, width: 160, height: 100)
        state.selectedTool = .select
        canvas.toolDidChange()
        let beforeResize = text.bounds
        canvas.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: 660, y: 300)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: 580, y: 300)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: NSPoint(x: 580, y: 300)))
        precondition(text.bounds == CGRect(x: 300, y: 100, width: 80, height: 100), "Off-image handle must resize, not move")
        precondition(state.undo() && state.annotations[0].bounds == beforeResize)
        precondition(state.redo() && state.annotations[0].bounds.width == 80)
        state.annotations[0].bounds = beforeResize
        canvas.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: 660, y: 350)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: 580, y: 330)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: NSPoint(x: 580, y: 330)))
        precondition(state.annotations[0].bounds == CGRect(x: 300, y: 100, width: 80, height: 80),
                     "Off-image corner must resize both dimensions without moving the opposite corner")

        // Select can enlarge and move text beyond the image, including negative coordinates.
        canvas.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: 580, y: 330)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: 680, y: 490)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: NSPoint(x: 680, y: 490)))
        let enlarged = CGRect(x: 300, y: 100, width: 180, height: 240)
        precondition(state.annotations[0].bounds == enlarged)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: 550, y: 300)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: 100, y: 100)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: NSPoint(x: 100, y: 100)))
        precondition(state.annotations[0].bounds == CGRect(x: -150, y: -100, width: 180, height: 240))
        precondition(state.undo() && state.annotations[0].bounds == enlarged)
        precondition(state.redo() && state.annotations[0].bounds.minX == -150)

        // Creation stays bounded; resizing that same shape in Select can exceed the image.
        state.selectedAnnotationID = nil
        state.selectedTool = .rectangle
        canvas.toolDidChange()
        canvas.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: 500, y: 350)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: 680, y: 490)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: NSPoint(x: 680, y: 490)))
        precondition(state.annotations.last!.bounds == CGRect(x: 300, y: 200, width: 100, height: 100))
        state.selectedTool = .select
        canvas.toolDidChange()
        canvas.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: 600, y: 450)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: 680, y: 490)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: NSPoint(x: 680, y: 490)))
        precondition(state.annotations.last!.bounds == CGRect(x: 300, y: 200, width: 180, height: 140))
        let expandedOutput = state.flattenedImage()!
        precondition(expandedOutput.size == state.canvasBounds.size, "Output must include the expanded canvas")
        let outputBitmap = NSBitmapImageRep(cgImage: expandedOutput.cgImageForRendering()!)
        let artifactDirectory = URL(fileURLWithPath: "artifacts/verification", isDirectory: true)
        try! FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        try! outputBitmap.representation(using: .png, properties: [:])!
            .write(to: artifactDirectory.appendingPathComponent("expanded-canvas-output.png"))

        let small = TextAnnotationEditorView(frame: CGRect(x: 0, y: 0, width: 60, height: 30), text: longText,
                                            font: .boldSystemFont(ofSize: 12), textColor: .black,
                                            maximumSize: CGSize(width: 60, height: 40), scale: 0.5)
        precondition(small.frame.width == 60 && small.frame.height <= 40)
        precondition(small.textView.textContainerInset == CGSize(width: 5, height: 3))
        precondition(small.text == longText)
        print("PASS: text wraps within image bounds, overflow retains text, off-image handles resize, undo restores bounds")
    }

    static func runTextClickAwayChecks() {
        let state = AnnotationDocumentState()
        let canvas = AnnotationCanvasView(state: state)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        state.load(image: NSImage(size: NSSize(width: 600, height: 400)))
        canvas.zoomToFit()
        var selectedTool: Tool?
        canvas.toolSelectionHandler = { selectedTool = $0 }
        func chooseText() {
            state.selectedTool = .text
            canvas.toolDidChange()
        }
        func click(_ point: NSPoint) {
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(point, to: nil),
                                          modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            canvas.mouseDown(with: event)
            canvas.mouseUp(with: event)
        }
        let origin = NSPoint(x: 250, y: 220)
        let outside = NSPoint(x: 150, y: 150)
        chooseText()
        click(origin)
        let editor = canvas.subviews.compactMap { $0 as? TextAnnotationEditorView }.first!
        editor.textView.insertText("Keep this text", replacementRange: NSRange(location: 0, length: 0))
        click(outside)
        precondition(!canvas.isEditingText && state.selectedTool == .select && selectedTool == .select)
        precondition(state.annotations.count == 1 && (state.annotations[0] as! TextAnnotation).text == "Keep this text")
        precondition(state.selectedAnnotationID == nil)
        click(NSPoint(x: 160, y: 160))
        precondition(state.annotations.count == 1, "Repeated outside clicks must not create text")
        precondition(state.undo() && state.annotations.isEmpty)
        precondition(state.redo() && state.annotations.count == 1)

        chooseText()
        click(NSPoint(x: 250, y: 340))
        precondition(state.annotations.count == 2 && canvas.isEditingText)
        // Styling commits the editor, but the next outside click must still leave Text.
        canvas.applySelectedTextBackground(NSColor.white.withAlphaComponent(0.75))
        precondition(!canvas.isEditingText)
        click(NSPoint(x: origin.x + 20, y: origin.y + 20))
        precondition(state.selectedTool == .select && state.annotations.count == 2)
        precondition(state.selectedAnnotationID == state.annotations[0].id, "Click-away should select the existing annotation")
        print("PASS: text click-away commits content, returns to Select, avoids extra boxes, supports re-entry and undo")
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
        let samplePoint = NSPoint(x: editor.frame.minX + 20, y: editor.frame.minY + 2)
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
        controller.selectTool(NSToolbarItem(itemIdentifier: .init("text")))
        let newTextLocation = canvas.convert(NSPoint(x: canvas.bounds.midX - 180, y: canvas.bounds.midY + 100), to: nil)
        canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: newTextLocation, modifierFlags: [],
                                                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                eventNumber: 0, clickCount: 1, pressure: 1)!)
        let outside = canvas.convert(NSPoint(x: canvas.bounds.midX - 250, y: canvas.bounds.midY - 150), to: nil)
        canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: outside, modifierFlags: [],
                                                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                eventNumber: 0, clickCount: 1, pressure: 1)!)
        precondition(window.toolbar?.selectedItemIdentifier?.rawValue == "select", "Toolbar must show Select after click-away")
        window.close()
        print("PASS: text background defaults, editing compositing, colour/opacity menu, undo/redo")
    }
}
