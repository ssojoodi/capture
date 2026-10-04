# Transparent PNG export

## Summary
Make PNG the default flattened output and preserve transparent canvas extensions. Composite JPEG output over an image-derived background.

## Product behavior target
Copy publishes PNG. Export and Save As suggest PNG and permit JPEG explicitly. Save to an existing JPEG retains its format. PNG preserves source alpha and empty expanded-canvas regions. JPEG uses the alpha-weighted average sRGB color of visible flattened pixels, sampled at up to 64 by 64 pixels; fully transparent images fall back to white. All JPEG paths use this behavior.

## Architecture changes
Keep rendering transparent. Centralize JPEG compositing in ImageRenderer before encoding. Reuse imageData with PNG as its default. Rename the export action and remove JPG-only labels. Keep export separate from save-state changes and use atomic file writes.

## UX acceptance criteria
PNG copy/export preserves transparency, including negative-coordinate extensions. Light images get light JPEG backgrounds, dark images get dark backgrounds, and tinted images retain their average tint. Transparent pixels do not count as black samples. Export cancellation does not change source URL or dirty state.

## Automated test plan
Test PNG alpha in expanded output and default encoding signature. Decode JPEG fixtures for light, dark, tinted, partially transparent, mixed-color, and fully transparent images. Verify clipboard PNG through an isolated pasteboard and export panel defaults in AppKit checks. Run Xcode tests and AppKit checks; document the known baseline blur failure separately.

## Manual verification plan
Inspect generated PNG and JPEG artifacts and launch the rebuilt application. Verify export menu/toolbar names. Desktop automation may remain unavailable as recorded in the preceding iteration.

## Assumptions and non-goals
Use an alpha-weighted arithmetic sRGB average, not dominant-color clustering. Sample the final cropped/annotated image so visible output determines its background. No new preferences or release publication. The canvas's neutral display backdrop is not encoded in PNG. This deliberately replaces the former white expanded-output fill.

## Verification results
- Required full Xcode suite ran. The existing blur-brightness failure remains (previously reproduced on unchanged HEAD). New JPEG assertions were corrected to inspect decoded sRGB samples directly rather than display-calibrated NSColor conversions.
- Final Xcode suite excluding that known baseline test: 36 tests passed, zero failures.
- All standalone AppKit checks passed when run after Xcode testing to avoid competing window focus. Clipboard PNG alpha, export panel defaults, both allowed formats, and generic Export label were verified.
- Generated and inspected transparent-output.png and sampled-background-output.jpg under artifacts/verification. The JPEG fills the transparent region with the fixture's pale image color.
- git diff --check passed. No release or commit was performed in this iteration.
