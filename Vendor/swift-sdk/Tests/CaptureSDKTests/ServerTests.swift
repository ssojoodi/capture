// Capture-owned regression tests for the supported server boundary; not upstream SDK source.
import Foundation
import Logging
import MCP
import Testing

private actor TestTransport: Transport {
    nonisolated let logger = Logger(label: "capture.sdk.tests", factory: { _ in SwiftLogNoOpLogHandler() })
    private let incoming = AsyncThrowingStream<Data, Error>.makeStream()
    nonisolated let outgoing = AsyncStream<Data>.makeStream()
    func connect() async throws {}
    func disconnect() async { incoming.continuation.finish(); outgoing.continuation.finish() }
    func send(_ data: Data) async throws { outgoing.continuation.yield(data) }
    func receive() -> AsyncThrowingStream<Data, Error> { incoming.stream }
    func inject(_ json: String) { incoming.continuation.yield(Data(json.utf8)) }
}

private enum TestFailure: Error { case timeout, disconnected }
private func reply(_ transport: TestTransport) async throws -> [String: Any] {
    let data = try await withThrowingTaskGroup(of: Data.self) { group in
        group.addTask {
            for await data in transport.outgoing.stream { return data }
            throw TestFailure.disconnected
        }
        group.addTask { try await Task.sleep(for: .seconds(5)); throw TestFailure.timeout }
        defer { group.cancelAll() }
        return try await group.next()!
    }
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

private actor HandlerState {
    var started = false
    var cancelled = false
    func start() { started = true }
    func cancel() { cancelled = true }
}
private enum Slow: MCP.Method {
    static let name = "test/slow"
    typealias Parameters = Empty
    typealias Result = Empty
}
private func waitFor(_ predicate: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !(await predicate()) {
        guard ContinuousClock.now < deadline else { throw TestFailure.timeout }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@Test func cancellationStopsHandlerAndKeepsServerResponsive() async throws {
    let server = Server(name: "Capture tests", version: "1", capabilities: .init(tools: .init()))
    let transport = TestTransport()
    let state = HandlerState()
    await server.withMethodHandler(Slow.self) { _ in
        await state.start()
        do { try await Task.sleep(for: .seconds(60)); return Empty() }
        catch { await state.cancel(); throw error }
    }
    try await server.start(transport: transport)
    await transport.inject(#"{"jsonrpc":"2.0","id":1,"method":"test/slow","params":{}}"#)
    try await waitFor { await state.started }
    await transport.inject(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1,"reason":"test"}}"#)
    try await waitFor { await state.cancelled }
    // Unknown cancellations and unsolicited responses must not break subsequent requests.
    await transport.inject(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":999}}"#)
    await transport.inject(#"{"jsonrpc":"2.0","id":999,"result":{}}"#)
    await transport.inject(#"{"jsonrpc":"2.0","id":2,"method":"ping","params":{}}"#)
    let result = try await reply(transport)
    #expect(result["id"] as? Int == 2) // No response is emitted for the cancelled request.
    #expect(result["result"] != nil)
    await server.stop()
}

@Test func unsupportedMethodsAndMalformedInputPreserveErrors() async throws {
    let server = Server(name: "Capture tests", version: "1", capabilities: .init(tools: .init()))
    let transport = TestTransport()
    try await server.start(transport: transport)
    for method in ["prompts/list", "resources/list", "completion/complete", "logging/setLevel"] {
        await transport.inject("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"\(method)\",\"params\":{}}")
        let result = try await reply(transport)
        #expect((result["error"] as? [String: Any])?["code"] as? Int == -32601)
    }
    await transport.inject("not JSON")
    let error = try await reply(transport)
    #expect((error["error"] as? [String: Any])?["code"] as? Int == -32700)
    await server.stop()
}

@Test func initializationPreservesArbitraryCapabilities() throws {
    let json = #"{"protocolVersion":"2025-06-18","clientInfo":{"name":"Codex","version":"1"},"capabilities":{"experimental":{"codex/state":{"enabled":true,"values":[1,null,"x"]}},"sampling":{"tools":{},"context":{}},"elicitation":{"form":{},"url":{}},"roots":{"listChanged":true},"future":{"nested":[false]}}}"#
    let parameters = try JSONDecoder().decode(Initialize.Parameters.self, from: Data(json.utf8))
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    let expected = try JSONDecoder().decode([String: Value].self, from: JSONSerialization.data(withJSONObject: object["capabilities"]!))
    #expect(parameters.capabilities == expected)
}

@Test func toolWireFormatPreservesCaptureOutputsAndMetadata() throws {
    let json = #"{"content":[{"type":"text","text":"done","_meta":{"source":"Capture"}},{"type":"image","data":"cG5n","mimeType":"image/png"}],"structuredContent":{"revision":2},"isError":false}"#
    let result = try JSONDecoder().decode(CallTool.Result.self, from: Data(json.utf8))
    let encoded = try JSONEncoder().encode(result)
    #expect(try JSONDecoder().decode(Value.self, from: encoded) == JSONDecoder().decode(Value.self, from: Data(json.utf8)))
    let toolJSON = #"{"name":"preview","description":"Preview","inputSchema":{},"annotations":{"readOnlyHint":true,"destructiveHint":false}}"#
    let tool = try JSONDecoder().decode(Tool.self, from: Data(toolJSON.utf8))
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tool)) as! [String: Any]
    let hints = object["annotations"] as! [String: Any]
    #expect(hints["readOnlyHint"] as? Bool == true)
    #expect(hints["destructiveHint"] as? Bool == false)
    let request = #"{"name":"preview","_meta":{"progressToken":"request-1","custom":{"enabled":true}}}"#
    let parameters = try JSONDecoder().decode(CallTool.Parameters.self, from: Data(request.utf8))
    #expect(try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(parameters)) == JSONDecoder().decode(Value.self, from: Data(request.utf8)))
}

@Test func unusedElicitationErrorDecodesAsGenericServerError() throws {
    let json = #"{"code":-32042,"message":"External input required","data":{"elicitations":[]}}"#
    let error = try JSONDecoder().decode(MCPError.self, from: Data(json.utf8))
    #expect(error == .serverError(code: -32042, message: "External input required"))
    #expect(error.code == -32042)
}
