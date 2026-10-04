# Copy selected annotations

## Summary
Copy a selected arrow, rectangle, ellipse, or text annotation as a transparent PNG for pasting into Keynote and other image-capable apps.

## Product behavior target
Command-C and Edit > Copy copy the selected object when the canvas has focus. Native text selection copying remains unchanged while editing. Edit > Copy Annotation explicitly copies the selected object and commits active text. Shift-Command-C and the Copy Image toolbar button keep copying the full canvas. No selection leaves the clipboard unchanged.

## Architecture changes
Share annotation rendering extents with expanded-canvas bounds. Render the selected object alone into transparent PNG at image-space resolution, including stroke/arrowhead padding, without base image, other annotations, selection handles, or viewport scaling. Route Copy through the native responder chain. Add a separate explicit Copy Annotation menu item and validate selection-dependent copy commands.

## UX acceptance criteria
Arrows in every direction, thick shapes, text with or without a background, and off-image objects copy without clipping. Result is a standalone raster image, not an editable native Keynote shape. Copy never alters geometry, selection, undo, or dirty state except to commit actual pending text edits. Existing full-image copy and text copying continue to work.

## Automated test plan
Decode individual PNGs and check alpha, dimensions, stroke edges, source-image exclusion, exclusion of other annotations, negative coordinates, and stable state. AppKit checks use an isolated pasteboard, validate no-selection behavior, and check responder routing for canvas versus text editor and independent windows. Run Xcode tests and standalone AppKit checks sequentially.

## Manual verification plan
Generate and inspect selected-object PNG artifacts. Launch the built app. Direct Keynote paste verification depends on desktop-control availability; report any limitation without claiming an external-app paste was tested.

## Assumptions and non-goals
Single-object selection only. PNG is compatible with image paste workflows, but does not carry Capture editing metadata. Blur is applied destructively to the source image and is not an independently selectable object. No new clipboard format, multi-selection, Keynote automation, release publication, or commit. Preserve the preceding uncommitted PNG export work.

## Verification results
- Required Xcode test command ran: 39 tests, 38 passed. Only the known pre-existing blur-brightness test failed (two assertions, identical to prior runs).
- All AppKit checks passed, including active-window Copy routing, native text Copy routing, isolated PNG pasteboard recognition through NSImage, no-selection clipboard preservation, active text commit for explicit Copy Annotation, and zoom-independent bytes.
- Generated and inspected artifacts/verification/copied-arrow.png: red arrow alone with transparent surrounding pixels and no source background or selection handles.
- Direct pasting into Keynote was not exercised; native desktop control was unavailable during this session. Standard PNG clipboard interoperability was verified via AppKit.
- git diff --check passed. Previous PNG export changes remain uncommitted alongside this feature.
