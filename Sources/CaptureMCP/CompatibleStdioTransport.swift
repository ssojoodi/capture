import Foundation
import MCP
import Logging

/// MCP permits arbitrary JSON in experimental capabilities. SDK 0.12.1 decodes
/// them as [String: String], so clients such as Codex can fail initialization.
/// Capture negotiates no experimental features: omit only that unused field
/// before SDK decoding, leaving standard capabilities and all other messages intact.
actor CompatibleStdioTransport: Transport {
    private let base = StdioTransport()
    nonisolated let logger = Logger(label: "capture.mcp", factory: { _ in SwiftLogNoOpLogHandler() })
    func connect() async throws { try await base.connect() }
    func disconnect() async { await base.disconnect() }
    func send(_ data: Data) async throws { try await base.send(data) }
    func receive() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await data in await base.receive() {
                        continuation.yield(Self.normalizeInitialization(data))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    private static func normalizeInitialization(_ data: Data) -> Data {
        guard var message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              message["method"] as? String == "initialize",
              var params = message["params"] as? [String: Any],
              var capabilities = params["capabilities"] as? [String: Any],
              capabilities.removeValue(forKey: "experimental") != nil else { return data }
        params["capabilities"] = capabilities
        message["params"] = params
        return (try? JSONSerialization.data(withJSONObject: message)) ?? data
    }
}
