# MCP SDK maintenance

Capture uses the official Swift MCP SDK for its local stdio helper. Keep protocol handling upstream; do not replace it with a custom JSON-RPC implementation to save space.

## Status and upstream baseline

Capture uses the pinned stdio-only SDK in `Vendor/swift-sdk` as its production dependency. Root `Package.swift` references that tracked local package. Its upstream license and exact source patch are stored alongside the source. Release bundles include the SDK license. The earlier `.build/stdio-experiment` directory is disposable and is not used by production builds.

- Upstream: `https://github.com/modelcontextprotocol/swift-sdk.git`
- Tested version: `0.12.1`
- Tested revision: `a0ae212ebf6eab5f754c3129608bc5557637e605`
- Retained MCP source: 15 Swift files; exact counts vary with the recorded patch.
- Required dependencies: `swift-log` and `swift-system`.
- EventSource is unnecessary for the subset. NIO is not linked into Capture's existing helper; its appearance in dependency resolution does not imply shipped code.

## Exact subset changes

Keep the upstream `Sources/MCP` files except these paths:

```text
Base/Authorization/
Base/Transports/HTTPClientTransport.swift
Base/Transports/NetworkTransport.swift
Base/Transports/InMemoryTransport.swift
Base/Transports/HTTPServer/
Base/PendingRequest.swift
Base/UnitInterval.swift
Base/Utilities/RequestContext.swift
Client/Sampling.swift
Client/Elicitation.swift
Client/Roots.swift
Server/Logging.swift
Server/Prompts.swift
Server/Completion.swift
Server/Resources.swift
Extensions/Data+Extensions.swift
```

All edits to retained upstream files are recorded in `Vendor/swift-sdk/stdio-only.patch` (apply with `git apply --unidiff-zero`). The patch removes outbound/client features, unused server capabilities and content types, URL elicitation errors and automatic data-URL conversion. Client capabilities accept arbitrary JSON. The helper uses upstream StdioTransport directly; no normalization wrapper remains.

The vendored manifest exposes the MCP library with Logging, SystemPackage and upstream StrictConcurrency. A Capture-owned test target checks the retained protocol boundary. Upstream documentation plugins, examples, conformance executables, EventSource and NIO dependencies are omitted.

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
3. Refresh from the new upstream source. Reapply exclusions and the recorded source changes only where still required. Review changed context types and new cross-references; do not blindly replay or broaden the patch to make compilation pass.
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

## HTTP context removal (October 31, 2026)

Removed HTTPServerTypes.swift and the unused HandlerContext/task-local plumbing from Server.swift. Handler tasks still retain the upstream cancellation and error-handling behavior. There are no HTTP transport/context types left in the retained source; icon URL documentation still mentions HTTP because URLs are valid protocol data.

The stripped arm64 -Osize helper measures 1,697,688 bytes (about 25 KB less than the previous production subset). A fresh helper build, MCP protocol/lifecycle checks and installed Codex discovery of all 13 tools passed. Both recorded source patches reverse and reapply cleanly. Release artifacts must be rebuilt after this change; existing packaged metadata was not modified by this cleanup.

## In-memory transport removal (October 31, 2026)

Removed the unreferenced InMemoryTransport.swift; no extra source patch was required. StdioTransport is now the only retained concrete transport. Release build, full MCP protocol/lifecycle checks and installed Codex discovery passed. The stripped arm64 -Osize helper measures 1,677,464 bytes, saving a further 20,224 bytes compared with the HTTP-context cleanup. Rebuild release artifacts before shipping.

## Outbound client removal (October 31, 2026)

Removed the unused client runtime, retaining handshake types and capability decoders. Protocol checks now initialize with sampling, elicitation, roots and nested experimental capabilities. The stripped arm64 -Osize helper measures 1,518,704 bytes, down from 1,677,464. Full protocol/lifecycle checks and installed Codex discovery passed.

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

The tools-only server stage passed the new direct cancellation/error tests, full stripped-helper protocol/lifecycle checks and actual Codex discovery. Its stripped arm64 -Osize helper is 1,127,328 bytes, down from 1,518,704.

### Initialization simplification

Client capabilities are retained as `[String: Value]`: Capture never calls them and must accept arbitrary experimental/future JSON. The obsolete CompatibleStdioTransport normalization wrapper is removed; the helper uses upstream StdioTransport directly. Root Package.swift no longer declares swift-log directly; the SDK still uses it for diagnostics. Test arbitrary capability preservation and real Codex initialization on upgrades.

