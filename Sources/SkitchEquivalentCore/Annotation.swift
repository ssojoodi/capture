import AppKit
import CoreImage

public protocol Annotation: AnyObject {
    var id: UUID { get }
    var bounds: CGRect { get set }
    func draw(in context: CGContext, baseImage: CGImage?, imageSize: CGSize, scale: CGFloat)
    func hitTest(_ point: CGPoint) -> Bool
    func moveBy(dx: CGFloat, dy: CGFloat)
    func copyAnnotation() -> Annotation
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

    public init(id: UUID = UUID(), start: CGPoint, end: CGPoint, color: NSColor = .systemRed, strokeWidth: CGFloat = 8) {
        self.id = id
        self.start = start
        self.end = end
        self.color = color
        self.strokeWidth = strokeWidth
    }

    public func draw(in context: CGContext, baseImage: CGImage?, imageSize: CGSize, scale: CGFloat) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(strokeWidth)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(20, strokeWidth * 4)
        let wingAngle = CGFloat.pi / 7
        let p1 = CGPoint(x: end.x - headLength * cos(angle - wingAngle), y: end.y - headLength * sin(angle - wingAngle))
        let p2 = CGPoint(x: end.x - headLength * cos(angle + wingAngle), y: end.y - headLength * sin(angle + wingAngle))
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
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

    public func copyAnnotation() -> Annotation {
        ArrowAnnotation(id: id, start: start, end: end, color: color, strokeWidth: strokeWidth)
    }
}

public final class TextAnnotation: Annotation {
    public let id: UUID
    public var bounds: CGRect
    public var text: String
    public var fontSize: CGFloat
    public var textColor: NSColor
    public var backgroundColor: NSColor

    public init(id: UUID = UUID(), bounds: CGRect, text: String = "Text", fontSize: CGFloat = 32, textColor: NSColor = .white, backgroundColor: NSColor = .systemRed) {
        self.id = id
        self.bounds = bounds.normalized
        self.text = text
        self.fontSize = fontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }

    public func draw(in context: CGContext, baseImage: CGImage?, imageSize: CGSize, scale: CGFloat) {
        context.saveGState()
        context.setFillColor(backgroundColor.cgColor)
        let radius = min(10, bounds.height / 4)
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        context.restoreGState()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let textRect = bounds.insetBy(dx: 10, dy: max(4, (bounds.height - fontSize * 1.2) / 2))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSString(string: text).draw(in: textRect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    public func hitTest(_ point: CGPoint) -> Bool {
        bounds.insetForHitTesting(6).contains(point)
    }

    public func moveBy(dx: CGFloat, dy: CGFloat) {
        bounds.origin.x += dx
        bounds.origin.y += dy
    }

    public func copyAnnotation() -> Annotation {
        TextAnnotation(id: id, bounds: bounds, text: text, fontSize: fontSize, textColor: textColor, backgroundColor: backgroundColor)
    }
}

public final class RectangleAnnotation: Annotation {
    public let id: UUID
    public var bounds: CGRect
    public var strokeColor: NSColor
    public var strokeWidth: CGFloat

    public init(id: UUID = UUID(), bounds: CGRect, strokeColor: NSColor = .systemRed, strokeWidth: CGFloat = 6) {
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

    public func copyAnnotation() -> Annotation {
        RectangleAnnotation(id: id, bounds: bounds, strokeColor: strokeColor, strokeWidth: strokeWidth)
    }
}

public final class EllipseAnnotation: Annotation {
    public let id: UUID
    public var bounds: CGRect
    public var strokeColor: NSColor
    public var strokeWidth: CGFloat

    public init(id: UUID = UUID(), bounds: CGRect, strokeColor: NSColor = .systemRed, strokeWidth: CGFloat = 6) {
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

    public func copyAnnotation() -> Annotation {
        EllipseAnnotation(id: id, bounds: bounds, strokeColor: strokeColor, strokeWidth: strokeWidth)
    }
}

public enum BlurRenderer {
    public static func blurredRegion(from baseImage: CGImage, imageSize: CGSize, rect imageRect: CGRect, radius: CGFloat) -> CGImage? {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let normalized = imageRect.normalized.clamped(to: imageBounds).integral
        guard !normalized.isNull, normalized.width >= 1, normalized.height >= 1 else { return nil }

        let pixelRect = CGRect(
            x: normalized.origin.x,
            y: imageSize.height - normalized.maxY,
            width: normalized.width,
            height: normalized.height
        ).integral.intersection(imageBounds)
        guard !pixelRect.isNull, let crop = baseImage.cropping(to: pixelRect) else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let pixelSize = max(4, radius)
        let sampleWidth = max(1, Int((normalized.width / pixelSize).rounded(.up)))
        let sampleHeight = max(1, Int((normalized.height / pixelSize).rounded(.up)))
        guard let sampleContext = CGContext(
            data: nil,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        sampleContext.interpolationQuality = .high
        sampleContext.draw(crop, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
        guard let sampledImage = sampleContext.makeImage() else { return nil }

        guard let outputContext = CGContext(
            data: nil,
            width: Int(normalized.width),
            height: Int(normalized.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        outputContext.interpolationQuality = .none
        outputContext.draw(sampledImage, in: CGRect(x: 0, y: 0, width: normalized.width, height: normalized.height))
        return outputContext.makeImage()
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

    public func copyAnnotation() -> Annotation {
        BlurAnnotation(id: id, bounds: bounds, radius: radius)
    }
}
