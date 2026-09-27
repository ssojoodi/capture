# Capture

Capture is a minimal native macOS screenshot annotation app.

The goal is a fast, light-mode editor for common screenshot markup:

- arrows
- text
- blur
- crop
- rectangles and ellipses
- copy flattened image to clipboard
- export as JPG

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

Capture → About Capture shows the app version and build number. Set `MARKETING_VERSION`
to the release date in `year.month.day` format (currently `2026.9.27`) and `CURRENT_PROJECT_VERSION` (currently `1`) in the Capture target's
Debug and Release build settings before a release. Increment the build number for each
published build. Both Xcode and `make release` use these settings.

The Makefile's `VERSION` variable only names the temporary DMG file; it does not set
the app version.

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

The final DMG is `web-page/Capture.dmg`. If a previous DMG exists there,
`make release` moves it to `docs/dmg-backups/` with a timestamp before moving
the new DMG into place. Backups stay out of Git.

## Local Xcode Signing Config

For local Xcode signing settings, copy:

```bash
cp Config/LocalSigning.example.xcconfig Config/LocalSigning.xcconfig
```

`Config/LocalSigning.xcconfig` is ignored by git. The current command-line release flow signs manually after building, so `release.env` remains the source of truth for release signing.
