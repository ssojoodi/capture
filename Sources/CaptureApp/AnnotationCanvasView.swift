import AppKit
import UniformTypeIdentifiers
import CaptureCore

final class AnnotationCanvasView: NSView {
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
    private var currentColor: NSColor = CapturePalette.softRed
    private var currentLineThickness: CGFloat = 7
    private var currentTextSize: CGFloat = 52
    private var currentTextBackground = NSColor.black.withAlphaComponent(0.5)
    private var activeTextEditor: TextAnnotationEditorView?
    private weak var activeTextAnnotation: TextAnnotation?
    // Keep the placement across focus changes, such as using text style controls.
    private var textPlacementID: UUID?
    private var activeTextWasNew = false
    private var activeTextDidRecordUndo = false
    private let defaultTextAnnotationSize = CGSize(width: 260, height: 76)
    var isEditingText: Bool { activeTextEditor != nil }
    var statusHandler: ((String) -> Void)?
    var toolSelectionHandler: ((Tool) -> Void)?
    var droppedFileHandler: ((URL) -> Bool)?
    var droppedImageHandler: ((NSImage) -> Bool)?

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
        textPlacementID = nil
        cancelInteraction()
        window?.invalidateCursorRects(for: self)
        toolSelectionHandler?(state.selectedTool)
        needsDisplay = true
    }

    func cancelInteraction() {
        interaction = .idle
        repositionActiveTextEditor()
        needsDisplay = true
    }

    func zoomToFit() {
        guard state.imageSize.width > 0, state.imageSize.height > 0 else { return }
        let inset: CGFloat = 72
        let available = bounds.insetBy(dx: inset, dy: inset).size
        let canvasBounds = state.canvasBounds
        zoom = max(0.05, min(available.width / canvasBounds.width, available.height / canvasBounds.height, 1))
        centerImage()
        repositionActiveTextEditor()
        needsDisplay = true
        statusHandler?("Zoom: fit (\(zoomPercentage)%)")
    }

    func commitTextEditing() {
        commitActiveTextEdit()
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
        repositionActiveTextEditor()
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
        repositionActiveTextEditor()
        needsDisplay = true
        statusHandler?("Zoom: \(zoomPercentage)%")
    }

    override func layout() {
        super.layout()
        if state.hasImage, zoom <= 1 {
            centerImage()
        }
        repositionActiveTextEditor()
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
        context.saveGState()
        context.addRect(state.canvasBounds)
        context.addRect(imageRect)
        context.clip(using: .evenOdd)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(state.canvasBounds)
        context.restoreGState()
        context.draw(baseCGImage, in: imageRect)

        let activeAnnotation: Annotation?
        if case let .creatingAnnotation(_, annotation) = interaction {
            activeAnnotation = annotation
        } else {
            activeAnnotation = nil
        }

        for annotation in state.annotations where annotation is BlurAnnotation {
            annotation.draw(in: context, baseImage: baseCGImage, imageSize: state.imageSize, scale: zoom)
        }

        if let activeAnnotation, activeAnnotation is BlurAnnotation {
            activeAnnotation.draw(in: context, baseImage: baseCGImage, imageSize: state.imageSize, scale: zoom)
        }

        for annotation in state.annotations where !(annotation is BlurAnnotation) {
            if annotation.id == activeTextAnnotation?.id, let text = annotation as? TextAnnotation {
                text.drawBackground(in: context)
            } else {
                annotation.draw(in: context, baseImage: baseCGImage, imageSize: state.imageSize, scale: zoom)
            }
        }

        if let activeAnnotation, !(activeAnnotation is BlurAnnotation) {
            activeAnnotation.draw(in: context, baseImage: baseCGImage, imageSize: state.imageSize, scale: zoom)
        }

        if let selected = state.annotation(with: state.selectedAnnotationID) {
            drawSelection(for: selected, in: context)
        }

        if let activeAnnotation {
            drawSelection(for: activeAnnotation, in: context)
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
        if state.selectedTool == .text,
           let text = state.annotation(with: textPlacementID) as? TextAnnotation,
           !text.bounds.contains(imagePoint(for: event.locationInWindow)) {
            state.selectedTool = .select
            toolDidChange()
            statusHandler?("Tool: select")
        }
        window?.makeFirstResponder(self)
        commitActiveTextEdit()
        guard state.hasImage else { return }
        let rawPoint = imagePoint(for: event.locationInWindow)
        interaction = .idle

        if let selected = state.annotation(with: state.selectedAnnotationID),
           let handle = AnnotationSelectionGeometry.hitHandle(at: rawPoint, annotation: selected, hitRadius: 10 / max(zoom, 0.01)) {
            interaction = .resizing(annotation: selected, handle: handle, didRecordUndo: false)
            needsDisplay = true
            return
        }

        if state.selectedTool == .select {
            let hit = state.annotation(at: rawPoint)
            state.selectedAnnotationID = hit?.id
            if event.clickCount >= 2, let text = hit as? TextAnnotation {
                beginEditing(text)
                needsDisplay = true
                return
            }
            if let hit {
                interaction = .moving(annotation: hit, lastPoint: rawPoint, didRecordUndo: false)
            }
            needsDisplay = true
            return
        }

        let point = rawPoint.clampedToImage(size: state.imageSize)
        switch state.selectedTool {
        case .arrow:
            interaction = .creatingAnnotation(start: point, annotation: ArrowAnnotation(start: point, end: point, color: currentColor, strokeWidth: currentLineThickness))
        case .text:
            let annotation = TextAnnotation(
                bounds: CGRect(origin: point, size: defaultTextAnnotationSize).fitted(inside: CGRect(origin: .zero, size: state.imageSize)),
                text: "",
                fontSize: currentTextSize,
                textColor: currentColor,
                backgroundColor: currentTextBackground,
                drawsBackground: currentTextBackground.alphaComponent > 0
            )
            state.addAnnotation(annotation, select: true)
            beginEditing(annotation, isNew: true)
            textPlacementID = annotation.id
            statusHandler?("Added text annotation")
        case .blur:
            interaction = .creatingAnnotation(start: point, annotation: BlurAnnotation(bounds: CGRect(origin: point, size: .zero)))
        case .rectangle:
            interaction = .creatingAnnotation(start: point, annotation: RectangleAnnotation(bounds: CGRect(origin: point, size: .zero), strokeColor: currentColor, strokeWidth: currentLineThickness))
        case .ellipse:
            interaction = .creatingAnnotation(start: point, annotation: EllipseAnnotation(bounds: CGRect(origin: point, size: .zero), strokeColor: currentColor, strokeWidth: currentLineThickness))
        case .crop:
            interaction = .creatingCrop(start: point, rect: CGRect(origin: point, size: .zero))
        case .select:
            break
        }
        needsDisplay = true
    }

    private func beginEditing(_ annotation: TextAnnotation, isNew: Bool = false) {
        activeTextEditor?.removeFromSuperview()
        let fittedBounds = annotation.bounds.fitted(inside: CGRect(origin: .zero, size: state.imageSize))
        let didFitBounds = fittedBounds != annotation.bounds
        if didFitBounds && !isNew { state.recordUndoSnapshot() }
        annotation.bounds = fittedBounds
        let editor = TextAnnotationEditorView(
            frame: viewRect(forImageRect: annotation.bounds),
            text: annotation.text,
            font: textEditorFont(for: annotation),
            textColor: annotation.textColor,
            maximumSize: CGSize(width: state.imageSize.width * zoom, height: state.imageSize.height * zoom),
            scale: zoom
        )
        editor.resizeHandleHitTest = { [weak self] point in
            guard let self, let selected = self.state.annotation(with: self.state.selectedAnnotationID) else { return false }
            let imagePoint = self.imagePoint(for: self.convert(point, to: nil))
            return AnnotationSelectionGeometry.hitHandle(at: imagePoint, annotation: selected, hitRadius: 10 / max(self.zoom, 0.01)) != nil
        }
        editor.onTextChanged = { [weak self] _, size in
            self?.resizeActiveTextAnnotation(toViewSize: size)
        }
        editor.onEditingEnded = { [weak self] _, _ in
            self?.commitActiveTextEdit()
        }
        addSubview(editor)
        activeTextEditor = editor
        activeTextAnnotation = annotation
        activeTextWasNew = isNew
        activeTextDidRecordUndo = didFitBounds && !isNew
        resizeActiveTextAnnotation(toViewSize: editor.frame.size)
        editor.focusAtEnd()
    }

    private func commitActiveTextEdit() {
        guard let editor = activeTextEditor else { return }
        editor.onTextChanged = nil
        editor.onEditingEnded = nil

        if let annotation = activeTextAnnotation {
            let text = editor.text
            if text != annotation.text {
                recordActiveTextUndoIfNeeded()
                annotation.text = text
            }
        }
        editor.removeFromSuperview()
        activeTextEditor = nil
        activeTextAnnotation = nil
        activeTextWasNew = false
        activeTextDidRecordUndo = false
        needsDisplay = true
    }

    private func repositionActiveTextEditor() {
        guard let editor = activeTextEditor, let annotation = activeTextAnnotation else { return }
        editor.updateFrame(
            viewRect(forImageRect: annotation.bounds),
            font: textEditorFont(for: annotation),
            textColor: annotation.textColor,
            maximumSize: CGSize(width: state.imageSize.width * zoom, height: state.imageSize.height * zoom),
            scale: zoom
        )
        resizeActiveTextAnnotation(toViewSize: editor.frame.size)
    }

    private func resizeActiveTextAnnotation(toViewSize viewSize: CGSize) {
        guard let annotation = activeTextAnnotation else { return }
        let newSize = imageSize(forViewSize: viewSize)
        let fittedBounds = CGRect(origin: annotation.bounds.origin, size: newSize)
            .fitted(inside: CGRect(origin: .zero, size: state.imageSize))
        if fittedBounds != annotation.bounds {
            recordActiveTextUndoIfNeeded()
            annotation.bounds = fittedBounds
        }
        activeTextEditor?.setFrameOrigin(viewRect(forImageRect: annotation.bounds).origin)
        if activeTextEditor?.hasOverflow == true {
            statusHandler?("Text exceeds image height; reduce text size or shorten the text")
        }
        needsDisplay = true
    }

    private func textEditorFont(for annotation: TextAnnotation) -> NSFont {
        .boldSystemFont(ofSize: max(1, annotation.fontSize * zoom))
    }

    private func imageSize(forViewSize viewSize: CGSize) -> CGSize {
        CGSize(width: viewSize.width / zoom, height: ceil(viewSize.height / zoom))
    }

    private func recordActiveTextUndoIfNeeded() {
        guard !activeTextWasNew, !activeTextDidRecordUndo else { return }
        state.recordUndoSnapshot()
        activeTextDidRecordUndo = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard state.hasImage else { return }
        let rawPoint = imagePoint(for: event.locationInWindow)
        let point = rawPoint.clampedToImage(size: state.imageSize)

        switch interaction {
        case .idle:
            return
        case let .resizing(annotation, handle, didRecordUndo):
            if !didRecordUndo {
                state.recordUndoSnapshot()
                interaction = .resizing(annotation: annotation, handle: handle, didRecordUndo: true)
            }
            let resizePoint = state.selectedTool == .select ? rawPoint : point
            if AnnotationSelectionGeometry.applyResize(annotation: annotation, handle: handle, to: resizePoint), annotation is TextAnnotation {
                if state.selectedTool != .select {
                    annotation.bounds = annotation.bounds.fitted(inside: CGRect(origin: .zero, size: state.imageSize))
                }
                repositionActiveTextEditor()
            }
        case let .moving(annotation, lastPoint, didRecordUndo):
            if !didRecordUndo {
                state.recordUndoSnapshot()
                interaction = .moving(annotation: annotation, lastPoint: lastPoint, didRecordUndo: true)
            }
            annotation.moveBy(dx: rawPoint.x - lastPoint.x, dy: rawPoint.y - lastPoint.y)
            if annotation is TextAnnotation && state.selectedTool != .select {
                annotation.bounds = annotation.bounds.fitted(inside: CGRect(origin: .zero, size: state.imageSize))
            }
            interaction = .moving(annotation: annotation, lastPoint: rawPoint, didRecordUndo: true)
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
            if annotation is BlurAnnotation {
                state.applyBlur(annotation.bounds)
                statusHandler?("Blurred image")
                return
            }
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
        if let urlString = pasteboard.string(forType: .fileURL), let url = URL(string: urlString) {
            return droppedFileHandler?(url) ?? false
        }
        if let image = NSImage(pasteboard: pasteboard) {
            return droppedImageHandler?(image) ?? false
        }
        return false
    }

    private func centerImage() {
        guard state.imageSize.width > 0, state.imageSize.height > 0 else { return }
        imageOrigin = CGPoint(
            x: bounds.midX - state.canvasBounds.midX * zoom,
            y: bounds.midY - state.canvasBounds.midY * zoom
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

    var selectedTextBackground: NSColor {
        guard let text = state.annotation(with: state.selectedAnnotationID) as? TextAnnotation else {
            return currentTextBackground
        }
        return text.backgroundColor.withAlphaComponent(text.drawsBackground ? text.backgroundColor.alphaComponent : 0)
    }

    func applySelectedTextBackground(_ color: NSColor) {
        commitActiveTextEdit()
        currentTextBackground = color
        if state.applyTextBackgroundToSelected(color) {
            statusHandler?("Changed text background")
            needsDisplay = true
        } else {
            statusHandler?("Text background selected")
        }
    }

    func applySelectedColor(_ color: NSColor) {
        currentColor = color
        if state.applyColorToSelected(color) {
            statusHandler?("Changed color")
            needsDisplay = true
        } else {
            statusHandler?("Color selected")
        }
    }

    func applySelectedSize(lineThickness: CGFloat, textSize: CGFloat) {
        currentLineThickness = lineThickness
        currentTextSize = textSize
        let selectedIsText = state.annotation(with: state.selectedAnnotationID) is TextAnnotation
        let size = selectedIsText ? textSize : lineThickness
        if state.applyThicknessToSelected(size) {
            repositionActiveTextEditor()
            if selectedIsText {
                statusHandler?("Changed font size")
            } else {
                statusHandler?("Changed thickness")
            }
            needsDisplay = true
        } else {
            statusHandler?("Size selected")
        }
    }
}

private extension CGPoint {
    func clampedToImage(size: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, x), size.width), y: min(max(0, y), size.height))
    }
}
