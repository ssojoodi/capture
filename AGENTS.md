# Capture Project Memory

## Product Direction

Capture is a fast, minimal, native macOS image annotation app inspired by Skitch.

Persistent product constraints:

- User-facing app name: `Capture`.
- Native Swift + AppKit.
- Elegant light-mode UI.
- Fast and minimal over feature-rich.
- Core workflow: open or paste image, annotate quickly, crop if needed, copy flattened image or export PNG (or JPEG with an image-matched background).
- No editable project file format unless explicitly planned later.
- No screenshot capture feature unless explicitly planned later.

## Iteration Planning Convention

Each implementation iteration must have a dedicated planning document in `docs/`.

Filename format:

```text
YYYY-MM-DD-HH-MM-2-4-words-describing-iteration.md
```

Example:

```text
2026-06-26-09-52-wysiwyg-undo-redo.md
```

Each planning file should include:

- Summary
- Product behavior target
- Architecture changes
- UX acceptance criteria
- Automated test plan
- Manual verification plan
- Assumptions and non-goals

Older planning files remain as historical records. Do not overwrite prior iteration plans when planning a new iteration.

## Goal Structure for Iterations

When using the Goal feature for an implementation iteration, keep the objective consistent:

```text
Implement docs/<timestamped-plan-file>.md, creating focused tests and minimal meaningful commits for each milestone, then verify with xcrun xcodebuild and a screen capture artifact before marking the goal complete.
```

Expected goal milestones:

- Read the current timestamped plan.
- Implement the smallest coherent product slice from that plan.
- Add or update focused automated tests where behavior can be isolated.
- Run `xcrun xcodebuild -project Capture.xcodeproj -scheme Capture -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test`.
- Launch the built `Capture.app`.
- Capture a verification screenshot under `artifacts/verification/`.
- Commit the plan and implementation with short, meaningful commit messages.
- Confirm the working tree is clean before completing the goal.

## Current Architecture Notes

- Internals may still use `Capture` names for project/module targets.
- Product-facing naming should stay `Capture`.
- The canvas is AppKit/Core Graphics based.
- Annotation coordinates should remain in image space so zoom does not reduce export fidelity.
- Expensive rendering, especially blur, should be cached or applied only when needed.
- Prefer direct, understandable model changes over broad abstraction.

## MCP SDK Maintenance

- Read [MCP-SDK.md](MCP-SDK.md) before changing the MCP SDK, helper dependencies, or transport compatibility code.
- Production uses the pinned stdio-only SDK 0.12.1 in `Vendor/swift-sdk`, with its upstream license, provenance and exact source patch. Never depend on ignored `.build` experiments or modify SwiftPM checkout caches as a release strategy.
- The subset omits all HTTP transport types and handler context; both Client.swift and Server.swift patches must be reviewed on upgrades. Preserve stdio request handling and cancellation.
- When updating the subset, pin the upstream revision, preserve its license, and record the exact exclusions and small source patch. Review upstream protocol/security changes and prefer an upstream stdio-only product if available.
- SDK upgrades require MCP protocol/lifecycle and Codex discovery checks against the actual stripped helper, plus a fresh size comparison. Reassess the experimental-capabilities workaround when upstream changes. Update the maintenance document and lockfile together; do not leave a local subset permanently frozen.

## UX Principles

- Tools should feel immediate.
- Drag previews are transient. After mouse-up, the user should see the actual result, not a lingering construction rectangle.
- Copy/export should not be the first time an edit appears correct.
- Toolbar and keyboard shortcuts should expose common actions without adding inspector complexity.
- If behavior differs from Skitch, document why in the relevant iteration plan.

## Release Configuration

- Distribution builds target Apple Silicon (`arm64`) only. Optimize Release binaries for size, preserve matching dSYMs outside the app, and strip the isolated candidate before signing.

- Edit `Config/Version.xcconfig` for the date-based app version and integer build number.
- Do not supply release versions through environment variables or `release.env`.
- `make release` reads and verifies built bundle metadata, signs and notarizes an isolated local candidate, then writes the validated DMG, checksum, and release.json to `web-page/`.
- Keep `release.env` limited to local signing identity and notarization Keychain profile.
- Run `make check-release` when changing release orchestration. Website deployment is separate.

## Release Preparation

When asked to prepare a release:

1. Update `Config/Version.xcconfig`: use today's local date for the date-based app version and increment the integer build number.
2. Add a new entry at the top of `web-page/release-notes.html`, dated today, with succinct functional bullets covering the changes since the previous release. Move the latest-update marker to this entry and update the page's description, social descriptions, and structured-data description.
3. Include screenshots only when they help explain the changes. Reuse relevant screenshots in the release's dated folder when available; otherwise create them if justified. Preserve historical screenshots, use accurate alt text and dimensions, and optimize displayed images. Text-only release notes are acceptable.
4. Validate the version settings, release notes, local links, and relevant tests. Commit the preparation, push the feature branch, and create a pull request against the repository's default branch with a concise summary and actual validation results.

Release preparation does not itself package or deploy the app. Keep `release.json` and the DMG checksum paired with the existing binary until `make release` generates new artifacts. Signing, notarization, website deployment, and merging the pull request remain separate actions unless requested.
