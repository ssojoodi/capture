import AppKit

public final class AnnotationDocumentState {
    public private(set) var baseImage: NSImage?
    public private(set) var baseCGImage: CGImage?
    public private(set) var imageSize: CGSize = .zero
    public var selectedTool: Tool = .select
    public var selectedAnnotationID: UUID?
    public var annotations: [Annotation] = []
    public private(set) var cropRect: CGRect?

    public init() {}

    public var hasImage: Bool { baseImage != nil }

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
    }

    public func addAnnotation(_ annotation: Annotation) {
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
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
        annotations.removeAll { $0.id == selectedAnnotationID }
        self.selectedAnnotationID = nil
    }

    public func setCropRect(_ rect: CGRect?) {
        guard let rect else {
            cropRect = nil
            return
        }
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let clamped = rect.normalized.clamped(to: imageBounds)
        cropRect = clamped.isNull || clamped.isEmpty ? nil : clamped
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
