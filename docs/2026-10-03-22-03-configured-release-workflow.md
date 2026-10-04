# Configured release workflow

## Summary
Adapt Retriever's checked-in version configuration and verified local release workflow. Refresh Capture's website sharing metadata and release imagery.

## Product behavior target
Config/Version.xcconfig is the single source for version 2026.10.3 and build 2. The built bundle determines DMG naming and release metadata. release.env contains signing identity and Keychain profile only; no version environment variable is required. Website previews accurately show this release.

## Architecture changes
Attach Version.xcconfig to both Xcode project configurations and remove duplicated app-target values. Replace Makefile release orchestration with a Python driver adapted from ~/workspace/retriever-app: isolated staging, explicit nested signing, accepted notarization, validation, checksums, local backup/replacement, and preserved symbols. Keep Capture's existing DMG layout and date-based versions. Build all standard macOS architectures with ONLY_ACTIVE_ARCH=NO and verify app/framework agreement.

## UX acceptance criteria
make release needs no VERSION input. Failed signing/notarization/verification preserves the previous download. Both website pages use absolute canonical and social image URLs, current descriptions, real image dimensions, and descriptive alt text. Historical release images remain unchanged. No website upload or branch push.

## Automated test plan
Verify effective Xcode settings and built bundle metadata. Adapt Retriever's release-orchestration and publication failure tests; test missing candidate and rejected notarization. Validate HTML metadata and local image references, and run the full Xcode suite and AppKit checks after configuration changes.

## Manual verification plan
Inspect the current public-safe app screenshot, add it under web-page/releases/2026-10-03/, and inspect its use in release notes. Build, sign, notarize, and validate a local DMG using existing accounts if available. Verify version/build, architectures, checksum, and app size.

## Assumptions and non-goals
Retriever reference is ~/workspace/retriever-app (the requested ~/workspace/retriever path does not exist). Retain Capture's date-based release version and integer build counter instead of copying Retriever's semantic version policy. No credential changes, remote publishing, or unrelated source changes.

## Verification results
- Full Xcode suite passed: 39 tests, zero failures. Debug Info.plist reports version 2026.10.3/build 2 from Version.xcconfig.
- Release orchestration/publication checks passed, including ignored VERSION environment input, signing/verification failure preservation, rejected/pending notarization, and metadata/checksum backups.
- All AppKit checks passed after configuration wiring. About checks compare against the shared version configuration instead of hardcoded version constants.
- Both HTML pages passed checks for absolute canonical/social URLs, unique metadata keys/anchors, matching actual PNG dimensions, and valid local image references. Inspected the 2520 x 1474 app screenshot used by both social previews.
- make release succeeded with no version argument. The app and framework contain arm64 and x86_64. Explicit nested signing, Apple notarization (Accepted), stapling, Gatekeeper assessment, and DMG integrity verification passed.
- Local distribution: web-page/Capture.dmg; metadata: web-page/release.json; checksum: web-page/Capture.dmg.sha256. Prior download backed up under docs/dmg-backups/.
- SHA-256: 6743d32b575e9b032fe037dff7fd8910ab1842d392764e60256e3cb58c0fa262.
- Signed app size: 2256 KiB (about 2.3 MB). Matching symbols and notarization evidence remain under .build/release/run-84iz4mig/.
- No website upload or branch push performed. Direct Keynote paste remains unverified; native PNG clipboard interoperability was tested.
