import AppKit
import UniformTypeIdentifiers
import CaptureCore

final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    private enum CanvasInteraction {
        case idle
        case creatingAnnotation(start: CGPoint, annotation: Annotation)
        case creatingCrop(start: CGPoint, rect: CGRect)
        case moving(annotation: Annotation, lastPoint: CGPoint, didRecordUndo: Bool)
        case resizing(annotation: Annotation, handle: SelectionHandle, didRecordUndo: Bool)
    }

    private let state: AnnotationDocumentState
    private var zoom: CGFloat = 1
    private var imageOrigin: CGPoint = .zero
    private var interaction: CanvasInteraction = .idle
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
        cancelInteraction()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func cancelInteraction() {
        interaction = .idle
        repositionActiveTextField()
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

        if let selected = state.annotation(with: state.selectedAnnotationID) {
            drawSelection(for: selected, in: context)
        }

        if case let .creatingAnnotation(_, annotation) = interaction {
            annotation.draw(in: context, baseImage: baseCGImage, imageSize: state.imageSize, scale: zoom)
            drawSelection(annotation.bounds, in: context)
        }

        let visibleCrop: CGRect?
        if case let .creatingCrop(_, rect) = interaction {
            visibleCrop = rect
        } else {
            visibleCrop = state.cropRect
        }
        if let crop = visibleCrop {
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

    private func drawSelection(for annotation: Annotation, in context: CGContext) {
        if annotation is ArrowAnnotation {
            drawArrowSelection(annotation, in: context)
            return
        }

        drawSelection(annotation.bounds, in: context)
        for (_, center) in AnnotationSelectionGeometry.handleCenters(for: annotation) {
            drawHandle(center, in: context)
        }
    }

    private func drawArrowSelection(_ annotation: Annotation, in context: CGContext) {
        guard let arrow = annotation as? ArrowAnnotation else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.selectedControlColor.cgColor)
        context.setLineWidth(2 / max(zoom, 0.01))
        context.setLineDash(phase: 0, lengths: [6 / max(zoom, 0.01), 4 / max(zoom, 0.01)])
        context.move(to: arrow.start)
        context.addLine(to: arrow.end)
        context.strokePath()
        context.restoreGState()
        drawHandle(arrow.start, in: context)
        drawHandle(arrow.end, in: context)
    }

    private func drawHandle(_ center: CGPoint, in context: CGContext) {
        let size = 10 / max(zoom, 0.01)
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.selectedControlColor.cgColor)
        context.setLineWidth(2 / max(zoom, 0.01))
        context.fillEllipse(in: rect)
        context.strokeEllipse(in: rect)
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
        interaction = .idle

        if let selected = state.annotation(with: state.selectedAnnotationID),
           let handle = AnnotationSelectionGeometry.hitHandle(at: point, annotation: selected, hitRadius: 10 / max(zoom, 0.01)) {
            interaction = .resizing(annotation: selected, handle: handle, didRecordUndo: false)
            needsDisplay = true
            return
        }

        if state.selectedTool == .select {
            if let selected = state.annotation(with: state.selectedAnnotationID),
               let handle = AnnotationSelectionGeometry.hitHandle(at: point, annotation: selected, hitRadius: 10 / max(zoom, 0.01)) {
                interaction = .resizing(annotation: selected, handle: handle, didRecordUndo: false)
                needsDisplay = true
                return
            }

            let hit = state.annotation(at: point)
            state.selectedAnnotationID = hit?.id
            if event.clickCount >= 2, let text = hit as? TextAnnotation {
                beginEditing(text)
                needsDisplay = true
                return
            }
            if let hit {
                interaction = .moving(annotation: hit, lastPoint: point, didRecordUndo: false)
            }
            needsDisplay = true
            return
        }

        switch state.selectedTool {
        case .arrow:
            interaction = .creatingAnnotation(start: point, annotation: ArrowAnnotation(start: point, end: point))
        case .text:
            let annotation = TextAnnotation(bounds: CGRect(x: point.x, y: point.y, width: 190, height: 58))
            state.addAnnotation(annotation, select: true)
            beginEditing(annotation, isNew: true)
            statusHandler?("Added text annotation")
        case .blur:
            interaction = .creatingAnnotation(start: point, annotation: BlurAnnotation(bounds: CGRect(origin: point, size: .zero)))
        case .rectangle:
            interaction = .creatingAnnotation(start: point, annotation: RectangleAnnotation(bounds: CGRect(origin: point, size: .zero)))
        case .ellipse:
            interaction = .creatingAnnotation(start: point, annotation: EllipseAnnotation(bounds: CGRect(origin: point, size: .zero)))
        case .crop:
            interaction = .creatingCrop(start: point, rect: CGRect(origin: point, size: .zero))
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
        guard state.hasImage else { return }
        let point = imagePoint(for: event.locationInWindow).clampedToImage(size: state.imageSize)

        switch interaction {
        case .idle:
            return
        case let .resizing(annotation, handle, didRecordUndo):
            if !didRecordUndo {
                state.recordUndoSnapshot()
                interaction = .resizing(annotation: annotation, handle: handle, didRecordUndo: true)
            }
            if AnnotationSelectionGeometry.applyResize(annotation: annotation, handle: handle, to: point), annotation is TextAnnotation {
                repositionActiveTextField()
            }
        case let .moving(annotation, lastPoint, didRecordUndo):
            if !didRecordUndo {
                state.recordUndoSnapshot()
                interaction = .moving(annotation: annotation, lastPoint: lastPoint, didRecordUndo: true)
            }
            annotation.moveBy(dx: point.x - lastPoint.x, dy: point.y - lastPoint.y)
            interaction = .moving(annotation: annotation, lastPoint: point, didRecordUndo: true)
        case let .creatingAnnotation(start, annotation):
            let rect = CGRect(x: start.x, y: start.y, width: point.x - start.x, height: point.y - start.y).normalized
            if let arrow = annotation as? ArrowAnnotation {
                arrow.end = point
            } else {
                annotation.bounds = rect
            }
        case let .creatingCrop(start, _):
            let rect = CGRect(x: start.x, y: start.y, width: point.x - start.x, height: point.y - start.y).normalized
            interaction = .creatingCrop(start: start, rect: rect)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            interaction = .idle
            needsDisplay = true
        }

        if case let .creatingAnnotation(_, annotation) = interaction,
           annotation.bounds.width > 4 || annotation.bounds.height > 4 {
            state.addAnnotation(annotation, select: true)
            statusHandler?("Added \(state.selectedTool.rawValue) annotation")
            return
        }

        if case let .creatingCrop(_, crop) = interaction, crop.width > 4, crop.height > 4 {
            state.applyCrop(crop)
            centerImage()
            statusHandler?("Cropped image")
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }

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

    func applySelectedColor(_ color: NSColor) {
        if state.applyColorToSelected(color) {
            statusHandler?("Changed color")
            needsDisplay = true
        } else {
            statusHandler?("Select an annotation to change color")
        }
    }

    func applySelectedSize(lineThickness: CGFloat, textSize: CGFloat) {
        let selectedIsText = state.annotation(with: state.selectedAnnotationID) is TextAnnotation
        let size = selectedIsText ? textSize : lineThickness
        if state.applyThicknessToSelected(size) {
            repositionActiveTextField()
            if selectedIsText {
                statusHandler?("Changed font size")
            } else {
                statusHandler?("Changed thickness")
            }
            needsDisplay = true
        } else {
            statusHandler?("Select text, a line, or a shape to change size")
        }
    }
}

private extension CGPoint {
    func clampedToImage(size: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, x), size.width), y: min(max(0, y), size.height))
    }
}
