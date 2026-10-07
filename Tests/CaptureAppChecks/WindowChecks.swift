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
                runShortcutChecks(app: app)
                runSizeChecks()
                runAboutChecks(app: app)
                runDuplicateChecks()
                runTextBoundsChecks()
                runInPlaceTextChecks()
                runWindowSizingChecks()
                runPNGOutputChecks()
                runShareChecks(app: app)
                runAnnotationCopyChecks(app: app)
                runCenteredRenderingChecks()
                runTextClickAwayChecks()
                runTextBackgroundChecks()
                if ProcessInfo.processInfo.environment["CAPTURE_RELEASE_SCREENSHOT"] == "1" {
                    captureReleasePreview()
                }
                runChecks(app: app, delegate: delegate)
            }
            precondition(closedController == nil, "Closed canvas controller was retained")
            print("PASS: Cmd-N, independent canvases, active-window shortcuts, quit cancellation, close cleanup")
            exit(0)
        }
        app.run()
    }

    static func runShortcutChecks(app: NSApplication) {
        let state = AnnotationDocumentState()
        let controller = MainWindowController(state: state)
        let window = controller.window!
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        let identifiers = window.toolbar!.items.map { $0.itemIdentifier.rawValue }
        let sizeIndex = identifiers.firstIndex(of: "thickness")!
        precondition(Array(identifiers[sizeIndex...sizeIndex + 2]) == ["thickness", "color", "textBackground"])
        let buttons = window.toolbar!.items.compactMap { $0.view as? ShortcutToolButton }
        precondition(buttons.count == 17 && buttons.allSatisfy { !$0.showsShortcut })
        func flags(_ modifiers: NSEvent.ModifierFlags, in target: NSWindow) {
            app.sendEvent(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: target.windowNumber, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)!)
        }
        func press(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = .option, repeatKey: Bool = false) {
            app.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: repeatKey, keyCode: code)!)
        }
        let toolbarHeight = window.frame.height - window.contentLayoutRect.height
        flags(.option, in: window)
        precondition(buttons.allSatisfy { $0.showsShortcut })
        window.layoutIfNeeded()
        precondition(window.frame.height - window.contentLayoutRect.height == toolbarHeight, "Hints must not change toolbar height")
        window.setContentSize(NSSize(width: 760, height: 520))
        window.layoutIfNeeded()
        for item in window.toolbar!.items where item.view is ShortcutToolButton {
            precondition(item.menuFormRepresentation?.action == item.action, "Custom buttons need working overflow actions")
            precondition((item.menuFormRepresentation?.target as? MainWindowController) === controller)
        }
        let overflowEllipse = window.toolbar!.items.first { $0.itemIdentifier.rawValue == "ellipse" }!.menuFormRepresentation!
        precondition(app.sendAction(overflowEllipse.action!, to: overflowEllipse.target, from: overflowEllipse))
        precondition(state.selectedTool == .ellipse && overflowEllipse.state == .on)
        window.setContentSize(NSSize(width: 1120, height: 780))
        for (tool, code, character) in [(Tool.arrow, UInt16(0), "å"), (.text, 17, "†"), (.ellipse, 14, "´"), (.rectangle, 15, "®"), (.blur, 11, "∫"), (.crop, 8, "ç")] {
            press(character, code: code)
            precondition(state.selectedTool == tool, "Option must use the base letter, not the resulting special character")
            precondition(window.toolbar!.selectedItemIdentifier!.rawValue == tool.rawValue)
            precondition(buttons.first { $0.identifier!.rawValue == tool.rawValue }!.state == .on)
        }
        press("a", code: 0, modifiers: [])
        press("Å", code: 0, modifiers: [.option, .shift])
        press("a", code: 0, modifiers: [.option, .command])
        press("a", code: 0, modifiers: [.option, .control])
        precondition(state.selectedTool == .crop, "Other modifiers must not trigger tool shortcuts")
        let sizeView = window.toolbar!.items.first { $0.itemIdentifier.rawValue == "thickness" }!.view as! ShortcutSizeControl
        precondition(sizeView.showsShortcuts && !sizeView.isEnabled)
        precondition(sizeView.frame.height == 28, "Shortcut hints must preserve the original Size control height")
        press("¡", code: 18)
        precondition(!sizeView.isEnabled, "Size shortcuts must respect disabled tools")
        let commandHints = ["select": "Esc", "open": "⌘O", "paste": "⇧⌘V", "save": "⌘S", "copy": "⇧⌘C", "export": "⌘E",
                            "undo": "⌘Z", "redo": "⇧⌘Z", "zoomIn": "⌘=", "zoomOut": "⌘−", "zoomFit": "⌘0"]
        for (identifier, hint) in commandHints {
            precondition(buttons.first { $0.identifier!.rawValue == identifier }!.shortcut == hint)
        }
        press("å", code: 0)
        for (index, code) in [UInt16(18), 19, 20, 21, 23].enumerated() {
            press(String(index + 1), code: code)
            precondition(sizeView.selectedSegment == index)
        }
        flags([], in: window)
        precondition(buttons.allSatisfy { !$0.showsShortcut } && !sizeView.showsShortcuts)
        let canvas = canvas(in: window)
        precondition(canvas.droppedImageHandler!(NSImage(size: NSSize(width: 600, height: 400))))
        press("†", code: 17)
        let location = canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: nil)
        canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        let editor = canvas.subviews.compactMap { $0 as? TextAnnotationEditorView }.first!
        editor.textView.insertText("Keep this annotation", replacementRange: NSRange(location: 0, length: 0))
        press("™", code: 19)
        precondition((state.annotations.first as! TextAnnotation).fontSize == 40)
        precondition(canvas.isEditingText && sizeView.selectedSegment == 1)
        press("†", code: 17, repeatKey: true)
        precondition(canvas.isEditingText, "Key repeat must not interrupt an editor")
        press("\u{1b}", code: 53, modifiers: [])
        precondition(!canvas.isEditingText && state.selectedTool == .select)
        let arrowButton = buttons.first { $0.identifier!.rawValue == "arrow" }!
        arrowButton.performClick(nil)
        precondition(state.selectedTool == .arrow && arrowButton.state == .on)
        precondition((state.annotations.first as! TextAnnotation).text == "Keep this annotation")
        let previousZoom = canvas.zoomPercentage
        app.sendEvent(key("=", window: window))
        precondition(canvas.zoomPercentage > previousZoom, "Zoom In must match its Command-= hint")
        app.sendEvent(key("0", window: window))
        press("†", code: 17)
        canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        let nextEditor = canvas.subviews.compactMap { $0 as? TextAnnotationEditorView }.first!
        nextEditor.textView.insertText("Option commits text", replacementRange: NSRange(location: 0, length: 0))
        press("å", code: 0)
        precondition(!canvas.isEditingText && (state.annotations.last as! TextAnnotation).text == "Option commits text")
        flags(.option, in: window)
        let otherState = AnnotationDocumentState()
        let other = MainWindowController(state: otherState)
        other.showWindow(nil)
        other.window!.makeKeyAndOrderFront(nil)
        precondition(buttons.allSatisfy { !$0.showsShortcut }, "Losing focus must clear hints")
        press("†", code: 17)
        precondition(state.selectedTool == .arrow && otherState.selectedTool == .select)
        flags(.option, in: other.window!)
        precondition(other.window!.toolbar!.items.compactMap { $0.view as? ShortcutToolButton }.allSatisfy { $0.showsShortcut })
        precondition(buttons.allSatisfy { !$0.showsShortcut })
        other.window!.close()
        window.makeKeyAndOrderFront(nil)
        respondToAlerts([.alertSecondButtonReturn]) { window.performClose(nil) }
        print("PASS: Option tool shortcuts, special characters, text commit, repeat, hint release and window isolation")
    }

    static func runSizeChecks() {
        let state = AnnotationDocumentState()
        let controller = MainWindowController(state: state)
        let window = controller.window!
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        let canvas = canvas(in: window)
        let control = window.toolbar!.items.first { $0.itemIdentifier.rawValue == "thickness" }!.view as! NSSegmentedControl
        let image = NSImage(size: NSSize(width: 600, height: 400))
        state.load(image: image)
        canvas.zoomToFit()
        precondition(control.selectedSegment == 2, "New windows start at M")
        func selectTool(_ tool: Tool) {
            controller.selectTool(NSToolbarItem(itemIdentifier: .init(tool.rawValue)))
        }
        func choose(_ index: Int) {
            control.selectedSegment = index
            controller.selectThickness(control)
        }
        func draw(_ tool: Tool, activateTool: Bool = true) -> Annotation {
            if activateTool { selectTool(tool) }
            let center = canvas.convert(NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: nil)
            func mouse(_ type: NSEvent.EventType, _ offset: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: CGPoint(x: center.x + offset, y: center.y + offset),
                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            canvas.mouseDown(with: mouse(.leftMouseDown, -60))
            if tool == .text {
                let editor = canvas.subviews.compactMap { $0 as? TextAnnotationEditorView }.first!
                editor.textView.insertText("Size check", replacementRange: NSRange(location: 0, length: 0))
                canvas.commitTextEditing()
            } else {
                canvas.mouseDragged(with: mouse(.leftMouseDragged, 60))
                canvas.mouseUp(with: mouse(.leftMouseUp, 60))
            }
            return state.annotations.last!
        }
        func size(_ annotation: Annotation) -> CGFloat {
            switch annotation {
            case let a as ArrowAnnotation: return a.strokeWidth
            case let a as RectangleAnnotation: return a.strokeWidth
            case let a as EllipseAnnotation: return a.strokeWidth
            case let a as TextAnnotation: return a.fontSize
            default: preconditionFailure("Unexpected annotation")
            }
        }
        precondition(size(draw(.arrow)) == 16, "Initial M must draw M without clicking Size")
        for tool in [Tool.arrow, .rectangle, .ellipse, .text] {
            let expectedSizes: [CGFloat] = tool == .text ? [32, 40, 52, 64, 82] : [4, 12, 16, 24, 32]
            for (index, expected) in expectedSizes.enumerated() {
                selectTool(tool)
                choose(index)
                let annotation = draw(tool)
                precondition(size(annotation) == CGFloat(expected))
                precondition(control.selectedSegment == index)
                selectTool(.select)
                let otherIndex = (index + 1) % 5
                choose(otherIndex)
                precondition(control.selectedSegment == otherIndex)
                controller.undo(nil)
                precondition(control.selectedSegment == index)
                precondition(size(state.annotation(with: annotation.id)!) == CGFloat(expected))
                controller.redo(nil)
                precondition(control.selectedSegment == otherIndex)
            }
        }
        selectTool(.select)
        let small = ArrowAnnotation(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 150, y: 10), strokeWidth: 12)
        state.addAnnotation(small)
        precondition(control.selectedSegment == 1, "Selecting an existing annotation must display its size")
        let large = TextAnnotation(bounds: CGRect(x: 30, y: 80, width: 220, height: 80), text: "Large", fontSize: 64)
        state.addAnnotation(large)
        precondition(control.selectedSegment == 3)
        state.selectedAnnotationID = small.id
        precondition(control.selectedSegment == 1)
        controller.duplicateSelected(nil)
        precondition(control.selectedSegment == 1)
        let custom = RectangleAnnotation(bounds: CGRect(x: 50, y: 50, width: 90, height: 90), strokeWidth: 9)
        state.addAnnotation(custom)
        precondition(control.selectedSegment == -1, "Custom sizes must not show an incorrect preset")
        selectTool(.text)
        precondition(state.selectedAnnotationID == nil)
        choose(4)
        precondition(custom.strokeWidth == 9, "Changing tools must not restyle the old selection")
        precondition(size(draw(.text)) == 82)
        for tool in [Tool.blur, .crop] {
            selectTool(tool)
            precondition(!control.isEnabled && control.selectedSegment == -1)
        }
        selectTool(.arrow)
        precondition(control.isEnabled && control.selectedSegment == 4)
        state.addAnnotation(small.copyAnnotation(id: UUID()))
        precondition(control.selectedSegment == 1)
        precondition(size(draw(.arrow, activateTool: false)) == 12, "Drawing with a retained selection must match the displayed size")
        selectTool(.text)
        let center = canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: nil)
        canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: center, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        let editor = canvas.subviews.compactMap { $0 as? TextAnnotationEditorView }.first!
        editor.textView.insertText("Keep my text", replacementRange: NSRange(location: 0, length: 0))
        choose(1)
        let textID = state.selectedAnnotationID!
        precondition((state.annotation(with: textID) as! TextAnnotation).fontSize == 40)
        precondition(abs(editor.textView.font!.pointSize - 40 * CGFloat(canvas.zoomPercentage) / 100) < 0.5)
        controller.undo(nil)
        precondition(!canvas.isEditingText && control.selectedSegment == 4)
        precondition((state.annotation(with: textID) as! TextAnnotation).text == "Keep my text", "Undoing a size change must preserve text being edited")
        controller.redo(nil)
        precondition(control.selectedSegment == 1)
        let other = MainWindowController()
        let otherControl = other.window!.toolbar!.items.first { $0.itemIdentifier.rawValue == "thickness" }!.view as! NSSegmentedControl
        precondition(otherControl.selectedSegment == 2, "Canvas size defaults must be independent")
        other.window!.close()
        respondToAlerts([.alertSecondButtonReturn]) { window.performClose(nil) }
        print("PASS: all sizes for arrows, rectangles, ellipses and text; selection, undo/redo, tool changes and independent defaults")
    }

    static func runAboutChecks(app: NSApplication) {
        let appURL = URL(fileURLWithPath: ".build/DerivedData/Build/Products/Debug/Capture.app")
        let info = Bundle(url: appURL)!.infoDictionary!
        let configuration = try! String(contentsOfFile: "Config/Version.xcconfig", encoding: .utf8)
        func versionSetting(_ name: String) -> String {
            let line = configuration.split(separator: "\n").first { $0.hasPrefix(name + " =") }!
            return line.split(separator: "=", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
        }
        precondition(info["CFBundleShortVersionString"] as? String == versionSetting("MARKETING_VERSION"))
        precondition(info["CFBundleVersion"] as? String == versionSetting("CURRENT_PROJECT_VERSION"))
        precondition(info["NSHumanReadableCopyright"] as? String == "© Sahand Sojoodi, 2026")
        let menu = app.mainMenu!.items[0].submenu!
        let about = menu.items[0]
        precondition(about.title == "About Capture")
        precondition(about.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        let existing = Set(app.windows.map(\.windowNumber))
        menu.performActionForItem(at: 0)
        let panel = app.windows.first { !existing.contains($0.windowNumber) && $0.isVisible }!
        panel.close()
        print("PASS: About menu opens native panel; app contains version and build metadata")
    }

    static func runDuplicateChecks() {
        let state = AnnotationDocumentState()
        let controller = MainWindowController(state: state)
        let window = controller.window!
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        let canvas = canvas(in: window)
        precondition(canvas.droppedImageHandler!(NSImage(size: NSSize(width: 600, height: 400))))
        let menuItem = NSMenuItem(title: "Duplicate", action: #selector(MainWindowController.duplicateSelected(_:)), keyEquivalent: "d")
        precondition(!controller.validateMenuItem(menuItem))
        controller.selectTool(NSToolbarItem(itemIdentifier: .init("text")))
        let location = canvas.convert(NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: nil)
        canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        let editor = canvas.subviews.compactMap { $0 as? TextAnnotationEditorView }.first!
        editor.textView.insertText("Copy this text", replacementRange: NSRange(location: 0, length: 0))
        precondition(controller.validateMenuItem(menuItem))
        precondition(NSApp.mainMenu!.performKeyEquivalent(with: key("d", window: window)))
        precondition(!canvas.isEditingText && state.selectedTool == .select)
        precondition(state.annotations.count == 2)
        precondition(state.annotations.allSatisfy { ($0 as? TextAnnotation)?.text == "Copy this text" })
        precondition(state.selectedAnnotationID == state.annotations.last!.id)
        controller.undo(nil)
        precondition(state.annotations.count == 1)
        controller.redo(nil)
        precondition(state.annotations.count == 2)
        respondToAlerts([.alertSecondButtonReturn]) { window.performClose(nil) }
        print("PASS: Cmd-D commits text, duplicates selection, and supports undo/redo")
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
        let originalOrigin = text.bounds.origin
        let editor = canvas.subviews.compactMap { $0 as? TextAnnotationEditorView }.first!
        let longText = String(repeating: "Long text wraps within this box. ", count: 15)
        editor.textView.insertText(longText, replacementRange: NSRange(location: 0, length: 0))
        precondition(text.bounds.width == originalWidth && text.bounds.origin == originalOrigin)
        precondition(!editor.hasOverflow && editor.text == longText && text.bounds.height > imageBounds.height, "Typing must grow beyond the image without losing text")
        let handle = NSPoint(x: editor.frame.minX, y: editor.frame.minY)
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
        print("PASS: text grows beyond image bounds, overflow retains text, off-image handles resize, undo restores bounds")
    }

    static func runWindowSizingChecks() {
        for screen in [CGRect(x: 0, y: 30, width: 2000, height: 1200),
                       CGRect(x: -1800, y: 100, width: 1600, height: 1000),
                       CGRect(x: 0, y: 0, width: 600, height: 400)] {
            let frame = MainWindowController.initialWindowFrame(in: screen)
            precondition(screen.contains(frame))
            precondition(frame.midX == screen.midX && frame.midY == screen.midY)
            precondition(frame.width == min(screen.width, max(760, screen.width * 0.7)))
            precondition(frame.height == min(screen.height, max(520, screen.height * 0.7)))
        }
        let controller = MainWindowController()
        if let screen = NSScreen.main {
            let actual = controller.window!.frame
            let expected = MainWindowController.initialWindowFrame(in: screen.visibleFrame)
            precondition(abs(actual.width - expected.width) <= 1 && abs(actual.height - expected.height) <= 1,
                         "Window frame should match 70% sizing within AppKit pixel rounding")
        }
        controller.window!.close()
        print("PASS: window uses 70% of usable screen, centered and bounded on small/secondary screens")
    }

    static func runInPlaceTextChecks() {
        let state = AnnotationDocumentState()
        let canvas = AnnotationCanvasView(state: state)
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1000, height: 800),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let image = NSImage(size: CGSize(width: 400, height: 300), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill(); return true
        }
        for rect in [CGRect(x: -180, y: -100, width: 160, height: 90),
                     CGRect(x: 450, y: 350, width: 200, height: 100),
                     CGRect(x: -50, y: -40, width: 600, height: 400)] {
            state.load(image: image)
            let text = TextAnnotation(bounds: rect, text: "Centered", fontSize: 24, textColor: .red)
            state.addAnnotation(text)
            state.selectedTool = .select
            canvas.toolDidChange()
            canvas.zoomToFit()
            canvas.resetZoom()
            let revision = state.revisionID
            let zoom = CGFloat(canvas.zoomPercentage) / 100
            // These fixtures fit at 100%; the annotation center maps from expanded canvas space.
            precondition(zoom == 1)
            let point = CGPoint(x: canvas.bounds.midX + (rect.midX - state.canvasBounds.midX),
                                y: canvas.bounds.midY + (rect.midY - state.canvasBounds.midY))
            func edit() -> TextAnnotationEditorView {
                canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown,
                    location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!)
                return canvas.subviews.compactMap { $0 as? TextAnnotationEditorView }.first!
            }
            let editor = edit()
            precondition(text.bounds == rect && state.revisionID == revision)
            precondition(editor.frame.size == rect.size)
            canvas.commitTextEditing()
            precondition(text.bounds == rect && state.revisionID == revision)
            let next = edit()
            let longText = String(repeating: "More text wraps and grows. ", count: 30)
            next.textView.insertText(longText, replacementRange: NSRange(location: 0, length: next.text.utf16.count))
            precondition(text.bounds.origin == rect.origin && text.bounds.width == rect.width)
            precondition(text.bounds.height > rect.height)
            let grown = text.bounds
            next.textView.insertText("Short", replacementRange: NSRange(location: 0, length: next.text.utf16.count))
            precondition(text.bounds == grown, "Deleting text must not shrink the box")
            canvas.commitTextEditing()
            precondition(state.undo())
            let restored = state.annotations[0] as! TextAnnotation
            precondition(restored.bounds == rect && restored.text == "Centered")
            precondition(state.redo())
            precondition(state.annotations[0].bounds == grown && (state.annotations[0] as! TextAnnotation).text == "Short")
        }
        for scale: CGFloat in [0.5, 1, 2] {
            let size = CGSize(width: 400 * scale, height: 200 * scale)
            let editor = TextAnnotationEditorView(frame: CGRect(origin: .zero, size: size), text: "First line\nSecond line",
                font: .boldSystemFont(ofSize: 24 * scale), textColor: .red, maximumSize: size, scale: scale)
            let manager = editor.textView.layoutManager!
            let height = TextAnnotationLayout.contentHeight(manager: manager, container: editor.textView.textContainer!, font: editor.textView.font!)
            precondition(abs(editor.textView.textContainerInset.height + height / 2 - size.height / 2) < 0.01)
            precondition(editor.textView.alignment == .center)
        }
        print("PASS: off-image/oversized text edits in place; no-op edit preserves revision; growth and undo; centered at multiple zooms")
    }

    static func captureReleasePreview() {
        let pixels = CGContext(data: nil, width: 1000, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixels.setFillColor(NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1).cgColor)
        pixels.fill(CGRect(x: 0, y: 0, width: 1000, height: 600))
        let state = AnnotationDocumentState()
        state.load(image: NSImage(cgImage: pixels.makeImage()!, size: CGSize(width: 1000, height: 600)))
        state.addAnnotation(TextAnnotation(bounds: CGRect(x: 55, y: 390, width: 890, height: 150),
            text: "Copy an arrow. Paste it anywhere.", fontSize: 40,
            textColor: NSColor(srgbRed: 0.06, green: 0.15, blue: 0.24, alpha: 1), drawsBackground: false))
        state.addAnnotation(TextAnnotation(bounds: CGRect(x: 560, y: 145, width: 335, height: 145),
            text: "Transparent PNG\nImage-matched JPEG", fontSize: 28,
            textColor: NSColor(srgbRed: 0.06, green: 0.15, blue: 0.24, alpha: 1), drawsBackground: false))
        state.addAnnotation(RectangleAnnotation(bounds: CGRect(x: 530, y: 110, width: 395, height: 210),
            strokeColor: NSColor(srgbRed: 0.08, green: 0.48, blue: 0.62, alpha: 1), strokeWidth: 6))
        state.addAnnotation(ArrowAnnotation(start: CGPoint(x: 130, y: 150), end: CGPoint(x: 460, y: 270),
            color: CapturePalette.softRed, strokeWidth: 16))
        state.selectedTool = .select
        let controller = MainWindowController(state: state)
        controller.showWindow(nil)
        let window = controller.window!
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        canvas(in: window).zoomToFit()
        window.displayIfNeeded()
        let view = window.contentView!.superview!
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: "artifacts/verification", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("release-2026-10-03.png"))
        window.close()
        print("PASS: generated public-safe release window preview")
    }

    static func runAnnotationCopyChecks(app: NSApplication) {
        let state = AnnotationDocumentState()
        let controller = MainWindowController(state: state)
        let window = controller.window!
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        let canvas = canvas(in: window)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally(); window.close() }
        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let annotationItem = NSMenuItem(title: "Copy Annotation", action: #selector(MainWindowController.copySelectedAnnotation(_:)), keyEquivalent: "")
        pasteboard.setString("Preserve clipboard", forType: .string)
        let changeCount = pasteboard.changeCount
        controller.copySelectedAnnotation(to: pasteboard)
        precondition(pasteboard.changeCount == changeCount)
        precondition(!controller.validateMenuItem(copyItem) && !controller.validateMenuItem(annotationItem))
        state.load(image: NSImage(size: CGSize(width: 600, height: 400)))
        let arrow = ArrowAnnotation(start: CGPoint(x: -80, y: 20), end: CGPoint(x: 140, y: 180), color: .red, strokeWidth: 16)
        state.addAnnotation(arrow)
        state.selectedTool = .select
        window.makeFirstResponder(canvas)
        precondition((app.target(forAction: #selector(NSText.copy(_:))) as? MainWindowController) === controller,
                     "Canvas Copy must resolve to the active window controller")
        precondition(controller.validateMenuItem(copyItem) && controller.validateMenuItem(annotationItem))
        let revision = state.revisionID
        controller.copySelectedAnnotation(to: pasteboard)
        let png = pasteboard.data(forType: .png)!
        precondition(NSImage(pasteboard: pasteboard) != nil, "Native image paste must recognize annotation PNG")
        precondition(state.revisionID == revision && state.selectedAnnotationID == arrow.id)
        let directory = URL(fileURLWithPath: "artifacts/verification", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! png.write(to: directory.appendingPathComponent("copied-arrow.png"))
        canvas.zoomToFit()
        canvas.zoomOut()
        controller.copySelectedAnnotation(to: pasteboard)
        precondition(pasteboard.data(forType: .png) == png, "Zoom must not change object copy resolution")

        state.selectedTool = .text
        canvas.toolDidChange()
        let location = canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: nil)
        canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        let editor = canvas.subviews.compactMap { $0 as? TextAnnotationEditorView }.first!
        editor.textView.insertText("Copy only this text", replacementRange: NSRange(location: 0, length: 0))
        editor.textView.setSelectedRange(NSRange(location: 0, length: 4))
        precondition((app.target(forAction: #selector(NSText.copy(_:))) as? NSTextView) === editor.textView,
                     "Normal Copy must still reach the text editor")
        controller.copySelectedAnnotation(to: pasteboard)
        precondition(!canvas.isEditingText)
        precondition((state.annotation(with: state.selectedAnnotationID) as! TextAnnotation).text == "Copy only this text")
        precondition(pasteboard.data(forType: .png) != nil)
        let other = MainWindowController()
        other.showWindow(nil)
        other.window!.makeKeyAndOrderFront(nil)
        other.window!.makeFirstResponder(self.canvas(in: other.window!))
        precondition((app.target(forAction: #selector(NSText.copy(_:))) as? MainWindowController) === other)
        precondition(!other.validateMenuItem(copyItem), "Copy must use the active window's selection")
        other.window!.close()
        print("PASS: selected annotation PNG, unchanged clipboard with no selection, text Copy routing, zoom independence and active window")
    }

    static func runPNGOutputChecks() {
        let state = AnnotationDocumentState()
        let context = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor(srgbRed: 0.94, green: 0.91, blue: 0.84, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 70, height: 80))
        state.load(image: NSImage(cgImage: context.makeImage()!, size: CGSize(width: 120, height: 80)))
        let controller = MainWindowController(state: state)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally(); controller.window!.close() }
        controller.copyFlattenedImage(to: pasteboard)
        let data = pasteboard.data(forType: .png)!
        let bitmap = NSBitmapImageRep(data: data)!
        precondition(bitmap.colorAt(x: 100, y: 40)!.alphaComponent == 0)
        let panel = controller.makeExportPanel()
        precondition(panel.nameFieldStringValue == "annotation.png")
        precondition(panel.allowedContentTypes.map(\.identifier) == ["public.png", "public.jpeg"])
        let exportItem = controller.window!.toolbar!.items.first { $0.itemIdentifier.rawValue == "export" }!
        precondition(exportItem.label == "Export")
        let directory = URL(fileURLWithPath: "artifacts/verification", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! data.write(to: directory.appendingPathComponent("transparent-output.png"))
        try! state.jpegData()!.write(to: directory.appendingPathComponent("sampled-background-output.jpg"))
        print("PASS: clipboard publishes transparent PNG; export defaults to PNG and allows JPEG")
    }

    static func runShareChecks(app: NSApplication) {
        let state = AnnotationDocumentState()
        let controller = MainWindowController(state: state)
        let window = controller.window!
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas(in: window))
        let item = NSMenuItem(title: "Share...", action: #selector(MainWindowController.shareImage(_:)), keyEquivalent: "")
        precondition(!controller.validateMenuItem(item))
        precondition((app.target(forAction: item.action!) as? MainWindowController) === controller)
        let context = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 80))
        state.load(image: NSImage(cgImage: context.makeImage()!, size: CGSize(width: 120, height: 80)))
        precondition(controller.validateMenuItem(item))
        let revision = state.revisionID
        let edited = window.isDocumentEdited
        let clipboardChange = NSPasteboard.general.changeCount
        let session = try! controller.preparePNGShare()
        let second = try! controller.preparePNGShare()
        precondition(session.fileURL != second.fileURL)
        precondition(session.fileURL.lastPathComponent == "annotation.png")
        let bytes = try! Data(contentsOf: session.fileURL)
        precondition(bytes == state.imageData(format: .png))
        let bitmap = NSBitmapImageRep(data: bytes)!
        precondition(bitmap.pixelsWide == 120 && bitmap.pixelsHigh == 80)
        precondition(bitmap.colorAt(x: 100, y: 40)!.alphaComponent == 0)
        precondition(state.revisionID == revision && window.isDocumentEdited == edited)
        precondition(NSPasteboard.general.changeCount == clipboardChange)
        let picker = NSSharingServicePicker(items: [session.fileURL])
        let service = NSSharingService(named: .composeEmail)!
        session.sharingServicePicker(picker, didChoose: service)
        precondition(FileManager.default.fileExists(atPath: session.fileURL.path), "Choosing a destination must retain its attachment")
        session.sharingService(service, didShareItems: [session.fileURL])
        precondition(!FileManager.default.fileExists(atPath: session.fileURL.path))
        second.sharingServicePicker(picker, didChoose: nil)
        precondition(!FileManager.default.fileExists(atPath: second.fileURL.path))
        let failed = try! controller.preparePNGShare()
        var receivedError = false
        failed.onFailure = { _ in receivedError = true }
        failed.sharingService(service, didFailToShareItems: [failed.fileURL], error: NSError(domain: "Test", code: 1))
        precondition(receivedError && !FileManager.default.fileExists(atPath: failed.fileURL.path))
        do {
            _ = try controller.preparePNGShare(directory: URL(fileURLWithPath: "/dev/null"))
            preconditionFailure("Writing under a file must fail")
        } catch { }
        window.close()
        print("PASS: Share routing, validation, full transparent PNG, independent files, unchanged document/clipboard, completion/cancellation/failure cleanup")
    }

    static func runCenteredRenderingChecks() {
        let state = AnnotationDocumentState()
        let canvas = AnnotationCanvasView(state: state)
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let pixels = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixels.setFillColor(NSColor.white.cgColor)
        pixels.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        state.load(image: NSImage(cgImage: pixels.makeImage()!, size: CGSize(width: 600, height: 400)))
        let rect = CGRect(x: 50, y: 80, width: 500, height: 240)
        let text = TextAnnotation(bounds: rect, text: "Centered text\nSecond line", fontSize: 32, textColor: .red,
                                  backgroundColor: .black.withAlphaComponent(0.5))
        state.addAnnotation(text)
        state.selectedTool = .select
        canvas.toolDidChange()
        canvas.zoomToFit()
        canvas.resetZoom()
        let directory = URL(fileURLWithPath: "artifacts/verification", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func snapshot(_ name: String) -> NSBitmapImageRep {
            window.displayIfNeeded()
            let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
            return bitmap
        }
        func redBounds(_ bitmap: NSBitmapImageRep) -> CGRect {
            var result = CGRect.null
            precondition(bitmap.bitsPerSample == 8 && !bitmap.isPlanar && bitmap.samplesPerPixel >= 3)
            let data = bitmap.bitmapData!
            let colorOffset = bitmap.bitmapFormat.contains(.alphaFirst) ? 1 : 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let offset = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel + colorOffset
                    if data[offset] > 153 && data[offset + 1] < 77 && data[offset + 2] < 77 {
                        result = result.union(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
            }
            precondition(!result.isNull, "Text must render visible red glyphs")
            return result
        }
        for step in 0..<3 {
            let point = CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
            canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 2, pressure: 1)!)
            precondition(canvas.isEditingText)
            let editing = snapshot("centered-text-editing-\(step).png")
            let before = redBounds(editing)
            canvas.commitTextEditing()
            let after = redBounds(snapshot("centered-text-committed-\(step).png"))
            precondition(abs(before.midX - after.midX) <= 2 && abs(before.midY - after.midY) <= 2,
                         "Editor and committed glyph positions must match")
            precondition(abs(before.width - after.width) <= 3 && abs(before.height - after.height) <= 3,
                         "Editor and committed wrapping must match")
            precondition(abs(after.midX - CGFloat(editing.pixelsWide) / 2) <= 4,
                         "Text must be horizontally centered")
            precondition(abs(after.midY - CGFloat(editing.pixelsHigh) / 2) <= 20,
                         "Text block must be vertically centered, allowing font ascender/descender metrics")
            precondition(text.bounds == rect)
            canvas.zoomOut()
        }
        let output = NSBitmapImageRep(cgImage: state.flattenedImage()!.cgImageForRendering()!)
        try! output.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("centered-text-export.png"))
        let exported = redBounds(output)
        precondition(abs(exported.midX - 300) <= 2 && abs(exported.midY - 200) <= 10)
        print("PASS: editing, committed and exported centered text match at 100%, 80%, 64% zoom")
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
