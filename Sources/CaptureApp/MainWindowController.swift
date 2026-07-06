import AppKit
import CaptureCore

final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private let state = AnnotationDocumentState()
    private let canvasView: AnnotationCanvasView
    private let statusLabel = NSTextField(labelWithString: "Open, paste, or drop an image to start")
    private var keyMonitor: Any?

    private enum ToolbarID {
        static let toolbar = NSToolbar.Identifier("Capture.toolbar")
        static let open = NSToolbarItem.Identifier("open")
        static let paste = NSToolbarItem.Identifier("paste")
        static let copy = NSToolbarItem.Identifier("copy")
        static let export = NSToolbarItem.Identifier("export")
        static let undo = NSToolbarItem.Identifier("undo")
        static let redo = NSToolbarItem.Identifier("redo")
        static let color = NSToolbarItem.Identifier("color")
        static let thickness = NSToolbarItem.Identifier("thickness")
        static let zoomIn = NSToolbarItem.Identifier("zoomIn")
        static let zoomOut = NSToolbarItem.Identifier("zoomOut")
        static let zoomFit = NSToolbarItem.Identifier("zoomFit")
    }

    private struct ToolbarSpec {
        let identifier: NSToolbarItem.Identifier
        let label: String
        let symbol: String
        let action: Selector
    }

    private var toolbarSpecs: [ToolbarSpec] {
        [
            ToolbarSpec(identifier: ToolbarID.open, label: "Open", symbol: "folder", action: #selector(openImage(_:))),
            ToolbarSpec(identifier: ToolbarID.paste, label: "Paste", symbol: "doc.on.clipboard", action: #selector(pasteImage(_:))),
            ToolbarSpec(identifier: ToolbarID.copy, label: "Copy", symbol: "doc.on.doc", action: #selector(copyFlattenedImage(_:))),
            ToolbarSpec(identifier: ToolbarID.export, label: "Export JPG", symbol: "square.and.arrow.down", action: #selector(exportJPG(_:))),
            ToolbarSpec(identifier: ToolbarID.undo, label: "Undo", symbol: "arrow.uturn.backward", action: #selector(undo(_:))),
            ToolbarSpec(identifier: ToolbarID.redo, label: "Redo", symbol: "arrow.uturn.forward", action: #selector(redo(_:))),
            ToolbarSpec(identifier: ToolbarID.zoomIn, label: "Zoom In", symbol: "plus.magnifyingglass", action: #selector(zoomIn(_:))),
            ToolbarSpec(identifier: ToolbarID.zoomOut, label: "Zoom Out", symbol: "minus.magnifyingglass", action: #selector(zoomOut(_:))),
            ToolbarSpec(identifier: ToolbarID.zoomFit, label: "Fit", symbol: "arrow.up.left.and.down.right.magnifyingglass", action: #selector(zoomToFit(_:))),
            ToolbarSpec(identifier: NSToolbarItem.Identifier(Tool.select.rawValue), label: "Select", symbol: "cursorarrow", action: #selector(selectTool(_:))),
            ToolbarSpec(identifier: NSToolbarItem.Identifier(Tool.arrow.rawValue), label: "Arrow", symbol: "arrow.up.right", action: #selector(selectTool(_:))),
            ToolbarSpec(identifier: NSToolbarItem.Identifier(Tool.text.rawValue), label: "Text", symbol: "textformat", action: #selector(selectTool(_:))),
            ToolbarSpec(identifier: NSToolbarItem.Identifier(Tool.blur.rawValue), label: "Blur", symbol: "drop", action: #selector(selectTool(_:))),
            ToolbarSpec(identifier: NSToolbarItem.Identifier(Tool.crop.rawValue), label: "Crop", symbol: "crop", action: #selector(selectTool(_:))),
            ToolbarSpec(identifier: NSToolbarItem.Identifier(Tool.rectangle.rawValue), label: "Rect", symbol: "rectangle", action: #selector(selectTool(_:))),
            ToolbarSpec(identifier: NSToolbarItem.Identifier(Tool.ellipse.rawValue), label: "Ellipse", symbol: "oval", action: #selector(selectTool(_:)))
        ]
    }

    init() {
        canvasView = AnnotationCanvasView(state: state)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1120, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppMenu.appName
        window.appearance = NSAppearance(named: .aqua)
        window.toolbarStyle = .expanded
        window.titleVisibility = .visible
        window.minSize = NSSize(width: 760, height: 520)
        super.init(window: window)
        window.contentView = makeContentView()
        window.toolbar = makeToolbar()
        installKeyMonitor()
        canvasView.statusHandler = { [weak self] text in self?.statusLabel.stringValue = text }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            if command, let key = event.charactersIgnoringModifiers?.lowercased() {
                switch key {
                case "o": self.openImage(nil); return nil
                case "v": self.pasteImage(nil); return nil
                case "c": self.copyFlattenedImage(nil); return nil
                case "e": self.exportJPG(nil); return nil
                case "z":
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
                        self.redo(nil)
                    } else {
                        self.undo(nil)
                    }
                    return nil
                case "+", "=": self.zoomIn(nil); return nil
                case "-": self.zoomOut(nil); return nil
                case "0": self.zoomToFit(nil); return nil
                default: break
                }
            }
            if event.keyCode == 51 {
                self.deleteSelected(nil)
                return nil
            }
            if event.keyCode == 53 {
                self.state.selectedTool = .select
                self.canvasView.cancelInteraction()
                self.canvasView.toolDidChange()
                self.statusLabel.stringValue = "Tool: select"
                return nil
            }
            return event
        }
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.955, blue: 0.94, alpha: 1).cgColor

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = NSColor(calibratedWhite: 0.34, alpha: 1)
        statusLabel.font = .systemFont(ofSize: 12)

        root.addSubview(canvasView)
        root.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: root.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -6),

            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)
        ])
        return root
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: ToolbarID.toolbar)
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.open,
            ToolbarID.paste,
            .space,
            NSToolbarItem.Identifier(Tool.select.rawValue),
            NSToolbarItem.Identifier(Tool.arrow.rawValue),
            NSToolbarItem.Identifier(Tool.text.rawValue),
            NSToolbarItem.Identifier(Tool.blur.rawValue),
            NSToolbarItem.Identifier(Tool.crop.rawValue),
            NSToolbarItem.Identifier(Tool.rectangle.rawValue),
            NSToolbarItem.Identifier(Tool.ellipse.rawValue),
            .space,
            ToolbarID.undo,
            ToolbarID.redo,
            .space,
            ToolbarID.color,
            ToolbarID.thickness,
            .space,
            ToolbarID.zoomOut,
            ToolbarID.zoomIn,
            ToolbarID.zoomFit,
            .space,
            ToolbarID.copy,
            ToolbarID.export
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if let spec = toolbarSpecs.first(where: { $0.identifier == itemIdentifier }) {
            return toolbarItem(spec)
        }

        switch itemIdentifier {
        case ToolbarID.color:
            return colorToolbarItem(itemIdentifier)
        case ToolbarID.thickness:
            return thicknessToolbarItem(itemIdentifier)
        default:
            return nil
        }
    }

    private func toolbarItem(_ spec: ToolbarSpec) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: spec.identifier)
        item.label = spec.label
        item.paletteLabel = spec.label
        item.toolTip = spec.label
        item.image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: spec.label)
        item.target = self
        item.action = spec.action
        return item
    }

    private func colorToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Color"
        item.paletteLabel = "Color"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 96, height: 28), pullsDown: false)
        for captureColor in CapturePalette.all {
            popup.addItem(withTitle: captureColor.name)
        }
        popup.target = self
        popup.action = #selector(selectColor(_:))
        item.view = popup
        item.minSize = NSSize(width: 96, height: 28)
        item.maxSize = NSSize(width: 116, height: 28)
        return item
    }

    private func thicknessToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Size"
        item.paletteLabel = "Size"
        let control = NSSegmentedControl(labels: ["XS", "S", "M", "L", "XL"], trackingMode: .selectOne, target: self, action: #selector(selectThickness(_:)))
        control.frame = NSRect(x: 0, y: 0, width: 142, height: 28)
        control.selectedSegment = 2
        item.view = control
        item.minSize = NSSize(width: 142, height: 28)
        item.maxSize = NSSize(width: 152, height: 28)
        return item
    }

    @objc func selectTool(_ sender: Any?) {
        let raw: String?
        if let item = sender as? NSToolbarItem {
            raw = item.itemIdentifier.rawValue
        } else if let button = sender as? NSButton {
            raw = button.identifier?.rawValue
        } else {
            raw = nil
        }
        guard let raw, let tool = Tool(rawValue: raw) else { return }
        state.selectedTool = tool
        canvasView.toolDidChange()
        statusLabel.stringValue = "Tool: \(tool.rawValue)"
    }

    @objc func zoomIn(_ sender: Any?) {
        canvasView.zoomIn()
    }

    @objc func zoomOut(_ sender: Any?) {
        canvasView.zoomOut()
    }

    @objc func zoomToFit(_ sender: Any?) {
        canvasView.zoomToFit()
    }

    @objc func selectColor(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard CapturePalette.all.indices.contains(index) else { return }
        canvasView.applySelectedColor(CapturePalette.all[index].color)
    }

    @objc func selectThickness(_ sender: NSSegmentedControl) {
        let lineThicknesses: [CGFloat] = [4, 12, 16, 24, 32]
        let textSizes: [CGFloat] = [32, 40, 52, 64, 82]
        let index = sender.selectedSegment
        guard lineThicknesses.indices.contains(index), textSizes.indices.contains(index) else { return }
        canvasView.applySelectedSize(lineThickness: lineThicknesses[index], textSize: textSizes[index])
    }

    @objc func undo(_ sender: Any?) {
        canvasView.cancelInteraction()
        if state.undo() {
            canvasView.needsDisplay = true
            statusLabel.stringValue = "Undo"
        } else {
            statusLabel.stringValue = "Nothing to undo"
        }
    }

    @objc func redo(_ sender: Any?) {
        canvasView.cancelInteraction()
        if state.redo() {
            canvasView.needsDisplay = true
            statusLabel.stringValue = "Redo"
        } else {
            statusLabel.stringValue = "Nothing to redo"
        }
    }

    @objc func openImage(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .bmp, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            load(image: image, message: "Opened \(url.lastPathComponent)")
        }
    }

    @objc func pasteImage(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard) {
            load(image: image, message: "Pasted image from clipboard")
        } else {
            statusLabel.stringValue = "Clipboard does not contain an image"
        }
    }

    @objc func copyFlattenedImage(_ sender: Any?) {
        guard let image = state.flattenedImage() else {
            statusLabel.stringValue = "Nothing to copy"
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        statusLabel.stringValue = "Copied flattened image"
    }

    @objc func exportJPG(_ sender: Any?) {
        guard let data = state.jpegData() else {
            statusLabel.stringValue = "Nothing to export"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = "annotation.jpg"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                statusLabel.stringValue = "Exported \(url.lastPathComponent)"
            } catch {
                statusLabel.stringValue = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    @objc func deleteSelected(_ sender: Any?) {
        canvasView.cancelInteraction()
        state.deleteSelectedAnnotation()
        canvasView.needsDisplay = true
    }

    private func load(image: NSImage, message: String) {
        state.load(image: image)
        canvasView.zoomToFit()
        canvasView.needsDisplay = true
        statusLabel.stringValue = message
    }
}
