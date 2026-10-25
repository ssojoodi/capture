import AppKit
import ImageIO
import CaptureCore
#if canImport(CaptureAutomation)
import CaptureAutomation
#endif

/// The adapter is owned by one window, and all calls execute on the app main thread.
final class AgentDocument {
    let id = UUID().uuidString
    private(set) var revision = UUID().uuidString
    let state: AnnotationDocumentState
    private let pasteboard: NSPasteboard
    init(state: AnnotationDocumentState, pasteboard: NSPasteboard = .general) {
        self.state = state; self.pasteboard = pasteboard
    }
    func didChange() { revision = UUID().uuidString }
    static let pixelLimit: CGFloat = 32_000_000
    static func checkSize(_ size: CGSize) throws {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              size.width <= 16384, size.height <= 16384, size.width * size.height <= pixelLimit else {
            throw AgentError("limit_exceeded", "Images and expanded canvases must be at most 16384 pixels per side and 32 megapixels.")
        }
    }
    static func image(at path: String) throws -> NSImage {
        let url = try fileURL(path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = props[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw AgentError("unsupported_image", "Cannot read this local image.")
        }
        try checkSize(CGSize(width: width.doubleValue, height: height.doubleValue))
        // Honor orientation, while keeping full source resolution.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width.intValue, height.intValue)]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw AgentError("unsupported_image", "Image decoding failed.") }
        return NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
    }
    static func fileURL(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.contains("\0") else { throw AgentError("invalid_path", "Use an absolute local file path.") }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
    func summary(busy: Bool) -> [String: Any] {
        ["documentID": id, "revision": revision, "busy": busy, "hasImage": state.hasImage,
         "imageSize": ["width": state.imageSize.width, "height": state.imageSize.height],
         "canvasBounds": rectJSON(state.canvasBounds), "canUndo": state.canUndo, "canRedo": state.canRedo]
    }
    func inspect() -> [String: Any] {
        var result = summary(busy: false)
        result["annotations"] = state.annotations.map(describe)
        return result
    }
    func perform(_ method: String, _ args: [String: Any]) throws -> [String: Any] {
        guard state.hasImage else { throw AgentError("no_image", "Open an image first.") }
        if !["inspect_document", "preview_document"].contains(method) {
            guard args["revision"] as? String == revision else { throw AgentError("stale_revision", "Document changed. Inspect it again before retrying.") }
        }
        switch method {
        case "inspect_document": return inspect()
        case "preview_document": return try preview()
        case "add_annotation", "update_annotation":
            let props = args["properties"] as! [String: Any]
            let old: Annotation?
            if method == "update_annotation" { old = try annotation(args) } else { old = nil }
            let kind = old.map(kindOf) ?? (args["kind"] as! String)
            let candidate = try makeAnnotation(kind: kind, properties: props, original: old)
            var bounds = CGRect(origin: .zero, size: state.imageSize)
            for annotation in state.annotations where annotation.id != old?.id { bounds = bounds.union(annotation.renderedBounds) }
            bounds = bounds.union(candidate.renderedBounds).integral
            try Self.checkSize(bounds.size)
            guard state.annotations.count < 2000 || old != nil else { throw AgentError("limit_exceeded", "Maximum 2000 annotations per document.") }
            if let old, let index = state.annotations.firstIndex(where: { $0.id == old.id }) {
                state.recordUndoSnapshot(); state.annotations[index] = candidate
            } else { state.addAnnotation(candidate, select: false) }
            var result = inspect(); result["annotationID"] = candidate.id.uuidString; return result
        case "delete_annotation":
            let annotation = try annotation(args)
            state.recordUndoSnapshot(); state.annotations.removeAll { $0.id == annotation.id }
            if state.selectedAnnotationID == annotation.id { state.selectedAnnotationID = nil }
        case "blur_region", "crop_document":
            try Self.checkSize(state.imageSize)
            let rect = try rectangle(args["bounds"]!).intersection(CGRect(origin: .zero, size: state.imageSize)).integral
            guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { throw AgentError("invalid_bounds", "Region does not intersect the original image.") }
            let before = state.revisionID
            if method == "blur_region" {
                let radius = try number(args, "radius", fallback: 16, range: 1...100)
                state.applyBlur(rect, radius: radius)
            } else { state.applyCrop(rect) }
            guard before != state.revisionID else { throw AgentError("render_failed", "Could not render the requested operation.") }
        case "undo": guard state.undo() else { throw AgentError("nothing_to_undo", "No edit to undo.") }
        case "redo": guard state.redo() else { throw AgentError("nothing_to_redo", "No edit to redo.") }
        case "export_image", "copy_image":
            try Self.checkSize(state.canvasBounds.size)
            var url: URL?; var format: RasterImageFormat = .png
            if method == "export_image" {
                url = try Self.fileURL(args["path"] as! String)
                switch url!.pathExtension.lowercased() {
                case "png": break
                case "jpg", "jpeg": format = .jpeg
                default: throw AgentError("invalid_format", "Use a .png, .jpg or .jpeg filename.")
                }
                guard !FileManager.default.fileExists(atPath: url!.path) || args["overwrite"] as? Bool == true else { throw AgentError("file_exists", "Output exists. Choose another path or set overwrite to true.") }
            }
            guard let data = state.imageData(format: format) else { throw AgentError("render_failed", "Could not render image.") }
            if let url {
                try writeExport(data, to: url, overwrite: args["overwrite"] as? Bool == true)
                var result = summary(busy: false); result["path"] = url.path; return result
            } else {
                pasteboard.clearContents()
                guard pasteboard.setData(data, forType: .png) else { throw AgentError("clipboard_failed", "Could not copy the image.") }
            }
        default: throw AgentError("unknown_tool", "Unknown document command.")
        }
        return inspect()
    }
    private func writeExport(_ data: Data, to url: URL, overwrite: Bool) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".capture-export-" + UUID().uuidString)
        try data.write(to: temporary, options: [.withoutOverwriting])
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Both operations publish a fully written file atomically. link fails if the destination exists.
        let result = overwrite ? Darwin.rename(temporary.path, url.path) : Darwin.link(temporary.path, url.path)
        guard result == 0 else {
            if errno == EEXIST { throw AgentError("file_exists", "Output exists. Choose another path or set overwrite to true.") }
            throw AgentError("export_failed", String(cString: strerror(errno)))
        }
    }
    private func annotation(_ args: [String: Any]) throws -> Annotation {
        guard let raw = args["annotationID"] as? String, let id = UUID(uuidString: raw), let annotation = state.annotation(with: id) else { throw AgentError("annotation_not_found", "Inspect the document for current annotation IDs.") }
        return annotation
    }
    private func kindOf(_ annotation: Annotation) -> String {
        switch annotation { case is HighlightAnnotation: return "highlighter"; case is ArrowAnnotation: return "arrow"; case is TextAnnotation: return "text"; case is RectangleAnnotation: return "rectangle"; case is EllipseAnnotation: return "ellipse"; default: return "blur" }
    }
    private func describe(_ annotation: Annotation) -> [String: Any] {
        var props: [String: Any] = ["bounds": rectJSON(annotation.bounds)]
        switch annotation {
        case let a as HighlightAnnotation: props = ["points": a.points.map(pointJSON), "color": colorJSON(a.color), "strokeWidth": a.strokeWidth]
        case let a as ArrowAnnotation: props = ["start": pointJSON(a.start), "end": pointJSON(a.end), "color": colorJSON(a.color), "strokeWidth": a.strokeWidth]
        case let a as RectangleAnnotation: props["color"] = colorJSON(a.strokeColor); props["strokeWidth"] = a.strokeWidth
        case let a as EllipseAnnotation: props["color"] = colorJSON(a.strokeColor); props["strokeWidth"] = a.strokeWidth
        case let a as TextAnnotation: props["text"] = a.text; props["fontSize"] = a.fontSize; props["color"] = colorJSON(a.textColor); props["backgroundColor"] = colorJSON(a.drawsBackground ? a.backgroundColor : .clear)
        default: break
        }
        return ["annotationID": annotation.id.uuidString, "kind": kindOf(annotation), "properties": props]
    }
    private func makeAnnotation(kind: String, properties p: [String: Any], original: Annotation?) throws -> Annotation {
        let allowed: Set<String>
        switch kind {
        case "highlighter": allowed = ["points", "color", "strokeWidth"]
        case "arrow": allowed = ["start", "end", "color", "strokeWidth"]
        case "rectangle", "ellipse": allowed = ["bounds", "color", "strokeWidth"]
        case "text": allowed = ["bounds", "text", "fontSize", "color", "backgroundColor"]
        default: throw AgentError("invalid_kind", "Unsupported annotation kind.")
        }
        guard !p.isEmpty, Set(p.keys).isSubset(of: allowed) else { throw AgentError("invalid_properties", "Properties do not match the annotation kind.") }
        let candidate: Annotation
        if let original {
            candidate = original.copyAnnotation()
        } else {
            let required = kind == "highlighter" ? ["points"] : kind == "arrow" ? ["start", "end"] : kind == "text" ? ["bounds", "text"] : ["bounds"]
            guard required.allSatisfy({ p[$0] != nil }) else {
                throw AgentError("invalid_properties", "Missing required annotation properties: \(required.joined(separator: ", ")).")
            }
            switch kind {
            case "highlighter": candidate = HighlightAnnotation(points: [])
            case "arrow": candidate = ArrowAnnotation(start: .zero, end: .zero, strokeWidth: 16)
            case "rectangle": candidate = RectangleAnnotation(bounds: .zero, strokeWidth: 16)
            case "ellipse": candidate = EllipseAnnotation(bounds: .zero, strokeWidth: 16)
            default: candidate = TextAnnotation(bounds: .zero, fontSize: 52)
            }
        }
        if let bounds = p["bounds"] { candidate.bounds = try rectangle(bounds) }
        let color = try p["color"].map { try parseColor($0) }
        let stroke = try p["strokeWidth"].map { _ in try number(p, "strokeWidth", fallback: 16, range: 1...256) }
        switch candidate {
        case let highlight as HighlightAnnotation:
            if let points = p["points"] as? [Any] { highlight.points = try points.map { try point($0) } }
            if let color { highlight.color = color }
            if let stroke { highlight.strokeWidth = stroke }
        case let arrow as ArrowAnnotation:
            if let start = p["start"] { arrow.start = try point(start) }
            if let end = p["end"] { arrow.end = try point(end) }
            if let color { arrow.color = color }
            if let stroke { arrow.strokeWidth = stroke }
            guard hypot(arrow.start.x - arrow.end.x, arrow.start.y - arrow.end.y) >= 2 else {
                throw AgentError("invalid_bounds", "Arrow must be at least two pixels long.")
            }
        case let rectangle as RectangleAnnotation:
            if let color { rectangle.strokeColor = color }
            if let stroke { rectangle.strokeWidth = stroke }
        case let ellipse as EllipseAnnotation:
            if let color { ellipse.strokeColor = color }
            if let stroke { ellipse.strokeWidth = stroke }
        case let text as TextAnnotation:
            if let value = p["text"] as? String { text.text = value }
            if p["fontSize"] != nil { text.fontSize = try number(p, "fontSize", fallback: 52, range: 6...256) }
            if let color { text.textColor = color }
            if let background = p["backgroundColor"] {
                text.backgroundColor = try parseColor(background)
                text.drawsBackground = text.backgroundColor.alphaComponent > 0
            }
            guard !text.text.isEmpty, text.text.count <= 10000, text.bounds.width >= 24 else {
                throw AgentError("invalid_text", "Text must contain 1–10000 characters and the box must be at least 24 pixels wide.")
            }
            let previous = original as? TextAnnotation
            if previous == nil || previous?.text != text.text || previous?.fontSize != text.fontSize || previous?.bounds.size != text.bounds.size {
                let font = NSFont.boldSystemFont(ofSize: text.fontSize)
                let storage = NSTextStorage(string: text.text, attributes: TextAnnotationLayout.attributes(font: font, color: text.textColor))
                let manager = NSLayoutManager(); let container = NSTextContainer()
                TextAnnotationLayout.configure(container, width: text.bounds.width)
                manager.addTextContainer(container); storage.addLayoutManager(manager)
                let height = ceil(TextAnnotationLayout.contentHeight(manager: manager, container: container, font: font) + TextAnnotationLayout.verticalInset * 2)
                let top = text.bounds.maxY
                text.bounds.size.height = max(text.bounds.height, height)
                text.bounds.origin.y = top - text.bounds.height
            }
        default: throw AgentError("invalid_kind", "Unsupported annotation kind.")
        }
        return candidate
    }

