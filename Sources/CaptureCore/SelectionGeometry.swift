import AppKit

public enum SelectionHandle: CaseIterable, Equatable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
    case arrowStart
    case arrowEnd
}

public enum AnnotationSelectionGeometry {
    public static func handleCenters(for annotation: Annotation) -> [(SelectionHandle, CGPoint)] {
        if let arrow = annotation as? ArrowAnnotation {
            return [(.arrowStart, arrow.start), (.arrowEnd, arrow.end)]
        }

        let rect = annotation.bounds.normalized
        return [
            (.topLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.top, CGPoint(x: rect.midX, y: rect.maxY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY))
        ]
    }

    public static func hitHandle(at point: CGPoint, annotation: Annotation, hitRadius: CGFloat) -> SelectionHandle? {
        handleCenters(for: annotation).first { _, center in
            hypot(point.x - center.x, point.y - center.y) <= hitRadius
        }?.0
    }

    public static func resizedRect(_ rect: CGRect, moving handle: SelectionHandle, to point: CGPoint, minimumSize: CGFloat = 12) -> CGRect {
        var minX = rect.normalized.minX
        var maxX = rect.normalized.maxX
        var minY = rect.normalized.minY
        var maxY = rect.normalized.maxY

        switch handle {
        case .topLeft:
            minX = min(point.x, maxX - minimumSize)
            maxY = max(point.y, minY + minimumSize)
        case .top:
            maxY = max(point.y, minY + minimumSize)
        case .topRight:
            maxX = max(point.x, minX + minimumSize)
            maxY = max(point.y, minY + minimumSize)
        case .right:
            maxX = max(point.x, minX + minimumSize)
        case .bottomRight:
            maxX = max(point.x, minX + minimumSize)
            minY = min(point.y, maxY - minimumSize)
        case .bottom:
            minY = min(point.y, maxY - minimumSize)
        case .bottomLeft:
            minX = min(point.x, maxX - minimumSize)
            minY = min(point.y, maxY - minimumSize)
        case .left:
            minX = min(point.x, maxX - minimumSize)
        case .arrowStart, .arrowEnd:
            break
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).normalized
    }

    @discardableResult
    public static func applyResize(annotation: Annotation, handle: SelectionHandle, to point: CGPoint) -> Bool {
        if let arrow = annotation as? ArrowAnnotation {
            switch handle {
            case .arrowStart:
                arrow.start = point
            case .arrowEnd:
                arrow.end = point
            default:
                return false
            }
            return true
        }

        guard handle != .arrowStart, handle != .arrowEnd else { return false }
        annotation.bounds = resizedRect(annotation.bounds, moving: handle, to: point)
        return true
    }
}
