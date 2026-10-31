# MCP SDK maintenance

Capture uses the official Swift MCP SDK for its local stdio helper. Keep protocol handling upstream; do not replace it with a custom JSON-RPC implementation to save space.

## Status and upstream baseline

Capture uses the pinned stdio-only SDK in `Vendor/swift-sdk` as its production dependency. Root `Package.swift` references that tracked local package. Its upstream license and exact source patch are stored alongside the source. Release bundles include the SDK license. The earlier `.build/stdio-experiment` directory is disposable and is not used by production builds.

- Upstream: `https://github.com/modelcontextprotocol/swift-sdk.git`
- Tested version: `0.12.1`
- Tested revision: `a0ae212ebf6eab5f754c3129608bc5557637e605`
- Retained MCP source: 28 Swift files, 7,338 lines, 278,906 bytes, including comments.
- Required dependencies: `swift-log` and `swift-system`.
- EventSource is unnecessary for the subset. NIO is not linked into Capture's existing helper; its appearance in dependency resolution does not imply shipped code.

## Exact subset changes

Keep the upstream `Sources/MCP` files except these paths:

```text
Base/Authorization/
Base/Transports/HTTPClientTransport.swift
Base/Transports/NetworkTransport.swift
Base/Transports/HTTPServer/StatefulHTTPServerTransport.swift
Base/Transports/HTTPServer/StatelessHTTPServerTransport.swift
Base/Transports/HTTPServer/HTTPRequestValidation.swift
```

Retain `Base/Transports/HTTPServer/HTTPServerTypes.swift`. The server uses its `HTTPRequest` and `HTTPContextProviding` types even with stdio. These shared types do not enable an HTTP transport.

In `Sources/MCP/Client/Client.swift`, retain the Capture modification notice and remove only this HTTP-specific hook from initialization:

```swift
// For HTTP transport, ensure subsequent MCP-Protocol-Version headers
// reflect the negotiated lifecycle version.
if let httpTransport = connection as? HTTPClientTransport {
    await httpTransport.updateNegotiatedProtocolVersion(result.protocolVersion)
}
```

The vendored SDK manifest exposes only the `MCP` library target, with Logging and SystemPackage dependencies and upstream StrictConcurrency enabled. Omit EventSource, documentation plugins, conformance executables and their NIO dependencies from that subset manifest. Keep client protocol types and other shared sources unless separately verified unnecessary.

Capture's `CompatibleStdioTransport` is a separate compatibility workaround: version 0.12.1 incorrectly constrains experimental capabilities to string values. Review whether upstream fixes this before carrying the workaround into another SDK version.

## Integration requirements

Preserve these properties when maintaining the production subset:

1. Keep the tracked vendor directory with upstream license and copyright notices. Do not reference `.build` or patch SwiftPM checkout caches during ordinary builds.
2. Record the upstream tag, full commit, exact exclusions and source patch alongside the subset. Preserve upstream source unchanged except for documented changes.
3. Update `Package.swift` and regenerate `Package.resolved` as applicable. Verify a clean checkout builds without the experiment directory.
4. Run the validation below against the actual bundled helper and update this document when paths or architecture change.

## Updating upstream

Review upstream changes when upgrading dependencies, investigating MCP compatibility, or responding to an upstream security fix. A local subset must not silently freeze the SDK forever.

1. Read upstream release notes and compare the pinned revision with the intended version. Check protocol, stdio framing, cancellation, lifecycle, capability decoding and security changes.
2. First check whether upstream now provides a supported stdio-only product. Prefer that over retaining our patch.
3. Refresh from the new upstream source. Reapply exclusions and the hook removal only where still required. Review changed context types and new cross-references; do not blindly replay or broaden the patch to make compilation pass.
4. Preserve upstream licenses. Update the recorded tag/revision, patch, manifest and dependency lockfile together.
5. Run validation and record actual results and stripped sizes in the PR. If a check fails, resolve it before shipping the update.

## Validation

- Build the Release helper for `arm64` with `-Osize`. Measure after the same symbol stripping used by release packaging. Do not compare a Debug or universal binary against a stripped arm64 binary.
- Run `scripts/check_mcp.py <candidate-helper> <compiled-AgentFixture>` for initialize/list/call, all tool operations, exports, invalid requests, stale/busy errors, multiple clients, opt-in changes and socket cleanup. It also checks passive discovery, concurrent first-call launch, reuse and explicit quit.
- Run `python3 scripts/check_codex_mcp.py <candidate-helper>` to verify installed Codex connects and discovers all 13 tools using temporary configuration.
- Run native window checks separately from other app-launch tests to avoid focus conflicts. Run core Xcode tests and `make check-release` when integrating the subset into release packaging.
- Verify app, framework and helper architectures and matching dSYMs. Test the stripped helper, not only the unstripped compiler output.
- Confirm excluded transport code and EventSource are absent using the unstripped candidate's symbols or a linker map. Symbol absence in an already stripped binary alone is not proof.

## Measured experiment

| Stripped arm64 helper | Bytes |
|---|---:|
| Full SDK, `-Osize` | 2,268,904 |
| Stdio subset, `-Osize` | 1,723,016 |
| Saving | 545,888 |

The saving is 24.1% of the helper and about 16.3% of the optimized app bundle. Estimated total app size falls from 3.36 MB to 2.81 MB; no subset DMG was packaged. Full MCP protocol/lifecycle checks and installed Codex discovery passed. HTTP transport, OAuth and EventSource symbols were absent from the unstripped subset helper.

## Production adoption validation (October 29, 2026)

A fresh SwiftPM scratch directory built the production local dependency without referencing the experiment. The actual Xcode Release bundle built successfully; its stripped helper measured 1,723,000 bytes and its ad-hoc-signed test bundle measured 2,829,251 bytes, including the upstream license. Final distribution signing may change these figures slightly.

All 41 core tests and release-workflow checks passed. MCP tools and lifecycle checks passed on isolated retry after a temporary fixture-readiness error. Installed Codex connected and discovered all 13 tools. All three dSYM UUIDs matched their production binaries. The documented patch reverses cleanly; retained source changes are confined to Client.swift. Package.resolved contains only swift-log and swift-system. No signed/notarized release DMG was published during adoption.