The initialization simplification passed three SDK boundary tests (including exact arbitrary capability preservation), full stripped-helper protocol/lifecycle tests and installed Codex discovery. The stripped helper is 1,078,576 bytes. Only the SDK, not the Capture helper, directly depends on Logging now.

### Capture tool output subset

`Tools.swift` retains text, image and structured tool results, tool safety annotations, and request/result metadata. Unused audio, embedded-resource and resource-link content models and tool-list-change notifications are omitted. Capture advertises a fixed tools list and never returns those content types. `Server.swift` retains only the advertised tools capability; unused initialization hooks and write-only client state are omitted.

Additional omitted paths are `Server/Resources.swift` and `Base/UnitInterval.swift`. The latter was needed only by the removed sampling/resource models. The source patch records all edits to retained files. Boundary tests verify text/image wire formats, structured results, safety hints and arbitrary request metadata alongside cancellation and initialization.

This stage passed all four SDK boundary tests, full stripped-helper protocol/lifecycle checks and installed Codex discovery. The stripped arm64 helper measures 927,312 bytes, down from 1,078,576.

### Elicitation error removal

`Error.swift` omits URLElicitationInfo and the URL-elicitation-specific error case. Capture never initiates this interaction. Incoming code -32042 falls through to the existing generic server-error decoder; standard JSON-RPC and transport errors are unchanged. Five SDK tests, full protocol/lifecycle checks and Codex discovery passed. The stripped helper measures 908,400 bytes.

### JSON string preservation

`Value.swift` omits its special binary-data case and automatic data-URL parsing. Capture uses ordinary JSON values and the dedicated image content field; literal data URLs in text arguments now remain unchanged. `Extensions/Data+Extensions.swift` and its RegexBuilder import are omitted. Six SDK boundary tests, full protocol/lifecycle checks and Codex discovery passed. The stripped helper measures 883,504 bytes.

## Stopping point for this reduction

The remaining 15 source files serve the supported path:

- `Server.swift`, `Messages.swift`, `ID.swift`, `Error.swift`: request dispatch, response/error encoding, batching and cancellation tracking.
- `Lifecycle.swift`, `Versioning.swift`, `Client.swift`, `Icon.swift`: standard initialization and client identity metadata, including future capabilities.
- `Tools.swift`, `Value.swift`, `Utilities/Progress.swift`: tool schemas/results and arbitrary JSON/request metadata. Progress notifications are omitted, but incoming metadata remains decodable.
- `Utilities/Cancellation.swift`, `Utilities/Ping.swift`: client cancellation and connection health checks.
- `Transport.swift`, `Transports/StdioTransport.swift`: upstream framing, partial I/O, EOF and nonblocking descriptor handling.

Keep swift-system for FileDescriptor/Errno and swift-log for upstream diagnostics. Neither is an HTTP dependency. Keep shared Codable/conformance helpers and older-version batch handling: removing individual convenience methods or replacing generic dispatch would expand the fork for little benefit. Capture's app-side automation validates permissions, document revisions and mutations and is not duplicated MCP transport code. Future functional changes may change this boundary; review actual usage before retaining or deleting code.

## Final progressive-cleanup verification (October 31, 2026)

The final retained SDK has 15 Swift source files and 2,723 lines. All six focused SDK tests, 41 Xcode core tests, native window checks and release-workflow/publication checks passed. The actual Xcode Release-bundle helper passed full protocol/lifecycle and installed Codex discovery checks (13 tools). An isolated stripped, ad-hoc-signed Release app launched successfully. Native verification images were regenerated under `artifacts/verification/`; `text-background-committed.png` was visually reviewed.

The exact source patch reverses every retained file to the recorded upstream baseline and reapplies byte-for-byte. Unstripped production symbols contain none of the removed HTTP/network/in-memory transports, EventSource, URL elicitation model or compatibility wrapper. The app, framework and helper are arm64-only, all dSYM UUIDs match, and the upstream license is bundled.

| Comparable local test artifact | Before progressive cleanup | Final |
|---|---:|---:|
| Stripped arm64 helper | 1,677,464 bytes | 883,504 bytes |
| Entire stripped app, including license | 2,829,251 bytes (initial subset adoption) | 1,981,621 bytes |

The helper is 47.3% smaller than the start of this cleanup. Bundle/signature sizes can vary slightly with distribution signing. All cleanup code and maintenance changes are committed; the pre-existing user-built `web-page/release.json` and `web-page/Capture.dmg.sha256` modifications are intentionally excluded. Rebuild with `make release` before shipping these changes. This verification does not notarize, publish, push, merge or deploy a release.
