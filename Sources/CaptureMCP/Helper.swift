import AppKit
import MCP
import CaptureAutomation

/// One persistent app connection, serialized even when the MCP client sends concurrent calls.
actor AppConnection {
    private var fd: Int32 = -1
    private let directory: String
    private let appURL: URL?
    private var startup: Task<Void, Error>?
    init(directory: String, appURL: URL? = nil) {
        self.directory = directory
        self.appURL = appURL
    }
    deinit { if fd >= 0 { Darwin.close(fd) } }
    func call(method: String, arguments: [String: Any]) async throws -> [String: Any] {
        if fd < 0 {
            if let appURL {
                if startup == nil {
                    // Invalid discovery-time probes must not open the app.
                    try AgentTools.validate(method, arguments: arguments)
                    startup = Task {
                        let workspace = NSWorkspace.shared
                        if workspace.runningApplications.contains(where: {
                            $0.bundleURL?.resolvingSymlinksInPath() == appURL
                        }) { return }
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.activates = false
                        let app = try await workspace.openApplication(at: appURL, configuration: configuration)
                        // Wait for the listener, not Launch Services' cached launch-completion flag.
                        // These probes send no commands, so edits can never be replayed.
                        let deadline = ContinuousClock.now + .seconds(10)
                        while !app.isTerminated && ContinuousClock.now < deadline {
                            if let probe = try? AgentWire.connect(to: self.directory) {
                                Darwin.close(probe)
                                return
                            }
                            if app.isFinishedLaunching { return } // Control may be disabled.
                            try await Task.sleep(for: .milliseconds(50))
                        }
                        guard !app.isTerminated else {
                            throw AgentError("connection_unavailable", "Capture quit while launching. Open it manually and restart the MCP connection.")
                        }
                        // A normal connection attempt below reports how to enable agent control.
                    }
                }
                try await startup!.value
            }
            // Other calls may have connected while this one awaited the shared startup.
            if fd < 0 { fd = try AgentWire.connect(to: directory) }
        }
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
            }
            let connection = AppConnection(directory: testDirectory ?? AgentWire.directory(for: appURL.path),
                                           appURL: testDirectory == nil ? appURL : nil)
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
