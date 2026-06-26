import AppKit
import UniformTypeIdentifiers
import SkitchEquivalentCore

final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    private let state: AnnotationDocumentState
    private var zoom: CGFloat = 1
    private var imageOrigin: CGPoint = .zero
    private var dragStartImagePoint: CGPoint?
    private var activeAnnotation: Annotation?
    private var activeCropRect: CGRect?
    private var movingAnnotation: Annotation?
    private var lastMovePoint: CGPoint?
    private var recordedMoveUndo = false
    private weak var activeTextField: NSTextField?
    private weak var activeTextAnnotation: TextAnnotation?
    private var activeTextWasNew = false
    var statusHandler: ((String) -> Void)?

    init(state: AnnotationDocumentState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.965, green: 0.96, blue: 0.945, alpha: 1).cgColor
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    var zoomPercentage: Int { Int((zoom * 100).rounded()) }

    func toolDidChange() {
        commitActiveTextEdit()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func zoomToFit() {
        guard state.imageSize.width > 0, state.imageSize.height > 0 else { return }
        let inset: CGFloat = 72
        let available = bounds.insetBy(dx: inset, dy: inset).size
        zoom = max(0.05, min(available.width / state.imageSize.width, available.height / state.imageSize.height, 1))
        centerImage()
        repositionActiveTextField()
        needsDisplay = true
        statusHandler?("Zoom: fit (\(zoomPercentage)%)")
    }

    func zoomIn() {
        zoomBy(1.25)
    }

    func zoomOut() {
        zoomBy(0.8)
    }

    func resetZoom() {
        guard state.hasImage else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let viewport = ViewportTransform(zoom: zoom, imageOrigin: imageOrigin).zoomed(to: 1, aroundViewPoint: center)
        zoom = viewport.zoom
        imageOrigin = viewport.imageOrigin
        repositionActiveTextField()
        needsDisplay = true
        statusHandler?("Zoom: 100%")
    }

    private func zoomBy(_ factor: CGFloat) {
        guard state.hasImage else { return }
        let nextZoom = min(8, max(0.05, zoom * factor))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let viewport = ViewportTransform(zoom: zoom, imageOrigin: imageOrigin).zoomed(to: nextZoom, aroundViewPoint: center)
        zoom = viewport.zoom
        imageOrigin = viewport.imageOrigin
        repositionActiveTextField()
        needsDisplay = true
        statusHandler?("Zoom: \(zoomPercentage)%")
    }

    override func layout() {
        super.layout()
        if state.hasImage, zoom <= 1 {
            centerImage()
        }
        repositionActiveTextField()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let cursor: NSCursor
        switch state.selectedTool {
        case .select:
            cursor = .arrow
        case .text:
            cursor = .iBeam
        case .arrow, .blur, .crop, .rectangle, .ellipse:
            cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor(calibratedRed: 0.965, green: 0.96, blue: 0.945, alpha: 1).setFill()
        dirtyRect.fill()

        guard let baseCGImage = state.baseCGImage else {
            drawPlaceholder(in: dirtyRect)
            return
        }

        context.saveGState()
        context.translateBy(x: imageOrigin.x, y: imageOrigin.y)
        context.scaleBy(x: zoom, y: zoom)
        let imageRect = CGRect(origin: .zero, size: state.imageSize)
        context.draw(baseCGImage, in: imageRect)

        for annotation in state.annotations {
            annotation.draw(in: context, baseImage: baseCGImage, imageSize: state.imageSize, scale: zoom)
        }

        if let activeAnnotation {
            activeAnnotation.draw(in: context, baseImage: baseCGImage, imageSize: state.imageSize, scale: zoom)
            drawSelection(activeAnnotation.bounds, in: context)
        }

        if let crop = activeCropRect ?? state.cropRect {
            drawCrop(crop, in: context)
        }
        context.restoreGState()
    }

    private func drawPlaceholder(in rect: CGRect) {
        let cardWidth = min(bounds.width - 96, 680)
        let cardHeight: CGFloat = 220
        let card = CGRect(x: bounds.midX - cardWidth / 2, y: bounds.midY - cardHeight / 2, width: cardWidth, height: cardHeight)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.08)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -4)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 24, yRadius: 24)
        NSColor.white.withAlphaComponent(0.88).setFill()
        cardPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedRed: 0.82, green: 0.80, blue: 0.74, alpha: 1).setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()

        let title = "Drop, paste, or open an image"
        let subtitle = "Arrows, text, blur, crop, shapes, copy, export."
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.38, alpha: 1),
            .paragraphStyle: paragraph
        ]
        title.draw(in: CGRect(x: card.minX + 24, y: card.midY + 8, width: card.width - 48, height: 40), withAttributes: titleAttributes)
        subtitle.draw(in: CGRect(x: card.minX + 24, y: card.midY - 28, width: card.width - 48, height: 24), withAttributes: subtitleAttributes)
    }

    private func drawSelection(_ rect: CGRect, in context: CGContext) {
        guard rect.width > 0 || rect.height > 0 else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.selectedControlColor.cgColor)
        context.setLineWidth(2 / max(zoom, 0.01))
        context.setLineDash(phase: 0, lengths: [6 / max(zoom, 0.01), 4 / max(zoom, 0.01)])
        context.stroke(rect.normalized.insetBy(dx: -6 / max(zoom, 0.01), dy: -6 / max(zoom, 0.01)))
        context.restoreGState()
    }

    private func drawCrop(_ rect: CGRect, in context: CGContext) {
        let crop = rect.normalized
        context.saveGState()
        context.setStrokeColor(NSColor.systemYellow.cgColor)
        context.setLineWidth(3 / max(zoom, 0.01))
        context.setLineDash(phase: 0, lengths: [10 / max(zoom, 0.01), 5 / max(zoom, 0.01)])
        context.stroke(crop)
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitActiveTextEdit()
        guard state.hasImage else { return }
        let point = imagePoint(for: event.locationInWindow).clampedToImage(size: state.imageSize)
        dragStartImagePoint = point
        lastMovePoint = point
        activeAnnotation = nil
        activeCropRect = nil
        movingAnnotation = nil
        recordedMoveUndo = false

        if state.selectedTool == .select {
            let hit = state.annotation(at: point)
            state.selectedAnnotationID = hit?.id
            if event.clickCount >= 2, let text = hit as? TextAnnotation {
                beginEditing(text)
                needsDisplay = true
                return
            }
            movingAnnotation = hit
            needsDisplay = true
            return
        }

        switch state.selectedTool {
        case .arrow:
            activeAnnotation = ArrowAnnotation(start: point, end: point)
        case .text:
            let annotation = TextAnnotation(bounds: CGRect(x: point.x, y: point.y, width: 190, height: 58))
            state.addAnnotation(annotation, select: false)
            beginEditing(annotation, isNew: true)
            statusHandler?("Added text annotation")
        case .blur:
            activeAnnotation = BlurAnnotation(bounds: CGRect(origin: point, size: .zero))
        case .rectangle:
            activeAnnotation = RectangleAnnotation(bounds: CGRect(origin: point, size: .zero))
        case .ellipse:
            activeAnnotation = EllipseAnnotation(bounds: CGRect(origin: point, size: .zero))
        case .crop:
            activeCropRect = CGRect(origin: point, size: .zero)
        case .select:
            break
        }
        needsDisplay = true
    }

    private func beginEditing(_ annotation: TextAnnotation, isNew: Bool = false) {
        activeTextField?.removeFromSuperview()
        let field = NSTextField(string: annotation.text)
        field.font = .boldSystemFont(ofSize: max(16, annotation.fontSize * zoom))
        field.textColor = annotation.textColor
        field.backgroundColor = annotation.drawsBackground ? annotation.backgroundColor : .clear
        field.drawsBackground = annotation.drawsBackground
        field.isBordered = false
        field.alignment = .center
        field.delegate = self
        field.target = self
        field.action = #selector(commitActiveTextEditAction(_:))
        field.frame = viewRect(forImageRect: annotation.bounds)
        addSubview(field)
        activeTextField = field
        activeTextAnnotation = annotation
        activeTextWasNew = isNew
        window?.makeFirstResponder(field)
    }

    @objc private func commitActiveTextEditAction(_ sender: Any?) {
        commitActiveTextEdit()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitActiveTextEdit()
    }

    private func commitActiveTextEdit() {
        guard let field = activeTextField else { return }
        if let annotation = activeTextAnnotation {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, text != annotation.text {
                if !activeTextWasNew {
                    state.recordUndoSnapshot()
                }
                annotation.text = text
            }
        }
        field.removeFromSuperview()
        activeTextField = nil
        activeTextAnnotation = nil
        activeTextWasNew = false
        needsDisplay = true
    }

    private func repositionActiveTextField() {
        guard let field = activeTextField, let annotation = activeTextAnnotation else { return }
        field.frame = viewRect(forImageRect: annotation.bounds)
        field.font = .boldSystemFont(ofSize: max(16, annotation.fontSize * zoom))
    }

    override func mouseDragged(with event: NSEvent) {
        guard state.hasImage, let start = dragStartImagePoint else { return }
        let point = imagePoint(for: event.locationInWindow).clampedToImage(size: state.imageSize)

        if let movingAnnotation, let lastMovePoint {
            if !recordedMoveUndo {
                state.recordUndoSnapshot()
                recordedMoveUndo = true
            }
            movingAnnotation.moveBy(dx: point.x - lastMovePoint.x, dy: point.y - lastMovePoint.y)
            self.lastMovePoint = point
            needsDisplay = true
            return
        }

        let rect = CGRect(x: start.x, y: start.y, width: point.x - start.x, height: point.y - start.y).normalized
        if let arrow = activeAnnotation as? ArrowAnnotation {
            arrow.end = point
        } else if let annotation = activeAnnotation {
            annotation.bounds = rect
        } else if state.selectedTool == .crop {
            activeCropRect = rect
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            activeAnnotation = nil
            dragStartImagePoint = nil
            movingAnnotation = nil
            lastMovePoint = nil
            activeCropRect = nil
            needsDisplay = true
        }

        if let annotation = activeAnnotation, annotation.bounds.width > 4 || annotation.bounds.height > 4 {
            state.addAnnotation(annotation, select: false)
            statusHandler?("Added \(state.selectedTool.rawValue) annotation")
            return
        }

        if let crop = activeCropRect, crop.width > 4, crop.height > 4 {
            state.applyCrop(crop)
            centerImage()
            statusHandler?("Cropped image")
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 {
            state.deleteSelectedAnnotation()
            needsDisplay = true
        } else if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                  let key = event.charactersIgnoringModifiers?.lowercased(),
                  key == "z" {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
                _ = state.redo()
                statusHandler?("Redo")
            } else {
                _ = state.undo()
                statusHandler?("Undo")
            }
            activeAnnotation = nil
            activeCropRect = nil
            repositionActiveTextField()
            needsDisplay = true
        } else if event.keyCode == 53 {
            state.selectedTool = .select
            toolDidChange()
            statusHandler?("Tool: select")
        } else {
            super.keyDown(with: event)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let urlString = pasteboard.string(forType: .fileURL), let url = URL(string: urlString), let image = NSImage(contentsOf: url) {
            state.load(image: image)
            zoomToFit()
            statusHandler?("Opened \(url.lastPathComponent)")
            needsDisplay = true
            return true
        }
        if let image = NSImage(pasteboard: pasteboard) {
            state.load(image: image)
            zoomToFit()
            statusHandler?("Dropped image")
            needsDisplay = true
            return true
        }
        return false
    }

    private func centerImage() {
        guard state.imageSize.width > 0, state.imageSize.height > 0 else { return }
        imageOrigin = CGPoint(
            x: (bounds.width - state.imageSize.width * zoom) / 2,
            y: (bounds.height - state.imageSize.height * zoom) / 2
        )
    }

    private func imagePoint(for windowPoint: CGPoint) -> CGPoint {
        let local = convert(windowPoint, from: nil)
        return ViewportTransform(zoom: zoom, imageOrigin: imageOrigin).imagePoint(forViewPoint: local)
    }

    private func viewRect(forImageRect imageRect: CGRect) -> CGRect {
        let normalized = imageRect.normalized
        let origin = ViewportTransform(zoom: zoom, imageOrigin: imageOrigin).viewPoint(forImagePoint: normalized.origin)
        return CGRect(x: origin.x, y: origin.y, width: normalized.width * zoom, height: normalized.height * zoom)
    }
}

private extension CGPoint {
    func clampedToImage(size: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, x), size.width), y: min(max(0, y), size.height))
    }
}
