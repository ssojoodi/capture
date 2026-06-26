import AppKit
import UniformTypeIdentifiers
import SkitchEquivalentCore

final class AnnotationCanvasView: NSView {
    private let state: AnnotationDocumentState
    private var zoom: CGFloat = 1
    private var imageOrigin: CGPoint = .zero
    private var dragStartImagePoint: CGPoint?
    private var activeAnnotation: Annotation?
    private var activeCropRect: CGRect?
    private var movingAnnotation: Annotation?
    private var lastMovePoint: CGPoint?
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

    func zoomToFit() {
        guard state.imageSize.width > 0, state.imageSize.height > 0 else { return }
        let inset: CGFloat = 48
        let available = bounds.insetBy(dx: inset, dy: inset).size
        zoom = max(0.05, min(available.width / state.imageSize.width, available.height / state.imageSize.height, 1))
        centerImage()
    }

    override func layout() {
        super.layout()
        centerImage()
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
            if annotation.id == state.selectedAnnotationID {
                drawSelection(annotation.bounds, in: context)
            }
        }

        if let crop = activeCropRect ?? state.cropRect {
            drawCrop(crop, in: context)
        }
        context.restoreGState()
    }

    private func drawPlaceholder(in rect: CGRect) {
        let cardWidth = min(bounds.width - 96, 680)
        let cardHeight: CGFloat = 220
        let card = CGRect(
            x: bounds.midX - cardWidth / 2,
            y: bounds.midY - cardHeight / 2,
            width: cardWidth,
            height: cardHeight
        )

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
        context.saveGState()
        context.setStrokeColor(NSColor.selectedControlColor.cgColor)
        context.setLineWidth(2 / zoom)
        context.setLineDash(phase: 0, lengths: [6 / zoom, 4 / zoom])
        context.stroke(rect.insetBy(dx: -6 / zoom, dy: -6 / zoom))
        context.restoreGState()
    }

    private func drawCrop(_ rect: CGRect, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.systemYellow.cgColor)
        context.setLineWidth(3 / zoom)
        context.setLineDash(phase: 0, lengths: [10 / zoom, 5 / zoom])
        context.stroke(rect)
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard state.hasImage else { return }
        let point = imagePoint(for: event.locationInWindow)
        dragStartImagePoint = point
        lastMovePoint = point
        activeAnnotation = nil
        activeCropRect = nil
        movingAnnotation = nil

        if state.selectedTool == .select {
            let hit = state.annotation(at: point)
            state.selectedAnnotationID = hit?.id
            if event.clickCount >= 2, let text = hit as? TextAnnotation {
                editTextAnnotation(text)
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
            let annotation = TextAnnotation(bounds: CGRect(x: point.x, y: point.y, width: 160, height: 56))
            state.addAnnotation(annotation)
            state.selectedTool = .select
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

    private func editTextAnnotation(_ annotation: TextAnnotation) {
        let alert = NSAlert()
        alert.messageText = "Edit text"
        alert.informativeText = "Keep it short for fast visual callouts."
        let field = NSTextField(string: annotation.text)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let next = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !next.isEmpty { annotation.text = next }
            statusHandler?("Updated text annotation")
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard state.hasImage, let start = dragStartImagePoint else { return }
        let point = imagePoint(for: event.locationInWindow)

        if let movingAnnotation, let lastMovePoint {
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
            state.addAnnotation(annotation)
            state.selectedTool = .select
            statusHandler?("Added annotation")
        } else if let crop = activeCropRect {
            state.setCropRect(crop)
            state.selectedTool = .select
            statusHandler?("Set crop region")
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 {
            state.deleteSelectedAnnotation()
            needsDisplay = true
        } else if event.keyCode == 53 {
            state.selectedTool = .select
            statusHandler?("Tool: select")
            needsDisplay = true
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
        return CGPoint(x: (local.x - imageOrigin.x) / zoom, y: (local.y - imageOrigin.y) / zoom)
    }
}
