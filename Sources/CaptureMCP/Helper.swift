import AppKit
import MCP
import CaptureAutomation

/// One persistent app connection, serialized even when the MCP client sends concurrent calls.
actor AppConnection {
    private var fd: Int32 = -1
    private let directory: String
    init(directory: String) { self.directory = directory }
    deinit { if fd >= 0 { Darwin.close(fd) } }
    func call(method: String, arguments: [String: Any]) throws -> [String: Any] {
        if fd < 0 { fd = try AgentWire.connect(to: directory) }
        do {
            try AgentWire.write(["method": method, "arguments": arguments], to: fd, limit: AgentWire.requestLimit)
            return try AgentWire.read(fd, limit: AgentWire.responseLimit)
        } catch {
            Darwin.close(fd); fd = -1
            // A lost response may follow a committed edit. Never retry automatically.
            throw error
        }
    }
}

@main
struct CaptureMCP {
    static func main() async {
        do {
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            let appURL = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            // Test harness can connect to its own app fixture without launching another process.
            let testDirectory = ProcessInfo.processInfo.environment["CAPTURE_MCP_TEST_SOCKET_DIRECTORY"]
            if testDirectory == nil {
                guard appURL.pathExtension == "app" else { throw AgentError("invalid_installation", "Run the helper bundled in Capture.app.") }
                let running = NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.resolvingSymlinksInPath() == appURL }
                if !running {
                    let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
                    _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
                }
            }
            let connection = AppConnection(directory: testDirectory ?? AgentWire.directory(for: appURL.path))
            let server = Server(name: "Capture", version: "1.0.0", capabilities: .init(tools: .init(listChanged: false)))
            await server.withMethodHandler(ListTools.self) { _ in
                let tools = try AgentTools.definitions.map { definition -> Tool in
                    let schema = try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: definition["inputSchema"]!))
                    let name = definition["name"] as! String
                    let readOnly = ["list_documents", "inspect_document", "preview_document"].contains(name)
                    return Tool(name: name, description: (definition["description"] as! String), inputSchema: schema,
                        annotations: .init(readOnlyHint: readOnly, destructiveHint: !readOnly && !["open_image", "add_annotation"].contains(name),
                                           idempotentHint: readOnly, openWorldHint: false))
                }
                return .init(tools: tools)
            }
            await server.withMethodHandler(CallTool.self) { params in
                do {
                    let arguments = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params.arguments ?? [:])) as! [String: Any]
                    try AgentTools.validate(params.name, arguments: arguments)
                    var result = try await connection.call(method: params.name, arguments: arguments)
                    let png = result.removeValue(forKey: "imagePNG") as? String
                    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                    var content: [Tool.Content] = [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)]
                    if let png { content.append(.image(data: png, mimeType: "image/png", annotations: nil, _meta: nil)) }
                    return try .init(content: content, structuredContent: try JSONDecoder().decode(Value.self, from: data), isError: result["error"] != nil)
                } catch {
                    let error = (error as? AgentError) ?? AgentError("operation_failed", error.localizedDescription)
                    let text = String(decoding: try JSONSerialization.data(withJSONObject: error.response), as: UTF8.self)
                    return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
                }
            }
            try await server.start(transport: CompatibleStdioTransport())
            await server.waitUntilCompleted()
        } catch {
            FileHandle.standardError.write(Data(("Capture MCP: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
