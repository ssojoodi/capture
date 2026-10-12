# Capture

Capture is a minimal native macOS screenshot annotation app.

The goal is a fast, light-mode editor for common screenshot markup:

- arrows
- text
- blur
- crop
- rectangles and ellipses
- copy flattened image to clipboard
- export as PNG (or JPEG with an image-matched background)

Select an arrow, shape, or text box and press Command-C (or choose Edit > Copy Annotation) to copy that object as a transparent PNG for Keynote or other apps. Text editing keeps normal text-selection copying. The pasted object is an image, not an editable native shape.

Copy Image (Shift-Command-C) writes the full canvas as PNG to the clipboard. Export and Save As default to PNG; use a `.jpg` or `.jpeg` filename for JPEG. PNG preserves transparency, including empty space around annotations outside the original image. JPEG fills transparent areas with the average visible image color (white if the image is fully transparent). Save keeps the format of an existing PNG or JPEG file.

## Requirements

- macOS 14.0 or newer
- Full Xcode app, not only Command Line Tools

## Project Layout

- `Sources/CaptureApp/`: native macOS application shell and canvas UI
- `Sources/CaptureCore/`: annotation model, rendering, export, and document state
- `Tests/CaptureCoreTests/`: unit tests for core behavior
- `Brand/`: source SVG brand assets
- `scripts/`: repeatable asset and DMG generation scripts
- `Config/`: shared and local signing configuration examples
- `Capture.xcodeproj/`: Xcode project

## Build And Run

Build from Terminal:

```bash
make
```

Build with Xcode signing disabled:

```bash
make buildlocal
```

Run tests:

```bash
make test
```

Build and open the app:

```bash
make run
```

## App Version

Capture → About Capture shows the version and build number from `Config/Version.xcconfig`.
This tracked file is the single source for Debug, Release, and release artifact naming:

```xcconfig
MARKETING_VERSION = 2026.10.3
CURRENT_PROJECT_VERSION = 2
```

Use the release date in `year.month.day` format and increment the build number for each
published build. Do not set `VERSION` in the environment or `release.env`. The release
driver reads the built app's Info.plist and verifies that it matches the configuration.

## Regenerate Assets

Brand source files live in `Brand/`.

Regenerate app icon PNGs and the DMG background:

```bash
make assets
```

Generated files are written to:

- `Sources/CaptureApp/Assets.xcassets/AppIcon.appiconset/`
- `.build/BrandAssets/`

## Signing And Release

Local release secrets live in `release.env`, which is ignored by git.

Create it from the example:

```bash
cp release.env.example release.env
```

Find your Developer ID signing identity:

```bash
security find-identity -v -p codesigning
```

Use the identity that starts with `Developer ID Application:`.

Create a notarization profile:

```bash
xcrun notarytool store-credentials "capture-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "APP-SPECIFIC-PASSWORD"
```

Set these values in `release.env`:

```makefile
SIGN_IDENTITY = Developer ID Application: Your Name (TEAMID)
NOTARY_PROFILE = capture-notary
```

Create a signed, notarized, stapled DMG:

```bash
make release
```

The final DMG is `web-page/Capture.dmg`. The release driver builds both Apple silicon
and Intel architectures in a reusable cache, signs the embedded framework before the app,
notarizes the DMG, and verifies its ticket and Gatekeeper assessment before replacing the
local download. Failed verification leaves the previous download intact.

Each run keeps its staging files, submission results, and matching dSYM files under
`.build/release/run-*/`. Previous downloads and metadata are backed up under
`docs/dmg-backups/`. The validated artifact's version, build, SHA-256, and size are written
to `web-page/release.json`; `web-page/Capture.dmg.sha256` holds the matching checksum.
These metadata files describe the built artifact; they are not version inputs.

Run `make check-release` to test release orchestration and failure handling without
credentials or Apple submissions. `make release` prepares local files only; upload the
website separately.

## Local Xcode Signing Config

For local Xcode signing settings, copy:

```bash
cp Config/LocalSigning.example.xcconfig Config/LocalSigning.xcconfig
```

`Config/LocalSigning.xcconfig` is ignored by git. The current command-line release flow signs manually after building, so `release.env` remains the source of truth for release signing.

## Update checker

Capture → Check for Updates… checks for a newer build and offers a browser download and release notes. Installation is manual. Automatically Check for Updates is off until enabled in the Capture menu.

All endpoints and timing live in `Sources/CaptureApp/UpdateController.swift`, in `UpdateConfiguration`: the manifest URL, download URL, release-notes URL, automatic-check interval (24 hours), and request timeout (15 seconds). There is no user setting for the interval. Manual checks bypass it; every network attempt, including a manual or failed attempt, postpones the next automatic check. Automatic results are shown once per new build and only while Capture is active.

When moving to a new host, update these configuration values and keep the old HTTPS endpoints working or redirect them to the new HTTPS endpoints. Installed copies retain the URLs they shipped with. Existing versions without the checker require a manual upgrade to the first checker-enabled release.

For website deployment, upload the validated DMG first, its matching checksum next, and `release.json` last. Verify the public manifest's version, build, byte count, and SHA-256 against the downloadable DMG. Publish all three from the same `make release` output; do not advertise a release before its download is available. The checker compares the manifest's integer `build` to `CFBundleVersion`; release preparation alone does not change the advertised download.
