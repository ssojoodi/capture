import AppKit
import CoreImage

public protocol Annotation: AnyObject {
    var id: UUID { get }
    var bounds: CGRect { get set }
    func draw(in context: CGContext, baseImage: CGImage?, imageSize: CGSize, scale: CGFloat)
    func hitTest(_ point: CGPoint) -> Bool
    func moveBy(dx: CGFloat, dy: CGFloat)
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
}

public final class BlurAnnotation: Annotation {
    public let id: UUID
    public var bounds: CGRect { didSet { invalidateCache() } }
    public var radius: CGFloat { didSet { invalidateCache() } }
    private var cachedKey: String?
    private var cachedImage: CGImage?

    public init(id: UUID = UUID(), bounds: CGRect, radius: CGFloat = 12) {
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

        let pixelRect = CGRect(
            x: bounds.origin.x,
            y: imageSize.height - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        ).integral.intersection(CGRect(origin: .zero, size: imageSize))
        guard let crop = baseImage.cropping(to: pixelRect), !pixelRect.isNull else { return }

        let key = "\(Int(pixelRect.origin.x))-\(Int(pixelRect.origin.y))-\(Int(pixelRect.width))-\(Int(pixelRect.height))-\(radius)"
        let blurred: CGImage
        if cachedKey == key, let cachedImage {
            blurred = cachedImage
        } else {
            let ciImage = CIImage(cgImage: crop).clampedToExtent()
            let filter = CIFilter(name: "CIGaussianBlur")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(radius, forKey: kCIInputRadiusKey)
            guard let output = filter?.outputImage?.cropped(to: ciImage.extent) else { return }

            let ciContext = CIContext(options: [.useSoftwareRenderer: false])
            guard let rendered = ciContext.createCGImage(output, from: output.extent) else { return }
            cachedKey = key
            cachedImage = rendered
            blurred = rendered
        }

        context.saveGState()
        context.draw(blurred, in: bounds)
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(3)
        context.stroke(bounds)
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
}
