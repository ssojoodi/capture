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
- `Base/Transports/HTTPServer/StatefulHTTPServerTransport.swift`
- `Base/Transports/HTTPServer/StatelessHTTPServerTransport.swift`
- `Base/Transports/HTTPServer/HTTPRequestValidation.swift`

Keep HTTPServerTypes.swift: the server requires its shared context types. Do not remove it simply because its filename contains HTTP.

To refresh: obtain the recorded/new upstream revision, copy retained sources afresh, review and apply stdio-only.patch with `git apply --unidiff-zero`, then update this provenance and the root dependency lockfile. Do not modify SwiftPM checkout caches. Validate a clean build and the actual stripped helper as described in MCP-SDK.md.