    private func number(_ args: [String: Any], _ key: String, fallback: CGFloat, range: ClosedRange<CGFloat>) throws -> CGFloat {
        let value = (args[key] as? NSNumber).map { CGFloat($0.doubleValue) } ?? fallback
        guard value.isFinite, range.contains(value) else { throw AgentError("invalid_arguments", "\(key) must be in \(range).") }
        return value
    }
    private func point(_ raw: Any) throws -> CGPoint {
        let p = raw as! [String: Any]
        let x = try number(p, "x", fallback: 0, range: -16384...32768)
        let y = try number(p, "y", fallback: 0, range: -16384...32768)
        return CGPoint(x: x, y: state.imageSize.height - y)
    }
    private func rectangle(_ raw: Any) throws -> CGRect {
        let p = raw as! [String: Any]; let top = try point(p)
        let w = try number(p, "width", fallback: 0, range: 1...16384)
        let h = try number(p, "height", fallback: 0, range: 1...16384)
        return CGRect(x: top.x, y: top.y - h, width: w, height: h)
    }
    private func rectJSON(_ rect: CGRect) -> [String: CGFloat] { ["x": rect.minX, "y": state.imageSize.height - rect.maxY, "width": rect.width, "height": rect.height] }
    private func pointJSON(_ point: CGPoint) -> [String: CGFloat] { ["x": point.x, "y": state.imageSize.height - point.y] }
    private func parseColor(_ raw: Any) throws -> NSColor {
        guard let text = raw as? String, text.hasPrefix("#"), [7, 9].contains(text.count), let hex = UInt64(text.dropFirst(), radix: 16) else { throw AgentError("invalid_color", "Use #RRGGBB or #RRGGBBAA.") }
        let rgba = text.count == 7 ? (hex << 8) | 255 : hex
        return NSColor(srgbRed: CGFloat((rgba >> 24) & 255) / 255, green: CGFloat((rgba >> 16) & 255) / 255, blue: CGFloat((rgba >> 8) & 255) / 255, alpha: CGFloat(rgba & 255) / 255)
    }
    private func colorJSON(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()), Int((c.alphaComponent * 255).rounded()))
    }
    private func preview() throws -> [String: Any] {
        try Self.checkSize(state.canvasBounds.size)
        let bounds = state.canvasBounds
        let scale = min(1, 1600 / max(bounds.width, bounds.height))
        let width = max(1, Int((bounds.width * scale).rounded())), height = max(1, Int((bounds.height * scale).rounded()))
        guard let cg = ImageRenderer.render(state: state, outputSize: CGSize(width: width, height: height))?.cgImageForRendering(),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            throw AgentError("render_failed", "Could not render preview.")
        }
        var result = summary(busy: false)
        result["preview"] = ["width": width, "height": height, "originX": bounds.minX,
            "originY": state.imageSize.height - bounds.maxY, "imagePixelsPerPreviewPixelX": bounds.width / CGFloat(width), "imagePixelsPerPreviewPixelY": bounds.height / CGFloat(height)]
        result["imagePNG"] = png.base64EncodedString()
        return result
    }
}
