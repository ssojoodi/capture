import AppKit

public enum RasterImageFormat {
    case jpeg
    case png
}

public final class AnnotationDocumentState {
    private struct DocumentSnapshot {
        let baseImage: NSImage?
        let baseCGImage: CGImage?
        let imageSize: CGSize
        let annotations: [Annotation]
        let cropRect: CGRect?
        let selectedAnnotationID: UUID?
        let revisionID: UUID
    }

    private let historyLimit = 50
    private var undoStack: [DocumentSnapshot] = []
    private var redoStack: [DocumentSnapshot] = []

    public private(set) var baseImage: NSImage?
    public private(set) var baseCGImage: CGImage?
    public private(set) var imageSize: CGSize = .zero
    public var selectedTool: Tool = .select
    public var selectedAnnotationID: UUID?
    public var annotations: [Annotation] = []
    public private(set) var cropRect: CGRect?
    public private(set) var revisionID = UUID()
    public var revisionDidChange: ((UUID) -> Void)?

    public init() {}

    public var hasImage: Bool { baseImage != nil }
    public var canvasBounds: CGRect {
        var result = CGRect(origin: .zero, size: imageSize)
        for annotation in annotations where !(annotation is BlurAnnotation) {
            var extent = annotation.bounds
            let padding: CGFloat
            switch annotation {
            case let arrow as ArrowAnnotation:
                padding = max(14, arrow.strokeWidth * 2.2) * 3.35 / 2 + 1
            case let rectangle as RectangleAnnotation:
                padding = rectangle.strokeWidth / 2 + 1
            case let ellipse as EllipseAnnotation:
                padding = ellipse.strokeWidth / 2 + 1
            default:
                padding = 0
            }
            extent = extent.insetBy(dx: -padding, dy: -padding)
            result = result.union(extent)
        }
        return result.integral
    }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
}

// MARK: - Image and annotation commands

extension AnnotationDocumentState {
    public func load(image: NSImage) {
        baseImage = image
        baseCGImage = image.cgImageForRendering()
        if let cgImage = baseCGImage {
            imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        } else {
            imageSize = image.size
        }
        annotations.removeAll()
        cropRect = nil
        selectedAnnotationID = nil
        selectedTool = .select
        undoStack.removeAll()
        redoStack.removeAll()
        revisionID = UUID()
        revisionDidChange?(revisionID)
    }

    public func addAnnotation(_ annotation: Annotation, select: Bool = true) {
        recordUndoSnapshot()
        annotations.append(annotation)
        selectedAnnotationID = select ? annotation.id : nil
    }

    public func annotation(with id: UUID?) -> Annotation? {
        guard let id else { return nil }
        return annotations.first { $0.id == id }
    }

    public func annotation(at point: CGPoint) -> Annotation? {
        annotations.reversed().first { $0.hitTest(point) }
    }

    @discardableResult
    public func duplicateSelectedAnnotation() -> Annotation? {
        guard let original = annotation(with: selectedAnnotationID) else { return nil }
        let duplicate = original.copyAnnotation(id: UUID())
        duplicate.moveBy(dx: 20, dy: -20)
        addAnnotation(duplicate)
        return duplicate
    }

    public func deleteSelectedAnnotation() {
        guard let selectedAnnotationID else { return }
        recordUndoSnapshot()
        annotations.removeAll { $0.id == selectedAnnotationID }
        self.selectedAnnotationID = nil
    }

    public func applyBlur(_ rect: CGRect, radius: CGFloat = 16) {
        guard let originalCGImage = baseCGImage else { return }
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let normalized = rect.normalized.clamped(to: imageBounds).integral
        guard !normalized.isNull, normalized.width >= 1, normalized.height >= 1 else { return }
        guard let blurred = BlurRenderer.blurredRegion(from: originalCGImage, imageSize: imageSize, rect: normalized, radius: radius) else { return }

        let colorSpace = originalCGImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(imageSize.width.rounded()),
            height: Int(imageSize.height.rounded()),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return }

        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(originalCGImage, in: imageBounds)
        context.draw(blurred, in: normalized)
        guard let updated = context.makeImage() else { return }
        recordUndoSnapshot()
        baseCGImage = updated
        baseImage = NSImage(cgImage: updated, size: imageSize)
        selectedAnnotationID = nil
    }

    @discardableResult
    public func applyColorToSelected(_ color: NSColor) -> Bool {
        guard let annotation = annotation(with: selectedAnnotationID) else { return false }
        switch annotation {
        case let arrow as ArrowAnnotation:
            guard !colorsMatch(arrow.color, color) else { return false }
            recordUndoSnapshot()
            arrow.color = color
        case let text as TextAnnotation:
            guard !colorsMatch(text.textColor, color) else { return false }
            recordUndoSnapshot()
            text.textColor = color
        case let rectangle as RectangleAnnotation:
            guard !colorsMatch(rectangle.strokeColor, color) else { return false }
            recordUndoSnapshot()
            rectangle.strokeColor = color
        case let ellipse as EllipseAnnotation:
            guard !colorsMatch(ellipse.strokeColor, color) else { return false }
            recordUndoSnapshot()
            ellipse.strokeColor = color
        default:
            return false
        }
        return true
    }

    @discardableResult
    public func applyTextBackgroundToSelected(_ color: NSColor) -> Bool {
        guard let text = annotation(with: selectedAnnotationID) as? TextAnnotation else { return false }
        let drawsBackground = color.alphaComponent > 0
        guard !colorsMatch(text.backgroundColor, color) || text.drawsBackground != drawsBackground else { return false }
        recordUndoSnapshot()
        text.backgroundColor = color
        text.drawsBackground = drawsBackground
        return true
    }

    @discardableResult
    public func applyThicknessToSelected(_ thickness: CGFloat) -> Bool {
        guard let annotation = annotation(with: selectedAnnotationID) else { return false }
        switch annotation {
        case let text as TextAnnotation:
            guard text.fontSize != thickness else { return false }
            recordUndoSnapshot()
            text.fontSize = thickness
        case let arrow as ArrowAnnotation:
            guard arrow.strokeWidth != thickness else { return false }
            recordUndoSnapshot()
            arrow.strokeWidth = thickness
        case let rectangle as RectangleAnnotation:
            guard rectangle.strokeWidth != thickness else { return false }
            recordUndoSnapshot()
            rectangle.strokeWidth = thickness
        case let ellipse as EllipseAnnotation:
            guard ellipse.strokeWidth != thickness else { return false }
            recordUndoSnapshot()
            ellipse.strokeWidth = thickness
        default:
            return false
        }
        return true
    }

    @discardableResult
    public func resizeSelected(handle: SelectionHandle, to point: CGPoint) -> Bool {
        guard let annotation = annotation(with: selectedAnnotationID) else { return false }
        if annotation is ArrowAnnotation {
            guard handle == .arrowStart || handle == .arrowEnd else { return false }
        } else {
            guard handle != .arrowStart, handle != .arrowEnd else { return false }
        }
        recordUndoSnapshot()
        return AnnotationSelectionGeometry.applyResize(annotation: annotation, handle: handle, to: point)
    }
}

