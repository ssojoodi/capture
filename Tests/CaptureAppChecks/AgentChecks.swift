import AppKit
import CaptureCore

extension WindowChecks {
    static func runAgentChecks() {
        let suite = "Capture.AgentControlChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let delegate = AppDelegate(agentDefaults: defaults, agentSocketIdentity: "/tmp/" + suite)
        let request: [String: Any] = ["method": "list_documents", "arguments": [:] as [String: Any]]
        precondition((delegate.handleAgentRequest(request)["error"] as? [String: String])?["code"] == "access_disabled")
        delegate.toggleAgentControl(nil)
        precondition(defaults.bool(forKey: "agentControl.enabled"))
        precondition(delegate.handleAgentRequest(request)["error"] == nil)
        delegate.toggleAgentControl(nil)
        precondition(!defaults.bool(forKey: "agentControl.enabled"))
        let state = AnnotationDocumentState()
        let cg = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.setFillColor(NSColor.systemBlue.cgColor); cg.fill(CGRect(x: 40, y: 40, width: 320, height: 220))
        state.load(image: NSImage(cgImage: cg.makeImage()!, size: CGSize(width: 400, height: 300)))
        let controller = MainWindowController(state: state)
        let document = controller.agentDocument
        let originalKey = NSApp.keyWindow
        func run(_ method: String, _ extra: [String: Any] = [:]) throws -> [String: Any] {
            var args: [String: Any] = ["documentID": document.id]
            if !["inspect_document", "preview_document"].contains(method) { args["revision"] = document.revision }
            args.merge(extra) { _, v in v }
            try AgentTools.validate(method, arguments: args)
            return try controller.agentPerform(method, arguments: args)
        }
        func fails(_ code: String, _ body: () throws -> Void) {
            let revision = document.revision
            do { try body(); preconditionFailure("Expected \(code)") }
            catch let error as AgentError { precondition(error.code == code, error.localizedDescription) }
            catch { preconditionFailure("Unexpected error: \(error)") }
            precondition(document.revision == revision, "Failed commands must not mutate history")
        }
        let box: [String: Any] = ["x": -30, "y": -20, "width": 130, "height": 70]
        let first = try! run("add_annotation", ["kind": "rectangle", "properties": ["bounds": box, "color": "#FF0000", "strokeWidth": 4]])
        let id = first["annotationID"] as! String
        precondition(state.annotations[0].bounds.minY == 250 && state.canvasBounds.minX < 0)
        let oldRevision = document.revision
        _ = try! run("update_annotation", ["annotationID": id, "properties": ["color": "#00FF00", "bounds": ["x": 15, "y": 30, "width": 90, "height": 40]]])
        let afterUpdate = document.revision
        fails("stale_revision") { _ = try controller.agentPerform("delete_annotation", arguments: ["documentID": document.id, "revision": oldRevision, "annotationID": id]) }
        _ = try! run("undo")
        precondition(document.revision != oldRevision && document.revision != afterUpdate)
        _ = try! run("redo")
        fails("invalid_properties") { _ = try run("update_annotation", ["annotationID": id, "properties": ["text": "wrong kind"]]) }
        fails("invalid_arguments") { _ = try run("add_annotation", ["kind": "rectangle", "properties": ["bounds": ["x": true, "y": 0, "width": 10, "height": 10]]]) }
        fails("invalid_properties") { _ = try run("add_annotation", ["kind": "arrow", "properties": ["start": ["x": 0, "y": 0]]]) }
        fails("limit_exceeded") { _ = try run("add_annotation", ["kind": "rectangle", "properties": ["bounds": ["x": -16000, "y": 0, "width": 16000, "height": 16000]]]) }
        _ = try! run("add_annotation", ["kind": "arrow", "properties": ["start": ["x": 50, "y": 20], "end": ["x": 220, "y": 100]]])
        _ = try! run("add_annotation", ["kind": "ellipse", "properties": ["bounds": ["x": 100, "y": 60, "width": 80, "height": 80]]])
        let text = try! run("add_annotation", ["kind": "text", "properties": ["bounds": ["x": 10, "y": 100, "width": 200, "height": 30], "text": "Capture MCP", "fontSize": 24, "backgroundColor": "#00000080"]])
        _ = try! run("update_annotation", ["annotationID": text["annotationID"]!, "properties": ["text": "Agent edit", "fontSize": 32]])
        let count = state.annotations.count
        _ = try! run("blur_region", ["bounds": ["x": 0, "y": 0, "width": 80, "height": 80]])
        precondition(state.annotations.count == count)
        let blurred = NSBitmapImageRep(cgImage: state.baseCGImage!)
        precondition(blurred.colorAt(x: 0, y: 0)!.alphaComponent < 0.01)
        let pasteboard = NSPasteboard.withUniqueName()
        let copyDocument = AgentDocument(state: state, pasteboard: pasteboard)
        _ = try! copyDocument.perform("copy_image", ["revision": copyDocument.revision])
        precondition(pasteboard.data(forType: .png) != nil)
        pasteboard.releaseGlobally()
        let preview = try! run("preview_document")
        let data = Data(base64Encoded: preview["imagePNG"] as! String)!
        let png = NSBitmapImageRep(data: data)!
        precondition(png.pixelsWide == Int(state.canvasBounds.width))
        let verification = URL(fileURLWithPath: "artifacts/verification")
        try! FileManager.default.createDirectory(at: verification, withIntermediateDirectories: true)
        try! data.write(to: verification.appendingPathComponent("capture-mcp-preview.png"))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("capture-agent-test-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        for ext in ["png", "jpg"] {
            let path = temp.appendingPathComponent("output." + ext).path
            _ = try! run("export_image", ["path": path])
            precondition(FileManager.default.fileExists(atPath: path))
            fails("file_exists") { _ = try run("export_image", ["path": path]) }
            _ = try! run("export_image", ["path": path, "overwrite": true])
        }
        fails("invalid_format") { _ = try run("export_image", ["path": temp.appendingPathComponent("x.gif").path]) }
        _ = try! run("crop_document", ["bounds": ["x": 20, "y": 20, "width": 200, "height": 180]])
        precondition(state.annotations.isEmpty && state.imageSize == CGSize(width: 200, height: 180))
        _ = try! run("undo"); precondition(state.annotations.count == count)
        _ = try! run("delete_annotation", ["annotationID": id]); precondition(state.annotation(with: UUID(uuidString: id)) == nil)
        _ = try! run("undo"); precondition(state.annotation(with: UUID(uuidString: id)) != nil)
        // User edits generate fresh revisions, and live drags block reads/edits.
        let beforeUser = document.revision
        state.addAnnotation(RectangleAnnotation(bounds: CGRect(x: 0, y: 0, width: 20, height: 20)))
        precondition(document.revision != beforeUser)
        let view = canvas(in: controller.window!)
        state.selectedTool = .rectangle; view.toolDidChange()
        let point = view.convert(CGPoint(x: 120, y: 120), to: nil)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: controller.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        view.mouseDown(with: down)
        precondition(controller.agentBusy)
        fails("document_busy") { _ = try run("inspect_document") }
        view.cancelInteraction()
        precondition(!controller.agentBusy && NSApp.keyWindow === originalKey)
        controller.window?.orderOut(nil)
        print("PASS: agent commands, coordinates, annotation types, revisions, undo/redo, errors, blur alpha, crop, export, busy/focus and preview artifact")
    }
}
