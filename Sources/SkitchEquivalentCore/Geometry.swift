import CoreGraphics

public extension CGRect {
    var normalized: CGRect {
        CGRect(
            x: min(origin.x, origin.x + size.width),
            y: min(origin.y, origin.y + size.height),
            width: abs(size.width),
            height: abs(size.height)
        )
    }

    func clamped(to bounds: CGRect) -> CGRect {
        intersection(bounds).standardized
    }

    func insetForHitTesting(_ amount: CGFloat) -> CGRect {
        insetBy(dx: -amount, dy: -amount)
    }
}

public func distanceFromPointToSegment(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    if dx == 0 && dy == 0 {
        return hypot(point.x - start.x, point.y - start.y)
    }

    let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)))
    let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
    return hypot(point.x - projection.x, point.y - projection.y)
}
