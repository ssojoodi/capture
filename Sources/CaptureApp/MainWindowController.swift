import AppKit
import CaptureCore
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let state: AnnotationDocumentState
    private let canvasView: AnnotationCanvasView
    private let statusLabel = NSTextField(labelWithString: "Open, paste, or drop an image to start")
    private weak var sizeControl: NSSegmentedControl?
    private var keyMonitor: Any?
    private var sourceURL: URL?
    private var sourceFormat: RasterImageFormat?
    private var savedRevisionID: UUID?
    var onWindowClosed: ((MainWindowController) -> Void)?
    private static let toolShortcuts: [Tool: String] = [
        .arrow: "a", .text: "t", .ellipse: "e", .rectangle: "r", .blur: "b", .crop: "c"
    ]
    private static let shortcutHints: [NSToolbarItem.Identifier: String] = [
        .init(Tool.select.rawValue): "Esc",
        ToolbarID.open: "⌘O", ToolbarID.paste: "⇧⌘V", ToolbarID.save: "⌘S",
        ToolbarID.copy: "⇧⌘C", ToolbarID.export: "⌘E", ToolbarID.undo: "⌘Z",
        ToolbarID.redo: "⇧⌘Z", ToolbarID.zoomIn: "⌘=", ToolbarID.zoomOut: "⌘−", ToolbarID.zoomFit: "⌘0"
    ]
    private static let textBackgroundColors = [
        CaptureColor(name: "Black", color: .black),
        CaptureColor(name: "White", color: .white)
    ] + Array(CapturePalette.all.prefix(5))

    private enum ToolbarID {
        static let toolbar = NSToolbar.Identifier("Capture.toolbar")
        static let open = NSToolbarItem.Identifier("open")
        static let paste = NSToolbarItem.Identifier("paste")
        static let save = NSToolbarItem.Identifier("save")
        static let copy = NSToolbarItem.Identifier("copy")
        static let export = NSToolbarItem.Identifier("export")
        static let undo = NSToolbarItem.Identifier("undo")
        static let redo = NSToolbarItem.Identifier("redo")
        static let color = NSToolbarItem.Identifier("color")
        static let thickness = NSToolbarItem.Identifier("thickness")
        static let textBackground = NSToolbarItem.Identifier("textBackground")
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
            ToolbarSpec(identifier: ToolbarID.save, label: "Save", symbol: "square.and.arrow.down", action: #selector(save(_:))),
            ToolbarSpec(identifier: ToolbarID.copy, label: "Copy Image", symbol: "doc.on.doc", action: #selector(copyFlattenedImage(_:))),
            ToolbarSpec(identifier: ToolbarID.export, label: "Export", symbol: "square.and.arrow.down", action: #selector(exportImage(_:))),
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

    static func initialWindowFrame(in visibleFrame: CGRect) -> CGRect {
        let size = CGSize(width: min(visibleFrame.width, max(760, visibleFrame.width * 0.7)),
                          height: min(visibleFrame.height, max(520, visibleFrame.height * 0.7)))
        return CGRect(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    init(state: AnnotationDocumentState = AnnotationDocumentState(), screen: NSScreen? = NSScreen.main) {
        self.state = state
        canvasView = AnnotationCanvasView(state: state)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1120, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppMenu.appName
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.toolbarStyle = .expanded
        window.titleVisibility = .visible
        let visibleFrame = screen?.visibleFrame
        window.minSize = NSSize(width: min(760, visibleFrame?.width ?? 760),
                                height: min(520, visibleFrame?.height ?? 520))
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView()
        window.toolbar = makeToolbar()
        if let visibleFrame {
            window.setFrame(Self.initialWindowFrame(in: visibleFrame), display: false)
        }
        window.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(state.selectedTool.rawValue)
        canvasView.toolSelectionHandler = { [weak self] tool in
            self?.window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tool.rawValue)
            self?.updateSizeControl()
            self?.updateToolButtons()
        }
        updateToolButtons()
        installKeyMonitor()
        canvasView.statusHandler = { [weak self] text in self?.statusLabel.stringValue = text }
        canvasView.droppedFileHandler = { [weak self] url in self?.openDroppedFile(url) ?? false }
        canvasView.droppedImageHandler = { [weak self] image in self?.replaceWithImage(image, sourceURL: nil, message: "Dropped image") ?? false }
        state.selectionDidChange = { [weak self] in self?.updateSizeControl() }
        state.revisionDidChange = { [weak self] _ in
            self?.updateDocumentPresentation()
            self?.updateSizeControl()
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, let window = self.window else { return event }
            if event.type == .flagsChanged {
                self.updateShortcutHints(event.modifierFlags)
                return event
            }
            guard event.window === window, window.isKeyWindow,
                  NSApp.modalWindow == nil, window.attachedSheet == nil else { return event }
            let shortcutModifiers = event.modifierFlags.intersection([.option, .command, .control, .shift])
            if shortcutModifiers == .option,
               let key = event.characters(byApplyingModifiers: [])?.lowercased() {
                if let tool = Self.toolShortcuts.first(where: { $0.value == key })?.key {
                    if !event.isARepeat {
                        self.activateTool(tool)
                    }
                    return nil
                }
                if let number = Int(key), let preset = AnnotationCanvasView.SizePreset(rawValue: number - 1) {
                    if !event.isARepeat && self.canvasView.canChangeSize {
                        self.canvasView.applySelectedSize(preset)
                        self.updateSizeControl()
                    }
                    return nil
                }
            }
            if event.keyCode == 53 && shortcutModifiers.isEmpty {
                self.activateTool(.select)
                return nil
            }
            if self.canvasView.isEditingText || window.firstResponder is NSTextView {
                return event
            }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommand = modifiers.contains(.command)
            let hasShift = modifiers.contains(.shift)
            if hasCommand, let key = event.charactersIgnoringModifiers?.lowercased() {
                switch key {
                case "o": self.openImage(nil); return nil
                case "v" where hasShift: self.pasteImage(nil); return nil
                case "c" where hasShift: self.copyFlattenedImage(nil); return nil
                case "e": self.exportImage(nil); return nil
                case "s" where hasShift: self.saveAs(nil); return nil
                case "s": self.save(nil); return nil
                case "z":
                    if hasShift {
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
            ToolbarID.save,
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
            ToolbarID.thickness,
            ToolbarID.color,
            ToolbarID.textBackground,
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

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tool.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
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
        case ToolbarID.textBackground:
            return textBackgroundToolbarItem(itemIdentifier)
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
        let tool = Tool(rawValue: spec.identifier.rawValue)
        let optionKey = tool.flatMap { Self.toolShortcuts[$0] }
        if let hint = optionKey?.uppercased() ?? Self.shortcutHints[spec.identifier] {
            let button = ShortcutToolButton(frame: NSRect(x: 0, y: 0, width: 52, height: 34))
            button.shortcut = hint
            button.image = item.image?.withSymbolConfiguration(.init(pointSize: 20, weight: .regular))
            button.widthAnchor.constraint(equalToConstant: 52).isActive = true
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            button.imagePosition = .imageOnly
            button.bezelStyle = .texturedRounded
            button.setButtonType(tool == nil ? .momentaryPushIn : .toggle)
            button.isBordered = false
            button.identifier = .init(spec.identifier.rawValue)
            button.target = self
            button.action = spec.action
            button.setAccessibilityLabel(spec.label)
            item.toolTip = "\(spec.label) (\(optionKey == nil ? hint : "⌥" + hint))"
            button.toolTip = item.toolTip
            item.view = button
            let menuItem = NSMenuItem(title: spec.label, action: spec.action, keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = spec.identifier.rawValue
            item.menuFormRepresentation = menuItem
        }
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

    private func textBackgroundToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Text Background"
        item.paletteLabel = item.label
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 112, height: 28), pullsDown: true)
        popup.menu = makeTextBackgroundMenu()
        popup.toolTip = "Background colour and opacity for selected and new text"
        popup.setAccessibilityLabel("Text Background")
        item.view = popup
        let overflowItem = NSMenuItem(title: item.label, action: nil, keyEquivalent: "")
        overflowItem.submenu = makeTextBackgroundMenu()
        item.menuFormRepresentation = overflowItem
        return item
    }

    private func makeTextBackgroundMenu() -> NSMenu {
        let menu = NSMenu(title: "Text Background")
        menu.addItem(withTitle: "Background", action: nil, keyEquivalent: "")
        let colorItem = menu.addItem(withTitle: "Colour", action: nil, keyEquivalent: "")
        let colors = NSMenu(title: "Colour")
        colors.delegate = self
        for (index, color) in Self.textBackgroundColors.enumerated() {
            let item = colors.addItem(withTitle: color.name, action: #selector(selectTextBackgroundColor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
        }
        colorItem.submenu = colors
        let opacityItem = menu.addItem(withTitle: "Opacity", action: nil, keyEquivalent: "")
        let opacities = NSMenu(title: "Opacity")
        opacities.delegate = self
        for percent in [0, 25, 50, 75, 100] {
            let title = percent == 0 ? "0% (None)" : "\(percent)%"
            let item = opacities.addItem(withTitle: title, action: #selector(selectTextBackgroundOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = percent
        }
        opacityItem.submenu = opacities
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        let color = canvasView.selectedTextBackground
        for item in menu.items {
            if item.action == #selector(selectTextBackgroundColor(_:)), Self.textBackgroundColors.indices.contains(item.tag) {
                let matches = color.withAlphaComponent(1).usingColorSpace(.sRGB)
                    == Self.textBackgroundColors[item.tag].color.usingColorSpace(.sRGB)
                item.state = matches ? .on : .off
            } else if item.action == #selector(selectTextBackgroundOpacity(_:)) {
                item.state = abs(color.alphaComponent * 100 - CGFloat(item.tag)) < 0.01 ? .on : .off
            }
        }
    }

    @objc func selectTextBackgroundColor(_ sender: NSMenuItem) {
        guard Self.textBackgroundColors.indices.contains(sender.tag) else { return }
        let color = Self.textBackgroundColors[sender.tag].color.withAlphaComponent(canvasView.selectedTextBackground.alphaComponent)
        canvasView.applySelectedTextBackground(color)
    }

    @objc func selectTextBackgroundOpacity(_ sender: NSMenuItem) {
        let opacity = CGFloat(min(100, max(0, sender.tag))) / 100
        canvasView.applySelectedTextBackground(canvasView.selectedTextBackground.withAlphaComponent(opacity))
    }

    private func thicknessToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Size"
        item.paletteLabel = "Size"
        let control = ShortcutSizeControl(labels: AnnotationCanvasView.SizePreset.allCases.map(\.label), trackingMode: .selectOne, target: self, action: #selector(selectThickness(_:)))
        control.frame = NSRect(x: 0, y: 0, width: 142, height: 28)
        control.segmentDistribution = .fillEqually
        for preset in AnnotationCanvasView.SizePreset.allCases {
            control.setToolTip("\(preset.label) (⌥\(preset.rawValue + 1))", forSegment: preset.rawValue)
        }
        sizeControl = control
        updateSizeControl()
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
        } else if let menuItem = sender as? NSMenuItem {
            raw = menuItem.representedObject as? String
        } else {
            raw = nil
        }
        guard let raw, let tool = Tool(rawValue: raw) else { return }
        activateTool(tool)
    }

    private func activateTool(_ tool: Tool) {
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

    private func updateSizeControl() {
        sizeControl?.isEnabled = canvasView.canChangeSize
        sizeControl?.needsDisplay = true
        sizeControl?.selectedSegment = canvasView.canChangeSize ? (canvasView.selectedSizePreset?.rawValue ?? -1) : -1
    }

    @objc func selectThickness(_ sender: NSSegmentedControl) {
        guard let preset = AnnotationCanvasView.SizePreset(rawValue: sender.selectedSegment) else { return }
        canvasView.applySelectedSize(preset)
        updateSizeControl()
    }

    @objc func undo(_ sender: Any?) {
        canvasView.commitTextEditing()
        canvasView.cancelInteraction()
        if state.undo() {
            canvasView.needsDisplay = true
            statusLabel.stringValue = "Undo"
        } else {
            statusLabel.stringValue = "Nothing to undo"
        }
    }

    @objc func redo(_ sender: Any?) {
        canvasView.commitTextEditing()
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
            _ = replaceWithImage(image, sourceURL: url, message: "Opened \(url.lastPathComponent)")
        }
    }

    // Text editors handle paste first; the window handles image paste otherwise.
    @objc func paste(_ sender: Any?) {
        pasteImage(sender)
    }

    @objc func pasteImage(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard) {
            _ = replaceWithImage(image, sourceURL: nil, message: "Pasted image from clipboard")
        } else {
            statusLabel.stringValue = "Clipboard does not contain an image"
        }
    }

    // NSTextView handles Copy first when editing; otherwise the canvas copies its selection.
    @objc func copy(_ sender: Any?) {
        copySelectedAnnotation(sender)
    }

    @objc func copySelectedAnnotation(_ sender: Any?) {
        copySelectedAnnotation(to: .general)
    }

    func copySelectedAnnotation(to pasteboard: NSPasteboard) {
        guard state.canCopySelectedAnnotation else {
            statusLabel.stringValue = "Select an annotation to copy"
            return
        }
        canvasView.commitTextEditing()
        guard let data = state.selectedAnnotationPNGData() else {
            statusLabel.stringValue = "Could not copy the selected annotation"
            return
        }
        pasteboard.clearContents()
        if pasteboard.setData(data, forType: .png) {
            statusLabel.stringValue = "Copied annotation as PNG"
        } else {
            statusLabel.stringValue = "Could not write annotation to clipboard"
        }
    }

    @objc func copyFlattenedImage(_ sender: Any?) {
        copyFlattenedImage(to: .general)
    }

    func copyFlattenedImage(to pasteboard: NSPasteboard) {
        canvasView.commitTextEditing()
        guard let data = state.imageData() else {
            statusLabel.stringValue = "Nothing to copy"
            return
        }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        statusLabel.stringValue = "Copied flattened image"
    }

    @objc func save(_ sender: Any?) {
        _ = saveCurrentImage()
    }

    @objc func saveAs(_ sender: Any?) {
        _ = saveAsCurrentImage()
    }

    @objc func exportImage(_ sender: Any?) {
        canvasView.commitTextEditing()
        guard state.hasImage else {
            statusLabel.stringValue = "Nothing to export"
            return
        }
        let panel = makeExportPanel()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let format = RasterImageFormat(url: url), let data = state.imageData(format: format) else {
            statusLabel.stringValue = "Export failed: choose a PNG or JPEG filename"
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            statusLabel.stringValue = "Exported \(url.lastPathComponent)"
        } catch {
            statusLabel.stringValue = "Export failed: \(error.localizedDescription)"
        }
    }

    func makeExportPanel() -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = suggestedSaveName(format: .png)
        return panel
    }

    @objc func duplicateSelected(_ sender: Any?) {
        canvasView.commitTextEditing()
        guard state.duplicateSelectedAnnotation() != nil else { return }
        state.selectedTool = .select
        canvasView.toolDidChange()
        canvasView.needsDisplay = true
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copy(_:)) || menuItem.action == #selector(copySelectedAnnotation(_:)) {
            return state.canCopySelectedAnnotation
        }
        if menuItem.action == #selector(duplicateSelected(_:)) {
            return state.annotation(with: state.selectedAnnotationID) != nil
        }
        return true
    }

    @objc func deleteSelected(_ sender: Any?) {
        canvasView.cancelInteraction()
        state.deleteSelectedAnnotation()
        canvasView.needsDisplay = true
    }

    private func updateToolButtons() {
        for item in window?.toolbar?.items ?? [] {
            guard Tool(rawValue: item.itemIdentifier.rawValue) != nil else { continue }
            let selected: NSControl.StateValue = item.itemIdentifier.rawValue == state.selectedTool.rawValue ? .on : .off
            (item.view as? ShortcutToolButton)?.state = selected
            item.menuFormRepresentation?.state = selected
        }
    }

    private func updateShortcutHints(_ modifiers: NSEvent.ModifierFlags) {
        let show = modifiers.contains(.option) && window?.isKeyWindow == true
            && NSApp.modalWindow == nil && window?.attachedSheet == nil
        for item in window?.toolbar?.items ?? [] {
            (item.view as? ShortcutToolButton)?.showsShortcut = show
            (item.view as? ShortcutSizeControl)?.showsShortcuts = show
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateShortcutHints(NSEvent.modifierFlags)
    }

    func windowDidResignKey(_ notification: Notification) {
        updateShortcutHints([])
    }

    func windowWillBeginSheet(_ notification: Notification) {
        updateShortcutHints([])
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmDiscardOrSaveChanges()
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClosed?(self)
    }

    func canTerminate() -> Bool {
        confirmDiscardOrSaveChanges(markDiscardedChanges: false)
    }

    private var hasUnsavedChanges: Bool {
        state.hasImage && savedRevisionID != state.revisionID
    }

    private func replaceWithImage(_ image: NSImage, sourceURL: URL?, message: String) -> Bool {
        guard confirmDiscardOrSaveChanges() else { return false }
        load(image: image, sourceURL: sourceURL, message: message)
        return true
    }

    private func openDroppedFile(_ url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url) else {
            statusLabel.stringValue = "Could not open \(url.lastPathComponent)"
            return false
        }
        return replaceWithImage(image, sourceURL: url, message: "Opened \(url.lastPathComponent)")
    }

    private func load(image: NSImage, sourceURL: URL?, message: String) {
        self.sourceURL = sourceURL
        sourceFormat = sourceURL.flatMap(RasterImageFormat.init(url:))
        state.load(image: image)
        savedRevisionID = state.revisionID
        canvasView.toolDidChange()
        canvasView.zoomToFit()
        canvasView.needsDisplay = true
        statusLabel.stringValue = message
        updateDocumentPresentation()
    }

    private func saveCurrentImage() -> Bool {
        canvasView.commitTextEditing()
        guard state.hasImage else {
            statusLabel.stringValue = "Nothing to save"
            return false
        }
        guard let sourceURL, let sourceFormat else {
            return saveAsCurrentImage()
        }
        guard hasUnsavedChanges else {
            statusLabel.stringValue = "No changes to save"
            return true
        }
        return writeFlattenedImage(to: sourceURL, format: sourceFormat)
    }

    private func saveAsCurrentImage() -> Bool {
        canvasView.commitTextEditing()
        guard state.hasImage else {
            statusLabel.stringValue = "Nothing to save"
            return false
        }

        let defaultFormat: RasterImageFormat = .png
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = suggestedSaveName(format: defaultFormat)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard let format = RasterImageFormat(url: url) else {
            presentSaveError("Choose a .png, .jpg, or .jpeg filename.")
            return false
        }
        return writeFlattenedImage(to: url, format: format)
    }

    private func writeFlattenedImage(to url: URL, format: RasterImageFormat) -> Bool {
        guard let data = state.imageData(format: format) else {
            presentSaveError("Capture could not render this image for saving.")
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            sourceURL = url
            sourceFormat = format
            savedRevisionID = state.revisionID
            statusLabel.stringValue = "Saved \(url.lastPathComponent)"
            updateDocumentPresentation()
            return true
        } catch {
            presentSaveError("Could not save \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    private func suggestedSaveName(format: RasterImageFormat) -> String {
        let baseName = sourceURL?.deletingPathExtension().lastPathComponent ?? "annotation"
        return "\(baseName).\(format.fileExtension)"
    }

    private func confirmDiscardOrSaveChanges(markDiscardedChanges: Bool = true) -> Bool {
        canvasView.commitTextEditing()
        guard hasUnsavedChanges else { return true }
        window?.makeKeyAndOrderFront(nil)

        let alert = NSAlert()
        alert.messageText = "Save changes to \(sourceURL?.lastPathComponent ?? "image")?"
        alert.informativeText = "Your annotations will be lost if you do not save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveCurrentImage()
        case .alertSecondButtonReturn:
            if markDiscardedChanges {
                savedRevisionID = state.revisionID
                updateDocumentPresentation()
            }
            return true
        default:
            return false
        }
    }

    private func updateDocumentPresentation() {
        guard let window else { return }
        window.representedURL = sourceURL
        window.title = sourceURL?.lastPathComponent ?? AppMenu.appName
        window.isDocumentEdited = hasUnsavedChanges
    }

    private func presentSaveError(_ message: String) {
        statusLabel.stringValue = message
        let alert = NSAlert()
        alert.messageText = "Save Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private extension RasterImageFormat {
    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": self = .jpeg
        case "png": self = .png
        default: return nil
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        }
    }
}

// Drawing the badge inside the button keeps its hit target and toolbar overflow behavior intact.
final class ShortcutToolButton: NSButton {
    var shortcut = ""
    var showsShortcut = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsShortcut else { return }
        ShortcutBadge.draw(shortcut, at: CGPoint(x: bounds.maxX, y: bounds.maxY - 15))
    }
}

private enum ShortcutBadge {
    static func draw(_ text: String, at topRight: CGPoint, height: CGFloat = 15) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: height - 5, weight: .semibold),
            .foregroundColor: NSColor.windowBackgroundColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let width = max(height, ceil(size.width) + 4)
        let badge = NSRect(x: topRight.x - width, y: topRight.y, width: width, height: height)
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: badge, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: CGPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), withAttributes: attributes)
    }
}

final class ShortcutSizeControl: NSSegmentedControl {
    var showsShortcuts = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsShortcuts && isEnabled else { return }
        let segmentWidth = bounds.width / CGFloat(segmentCount)
        for index in 0..<segmentCount {
            ShortcutBadge.draw(String(index + 1), at: CGPoint(x: CGFloat(index + 1) * segmentWidth - 1, y: bounds.maxY - 12), height: 12)
        }
    }
}
