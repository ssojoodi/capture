import AppKit

public final class AnnotationDocumentState {
    private struct DocumentSnapshot {
        let baseImage: NSImage?
        let baseCGImage: CGImage?
        let imageSize: CGSize
        let annotations: [Annotation]
        let cropRect: CGRect?
        let selectedAnnotationID: UUID?
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

    public init() {}

    public var hasImage: Bool { baseImage != nil }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

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

    public func deleteSelectedAnnotation() {
        guard let selectedAnnotationID else { return }
        recordUndoSnapshot()
        annotations.removeAll { $0.id == selectedAnnotationID }
        self.selectedAnnotationID = nil
    }

    @discardableResult
    public func applyColorToSelected(_ color: NSColor) -> Bool {
        guard let annotation = annotation(with: selectedAnnotationID) else { return false }
        switch annotation {
        case let arrow as ArrowAnnotation:
            recordUndoSnapshot()
            arrow.color = color
        case let text as TextAnnotation:
            recordUndoSnapshot()
            text.textColor = color
        case let rectangle as RectangleAnnotation:
            recordUndoSnapshot()
            rectangle.strokeColor = color
        case let ellipse as EllipseAnnotation:
            recordUndoSnapshot()
            ellipse.strokeColor = color
        default:
            return false
        }
        return true
    }

    @discardableResult
    public func applyThicknessToSelected(_ thickness: CGFloat) -> Bool {
        guard let annotation = annotation(with: selectedAnnotationID) else { return false }
        switch annotation {
        case let arrow as ArrowAnnotation:
            recordUndoSnapshot()
            arrow.strokeWidth = thickness
        case let rectangle as RectangleAnnotation:
            recordUndoSnapshot()
            rectangle.strokeWidth = thickness
        case let ellipse as EllipseAnnotation:
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
        recordUndoSnapshot()
        if let arrow = annotation as? ArrowAnnotation {
            switch handle {
            case .arrowStart:
                arrow.start = point
            case .arrowEnd:
                arrow.end = point
            default:
                return false
            }
        } else {
            annotation.bounds = AnnotationSelectionGeometry.resizedRect(annotation.bounds, moving: handle, to: point)
        }
        return true
    }

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

    public func recordUndoSnapshot() {
        undoStack.append(snapshot())
        if undoStack.count > historyLimit {
            undoStack.removeFirst(undoStack.count - historyLimit)
        }
        redoStack.removeAll()
    }

    @discardableResult
    public func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(snapshot())
        restore(previous)
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(snapshot())
        restore(next)
        return true
    }

    private func snapshot() -> DocumentSnapshot {
        DocumentSnapshot(
            baseImage: baseImage,
            baseCGImage: baseCGImage,
            imageSize: imageSize,
            annotations: annotations.map { $0.copyAnnotation() },
            cropRect: cropRect,
            selectedAnnotationID: selectedAnnotationID
        )
    }

    private func restore(_ snapshot: DocumentSnapshot) {
        baseImage = snapshot.baseImage
        baseCGImage = snapshot.baseCGImage
        imageSize = snapshot.imageSize
        annotations = snapshot.annotations.map { $0.copyAnnotation() }
        cropRect = snapshot.cropRect
        selectedAnnotationID = snapshot.selectedAnnotationID
    }

    public func flattenedImage() -> NSImage? {
        guard hasImage else { return nil }
        return ImageRenderer.render(state: self)
    }

    public func jpegData(quality: CGFloat = 0.9) -> Data? {
        guard let image = flattenedImage(), let cgImage = image.cgImageForRendering() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}

public extension NSImage {
    func cgImageForRendering() -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}
