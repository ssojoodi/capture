import Foundation

public enum AgentTools {
    // Immutable JSON schemas, shared by concurrent helper and app requests.
    nonisolated(unsafe) public static let definitions: [[String: Any]] = {
        let string: [String: Any] = ["type": "string"]
        let number: [String: Any] = ["type": "number"]
        let point: [String: Any] = object(["x": number, "y": number], required: ["x", "y"])
        let rect = object(["x": number, "y": number, "width": number, "height": number], required: ["x", "y", "width", "height"])
        let properties: [String: Any] = ["points": ["type": "array", "items": point, "minItems": 1, "maxItems": 10000], "bounds": rect, "start": point, "end": point,
            "color": ["type": "string", "description": "sRGB #RRGGBB or #RRGGBBAA"], "strokeWidth": number,
            "text": string, "fontSize": number, "backgroundColor": string]
        let doc = ["documentID": string]
        let revision = doc.merging(["revision": string]) { _, v in v }
        func tool(_ name: String, _ description: String, _ props: [String: Any], _ required: [String]) -> [String: Any] {
            ["name": name, "description": description, "inputSchema": object(props, required: required)]
        }
        return [
            tool("list_documents", "List open documents, IDs, revisions and busy state. Agent control must be enabled.", [:], []),
            tool("open_image", "Open an absolute local image path in a new visible document. Does not replace existing documents.", ["path": string], ["path"]),
            tool("inspect_document", "Get annotation IDs/properties, dimensions and revision. Coordinates are pixels from original image top-left, positive Y down; annotations may extend outside the image.", doc, ["documentID"]),
            tool("preview_document", "Get flattened PNG (max1600 pixels, no upscaling), revision and coordinate mapping. Inspect before editing; a crop flattens and resets the image origin.", doc, ["documentID"]),
            tool("add_annotation", "Add arrow, rectangle, ellipse, highlighter or text. Highlighter requires points (1–10000), uses strokeWidth (default48), yellow colour and fixed35% opacity. Arrow requires start/end; other kinds require bounds; text requires text. Defaults: soft red, stroke16, font52, half-opaque black text background. One undo step.", revision.merging(["kind": ["type": "string", "enum": ["arrow", "rectangle", "ellipse", "highlighter", "text"]], "properties": object(properties, required: [])]) { _, v in v }, ["documentID", "revision", "kind", "properties"]),
            tool("update_annotation", "Change an annotation by ID. Only fields supported by its kind are accepted. Use arrow start/end to move or resize arrows. Text boxes expand vertically to fit text. One undo step.", revision.merging(["annotationID": string, "properties": object(properties, required: [])]) { _, v in v }, ["documentID", "revision", "annotationID", "properties"]),
            tool("delete_annotation", "Delete an annotation by ID. One undo step.", revision.merging(["annotationID": string]) { _, v in v }, ["documentID", "revision", "annotationID"]),
            tool("blur_region", "Blur base-image pixels inside bounds, clipped to the original image. Radius defaults to16. Not a movable annotation; undo restores pixels.", revision.merging(["bounds": rect, "radius": number]) { _, v in v }, ["documentID", "revision", "bounds"]),
            tool("crop_document", "Crop within original image bounds. Flattens visible annotations into pixels and clears editable annotations. Undo restores them. Coordinates reset to the cropped image.", revision.merging(["bounds": rect]) { _, v in v }, ["documentID", "revision", "bounds"]),
            tool("undo", "Undo the last user or agent edit in this document. Returns a fresh revision.", revision, ["documentID", "revision"]),
            tool("redo", "Redo the last undone edit. Returns a fresh revision.", revision, ["documentID", "revision"]),
            tool("export_image", "Export a flattened PNG or JPEG to an absolute local path. Extension selects format. overwrite defaults false. Does not change the document's source file or saved state.", revision.merging(["path": string, "overwrite": ["type": "boolean"]]) { _, v in v }, ["documentID", "revision", "path"]),
            tool("copy_image", "Copy the full flattened PNG to the system clipboard; does not read the clipboard.", revision, ["documentID", "revision"])
        ]
    }()
    private static func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }
    /// Validate the same schema at the app boundary, not only in the MCP client.
    public static func validate(_ method: String, arguments: [String: Any]) throws {
        guard let tool = definitions.first(where: { $0["name"] as? String == method }), let schema = tool["inputSchema"] as? [String: Any] else {
            throw AgentError("unknown_tool", "Unknown tool: \(method)")
        }
        try validateValue(arguments, schema: schema, path: method)
    }
    private static func validateValue(_ value: Any, schema: [String: Any], path: String) throws {
        func invalid() -> AgentError { AgentError("invalid_arguments", "Invalid or unexpected value at \(path).") }
        switch schema["type"] as? String {
        case "object":
            guard let obj = value as? [String: Any], let props = schema["properties"] as? [String: Any] else { throw invalid() }
            guard Set(obj.keys).isSubset(of: Set(props.keys)), (schema["required"] as? [String] ?? []).allSatisfy({ obj[$0] != nil }) else { throw invalid() }
            for (key, v) in obj { try validateValue(v, schema: props[key] as! [String: Any], path: path + "." + key) }
        case "array":
            guard let values = value as? [Any], let items = schema["items"] as? [String: Any],
                  values.count >= (schema["minItems"] as? Int ?? 0),
                  values.count <= (schema["maxItems"] as? Int ?? 10000) else { throw invalid() }
            for (index, item) in values.enumerated() { try validateValue(item, schema: items, path: path + "[\(index)]") }
        case "string":
            guard let str = value as? String, str.utf8.count <= 65536 else { throw invalid() }
            if let values = schema["enum"] as? [String], !values.contains(str) { throw invalid() }
        case "number":
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { throw invalid() }
        case "boolean":
            guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw invalid() }
        default: throw invalid()
        }
    }
}
import CoreFoundation
