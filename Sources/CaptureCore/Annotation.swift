import AppKit

public protocol Annotation: AnyObject {
    var id: UUID { get }
    var bounds: CGRect { get set }
    func draw(in context: CGContext, baseImage: CGImage?, imageSize: CGSize, scale: CGFloat)
    func hitTest(_ point: CGPoint) -> Bool
    func moveBy(dx: CGFloat, dy: CGFloat)
    func copyAnnotation(id: UUID) -> Annotation
}

public extension Annotation {
    func copyAnnotation() -> Annotation { copyAnnotation(id: id) }
}

public final class ArrowAnnotation: Annotation {
    public let id: UUID
    public var start: CGPoint
    public var end: CGPoint
    public var color: NSColor
    public var strokeWidth: CGFloat

    public var bounds: CGRect {
        get { CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y).normalized }
        set {
            let old = bounds
            moveBy(dx: newValue.midX - old.midX, dy: newValue.midY - old.midY)
        }
    }

    public init(id: UUID = UUID(), start: CGPoint, end: CGPoint, color: NSColor = CapturePalette.softRed, strokeWidth: CGFloat = 8) {
        self.id = id
        self.start = start
        self.end = end
        self.color = color
        self.strokeWidth = strokeWidth
    }

    public func draw(in context: CGContext, baseImage: CGImage?, imageSize: CGSize, scale: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length >= 2 else { return }

        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux
        let shaftWidth = max(14, strokeWidth * 2.2)
        let tailWidth = shaftWidth * 0.72
        let headLength = min(max(34, shaftWidth * 3.2), length * 0.55)
        let headWidth = shaftWidth * 3.35
        let neck = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        let tailCapInset = min(length * 0.18, tailWidth * 0.5)
        let tailCenter = CGPoint(x: start.x + ux * tailCapInset, y: start.y + uy * tailCapInset)

        let tailLeft = CGPoint(x: tailCenter.x + px * tailWidth / 2, y: tailCenter.y + py * tailWidth / 2)
        let tailRight = CGPoint(x: tailCenter.x - px * tailWidth / 2, y: tailCenter.y - py * tailWidth / 2)
        let neckLeft = CGPoint(x: neck.x + px * shaftWidth / 2, y: neck.y + py * shaftWidth / 2)
        let neckRight = CGPoint(x: neck.x - px * shaftWidth / 2, y: neck.y - py * shaftWidth / 2)
        let headLeft = CGPoint(x: neck.x + px * headWidth / 2, y: neck.y + py * headWidth / 2)
        let headRight = CGPoint(x: neck.x - px * headWidth / 2, y: neck.y - py * headWidth / 2)
        let tailControlLeft = CGPoint(x: start.x + px * tailWidth / 2, y: start.y + py * tailWidth / 2)
        let tailControlRight = CGPoint(x: start.x - px * tailWidth / 2, y: start.y - py * tailWidth / 2)

        context.saveGState()
        context.setFillColor(color.cgColor)
        context.move(to: tailLeft)
        context.addLine(to: neckLeft)
        context.addLine(to: headLeft)
        context.addLine(to: end)
        context.addLine(to: headRight)
        context.addLine(to: neckRight)
        context.addLine(to: tailRight)
        context.addQuadCurve(to: tailLeft, control: CGPoint(
            x: (tailControlLeft.x + tailControlRight.x) / 2 - ux * tailWidth * 0.45,
            y: (tailControlLeft.y + tailControlRight.y) / 2 - uy * tailWidth * 0.45
        ))
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    public func hitTest(_ point: CGPoint) -> Bool {
        distanceFromPointToSegment(point, start, end) <= max(12, strokeWidth * 1.5)
    }

    public func moveBy(dx: CGFloat, dy: CGFloat) {
        start.x += dx
        start.y += dy
        end.x += dx
        end.y += dy
    }

    public func copyAnnotation(id: UUID) -> Annotation {
        ArrowAnnotation(id: id, start: start, end: end, color: color, strokeWidth: strokeWidth)
    }
}

/// Shared TextKit metrics for the live editor and flattened output.
public enum TextAnnotationLayout {
    public static let horizontalInset: CGFloat = 10
    public static let verticalInset: CGFloat = 6