// MARK: - Crop commands

extension AnnotationDocumentState {
    public func setCropRect(_ rect: CGRect?) {
        recordUndoSnapshot()
        guard let rect else {
            cropRect = nil
            return
        }
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let clamped = rect.normalized.clamped(to: imageBounds)
        cropRect = clamped.isNull || clamped.isEmpty ? nil : clamped
    }

    public func applyCrop(_ rect: CGRect) {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let clamped = rect.normalized.clamped(to: imageBounds)
        guard !clamped.isNull, !clamped.isEmpty else { return }
        recordUndoSnapshot()
        cropRect = clamped
        guard let croppedImage = flattenedImage(), let croppedCGImage = croppedImage.cgImageForRendering() else {
            cropRect = nil
            return
        }
        baseImage = croppedImage
        baseCGImage = croppedCGImage
        imageSize = CGSize(width: croppedCGImage.width, height: croppedCGImage.height)
        annotations.removeAll()
        cropRect = nil
        selectedAnnotationID = nil
    }
}

// MARK: - Undo and redo

extension AnnotationDocumentState {
    public func recordUndoSnapshot() {
        undoStack.append(snapshot())
        if undoStack.count > historyLimit {
            undoStack.removeFirst(undoStack.count - historyLimit)
        }
        redoStack.removeAll()
        revisionID = UUID()
        revisionDidChange?(revisionID)
    }

    @discardableResult
    public func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(snapshot())
        restore(previous)
        revisionDidChange?(revisionID)
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(snapshot())
        restore(next)
        revisionDidChange?(revisionID)
        return true
    }
}

// MARK: - Snapshot internals

private extension AnnotationDocumentState {
    private func snapshot() -> DocumentSnapshot {
        DocumentSnapshot(
            baseImage: baseImage,
            baseCGImage: baseCGImage,
            imageSize: imageSize,
            annotations: annotations.map { $0.copyAnnotation() },
            cropRect: cropRect,
            selectedAnnotationID: selectedAnnotationID,
            revisionID: revisionID
        )
    }

    private func restore(_ snapshot: DocumentSnapshot) {
        baseImage = snapshot.baseImage
        baseCGImage = snapshot.baseCGImage
        imageSize = snapshot.imageSize
        annotations = snapshot.annotations.map { $0.copyAnnotation() }
        cropRect = snapshot.cropRect
        selectedAnnotationID = snapshot.selectedAnnotationID
        revisionID = snapshot.revisionID
    }

    private func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard let left = lhs.usingColorSpace(.sRGB), let right = rhs.usingColorSpace(.sRGB) else {
            return lhs == rhs
        }
        return abs(left.redComponent - right.redComponent) < 0.0001
            && abs(left.greenComponent - right.greenComponent) < 0.0001
            && abs(left.blueComponent - right.blueComponent) < 0.0001
            && abs(left.alphaComponent - right.alphaComponent) < 0.0001
    }
}

// MARK: - Rendered output

extension AnnotationDocumentState {
    public func flattenedImage() -> NSImage? {
        guard hasImage else { return nil }
        return ImageRenderer.render(state: self)
    }

    public func imageData(format: RasterImageFormat, jpegQuality: CGFloat = 0.9) -> Data? {
        guard let image = flattenedImage(), let cgImage = image.cgImageForRendering() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        switch format {
        case .jpeg:
            return rep.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
        case .png:
            return rep.representation(using: .png, properties: [:])
        }
    }

    public func jpegData(quality: CGFloat = 0.9) -> Data? {
        imageData(format: .jpeg, jpegQuality: quality)
    }
}

public extension NSImage {
    func cgImageForRendering() -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}
