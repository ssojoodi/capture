# Capture stdio-only MCP SDK

Upstream: https://github.com/modelcontextprotocol/swift-sdk.git

Version: **0.12.1**

Revision: **a0ae212ebf6eab5f754c3129608bc5557637e605**

This is Capture's production SDK dependency. Source copyright notices and the complete upstream license (including its Apache-2.0/MIT transition notice) are preserved. See [MCP-SDK.md](../../MCP-SDK.md) for update requirements and validation.

The included Sources/MCP files are unchanged upstream files except for the removal recorded in `stdio-only.patch`. The custom Package.swift exposes only the MCP library and depends on swift-log and swift-system. Upstream tests, examples, conformance executables and documentation tooling are not vendored.

Omitted source paths (relative to Sources/MCP):

- `Base/Authorization/`
- `Base/Transports/HTTPClientTransport.swift`
- `Base/Transports/NetworkTransport.swift`
- `Base/Transports/InMemoryTransport.swift`
- `Base/Transports/HTTPServer/`

`Server.swift` removes the unused HTTP handler context, its task-local storage and the transport cast. Request handling and cancellation remain intact. The entire HTTPServer directory is omitted. Client.swift keeps initialization identity/capability types but omits the outbound client runtime. All Client.swift and Server.swift changes are recorded in `stdio-only.patch`.

To refresh: obtain the recorded/new upstream revision, copy retained sources afresh, review and apply stdio-only.patch with `git apply --unidiff-zero`, then update this provenance and the root dependency lockfile. Do not modify SwiftPM checkout caches. Validate a clean build and the actual stripped helper as described in MCP-SDK.md.

### Tools-only server reduction

Capture does not send MCP requests to clients. Sampling, elicitation, roots, protocol log notifications, outbound request continuations and their cancellation sender are omitted. Inbound request cancellation, framing, negotiation, error responses and generic request dispatch are retained. Initialization capability models remain for decoding client metadata. Unused prompts/completion models are also omitted. Capture-owned boundary tests live in `Vendor/swift-sdk/Tests/CaptureSDKTests`; run `swift test --package-path Vendor/swift-sdk --scratch-path .build/mcp-sdk-tests`.

Additional omitted source paths:

- `Client/Sampling.swift`
- `Client/Elicitation.swift`
- `Client/Roots.swift`
- `Server/Logging.swift`
- `Server/Prompts.swift`
- `Server/Completion.swift`
- `Base/PendingRequest.swift`
- `Base/Utilities/RequestContext.swift`

`Progress.swift` retains upstream Metadata/ProgressToken decoding, but omits the unused emitted progress notification.

### Initialization simplification

Client capabilities are retained as `[String: Value]`: Capture never calls them and must accept arbitrary experimental/future JSON. The obsolete CompatibleStdioTransport normalization wrapper is removed; the helper uses upstream StdioTransport directly. Root Package.swift no longer declares swift-log directly; the SDK still uses it for diagnostics. Test arbitrary capability preservation and real Codex initialization on upgrades.