    public static func attributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    public static func configure(_ container: NSTextContainer, width: CGFloat, scale: CGFloat = 1) {
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.containerSize = CGSize(width: max(1, width - horizontalInset * scale * 2),
                                         height: .greatestFiniteMagnitude)
        container.lineBreakMode = .byWordWrapping
    }

    public static func contentHeight(manager: NSLayoutManager, container: NSTextContainer, font: NSFont) -> CGFloat {
        manager.ensureLayout(for: container)
        return max(manager.defaultLineHeight(for: font), manager.usedRect(for: container).maxY,
                   manager.extraLineFragmentRect.maxY)
    }

    public static func verticalOffset(height: CGFloat, contentHeight: CGFloat, scale: CGFloat = 1) -> CGFloat {
        max(verticalInset * scale, (height - contentHeight) / 2)
    }

    public static func initialBounds(at point: CGPoint, canvas: CGRect, fontSize: CGFloat) -> CGRect {
        let margin = min(20, min(canvas.width, canvas.height) / 4)
        let available = canvas.insetBy(dx: margin, dy: margin)
        let minimumWidth = min(260, available.width)
        let x = min(max(point.x, available.minX), available.maxX - minimumWidth)
        let manager = NSLayoutManager()
        let height = max(76, manager.defaultLineHeight(for: .boldSystemFont(ofSize: fontSize)) + verticalInset * 2)
        return CGRect(x: x, y: point.y, width: available.maxX - x, height: height).fitted(inside: available)
    }
}

public final class TextAnnotation: Annotation {
    public let id: UUID
    public var bounds: CGRect
    public var text: String
    public var fontSize: CGFloat
    public var textColor: NSColor
    public var backgroundColor: NSColor
    public var drawsBackground: Bool

    public init(
        id: UUID = UUID(),
        bounds: CGRect,
        text: String = "Text",
        fontSize: CGFloat = 32,
        textColor: NSColor = CapturePalette.softRed,
        backgroundColor: NSColor = NSColor.black.withAlphaComponent(0.5),
        drawsBackground: Bool = true
    ) {
        self.id = id
        self.bounds = bounds.normalized
        self.text = text
        self.fontSize = fontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.drawsBackground = drawsBackground
    }

    public func drawBackground(in context: CGContext) {
        if drawsBackground {
            context.saveGState()
            context.setFillColor(backgroundColor.cgColor)
            let radius = min(10, bounds.height / 4)
            context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
            context.restoreGState()
        }
    }

    public func draw(in context: CGContext, baseImage: CGImage?, imageSize: CGSize, scale: CGFloat) {
        drawBackground(in: context)

        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let storage = NSTextStorage(string: text, attributes: TextAnnotationLayout.attributes(font: font, color: textColor))
        let manager = NSLayoutManager()
        let container = NSTextContainer()
        TextAnnotationLayout.configure(container, width: bounds.width)
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let height = TextAnnotationLayout.contentHeight(manager: manager, container: container, font: font)
        let origin = CGPoint(x: TextAnnotationLayout.horizontalInset,
                             y: TextAnnotationLayout.verticalOffset(height: bounds.height, contentHeight: height))
        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: bounds.minX, y: bounds.maxY)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        manager.drawGlyphs(forGlyphRange: manager.glyphRange(for: container), at: origin)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    public func hitTest(_ point: CGPoint) -> Bool {
        bounds.insetForHitTesting(6).contains(point)
    }

    public func moveBy(dx: CGFloat, dy: CGFloat) {
        bounds.origin.x += dx
        bounds.origin.y += dy
    }

    public func copyAnnotation(id: UUID) -> Annotation {
        TextAnnotation(id: id, bounds: bounds, text: text, fontSize: fontSize, textColor: textColor, backgroundColor: backgroundColor, drawsBackground: drawsBackground)
    }
}

public final class RectangleAnnotation: Annotation {
    public let id: UUID
    public var bounds: CGRect
    public var strokeColor: NSColor
    public var strokeWidth: CGFloat

    public init(id: UUID = UUID(), bounds: CGRect, strokeColor: NSColor = CapturePalette.softRed, strokeWidth: CGFloat = 6) {
        self.id = id
        self.bounds = bounds.normalized
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }

    public func draw(in context: CGContext, baseImage: CGImage?, imageSize: CGSize, scale: CGFloat) {
        context.saveGState()
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(strokeWidth)
        context.stroke(bounds)
        context.restoreGState()
    }

    public func hitTest(_ point: CGPoint) -> Bool {
        bounds.insetForHitTesting(8).contains(point) && !bounds.insetBy(dx: 12, dy: 12).contains(point)
    }

    public func moveBy(dx: CGFloat, dy: CGFloat) {
        bounds.origin.x += dx
        bounds.origin.y += dy
    }

    public func copyAnnotation(id: UUID) -> Annotation {
        RectangleAnnotation(id: id, bounds: bounds, strokeColor: strokeColor, strokeWidth: strokeWidth)
    }
}

public final class EllipseAnnotation: Annotation {
    public let id: UUID
    public var bounds: CGRect
    public var strokeColor: NSColor
    public var strokeWidth: CGFloat

    public init(id: UUID = UUID(), bounds: CGRect, strokeColor: NSColor = CapturePalette.softRed, strokeWidth: CGFloat = 6) {
        self.id = id
        self.bounds = bounds.normalized
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }

    public func draw(in context: CGContext, baseImage: CGImage?, imageSize: CGSize, scale: CGFloat) {
        context.saveGState()
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(strokeWidth)
        context.strokeEllipse(in: bounds)
        context.restoreGState()
    }

    public func hitTest(_ point: CGPoint) -> Bool {
        let rx = bounds.width / 2
        let ry = bounds.height / 2
        if rx <= 0 || ry <= 0 { return false }
        let nx = (point.x - bounds.midX) / rx
        let ny = (point.y - bounds.midY) / ry
        let value = nx * nx + ny * ny
        return value >= 0.72 && value <= 1.28
    }

    public func moveBy(dx: CGFloat, dy: CGFloat) {
        bounds.origin.x += dx
        bounds.origin.y += dy
    }

    public func copyAnnotation(id: UUID) -> Annotation {
        EllipseAnnotation(id: id, bounds: bounds, strokeColor: strokeColor, strokeWidth: strokeWidth)
    }
}

public final class BlurAnnotation: Annotation {
    public let id: UUID
    public var bounds: CGRect { didSet { invalidateCache() } }
    public var radius: CGFloat { didSet { invalidateCache() } }
    private var cachedKey: String?
    private var cachedImage: CGImage?

    public init(id: UUID = UUID(), bounds: CGRect, radius: CGFloat = 16) {
        self.id = id
        self.bounds = bounds.normalized
        self.radius = radius
    }

    public func draw(in context: CGContext, baseImage: CGImage?, imageSize: CGSize, scale: CGFloat) {
        guard let baseImage else {
            context.saveGState()
            context.setFillColor(NSColor.systemGray.withAlphaComponent(0.35).cgColor)
            context.fill(bounds)
            context.restoreGState()
            return
        }

        let normalized = bounds.normalized.clamped(to: CGRect(origin: .zero, size: imageSize)).integral
        guard !normalized.isNull, normalized.width >= 1, normalized.height >= 1 else { return }
        let key = "\(Int(normalized.origin.x))-\(Int(normalized.origin.y))-\(Int(normalized.width))-\(Int(normalized.height))-\(radius)"
        let blurred: CGImage
        if cachedKey == key, let cachedImage {
            blurred = cachedImage
        } else if let rendered = BlurRenderer.blurredRegion(from: baseImage, imageSize: imageSize, rect: normalized, radius: radius) {
            cachedKey = key
            cachedImage = rendered
            blurred = rendered
        } else {
            return
        }

        context.saveGState()
        context.draw(blurred, in: normalized)
        context.restoreGState()
    }

    public func hitTest(_ point: CGPoint) -> Bool {
        bounds.insetForHitTesting(6).contains(point)
    }

    private func invalidateCache() {
        cachedKey = nil
        cachedImage = nil
    }

    public func moveBy(dx: CGFloat, dy: CGFloat) {
        bounds.origin.x += dx
        bounds.origin.y += dy
    }

    public func copyAnnotation(id: UUID) -> Annotation {
        BlurAnnotation(id: id, bounds: bounds, radius: radius)
    }
}
